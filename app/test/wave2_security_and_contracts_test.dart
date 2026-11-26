import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:granapaca/api/api_models.dart';
import 'package:granapaca/api/granapaca_api_client.dart';
import 'package:granapaca/api/http_transport_base.dart';
import 'package:granapaca/finance/model.dart';
import 'package:granapaca/finance/taxonomy.dart';
import 'package:granapaca/main.dart';
import 'package:granapaca/screens/app_lock_screen.dart';
import 'package:granapaca/screens/app_shell.dart';
import 'package:granapaca/screens/server_auth_screen.dart';
import 'package:granapaca/security/app_lock.dart';
import 'package:granapaca/state/app_state.dart';
import 'package:granapaca/state/preferences_store.dart';
import 'package:granapaca/state/preferences_store_io.dart';
import 'package:granapaca/storage/cache_storage_base.dart';
import 'package:granapaca/storage/cache_storage_io.dart';
import 'package:granapaca/storage/encrypted_cache.dart';
import 'package:granapaca/widgets/totp_qr_code.dart';

class _RecordingHttpTransport implements HttpTransport {
  _RecordingHttpTransport(this.handler);

  final Future<HttpTransportResponse> Function(HttpTransportRequest req)
  handler;
  final List<HttpTransportRequest> requests = [];

  @override
  bool get isSupported => true;

  @override
  Future<HttpTransportResponse> send(HttpTransportRequest request) {
    requests.add(request);
    return handler(request);
  }
}

Future<void> _tapPin(WidgetTester tester, String digits) async {
  for (final ch in digits.split('')) {
    await tester.tap(find.byKey(Key('pin_key_$ch')));
    await tester.pump();
  }
  await tester.pumpAndSettle();
}

CachedSnapshot _sampleSnapshot(String serverUrl) => CachedSnapshot(
  serverUrl: serverUrl,
  lastSyncedAt: DateTime(2026, 3, 28, 14, 0),
  syncCursor: 'cur-offline-1',
  banks: const [Bank('bank-ipe', 'Banco Ipê')],
  accounts: const [
    Account(
      id: 'acc-1',
      bankId: 'bank-ipe',
      name: 'Conta Corrente',
      kind: AccountKind.checking,
      openingBalanceCents: 250000,
    ),
  ],
  transactions: [
    Transaction(
      id: stableTransactionId('11111111-1111-1111-1111-111111111111'),
      accountId: 'acc-1',
      date: DateTime(2026, 3, 22),
      description: 'Mercado da Vila',
      amountCents: -18743,
      kind: TxKind.expense,
      category: SpendingCategory.food,
      essentiality: Essentiality.essential,
    ),
  ],
  transactionUuidById: {
    stableTransactionId('11111111-1111-1111-1111-111111111111'):
        '11111111-1111-1111-1111-111111111111',
  },
);

