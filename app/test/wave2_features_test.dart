import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:granapaca/api/api_models.dart';
import 'package:granapaca/api/granapaca_api_client.dart';
import 'package:granapaca/api/http_transport.dart';
import 'package:granapaca/finance/model.dart';
import 'package:granapaca/finance/taxonomy.dart';
import 'package:granapaca/main.dart';
import 'package:granapaca/screens/app_lock_screen.dart';
import 'package:granapaca/screens/connections_screen.dart';
import 'package:granapaca/screens/review_queue_screen.dart';
import 'package:granapaca/screens/server_auth_screen.dart';
import 'package:granapaca/security/app_lock.dart';
import 'package:granapaca/state/app_state.dart';
import 'package:granapaca/state/preferences_store.dart';
import 'package:granapaca/storage/cache_storage.dart';
import 'package:granapaca/storage/cache_storage_io.dart';
import 'package:granapaca/storage/encrypted_cache.dart';
import 'package:granapaca/storage/pure_crypto.dart';

typedef _TransportHandler =
    Future<HttpTransportResponse> Function(HttpTransportRequest request);

class _FakeHttpTransport extends HttpTransport {
  _FakeHttpTransport(this._handler);

  final _TransportHandler _handler;
  final List<HttpTransportRequest> requests = [];

  @override
  Future<HttpTransportResponse> send(HttpTransportRequest request) async {
    requests.add(request);
    return _handler(request);
  }
}

class _FakeBiometricAuthenticator implements BiometricAuthenticator {
  _FakeBiometricAuthenticator({
    this.available = true,
    this.nextResult = BiometricAuthResult.authenticated,
  });

  bool available;
  BiometricAuthResult nextResult;
  int calls = 0;

  @override
  Future<bool> isAvailable() async => available;

  @override
  Future<BiometricAuthResult> authenticate({
    required String localizedReason,
  }) async {
    calls++;
    return nextResult;
  }
}

Future<void> _tapPinDigits(WidgetTester tester, String pin) async {
  for (final ch in pin.split('')) {
    await tester.tap(find.byKey(Key('pin_key_$ch')));
    await tester.pump();
  }
  await tester.pumpAndSettle();
}

Future<void> _tapTab(WidgetTester tester, String label) async {
  final rail = find.byType(NavigationRail);
  final bar = find.byType(NavigationBar);
  final navContainer = rail.evaluate().isNotEmpty ? rail : bar;
  final target = find.descendant(
    of: navContainer,
    matching: find.text(label),
  );
  await tester.tap(target);
  await tester.pumpAndSettle();
}

Future<void> _scrollTo(
  WidgetTester tester,
  Finder finder, {
  Finder? scrollable,
}) async {
  final targetScrollable = scrollable ?? find.byType(Scrollable).last;
  await tester.scrollUntilVisible(
    finder,
    250,
    scrollable: targetScrollable,
  );
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
}

Dataset _datasetWithUncategorized() => Dataset(
  banks: const [
    Bank('aurora', 'Banco Aurora', colorValue: 0xFF8B3E05),
  ],
  accounts: const [
    Account(
      id: 'aurora-cc',
      bankId: 'aurora',
      name: 'Conta corrente',
      kind: AccountKind.checking,
      openingBalanceCents: 150000,
    ),
  ],
  transactions: [
    Transaction(
      id: 1,
      accountId: 'aurora-cc',
      date: DateTime(2026, 3, 10),
      description: 'Aluguel',
      amountCents: -100000,
      kind: TxKind.expense,
      category: SpendingCategory.housing,
      essentiality: Essentiality.essential,
    ),
    Transaction(
      id: 2,
      accountId: 'aurora-cc',
      date: DateTime(2026, 3, 12),
      description: 'Café da Praça',
      amountCents: -2500,
      kind: TxKind.expense,
    ),
    Transaction(
      id: 3,
      accountId: 'aurora-cc',
      date: DateTime(2026, 3, 15),
      description: '  CAFE DA PRACA ',
      amountCents: -3500,
      kind: TxKind.expense,
    ),
    Transaction(
      id: 4,
      accountId: 'aurora-cc',
      date: DateTime(2026, 3, 18),
      description: 'Banca do Largo',
      amountCents: -1500,
      kind: TxKind.expense,
    ),
  ],
  today: DateTime(2026, 3, 28),
);