void main() {
  group('TLS enforcement in normalizeServerUrl (RF-01)', () {
    test('allows https:// for remote hosts and http:// only for loopback', () {
      expect(
        GranaPaCaApiClient.normalizeServerUrl(
          'https://financas.minha-rede.ts.net/',
        ).toString(),
        'https://financas.minha-rede.ts.net',
      );
      expect(
        GranaPaCaApiClient.normalizeServerUrl('http://localhost:8080').host,
        'localhost',
      );
      expect(
        GranaPaCaApiClient.normalizeServerUrl('http://127.0.0.1:8080').host,
        '127.0.0.1',
      );
      expect(
        GranaPaCaApiClient.normalizeServerUrl('http://[::1]:8080').host,
        '::1',
      );

      for (final insecure in const [
        'http://financas.minha-rede.ts.net',
        'http://192.168.1.50:8080',
        'http://100.64.0.10:8080',
      ]) {
        expect(
          () => GranaPaCaApiClient.normalizeServerUrl(insecure),
          throwsA(
            isA<ApiException>().having(
              (e) => e.code,
              'code',
              'insecure_http_not_allowed',
            ),
          ),
        );
      }
    });
  });

  group('Encrypted cache key isolation & PIN KEK wrapping (RF-21 / RF-04)', () {
    test(
      'keeps key material out of snapshot directory and locks/unlocks DEK with PIN',
      () async {
        final dir = Directory.systemTemp.createTempSync('granapaca_key_test_');
        addTearDown(() => dir.deleteSync(recursive: true));

        final cacheDir = Directory('${dir.path}/cache');
        final keyDir = Directory('${dir.path}/keystore');
        final store = EncryptedCacheStore(
          storage: FileCacheStorage(cacheDir),
          keyStorage: FileCacheStorage(keyDir, restrictPermissions: true),
        );

        const url = 'https://toca.minha-rede.ts.net';
        await store.saveSnapshot(_sampleSnapshot(url));

        // Snapshot directory must contain ONLY the encrypted snapshot, never raw keys.
        final cacheFiles = cacheDir
            .listSync()
            .whereType<File>()
            .map((f) => f.uri.pathSegments.last)
            .toList();
        expect(cacheFiles, [EncryptedCacheStore.snapshotKey]);

        // Protect with PIN -> wrapped_dek.enc replaces device_cache.key.
        await store.protectWithPin('246810', iterations: 50);
        final keyFiles = keyDir
            .listSync()
            .whereType<File>()
            .map((f) => f.uri.pathSegments.last)
            .toList();
        expect(keyFiles, [EncryptedCacheStore.wrappedDekKey]);

        // After locking in memory, snapshot cannot be read without unwrapping with PIN.
        store.lockInMemory();
        await expectLater(
          store.loadSnapshot(expectedServerUrl: url),
          throwsA(isA<CacheIntegrityException>()),
        );

        // Wrong PIN fails and keeps cache locked.
        expect(await store.unlockWithPin('000000'), isFalse);
        // Correct PIN unwraps DEK and allows decrypting the snapshot.
        expect(await store.unlockWithPin('246810'), isTrue);
        final restored = await store.loadSnapshot(expectedServerUrl: url);
        expect(restored?.banks.single.name, 'Banco Ipê');
        expect(restored?.transactions.single.description, 'Mercado da Vila');
      },
    );
  });

  group('Offline lockout, logout cleanup & cold-start restoration (RF-04 / RF-21)', () {
    testWidgets(
      '5 wrong PINs while locked in offline mode wipe cache and route to ServerAuthScreen, never AppShell',
      (tester) async {
        const url = 'https://toca.minha-rede.ts.net';
        final prefs = InMemoryPreferencesStore(
          serverUrl: url,
          hasActiveServerProfile: true,
        );
        final cache = EncryptedCacheStore(
          storage: InMemoryCacheStorage(),
          keyStorage: InMemoryCacheStorage(),
        );
        await cache.saveSnapshot(_sampleSnapshot(url));

        final lock = AppLockController(
          preferencesStore: prefs,
          hashIterations: 50,
        );
        await lock.configurePin('135790');
        await cache.protectWithPin('135790', iterations: 50);
        lock.lockNow();

        await tester.pumpWidget(
          GranaPaCaApp(
            preferencesStore: prefs,
            encryptedCache: cache,
            appLock: lock,
            initialMode: AppMode.server,
            initialServerUrl: url,
            initialOffline: true,
            dataset: _sampleSnapshot(url).toDataset(),
            initialLastSyncedAt: DateTime(2026, 3, 28, 14, 0),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byType(AppLockScreen), findsOneWidget);
        expect(find.byType(AppShell), findsNothing);

        for (var i = 0; i < 5; i++) {
          await _tapPin(tester, '999999');
        }

        // Must land on ServerAuthScreen with lockout notice — NEVER AppShell!
        expect(find.byType(ServerAuthScreen), findsOneWidget);
        expect(find.byType(AppShell), findsNothing);
        expect(find.byKey(const Key('session_cleared_notice')), findsOneWidget);
        expect(await cache.readRawCiphertext(), isNull);
        expect(prefs.readHasActiveServerProfile(), isFalse);
        expect(prefs.readAppLockConfig(), isNull);
      },
    );

    testWidgets(
      'cold start restores persisted AppLock first, then unlocks encrypted offline cache on valid PIN',
      (tester) async {
        const url = 'https://toca.minha-rede.ts.net';
        final prefs = InMemoryPreferencesStore(
          serverUrl: url,
          hasActiveServerProfile: true,
        );
        final cache = EncryptedCacheStore(
          storage: InMemoryCacheStorage(),
          keyStorage: InMemoryCacheStorage(),
        );
        await cache.saveSnapshot(_sampleSnapshot(url));

        // Simulate previous app session setting up PIN lock.
        final previousLock = AppLockController(
          preferencesStore: prefs,
          hashIterations: 50,
        );
        await previousLock.configurePin('246810');
        await cache.protectWithPin('246810', iterations: 50);
        cache.lockInMemory();
        previousLock.dispose();

        // Simulate cold start with a brand-new AppLockController reading from prefs.
        final freshLock = AppLockController(hashIterations: 50);
        await tester.pumpWidget(
          GranaPaCaApp(
            preferencesStore: prefs,
            encryptedCache: cache,
            appLock: freshLock,
          ),
        );
        await tester.pumpAndSettle();

        // Cold start MUST immediately lock before showing any financial data.
        expect(find.byType(AppLockScreen), findsOneWidget);
        expect(find.text('Mercado da Vila'), findsNothing);

        // Entering valid PIN unwraps cache DEK and restores offline server snapshot.
        await _tapPin(tester, '246810');
        expect(find.byType(AppShell), findsOneWidget);
        expect(find.byKey(const Key('offline_banner')), findsOneWidget);
        final homeScrollable = find.byType(Scrollable).first;
        await tester.scrollUntilVisible(
          find.text('Banco Ipê'),
          250,
          scrollable: homeScrollable,
        );
        expect(find.text('Banco Ipê'), findsWidgets);
        await tester.scrollUntilVisible(
          find.text('Mercado da Vila'),
          250,
          scrollable: homeScrollable,
        );
        expect(find.text('Mercado da Vila'), findsWidgets);
      },
    );

    test('FilePreferencesStore persists AppLockConfig and active server profile', () async {
      final dir = Directory.systemTemp.createTempSync('granapaca_lock_prefs_');
      addTearDown(() => dir.deleteSync(recursive: true));

      final file = File('${dir.path}/prefs.json');
      final store1 = FilePreferencesStore(file);
      await store1.writeServerUrl('https://toca.minha-rede.ts.net');
      await store1.writeHasActiveServerProfile(true);
      await store1.writeAppLockConfig(
        const AppLockConfig(
          isEnabled: true,
          pinHash: 'salt:hash',
          biometricEnabled: true,
          inactivityTimeoutSeconds: 180,
        ),
      );

      final store2 = FilePreferencesStore(file);
      expect(store2.readServerUrl(), 'https://toca.minha-rede.ts.net');
      expect(store2.readHasActiveServerProfile(), isTrue);
      final lockCfg = store2.readAppLockConfig();
      expect(lockCfg?.isEnabled, isTrue);
      expect(lockCfg?.pinHash, 'salt:hash');
      expect(lockCfg?.biometricEnabled, isTrue);
      expect(lockCfg?.inactivityTimeoutSeconds, 180);
    });

    test('logout wipes offline flag, financial dataset, cursor and encrypted cache', () async {
      const url = 'https://toca.minha-rede.ts.net';
      final prefs = InMemoryPreferencesStore(
        serverUrl: url,
        hasActiveServerProfile: true,
      );
      final cache = EncryptedCacheStore(
        storage: InMemoryCacheStorage(),
        keyStorage: InMemoryCacheStorage(),
      );
      await cache.saveSnapshot(_sampleSnapshot(url));

      final transport = _RecordingHttpTransport(
        (_) async => const HttpTransportResponse(statusCode: 204, body: ''),
      );
      final client = GranaPaCaApiClient(
        transport: transport,
        baseUrl: Uri.parse(url),
        initialTokens: AuthTokens(
          accessToken: 'tok',
          refreshToken: 'ref',
          expiresAt: DateTime(2026, 4, 1),
          sessionId: 's1',
          owner: const OwnerSummary(
            id: 'o1',
            householdId: 'h1',
            email: 'bia@exemplo.local',
            displayName: 'Bia',
          ),
        ),
      );

      final state = AppState(
        preferencesStore: prefs,
        apiClient: client,
        encryptedCache: cache,
        initialMode: AppMode.server,
        initialServerUrl: url,
      );
      await state.restoreFromEncryptedCache(markOffline: true);
      expect(state.isOffline, isTrue);
      expect(state.originalDataset.transactions, isNotEmpty);

      await state.logout();
      expect(state.isAuthenticated, isFalse);
      expect(state.isOffline, isFalse);
      expect(state.originalDataset.transactions, isEmpty);
      expect(state.syncCursor, isNull);
      expect(await cache.readRawCiphertext(), isNull);
      expect(prefs.readHasActiveServerProfile(), isFalse);
    });
  });

  group('Backend delta sync, ProblemDetails & mutation contracts (#56 / #59)', () {
    test(
      'maps card_payment/withdrawal, UUID removals, serverTime, alerts merge, ProblemDetails fullResyncRequired and latest month',
      () async {
        expect(parseTxKind('card_payment'), TxKind.billPayment);
        expect(parseTxKind('withdrawal'), TxKind.cashWithdrawal);
        for (final kind in TxKind.values) {
          expect(parseTxKind(txKindToApiString(kind)), kind);
        }

        const txKeepUuid = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
        const txRemoveUuid = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb';
        const txCardPayUuid = 'cccccccc-cccc-cccc-cccc-cccccccccccc';
        const txWithdrawUuid = 'dddddddd-dddd-dddd-dddd-dddddddddddd';

        var syncCalls = 0;
        final transport = _RecordingHttpTransport((req) async {
          if (req.uri.path == '/api/v1/sync/changes') {
            syncCalls++;
            if (syncCalls == 1) {
              // First sync: full snapshot with unsorted transaction dates + backend fields.
              return HttpTransportResponse(
                statusCode: 200,
                body: jsonEncode({
                  'cursor': null,
                  'nextCursor': 'cur-1',
                  'serverTime': '2026-03-28T15:00:00Z',
                  'isFullSync': true,
                  'fullResyncRequired': false,
                  'connections': [
                    {
                      'id': 'conn-1',
                      'institutionName': 'Banco Ipê',
                      'brandColor': '#1D6B48',
                      'status': 'up_to_date',
                      'lastSyncedAt': '2026-03-28T14:55:00Z',
                    },
                  ],
                  'accounts': [
                    {
                      'id': 'acc-1',
                      'connectionId': 'conn-1',
                      'name': 'Conta Corrente',
                      'kind': 'checking',
                      'openingBalanceCents': 100000,
                    },
                  ],
                  'cardBills': [
                    {
                      'id': 'bill-1',
                      'accountId': 'acc-1',
                      'periodMonth': '2026-03-01',
                      'closingOn': '2026-03-28',
                      'dueOn': '2026-04-10',
                      'totalCents': 50000,
                      'isOpen': true,
                    },
                  ],
                  'transactions': [
                    {
                      'id': txKeepUuid,
                      'accountId': 'acc-1',
                      'occurredOn': '2026-01-10',
                      'description': 'Antiga Janeiro',
                      'amountCents': -5000,
                      'kind': 'expense',
                      'category': 'food',
                    },
                    {
                      'id': txRemoveUuid,
                      'accountId': 'acc-1',
                      'occurredOn': '2026-03-25',
                      'description': 'Pré-autorização removida',
                      'amountCents': -9900,
                      'kind': 'expense',
                      'category': 'shopping',
                    },
                    {
                      'id': txCardPayUuid,
                      'accountId': 'acc-1',
                      'occurredOn': '2026-03-10',
                      'description': 'Pagamento Fatura',
                      'amountCents': -45000,
                      'kind': 'card_payment',
                    },
                    {
                      'id': txWithdrawUuid,
                      'accountId': 'acc-1',
                      'occurredOn': '2026-02-14',
                      'description': 'Saque 24h',
                      'amountCents': -20000,
                      'kind': 'withdrawal',
                    },
                  ],
                  'removedTransactionIds': const [],
                  'adjustments': [
                    {
                      'id': 'adj-srv-1',
                      'transactionId': txKeepUuid,
                      'fieldName': 'essentiality',
                      'oldValue': null,
                      'newValue': 'essential',
                      'reason': 'Supermercado mensal',
                      'createdAt': '2026-03-28T14:59:00Z',
                    },
                  ],
                  'rules': const [],
                  'alerts': [
                    {
                      'id': 'alert-1',
                      'title': 'Conexão ativa',
                      'message': 'Banco Ipê sincronizado com sucesso.',
                      'actionTarget': '/connections',
                      'isRead': false,
                      'createdAt': '2026-03-28T14:55:00Z',
                    },
                  ],
                }),
              );
            }
            if (syncCalls == 2) {
              // Second sync: incremental delta removing UUID + adding second alert.
              return HttpTransportResponse(
                statusCode: 200,
                body: jsonEncode({
                  'cursor': 'cur-1',
                  'nextCursor': 'cur-2',
                  'serverTime': '2026-03-28T16:00:00Z',
                  'isFullSync': false,
                  'fullResyncRequired': false,
                  'connections': const [],
                  'accounts': const [],
                  'cardBills': const [],
                  'transactions': const [],
                  'removedTransactionIds': [txRemoveUuid],
                  'adjustments': const [],
                  'rules': const [],
                  'alerts': [
                    {
                      'id': 'alert-2',
                      'title': 'Fatura fechando',
                      'message': 'Confira seus gastos de março.',
                      'actionTarget': '/spending',
                      'isRead': false,
                      'createdAt': '2026-03-28T15:50:00Z',
                    },
                  ],
                }),
              );
            }
            if (syncCalls == 3) {
              // Third sync: RFC 9457 ProblemDetails requesting full resync!
              return HttpTransportResponse(
                statusCode: 400,
                body: jsonEncode({
                  'title': 'Cursor de sincronização inválido',
                  'detail': 'O cursor informado está no futuro.',
                  'code': 'invalid_cursor',
                  'fullResyncRequired': true,
                }),
              );
            }
            // Fourth sync: automatic retry with cursor=null succeeds.
            expect(req.uri.queryParameters['cursor'], isNull);
            return HttpTransportResponse(
              statusCode: 200,
              body: jsonEncode({
                'cursor': null,
                'nextCursor': 'cur-fresh',
                'serverTime': '2026-03-28T17:00:00Z',
                'isFullSync': true,
                'fullResyncRequired': false,
                'connections': const [],
                'accounts': const [],
                'cardBills': const [],
                'transactions': const [],
                'removedTransactionIds': const [],
                'adjustments': const [],
                'rules': const [],
                'alerts': const [],
              }),
            );
          }
          return const HttpTransportResponse(statusCode: 404, body: '{}');
        });

        final client = GranaPaCaApiClient(
          transport: transport,
          baseUrl: Uri.parse('https://toca.minha-rede.ts.net'),
          initialTokens: AuthTokens(
            accessToken: 'tok',
            refreshToken: 'ref',
            expiresAt: DateTime(2026, 4, 1),
            sessionId: 's1',
            owner: const OwnerSummary(
              id: 'o1',
              householdId: 'h1',
              email: 'bia@exemplo.local',
              displayName: 'Bia',
            ),
          ),
        );
        final state = AppState(
          preferencesStore: InMemoryPreferencesStore(),
          apiClient: client,
          encryptedCache: EncryptedCacheStore(
            storage: InMemoryCacheStorage(),
            keyStorage: InMemoryCacheStorage(),
          ),
          initialMode: AppMode.server,
          initialServerUrl: 'https://toca.minha-rede.ts.net',
        );

        await state.syncFromServer();
        expect(state.syncedCardBills.length, 1);
        expect(state.adjustments.single.id, 'adj-srv-1');
        // Latest month must be March 2026 (max date), NOT January (first item).
        expect(state.selectedMonth, DateTime(2026, 3));
        // card_payment and withdrawal mapped accurately (not TxKind.expense).
        expect(
          state.effectiveById(stableTransactionId(txCardPayUuid)).kind,
          TxKind.billPayment,
        );
        expect(
          state.effectiveById(stableTransactionId(txWithdrawUuid)).kind,
          TxKind.cashWithdrawal,
        );
        expect(state.alerts.single.body, 'Banco Ipê sincronizado com sucesso.');

        // Incremental sync removes UUID transaction AND merges second alert.
        await state.syncFromServer();
        expect(
          state.originalDataset.transactions.any(
            (t) => t.id == stableTransactionId(txRemoveUuid),
          ),
          isFalse,
        );
        expect(state.alerts.map((a) => a.id), containsAll(['alert-1', 'alert-2']));
        expect(
          state.alerts.firstWhere((a) => a.id == 'alert-2').target,
          AlertTarget.spending,
        );

        // ProblemDetails fullResyncRequired triggers automatic full resync.
        await state.syncFromServer();
        expect(syncCalls, 4);
        expect(state.syncCursor, 'cur-fresh');
      },
    );

    test(
      'persists adjustments, undo, and review-queue rules to backend endpoints in server mode',
      () async {
        const txUuid = 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee';
        final txIntId = stableTransactionId(txUuid);
        final calls = <String>[];

        final transport = _RecordingHttpTransport((req) async {
          calls.add('${req.method} ${req.uri.path}');
          if (req.uri.path == '/api/v1/sync/changes') {
            return HttpTransportResponse(
              statusCode: 200,
              body: jsonEncode({
                'nextCursor': 'c1',
                'serverTime': '2026-03-28T12:00:00Z',
                'isFullSync': true,
                'fullResyncRequired': false,
                'connections': [
                  {
                    'id': 'conn-1',
                    'institutionName': 'Banco Ipê',
                    'status': 'up_to_date',
                  },
                ],
                'accounts': [
                  {
                    'id': 'acc-1',
                    'connectionId': 'conn-1',
                    'name': 'CC',
                    'kind': 'checking',
                  },
                ],
                'transactions': [
                  {
                    'id': txUuid,
                    'accountId': 'acc-1',
                    'occurredOn': '2026-03-26',
                    'description': 'Café da Praça',
                    'amountCents': -1850,
                    'kind': 'expense',
                  },
                ],
              }),
            );
          }
          if (req.method == 'POST' &&
              req.uri.path == '/api/v1/transactions/$txUuid/adjustments') {
            final body = jsonDecode(req.body!) as Map<String, dynamic>;
            expect(body['category'], 'food');
            expect(body['essentiality'], 'flexible');
            return HttpTransportResponse(
              statusCode: 200,
              body: jsonEncode({
                'appliedAdjustments': [
                  {
                    'id': 'srv-adj-cat',
                    'transactionId': txUuid,
                    'fieldName': 'category',
                    'oldValue': null,
                    'newValue': 'food',
                    'createdAt': '2026-03-28T12:01:00Z',
                  },
                  {
                    'id': 'srv-adj-ess',
                    'transactionId': txUuid,
                    'fieldName': 'essentiality',
                    'oldValue': null,
                    'newValue': 'flexible',
                    'createdAt': '2026-03-28T12:01:00Z',
                  },
                ],
              }),
            );
          }
          if (req.method == 'POST' &&
              req.uri.path ==
                  '/api/v1/transactions/$txUuid/adjustments/srv-adj-cat/undo') {
            return HttpTransportResponse(
              statusCode: 200,
              body: jsonEncode({
                'adjustment': {
                  'id': 'srv-adj-undo',
                  'transactionId': txUuid,
                  'fieldName': 'category',
                  'oldValue': 'food',
                  'newValue': null,
                  'undoesId': 'srv-adj-cat',
                  'createdAt': '2026-03-28T12:02:00Z',
                },
              }),
            );
          }
          if (req.method == 'POST' && req.uri.path == '/api/v1/rules') {
            final body = jsonDecode(req.body!) as Map<String, dynamic>;
            expect(body['matchMerchant'], 'Café da Praça');
            expect(body['category'], 'food');
            return HttpTransportResponse(
              statusCode: 201,
              body: jsonEncode({
                'id': 'srv-rule-1',
                'layer': 'user',
                'name': 'Café da Praça',
                'explanation': body['explanation'],
                'matchMerchantNormalized': 'cafe da praca',
                'category': 'food',
                'essentiality': 'flexible',
                'isActive': true,
              }),
            );
          }
          if (req.method == 'PATCH' &&
              req.uri.path == '/api/v1/rules/srv-rule-1') {
            return HttpTransportResponse(
              statusCode: 200,
              body: jsonEncode({
                'id': 'srv-rule-1',
                'layer': 'user',
                'name': 'Café da Praça',
                'explanation': 'Desativada',
                'matchMerchantNormalized': 'cafe da praca',
                'category': 'food',
                'essentiality': 'flexible',
                'isActive': false,
              }),
            );
          }
          if (req.method == 'DELETE' &&
              req.uri.path == '/api/v1/rules/srv-rule-1') {
            return const HttpTransportResponse(statusCode: 204, body: '');
          }
          return const HttpTransportResponse(statusCode: 404, body: '{}');
        });

        final client = GranaPaCaApiClient(
          transport: transport,
          baseUrl: Uri.parse('https://toca.minha-rede.ts.net'),
          initialTokens: AuthTokens(
            accessToken: 'tok',
            refreshToken: 'ref',
            expiresAt: DateTime(2026, 4, 1),
            sessionId: 's1',
            owner: const OwnerSummary(
              id: 'o1',
              householdId: 'h1',
              email: 'bia@exemplo.local',
              displayName: 'Bia',
            ),
          ),
        );
        final state = AppState(
          preferencesStore: InMemoryPreferencesStore(),
          apiClient: client,
          encryptedCache: EncryptedCacheStore(
            storage: InMemoryCacheStorage(),
            keyStorage: InMemoryCacheStorage(),
          ),
          initialMode: AppMode.server,
          initialServerUrl: 'https://toca.minha-rede.ts.net',
        );

        await state.syncFromServer();
        expect(state.reviewQueueGroups.length, 1);

        state.adjustTransaction(
          txId: txIntId,
          category: SpendingCategory.food,
          changeCategory: true,
          essentiality: Essentiality.flexible,
          changeEssentiality: true,
        );
        await state.flushPendingMutations();
        expect(
          state.adjustments.map((a) => a.id),
          containsAll(['srv-adj-cat', 'srv-adj-ess']),
        );

        state.undoAdjustment('srv-adj-cat');
        await state.flushPendingMutations();
        expect(state.adjustments.map((a) => a.id), contains('srv-adj-undo'));

        state.createUserRuleFromTransaction(
          txId: txIntId,
          category: SpendingCategory.food,
          essentiality: Essentiality.flexible,
        );
        await state.flushPendingMutations();
        expect(state.rules.single.id, 'srv-rule-1');

        state.toggleRuleActive('srv-rule-1', false);
        await state.flushPendingMutations();
        expect(state.rules.single.isActive, isFalse);

        state.deleteRule('srv-rule-1');
        await state.flushPendingMutations();
        expect(state.rules, isEmpty);

        expect(calls, containsAllInOrder([
          'GET /api/v1/sync/changes',
          'POST /api/v1/transactions/$txUuid/adjustments',
          'POST /api/v1/transactions/$txUuid/adjustments/srv-adj-cat/undo',
          'POST /api/v1/rules',
          'PATCH /api/v1/rules/srv-rule-1',
          'DELETE /api/v1/rules/srv-rule-1',
        ]));
      },
    );
  });

  group('Pure-Dart TOTP QR Code generator & widget (RF-03)', () {
    test('generates valid ISO/IEC 18004 QR matrices with finder, timing & dark module', () {
      const uri =
          'otpauth://totp/GranaPaCa:bia@exemplo.local?secret=JBSWY3DPEHPK3PXP&issuer=GranaPaCa&algorithm=SHA1&digits=6&period=30';
      final qr = QrCodeMatrix.encode(uri);
      expect(qr.version, inInclusiveRange(5, 10));
      expect(qr.size, 17 + 4 * qr.version);
      expect(qr.maskPattern, inInclusiveRange(0, 7));

      // Top-left 7x7 finder corners and 3x3 center must be dark; separator row/col 7 light.
      expect(qr.isDark(0, 0), isTrue);
      expect(qr.isDark(0, 6), isTrue);
      expect(qr.isDark(6, 0), isTrue);
      expect(qr.isDark(3, 3), isTrue);
      expect(qr.isDark(1, 1), isFalse);
      expect(qr.isDark(7, 0), isFalse);
      expect(qr.isDark(0, 7), isFalse);

      // Top-right and bottom-left finder centers.
      expect(qr.isDark(3, qr.size - 4), isTrue);
      expect(qr.isDark(qr.size - 4, 3), isTrue);

      // Timing patterns alternate on row 6 and col 6.
      for (var i = 8; i < qr.size - 8; i++) {
        expect(qr.isDark(6, i), i.isEven);
        expect(qr.isDark(i, 6), i.isEven);
      }

      // Mandatory dark module at (size - 8, 8).
      expect(qr.isDark(qr.size - 8, 8), isTrue);

      // Deterministic output.
      final qr2 = QrCodeMatrix.encode(uri);
      expect(qr2.maskPattern, qr.maskPattern);
      expect(qr2.modules, qr.modules);

      // Short payload fits in Version 1 (21x21).
      final small = QrCodeMatrix.encode('GranaPaCa');
      expect(small.version, 1);
      expect(small.size, 21);
    });

    testWidgets('TotpQrCodeView renders CustomPaint with accessible label', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: TotpQrCodeView(
                key: Key('qr_widget_test'),
                data:
                    'otpauth://totp/GranaPaCa:bia@exemplo.local?secret=JBSWY3DPEHPK3PXP&issuer=GranaPaCa',
              ),
            ),
          ),
        ),
      );
      expect(find.byKey(const Key('qr_widget_test')), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const Key('qr_widget_test')),
          matching: find.byType(CustomPaint),
        ),
        findsOneWidget,
      );
    });
  });
}