void main() {
  group('PureCrypto & EncryptedCacheStore (RF-21)', () {
    test('computes NIST SHA-256 and RFC 4231 HMAC-SHA256 accurately', () {
      final shaAbc = PureCrypto.sha256(Uint8List.fromList(utf8.encode('abc')));
      expect(
        shaAbc.sublist(0, 4),
        orderedEquals(const [0xBA, 0x78, 0x16, 0xBF]),
      );
      expect(
        shaAbc.sublist(28, 32),
        orderedEquals(const [0xF2, 0x00, 0x15, 0xAD]),
      );

      final hmac = PureCrypto.hmacSha256(
        Uint8List.fromList(List.filled(20, 0x0B)),
        Uint8List.fromList(utf8.encode('Hi There')),
      );
      expect(
        hmac.sublist(0, 4),
        orderedEquals(const [0xB0, 0x34, 0x4C, 0x61]),
      );
      expect(
        hmac.sublist(28, 32),
        orderedEquals(const [0x2E, 0x32, 0xCF, 0xF7]),
      );
    });

    test(
      'encrypts snapshot with zero plaintext on disk, detects tampering, '
      'binds server URL AAD, and wipes cleanly',
      () async {
        final dir = Directory.systemTemp.createTempSync('granapaca_cache_test_');
        addTearDown(() => dir.deleteSync(recursive: true));

        final fileStorage = FileCacheStorage(dir);
        final key = Uint8List.fromList(List.generate(32, (i) => (i * 7 + 3) & 0xFF));
        final store = EncryptedCacheStore(storage: fileStorage, masterKey: key);

        const serverUrl = 'https://toca.exemplo.local';
        final snapshot = CachedSnapshot(
          serverUrl: serverUrl,
          lastSyncedAt: DateTime(2026, 3, 28, 9, 45),
          syncCursor: 'cursor-seq-42',
          banks: const [Bank('aurora', 'Banco Aurora')],
          accounts: const [
            Account(
              id: 'aurora-cc',
              bankId: 'aurora',
              name: 'Conta corrente',
              kind: AccountKind.checking,
              openingBalanceCents: 2594281,
            ),
          ],
          transactions: [
            Transaction(
              id: 10,
              accountId: 'aurora-cc',
              date: DateTime(2026, 3, 27),
              description: 'Farmácia Vida Plena',
              amountCents: -6420,
              kind: TxKind.expense,
              category: SpendingCategory.health,
              essentiality: Essentiality.essential,
            ),
          ],
          bills: [
            CachedCardBill(
              accountId: 'aurora-card',
              year: 2026,
              month: 3,
              closingDate: DateTime(2026, 3, 28),
              dueDate: DateTime(2026, 4, 10),
              totalCents: 198380,
              isOpen: true,
            ),
          ],
          connections: [
            BankConnectionInfo(
              id: 'aurora',
              provider: 'pluggy',
              externalItemId: 'item-1',
              institutionName: 'Banco Aurora',
              brandColor: '#8B3E05',
              status: BankConnectionStatus.upToDate,
              lastSyncedAt: DateTime(2026, 3, 28, 9, 45),
            ),
          ],
        );

        await store.saveSnapshot(snapshot);
        final rawBytes1 = await store.readRawCiphertext();
        expect(rawBytes1, isNotNull);

        // Raw bytes on disk MUST NEVER contain plaintext financial data.
        final rawLatin1 = latin1.decode(rawBytes1!);
        expect(rawLatin1.contains('Banco Aurora'), isFalse);
        expect(rawLatin1.contains('Farmácia'), isFalse);
        expect(rawLatin1.contains('2594281'), isFalse);
        expect(rawLatin1.contains('cursor-seq-42'), isFalse);

        // Roundtrip decrypts cleanly with matching server URL.
        final restored = await store.loadSnapshot(expectedServerUrl: serverUrl);
        expect(restored, isNotNull);
        expect(restored!.syncCursor, 'cursor-seq-42');
        expect(restored.banks.single.name, 'Banco Aurora');
        expect(restored.transactions.single.description, 'Farmácia Vida Plena');
        expect(restored.bills.single.totalCents, 198380);

        // Second write uses a fresh nonce -> different ciphertext.
        await store.saveSnapshot(snapshot);
        final rawBytes2 = await store.readRawCiphertext();
        expect(rawBytes2, isNotNull);
        expect(PureCrypto.constantTimeEquals(rawBytes1, rawBytes2!), isFalse);

        // Different server URL fails associated-data MAC verification.
        await expectLater(
          store.loadSnapshot(expectedServerUrl: 'https://outro.exemplo.local'),
          throwsA(isA<CacheIntegrityException>()),
        );

        // Tampering with a single ciphertext byte fails MAC verification.
        final tampered = Uint8List.fromList(rawBytes2);
        tampered[25] ^= 0x01;
        await fileStorage.writeBytes(EncryptedCacheStore.snapshotKey, tampered);
        await expectLater(
          store.loadSnapshot(expectedServerUrl: serverUrl),
          throwsA(isA<CacheIntegrityException>()),
        );

        // Wiping removes the snapshot completely.
        await store.wipe();
        expect(await store.loadSnapshot(expectedServerUrl: serverUrl), isNull);
      },
    );
  });

  group('GranaPaCaApiClient & Auth/Sync flows (RF-01, RF-02, RF-03, RF-12, RF-21)', () {
    test('RF-01 validates server-info, translates errors to pt-BR, and wipes cache on server switch', () async {
      final storage = InMemoryCacheStorage();
      final cache = EncryptedCacheStore(storage: storage);
      final prefs = InMemoryPreferencesStore();

      var serverMode = 'network_error';
      final transport = _FakeHttpTransport((req) async {
        if (req.uri.path == '/api/v1/server-info') {
          if (serverMode == 'network_error') {
            throw const HttpTransportException(
              kind: HttpTransportErrorKind.network,
              message: 'socket closed',
            );
          }
          if (serverMode == 'not_granapaca') {
            return HttpTransportResponse(
              statusCode: 200,
              body: jsonEncode({'app': 'OutroApp', 'apiVersion': 1}),
            );
          }
          return HttpTransportResponse(
            statusCode: 200,
            body: jsonEncode({
              'app': 'GranaPaCa',
              'version': '0.2.0',
              'apiVersion': 1,
              'ownerConfigured': true,
              'providerMode': 'pluggy',
            }),
          );
        }
        return const HttpTransportResponse(statusCode: 204, body: '');
      });

      final client = GranaPaCaApiClient(transport: transport);
      final state = AppState(
        preferencesStore: prefs,
        apiClient: client,
        encryptedCache: cache,
      );

      // Network failure -> human-friendly pt-BR message, URL NOT saved.
      await expectLater(
        state.validateAndConnectServer('https://servidor-a.local'),
        throwsA(
          isA<ApiException>().having(
            (e) => e.message,
            'message',
            allOf(
              contains('Não conseguimos alcançar'),
              isNot(contains('SocketException')),
            ),
          ),
        ),
      );
      expect(prefs.readServerUrl(), isNull);

      // Wrong app -> friendly rejection, URL NOT saved.
      serverMode = 'not_granapaca';
      await expectLater(
        state.validateAndConnectServer('https://servidor-a.local'),
        throwsA(
          isA<ApiException>().having(
            (e) => e.code,
            'code',
            'not_granapaca_server',
          ),
        ),
      );
      expect(prefs.readServerUrl(), isNull);

      // Valid server A -> saved.
      serverMode = 'ok';
      final infoA = await state.validateAndConnectServer(
        'https://servidor-a.local',
      );
      expect(infoA.app, 'GranaPaCa');
      expect(prefs.readServerUrl(), 'https://servidor-a.local');

      // Write cached snapshot for server A and set an active session.
      client.setTokens(
        AuthTokens(
          accessToken: 'tok-a-1',
          refreshToken: 'ref-a-1',
          expiresAt: DateTime(2026, 3, 29),
          sessionId: 'sess-a',
          owner: const OwnerSummary(
            id: 'own-1',
            householdId: 'hh-1',
            email: 'bia@demo.local',
            displayName: 'Bia',
          ),
        ),
      );
      await cache.saveSnapshot(
        CachedSnapshot(
          serverUrl: 'https://servidor-a.local',
          lastSyncedAt: DateTime(2026, 3, 28, 10, 0),
          banks: const [Bank('b1', 'Banco A')],
          accounts: const [],
          transactions: const [],
        ),
      );
      expect(await cache.readRawCiphertext(), isNotNull);

      // Switching to server B MUST end session AND wipe previous server's cache!
      await state.validateAndConnectServer('https://servidor-b.local');
      expect(state.serverUrl, 'https://servidor-b.local');
      expect(state.isAuthenticated, isFalse);
      expect(await cache.readRawCiphertext(), isNull);
    });

    test('ADR-019 / RF-03 rotates tokens automatically on 401 and retries once', () async {
      var connectionsCalls = 0;
      final transport = _FakeHttpTransport((req) async {
        if (req.uri.path == '/api/v1/connections') {
          connectionsCalls++;
          if (req.headers['Authorization'] == 'Bearer expired-access') {
            return const HttpTransportResponse(statusCode: 401, body: '{}');
          }
          expect(req.headers['Authorization'], 'Bearer fresh-access');
          return HttpTransportResponse(
            statusCode: 200,
            body: jsonEncode({
              'items': [
                {
                  'id': 'conn-1',
                  'provider': 'pluggy',
                  'externalItemId': 'item-1',
                  'institutionName': 'Banco Aurora',
                  'brandColor': '#8B3E05',
                  'status': 'up_to_date',
                },
              ],
            }),
          );
        }
        if (req.uri.path == '/api/v1/auth/refresh') {
          return HttpTransportResponse(
            statusCode: 200,
            body: jsonEncode({
              'status': 'authenticated',
              'accessToken': 'fresh-access',
              'refreshToken': 'fresh-refresh',
              'expiresAt': '2026-03-29T12:00:00Z',
              'sessionId': 'sess-1',
              'owner': {
                'id': 'own-1',
                'householdId': 'hh-1',
                'email': 'bia@demo.local',
                'displayName': 'Bia',
              },
            }),
          );
        }
        return const HttpTransportResponse(statusCode: 404, body: '{}');
      });

      final client = GranaPaCaApiClient(
        transport: transport,
        baseUrl: Uri.parse('https://toca.local'),
        initialTokens: AuthTokens(
          accessToken: 'expired-access',
          refreshToken: 'old-refresh',
          expiresAt: DateTime(2026, 3, 28),
          sessionId: 'sess-1',
          owner: const OwnerSummary(
            id: 'own-1',
            householdId: 'hh-1',
            email: 'bia@demo.local',
            displayName: 'Bia',
          ),
        ),
      );

      final conns = await client.fetchConnections();
      expect(connectionsCalls, 2);
      expect(conns.single.institutionName, 'Banco Aurora');
      expect(client.tokens?.accessToken, 'fresh-access');
      expect(client.tokens?.refreshToken, 'fresh-refresh');
    });

    testWidgets(
      'RF-01 + RF-02 + RF-03 complete UI flow: server validation -> owner setup -> '
      'login -> mandatory TOTP enrollment -> 8 recovery codes -> app -> logout',
      (tester) async {
        var ownerConfigured = false;
        final transport = _FakeHttpTransport((req) async {
          switch (req.uri.path) {
            case '/api/v1/server-info':
              return HttpTransportResponse(
                statusCode: 200,
                body: jsonEncode({
                  'app': 'GranaPaCa',
                  'version': '0.2.0',
                  'apiVersion': 1,
                  'ownerConfigured': ownerConfigured,
                  'providerMode': 'pluggy',
                }),
              );
            case '/api/v1/auth/setup':
              ownerConfigured = true;
              return HttpTransportResponse(
                statusCode: 201,
                body: jsonEncode({
                  'ownerId': 'own-1',
                  'householdId': 'hh-1',
                  'email': 'bia@exemplo.local',
                  'displayName': 'Bia',
                }),
              );
            case '/api/v1/auth/login':
              return HttpTransportResponse(
                statusCode: 200,
                body: jsonEncode({
                  'status': 'totp_setup_required',
                  'pendingToken': 'pend-123',
                }),
              );
            case '/api/v1/auth/totp/setup':
              return HttpTransportResponse(
                statusCode: 200,
                body: jsonEncode({
                  'manualKey': 'JBSWY3DPEHPK3PXP',
                  'otpauthUri':
                      'otpauth://totp/GranaPaCa:bia@exemplo.local?secret=JBSWY3DPEHPK3PXP&issuer=GranaPaCa',
                }),
              );
            case '/api/v1/auth/totp/confirm':
              return HttpTransportResponse(
                statusCode: 200,
                body: jsonEncode({
                  'status': 'authenticated',
                  'accessToken': 'acc-1',
                  'refreshToken': 'ref-1',
                  'expiresAt': '2026-03-29T12:00:00Z',
                  'sessionId': 'sess-1',
                  'owner': {
                    'id': 'own-1',
                    'householdId': 'hh-1',
                    'email': 'bia@exemplo.local',
                    'displayName': 'Bia',
                  },
                  'recoveryCodes': const [
                    'AAAA-1111',
                    'BBBB-2222',
                    'CCCC-3333',
                    'DDDD-4444',
                    'EEEE-5555',
                    'FFFF-6666',
                    'GGGG-7777',
                    'HHHH-8888',
                  ],
                }),
              );
            case '/api/v1/sync/changes':
              return HttpTransportResponse(
                statusCode: 200,
                body: jsonEncode({
                  'nextCursor': 'cur-1',
                  'hasMore': false,
                  'syncedAt': '2026-03-28T10:30:00Z',
                  'banks': const [],
                  'accounts': const [],
                  'transactions': const [],
                  'connections': const [],
                }),
              );
            case '/api/v1/auth/logout':
              return const HttpTransportResponse(statusCode: 204, body: '');
            default:
              return const HttpTransportResponse(statusCode: 404, body: '{}');
          }
        });

        final client = GranaPaCaApiClient(transport: transport);
        await tester.pumpWidget(
          GranaPaCaApp(
            apiClient: client,
            startInServerAuth: true,
          ),
        );
        await tester.pumpAndSettle();

        // Step 1: Server validation
        await tester.enterText(
          find.byKey(const Key('server_url_field')),
          'https://minha-toca.local',
        );
        await tester.tap(find.byKey(const Key('server_validate_button')));
        await tester.pumpAndSettle();

        // Step 2: Owner Setup (RF-02)
        expect(find.text('Primeiro acesso da instância'), findsOneWidget);
        await tester.enterText(find.byKey(const Key('setup_name_field')), 'Bia');
        await tester.enterText(
          find.byKey(const Key('setup_email_field')),
          'bia@exemplo.local',
        );
        await tester.enterText(
          find.byKey(const Key('setup_password_field')),
          'Caju!Verde#2026',
        );
        await tester.enterText(
          find.byKey(const Key('setup_confirm_password_field')),
          'Caju!Verde#2026',
        );
        final setupSubmit = find.byKey(const Key('setup_owner_submit_button'));
        await _scrollTo(tester, setupSubmit);
        await tester.tap(setupSubmit);
        await tester.pumpAndSettle();

        // Step 3: Login -> triggers mandatory TOTP setup
        expect(find.text('Entrar na sua instância'), findsOneWidget);
        final loginBtn = find.byKey(const Key('login_submit_button'));
        await _scrollTo(tester, loginBtn);
        await tester.tap(loginBtn);
        await tester.pumpAndSettle();

        // Step 4A: Mandatory TOTP setup (QR Code + Base32 key)
        expect(find.text('Ative o autenticador (2FA obrigatório)'), findsOneWidget);
        expect(find.byKey(const Key('totp_qr_code')), findsOneWidget);
        expect(find.text('JBSWY3DPEHPK3PXP'), findsOneWidget);
        final totpCodeField = find.byKey(const Key('totp_confirm_code_field'));
        await _scrollTo(tester, totpCodeField);
        await tester.enterText(totpCodeField, '654321');
        final confirmBtn = find.byKey(const Key('totp_confirm_button'));
        await _scrollTo(tester, confirmBtn);
        await tester.tap(confirmBtn);
        await tester.pumpAndSettle();

        // Step 4B: 8 recovery codes shown; continue disabled until checkbox checked
        expect(find.text('Guarde seus códigos de recuperação'), findsOneWidget);
        expect(find.text('AAAA-1111'), findsOneWidget);
        expect(find.text('HHHH-8888'), findsOneWidget);

        final continueBtn = find.byKey(
          const Key('recovery_codes_continue_button'),
        );
        await _scrollTo(tester, continueBtn);
        expect(
          tester.widget<FilledButton>(continueBtn).onPressed,
          isNull,
        );

        await tester.tap(
          find.byKey(const Key('recovery_codes_saved_checkbox')),
        );
        await tester.pumpAndSettle();
        await tester.tap(continueBtn);
        await tester.pumpAndSettle();

        // Entered app in server mode (no demo banner!)
        expect(find.textContaining('Modo demonstração'), findsNothing);
        expect(client.isAuthenticated, isTrue);

        // Navigate to Ajustes and sign out (RF-03)
        final navTarget = find.text('Ajustes').last;
        await tester.tap(navTarget);
        await tester.pumpAndSettle();

        final logoutBtn = find.byKey(const Key('settings_logout_button'));
        await _scrollTo(tester, logoutBtn);
        await tester.tap(logoutBtn);
        await tester.pumpAndSettle();
        expect(client.isAuthenticated, isFalse);
      },
    );

    testWidgets(
      'RF-21 offline mode loads cached data with last-sync date and blocks transaction editing',
      (tester) async {
        final cache = EncryptedCacheStore(storage: InMemoryCacheStorage());
        const serverUrl = 'https://toca.exemplo.local';
        final lastSync = DateTime(2026, 3, 28, 14, 20);

        // Pre-populate encrypted cache as if synced earlier.
        await cache.saveSnapshot(
          CachedSnapshot(
            serverUrl: serverUrl,
            lastSyncedAt: lastSync,
            syncCursor: 'cursor-10',
            banks: const [Bank('aurora', 'Banco Aurora')],
            accounts: const [
              Account(
                id: 'aurora-cc',
                bankId: 'aurora',
                name: 'Conta corrente',
                kind: AccountKind.checking,
                openingBalanceCents: 100000,
              ),
            ],
            transactions: [
              Transaction(
                id: 77,
                accountId: 'aurora-cc',
                date: DateTime(2026, 3, 27),
                description: 'Mercado Offline Teste',
                amountCents: -4500,
                kind: TxKind.expense,
                category: SpendingCategory.food,
                essentiality: Essentiality.essential,
              ),
            ],
          ),
        );

        final offlineTransport = _FakeHttpTransport((_) async {
          throw const HttpTransportException(
            kind: HttpTransportErrorKind.network,
            message: 'offline',
          );
        });
        final client = GranaPaCaApiClient(
          transport: offlineTransport,
          baseUrl: Uri.parse(serverUrl),
        );

        // Restore cached dataset into AppState in offline server mode.
        final snapshot = await cache.loadSnapshot(expectedServerUrl: serverUrl);
        expect(snapshot, isNotNull);

        await tester.pumpWidget(
          GranaPaCaApp(
            dataset: snapshot!.toDataset(),
            apiClient: client,
            encryptedCache: cache,
            initialMode: AppMode.server,
            initialServerUrl: serverUrl,
            initialOffline: true,
            initialLastSyncedAt: lastSync,
          ),
        );
        await tester.pumpAndSettle();

        // Offline banner with DD/MM às HH:mm is displayed!
        expect(
          find.textContaining('Sem conexão com o servidor · última sincronização em 28/03 às 14:20'),
          findsOneWidget,
        );
        // Cached transaction is visible in Extrato.
        await tester.tap(find.text('Extrato').last);
        await tester.pumpAndSettle();
        expect(find.text('Mercado Offline Teste'), findsOneWidget);

        // Attempting to edit while offline shows clear pt-BR warning and refuses edit!
        await tester.tap(find.text('Mercado Offline Teste'));
        await tester.pumpAndSettle();

        final sheetScrollable = find.byType(Scrollable).last;
        final warning = find.byKey(const Key('tx_offline_edit_warning'));
        await _scrollTo(tester, warning, scrollable: sheetScrollable);
        expect(
          find.text(AppState.offlineEditBlockedMessage),
          findsOneWidget,
        );

        final lazerChip = find.byKey(const Key('cat_choice_leisure'));
        await _scrollTo(tester, lazerChip, scrollable: sheetScrollable);
        await tester.tap(lazerChip);
        await tester.pumpAndSettle();

        final saveBtn = find.byKey(const Key('save_correction_button'));
        await _scrollTo(tester, saveBtn, scrollable: sheetScrollable);
        await tester.tap(saveBtn);
        await tester.pumpAndSettle();

        // SnackBar warning appears and NO adjustment was recorded.
        expect(
          find.text(AppState.offlineEditBlockedMessage),
          findsWidgets,
        );
        expect(
          find.text('Nenhum ajuste manual registrado nesta transação.'),
          findsOneWidget,
        );
      },
    );
  });

  group('RF-04 App Lock (PIN, Biometrics fallback, Inactivity & 5-attempt lockout)', () {
    test('stores only salted hash, locks after inactivity timeout, and supports biometric fallback', () async {
      var now = DateTime(2026, 3, 28, 10, 0, 0);
      final bio = _FakeBiometricAuthenticator(
        available: true,
        nextResult: BiometricAuthResult.cancelled,
      );
      var lockoutCalled = false;

      final lock = AppLockController(
        biometricAuthenticator: bio,
        clock: () => now,
        inactivityTimeout: const Duration(minutes: 2),
        hashIterations: 100,
        onLockoutSessionCleared: () => lockoutCalled = true,
      );

      await lock.configurePin('135790', enableBiometric: true);
      expect(lock.isEnabled, isTrue);
      expect(lock.hasPin, isTrue);
      // Plaintext PIN is NEVER stored.
      expect(lock.storedPinHash, isNotNull);
      expect(lock.storedPinHash!.contains('135790'), isFalse);
      expect(lock.storedPinHash!.contains(':'), isTrue);

      // Short background pause (60s < 2min) does NOT lock.
      lock.handleLifecycleState(AppLifecycleState.paused);
      now = now.add(const Duration(seconds: 60));
      lock.handleLifecycleState(AppLifecycleState.resumed);
      expect(lock.isLocked, isFalse);

      // Long background pause (>= 2min) locks automatically.
      lock.handleLifecycleState(AppLifecycleState.paused);
      now = now.add(const Duration(minutes: 2, seconds: 1));
      lock.handleLifecycleState(AppLifecycleState.resumed);
      expect(lock.isLocked, isTrue);

      // Biometric cancel leaves locked so user falls back to PIN.
      final cancelRes = await lock.tryBiometricUnlock();
      expect(cancelRes, BiometricAuthResult.cancelled);
      expect(lock.isLocked, isTrue);

      // Biometric success unlocks cleanly.
      bio.nextResult = BiometricAuthResult.authenticated;
      final okRes = await lock.tryBiometricUnlock();
      expect(okRes, BiometricAuthResult.authenticated);
      expect(lock.isLocked, isFalse);

      // Device without biometrics falls back cleanly to PIN.
      bio.available = false;
      lock.lockNow();
      expect(await lock.tryBiometricUnlock(), BiometricAuthResult.unavailable);
      expect(lock.verifyPin('135790'), isTrue);
      expect(lock.isLocked, isFalse);
      expect(lockoutCalled, isFalse);
    });

    testWidgets(
      '5 consecutive wrong PIN attempts on AppLockScreen clear active session and force re-login',
      (tester) async {
        final lock = AppLockController(hashIterations: 50);
        await lock.configurePin('246810');
        lock.lockNow();

        final client = GranaPaCaApiClient(
          baseUrl: Uri.parse('https://toca.local'),
          initialTokens: AuthTokens(
            accessToken: 'active-token',
            refreshToken: 'active-refresh',
            expiresAt: DateTime(2026, 3, 29),
            sessionId: 'sess-lock',
            owner: const OwnerSummary(
              id: 'own-1',
              householdId: 'hh-1',
              email: 'bia@exemplo.local',
              displayName: 'Bia',
            ),
          ),
        );

        await tester.pumpWidget(
          GranaPaCaApp(
            apiClient: client,
            appLock: lock,
            initialMode: AppMode.server,
            initialServerUrl: 'https://toca.local',
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byType(AppLockScreen), findsOneWidget);
        expect(client.isAuthenticated, isTrue);

        // Attempts 1..4 show remaining attempts warning.
        for (var attempt = 1; attempt <= 4; attempt++) {
          await _tapPinDigits(tester, '000000');
          final remaining = 5 - attempt;
          expect(
            find.textContaining('Restam $remaining'),
            findsOneWidget,
          );
          expect(client.isAuthenticated, isTrue);
        }

        // 5th consecutive failed attempt clears the session and routes to login!
        await _tapPinDigits(tester, '000000');
        expect(client.isAuthenticated, isFalse);
        expect(find.byType(ServerAuthScreen), findsOneWidget);
        expect(find.byKey(const Key('session_cleared_notice')), findsOneWidget);
      },
    );
  });

  group('RF-12, RF-13, RF-14 ConnectionsScreen', () {
    testWidgets(
      'renders all 4 status badges, <=30d renewal warning, guided Meu Pluggy steps '
      'with zero bank password fields, and empty sync checklist',
      (tester) async {
        final refNow = DateTime(2026, 3, 28, 12, 0);
        final transport = _FakeHttpTransport((req) async {
          if (req.uri.path == '/api/v1/connections/sync') {
            return HttpTransportResponse(
              statusCode: 200,
              body: jsonEncode({
                'connectionsProcessed': 0,
                'accountsSynced': 0,
                'transactionsInserted': 0,
                'transactionsVersioned': 0,
                'transactionsRemoved': 0,
                'transfersLinked': 0,
                'failedConnections': 0,
                'message': 'Nenhuma conexão bancária encontrada.',
              }),
            );
          }
          if (req.uri.path == '/api/v1/connections') {
            return HttpTransportResponse(
              statusCode: 200,
              body: jsonEncode({'items': const []}),
            );
          }
          if (req.uri.path == '/api/v1/sync/changes') {
            return HttpTransportResponse(
              statusCode: 200,
              body: jsonEncode({
                'nextCursor': 'c1',
                'hasMore': false,
                'syncedAt': '2026-03-28T12:00:00Z',
              }),
            );
          }
          return const HttpTransportResponse(statusCode: 200, body: '{}');
        });

        final client = GranaPaCaApiClient(
          transport: transport,
          baseUrl: Uri.parse('https://toca.local'),
          initialTokens: AuthTokens(
            accessToken: 'tok-conn',
            refreshToken: 'ref-conn',
            expiresAt: DateTime(2026, 3, 29),
            sessionId: 's1',
            owner: const OwnerSummary(
              id: 'o1',
              householdId: 'h1',
              email: 'bia@exemplo.local',
              displayName: 'Bia',
            ),
          ),
        );

        final sampleConnections = [
          BankConnectionInfo(
            id: 'c-up',
            provider: 'pluggy',
            externalItemId: 'item-up',
            institutionName: 'Banco Siriema',
            brandColor: '#2A7550',
            status: BankConnectionStatus.upToDate,
            lastSyncedAt: DateTime(2026, 3, 28, 8, 15),
            consentExpiresAt: DateTime(2026, 6, 20),
          ),
          BankConnectionInfo(
            id: 'c-delayed',
            provider: 'pluggy',
            externalItemId: 'item-delayed',
            institutionName: 'Banco Aurora',
            brandColor: '#8B3E05',
            status: BankConnectionStatus.delayed,
            lastSyncedAt: DateTime(2026, 3, 27, 8, 15),
            consentExpiresAt: DateTime(2026, 4, 12), // 15 days <= 30d!
            expiringSoon: true,
          ),
          BankConnectionInfo(
            id: 'c-err',
            provider: 'pluggy',
            externalItemId: 'item-err',
            institutionName: 'Banco Ipê',
            brandColor: '#6E4AA3',
            status: BankConnectionStatus.error,
            lastSyncedAt: DateTime(2026, 3, 26, 8, 0),
          ),
          BankConnectionInfo(
            id: 'c-exp',
            provider: 'pluggy',
            externalItemId: 'item-exp',
            institutionName: 'Banco Tucano',
            brandColor: '#22649C',
            status: BankConnectionStatus.expired,
            lastSyncedAt: DateTime(2026, 3, 20, 8, 0),
            consentExpiresAt: DateTime(2026, 3, 21),
          ),
        ];

        final state = AppState(
          apiClient: client,
          initialMode: AppMode.server,
          initialServerUrl: 'https://toca.local',
          initialConnections: sampleConnections,
        );

        await tester.pumpWidget(
          AppScope(
            state: state,
            child: MaterialApp(
              home: ConnectionsScreen(clock: () => refNow),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Prominent renewal warning banner for <=30d & expired connections (RF-14)
        expect(
          find.byKey(const Key('connections_expiry_warning_banner')),
          findsOneWidget,
        );
        expect(find.textContaining('Banco Aurora'), findsWidgets);

        // All 4 status badges rendered
        expect(find.text('Em dia'), findsOneWidget);
        expect(find.text('Atrasada'), findsOneWidget);
        await _scrollTo(tester, find.text('Com erro'));
        expect(find.text('Com erro'), findsOneWidget);
        await _scrollTo(tester, find.text('Vencida'));
        expect(find.text('Vencida'), findsOneWidget);

        // Guided 3-step Meu Pluggy flow with ZERO bank password inputs (RF-12)
        final pluggyCard = find.byKey(const Key('meu_pluggy_guided_card'));
        await _scrollTo(tester, pluggyCard);
        expect(find.textContaining('meu.pluggy.ai'), findsWidgets);
        expect(
          find.textContaining('nunca pede a senha do seu banco'),
          findsOneWidget,
        );
        expect(find.textContaining('Senha do banco'), findsNothing);

        // Tapping "Já conectei" when sync finds 0 connections displays empty checklist!
        final alreadyBtn = find.byKey(
          const Key('connections_already_connected_button'),
        );
        await _scrollTo(tester, alreadyBtn);
        await tester.tap(alreadyBtn);
        await tester.pumpAndSettle();

        final checklist = find.byKey(const Key('empty_sync_checklist'));
        await _scrollTo(tester, checklist);
        expect(
          find.text('Ainda não encontramos bancos novos'),
          findsOneWidget,
        );
      },
    );
  });

  group('RF-31 Dedicated Review Queue ("A revisar") & "Sem categoria" in charts', () {
    testWidgets('shows friendly "Tudo classificado" empty state when queue is empty', (
      tester,
    ) async {
      final state = AppState(); // Demo dataset has all spending categorized.

      await tester.pumpWidget(
        AppScope(
          state: state,
          child: const MaterialApp(home: ReviewQueueScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('A revisar'), findsOneWidget);
      expect(find.textContaining('Tudo classificado'), findsOneWidget);
    });

    testWidgets(
      'groups uncategorized merchants with count, classifies & creates rule via '
      '"Aplicar às semelhantes", and renders "Sem categoria" in Gastos charts',
      (tester) async {
        final dataset = _datasetWithUncategorized();

        // First verify Gastos displays "Sem categoria" in BOTH Donut and Ranking!
        await tester.pumpWidget(GranaPaCaApp(dataset: dataset));
        await tester.pumpAndSettle();

        await _tapTab(tester, 'Gastos');

        expect(
          find.byKey(const Key('donut_legend_uncategorized')),
          findsOneWidget,
        );
        expect(find.text('Sem categoria'), findsWidgets);
        final uncatRank = find.byKey(const Key('ranking_row_uncategorized'));
        await _scrollTo(
          tester,
          uncatRank,
          scrollable: find.byType(Scrollable).first,
        );
        expect(uncatRank, findsOneWidget);

        // Open Extrato -> tap Review Queue banner ("A revisar")
        await _tapTab(tester, 'Extrato');

        final banner = find.byKey(const Key('history_open_review_queue'));
        expect(banner, findsOneWidget);
        await tester.tap(banner);
        await tester.pumpAndSettle();

        // Grouped by normalized merchant: Café da Praça (2 transações) + Banca do Largo (1)
        expect(find.text('2 transações'), findsOneWidget);
        expect(find.text('1 transação'), findsOneWidget);

        // Classify Café da Praça -> Alimentação + Flexível -> Aplicar às semelhantes!
        await tester.tap(find.byKey(const Key('review_group_cafe da praca')));
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('review_cat_food')));
        await tester.tap(find.byKey(const Key('review_ess_flexible')));
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('review_save_button')));
        await tester.pumpAndSettle();

        expect(find.text('Aplicar às semelhantes?'), findsOneWidget);
        await tester.tap(find.byKey(const Key('review_apply_similar_button')));
        await tester.pumpAndSettle();

        // Entire Café da Praça group (both transactions!) removed from queue!
        expect(find.byKey(const Key('review_group_cafe da praca')), findsNothing);
        expect(find.byKey(const Key('review_group_banca do largo')), findsOneWidget);

        // Classify last group -> empty state "Tudo classificado por aqui!"
        await tester.tap(find.byKey(const Key('review_group_banca do largo')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('review_cat_leisure')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('review_save_button')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('review_only_this_button')));
        await tester.pumpAndSettle();

        expect(find.textContaining('Tudo classificado'), findsOneWidget);
      },
    );

    test(
      'RF-21 incremental cursor delta sync applies additions/removals and persists encrypted cache, '
      'and RF-03 lists/revokes sessions',
      () async {
        final cache = EncryptedCacheStore(storage: InMemoryCacheStorage());
        var syncStep = 0;
        var sessions = [
          {
            'id': 'sess-current',
            'deviceName': 'Linux Desktop',
            'createdAt': '2026-03-28T08:00:00Z',
            'expiresAt': '2026-04-27T08:00:00Z',
            'isCurrent': true,
          },
          {
            'id': 'sess-phone',
            'deviceName': 'Celular Android',
            'createdAt': '2026-03-27T08:00:00Z',
            'expiresAt': '2026-04-26T08:00:00Z',
            'isCurrent': false,
          },
        ];

        final transport = _FakeHttpTransport((req) async {
          if (req.uri.path == '/api/v1/sync/changes') {
            syncStep++;
            if (syncStep == 1) {
              expect(req.uri.queryParameters['cursor'], isNull);
              return HttpTransportResponse(
                statusCode: 200,
                body: jsonEncode({
                  'nextCursor': 'cur-001',
                  'hasMore': false,
                  'syncedAt': '2026-03-28T10:00:00Z',
                  'banks': [
                    {'id': 'b-1', 'name': 'Banco Aurora', 'brandColor': '#8B3E05'},
                  ],
                  'accounts': [
                    {
                      'id': 'acc-1',
                      'bankId': 'b-1',
                      'name': 'Conta corrente',
                      'kind': 'checking',
                      'openingBalanceCents': 50000,
                    },
                  ],
                  'transactions': [
                    {
                      'id': 101,
                      'accountId': 'acc-1',
                      'occurredOn': '2026-03-25',
                      'description': 'Padaria Central',
                      'amountCents': -1500,
                      'kind': 'expense',
                      'category': 'food',
                    },
                    {
                      'id': 102,
                      'accountId': 'acc-1',
                      'occurredOn': '2026-03-26',
                      'description': 'Compra removida depois',
                      'amountCents': -2000,
                      'kind': 'expense',
                    },
                  ],
                }),
              );
            }
            expect(req.uri.queryParameters['cursor'], 'cur-001');
            return HttpTransportResponse(
              statusCode: 200,
              body: jsonEncode({
                'nextCursor': 'cur-002',
                'hasMore': false,
                'syncedAt': '2026-03-28T11:30:00Z',
                'transactions': [
                  {
                    'id': 103,
                    'accountId': 'acc-1',
                    'occurredOn': '2026-03-28',
                    'description': 'Mercado Novo',
                    'amountCents': -4200,
                    'kind': 'expense',
                    'category': 'food',
                  },
                ],
                'removedTransactionIds': [102],
              }),
            );
          }
          if (req.uri.path == '/api/v1/auth/sessions' && req.method == 'GET') {
            return HttpTransportResponse(
              statusCode: 200,
              body: jsonEncode(sessions),
            );
          }
          if (req.uri.path == '/api/v1/auth/sessions/sess-phone' &&
              req.method == 'DELETE') {
            sessions = sessions
                .where((s) => s['id'] != 'sess-phone')
                .toList();
            return const HttpTransportResponse(statusCode: 204, body: '');
          }
          return const HttpTransportResponse(statusCode: 404, body: '{}');
        });

        final client = GranaPaCaApiClient(
          transport: transport,
          baseUrl: Uri.parse('https://toca.local'),
          initialTokens: AuthTokens(
            accessToken: 'tok-sync',
            refreshToken: 'ref-sync',
            expiresAt: DateTime(2026, 3, 29),
            sessionId: 'sess-current',
            owner: const OwnerSummary(
              id: 'o1',
              householdId: 'h1',
              email: 'bia@exemplo.local',
              displayName: 'Bia',
            ),
          ),
        );

        final state = AppState(
          apiClient: client,
          encryptedCache: cache,
          initialMode: AppMode.server,
          initialServerUrl: 'https://toca.local',
        );

        // First sync loads initial snapshot + cursor cur-001.
        expect(await state.syncFromServer(), isTrue);
        expect(state.syncCursor, 'cur-001');
        expect(state.originalDataset.transactions.length, 2);

        // Second sync sends cursor=cur-001, adds tx 103, removes tx 102, updates cursor=cur-002.
        expect(await state.syncFromServer(), isTrue);
        expect(state.syncCursor, 'cur-002');
        expect(
          state.originalDataset.transactions.map((t) => t.id).toSet(),
          {101, 103},
        );

        // Encrypted cache matches latest delta state.
        final cached = await cache.loadSnapshot(
          expectedServerUrl: 'https://toca.local',
        );
        expect(cached?.syncCursor, 'cur-002');
        expect(cached?.transactions.map((t) => t.id).toSet(), {101, 103});

        // Sessions list & revoke.
        final listed = await state.loadActiveSessions();
        expect(listed.length, 2);
        await state.revokeActiveSession('sess-phone');
        expect(state.activeSessions.length, 1);
        expect(state.activeSessions.single.id, 'sess-current');
      },
    );
  });
}
