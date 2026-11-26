import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:granapaca/api/api_models.dart';
import 'package:granapaca/api/granapaca_api_client.dart';
import 'package:granapaca/api/http_transport.dart';
import 'package:granapaca/demo/demo_data.dart';
import 'package:granapaca/finance/model.dart';
import 'package:granapaca/finance/planning_queries.dart';
import 'package:granapaca/finance/queries.dart';
import 'package:granapaca/finance/taxonomy.dart';
import 'package:granapaca/main.dart';
import 'package:granapaca/screens/cash_entry_sheet.dart';
import 'package:granapaca/screens/spending_analytics_widgets.dart';
import 'package:granapaca/state/app_state.dart';
import 'package:granapaca/storage/cache_storage_base.dart';
import 'package:granapaca/storage/encrypted_cache.dart';
import 'package:granapaca/theme/grana_theme.dart';

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
  final targetScrollable = scrollable ?? find.byType(Scrollable).first;
  await tester.scrollUntilVisible(
    finder,
    250,
    scrollable: targetScrollable,
  );
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
}

const _sampleNfceXml = '''
<NFe>
  <infNFe Id="NFe32260300000000000000650010000001231000000123">
    <ide><dhEmi>2026-03-27T10:15:00-03:00</dhEmi></ide>
    <emit><xNome>Supermercado Exemplo Ficticio LTDA</xNome></emit>
    <det nItem="1"><prod><xProd>Arroz Integral 5kg</xProd><qCom>1.00</qCom><vProd>28.90</vProd></prod></det>
    <det nItem="2"><prod><xProd>Detergente Neutro 500ml</xProd><qCom>2.00</qCom><vProd>7.50</vProd></prod></det>
    <det nItem="3"><prod><xProd>Chocolate Amargo 100g</xProd><qCom>1.00</qCom><vProd>12.60</vProd></prod></det>
    <total><ICMSTot><vNF>49.00</vNF></ICMSTot></total>
  </infNFe>
</NFe>''';

// Fictitious 44-digit ES NFC-e access key (UF 32 = ES, year/month 2603, zeroed digits).
const _sampleEsQrUrl =
    'https://app.sefaz.es.gov.br/ConsultaNFCe/?p=32260300000000000000650010000001231000000123|2|1|1|123456';

void main() {
  group('Wave 3 Pure Finance & Planning Engine', () {
    test('validates exact-cent transaction splits (RN-24, ADR-013) and splits categoryRanking', () {
      const validSplits = [
        TxSplit(
          id: 's1',
          description: 'Mercado',
          amountCents: 6000,
          category: SpendingCategory.food,
          essentiality: Essentiality.essential,
        ),
        TxSplit(
          id: 's2',
          description: 'Limpeza',
          amountCents: 4000,
          category: SpendingCategory.housing,
          essentiality: Essentiality.essential,
        ),
      ];
      expect(validateSplitTotal(-10000, validSplits), isTrue);
      expect(splitRemainingCents(-10000, validSplits), 0);

      // Off by 1 cent MUST fail RN-24.
      const invalidSplits = [
        TxSplit(id: 's1', description: 'Parte 1', amountCents: 6000),
        TxSplit(id: 's2', description: 'Parte 2', amountCents: 3999),
      ];
      expect(validateSplitTotal(-10000, invalidSplits), isFalse);
      expect(splitRemainingCents(-10000, invalidSplits), 1);
      expect(validateSplitTotal(-10000, const []), isFalse);

      // Category ranking allocates exact split cents across categories.
      final tx = Transaction(
        id: 1,
        accountId: 'aurora-cc',
        date: DateTime(2026, 3, 15),
        description: 'Compra mista',
        amountCents: -10000,
        kind: TxKind.expense,
        category: SpendingCategory.food,
        essentiality: Essentiality.essential,
        splits: validSplits,
      );
      final ranking = categoryRanking([tx]);
      expect(ranking.length, 2);
      expect(ranking[0].category, SpendingCategory.food);
      expect(ranking[0].cents, 6000);
      expect(ranking[1].category, SpendingCategory.housing);
      expect(ranking[1].cents, 4000);
    });

    test('computes dailySpendingHeatmap, fiftyThirtyTwenty, monthComparison, projection excluding atypical, and detectSubscriptions', () {
      final demo = demoDataset();
      final march = DateTime(2026, 3);

      // Heatmap covers all 31 days of March with empty days = 0 and active days in 1..5.
      final cells = dailySpendingHeatmap(demo.transactions, march);
      expect(cells.length, 31);
      expect(cells.any((c) => c.intensity == 0), isTrue);
      expect(cells.any((c) => c.intensity == 5), isTrue);
      expect(
        cells.every((c) => c.intensity >= 0 && c.intensity <= 5),
        isTrue,
      );
      expect(
        cells.fold(0, (s, c) => s + c.spentCents),
        summary(demo, march).spentCents,
      );

      // 50/30/20: Needs = Essencial, Wants = Importante + Flexível, Savings = leftover.
      final rule = fiftyThirtyTwenty(demo.transactions, march);
      expect(rule.incomeCents, 705000);
      expect(rule.savingsCents, 288182);
      expect(rule.needsCents + rule.wantsCents, 416818);
      expect(
        rule.needsShare + rule.wantsShare + rule.savingsShare,
        closeTo(1.0, 1e-9),
      );

      // Month-over-month comparison compares March vs February.
      final cmp = monthComparison(demo.transactions, march);
      expect(cmp.currentMonth, DateTime(2026, 3));
      expect(cmp.previousMonth, DateTime(2026, 2));
      expect(cmp.currentSpentCents, 416818);
      expect(cmp.previousSpentCents, greaterThan(0));
      expect(cmp.deltaCents, cmp.currentSpentCents - cmp.previousSpentCents);
      expect(cmp.categoryDeltas, isNotEmpty);

      // End-of-month projection excludes atypical expenses from daily run-rate!
      final withAtypical = [
        Transaction(
          id: 1,
          accountId: 'a',
          date: DateTime(2026, 3, 5),
          description: 'Mercado regular',
          amountCents: -100000,
          kind: TxKind.expense,
        ),
        Transaction(
          id: 2,
          accountId: 'a',
          date: DateTime(2026, 3, 8),
          description: 'Conserto emergencial atípico',
          amountCents: -500000,
          kind: TxKind.expense,
          isAtypical: true,
        ),
      ];
      final proj = projectMonthEndSpending(
        withAtypical,
        march,
        DateTime(2026, 3, 15),
      );
      expect(proj.regularSpentCents, 100000);
      expect(proj.atypicalSpentCents, 500000);
      expect(proj.atypicalCount, 1);
      // 100000 * 31 / 15 = 206667 (atypical R$ 5.000 NOT multiplied by 31/15!)
      expect(proj.projectedRegularCents, (100000 * 31 / 15).round());
      expect(proj.projectedTotalCents, proj.projectedRegularCents + 500000);

      // Subscription detector identifies monthly services and skips multi-visit / installments.
      final subs = detectSubscriptions(demo.transactions);
      final subNames = subs.map((s) => s.displayName).toSet();
      expect(subNames, contains('Streaming Cine+'));
      expect(subNames, contains('Internet Fibra Lar'));
      expect(subNames, contains('Academia Movimento'));
      expect(subNames, isNot(contains('Padaria Pão de Ontem')));
      expect(subNames, isNot(contains('Notebook Loja Byte')));
    });

    test('parses NFC-e XML and ES SEFAZ QR URL, reconciles exact splits, exports RFC 4180 CSV / JSON, and parses OFX/CSV imports', () {
      // NFC-e XML parsing
      final xmlRes = parseNfceInput(_sampleNfceXml);
      expect(xmlRes.sourceType, 'nfce_xml');
      expect(xmlRes.issuerName, 'Supermercado Exemplo Ficticio LTDA');
      expect(xmlRes.totalCents, 4900);
      expect(xmlRes.items.length, 3);
      expect(xmlRes.items[0].description, 'Arroz Integral 5kg');
      expect(xmlRes.items[0].amountCents, 2890);
      expect(xmlRes.items[0].suggestedCategory, SpendingCategory.food);
      expect(xmlRes.items[1].suggestedCategory, SpendingCategory.housing);
      expect(xmlRes.items[2].suggestedEssentiality, Essentiality.flexible);

      // Reconciles exact cents against transaction total (even with discount/difference).
      final splitsExact = receiptItemsToSplits(xmlRes.items, -4900);
      expect(validateSplitTotal(-4900, splitsExact), isTrue);
      final splitsAdjusted = receiptItemsToSplits(xmlRes.items, -5000);
      expect(validateSplitTotal(-5000, splitsAdjusted), isTrue);
      final splitsDiscounted = receiptItemsToSplits(xmlRes.items, -4500);
      expect(validateSplitTotal(-4500, splitsDiscounted), isTrue);

      // ES SEFAZ QR URL parsing
      final qrRes = parseNfceInput(_sampleEsQrUrl);
      expect(qrRes.sourceType, 'nfce_qr_url');
      expect(qrRes.accessKey, '32260300000000000000650010000001231000000123');
      expect(qrRes.issuerName, contains('ES'));
      expect(qrRes.issuerName, contains('sefaz.es.gov.br'));

      // RFC 4180 CSV & JSON backup
      final state = AppState();
      final csv = buildTransactionsCsv(
        state.effectiveTransactions,
        state.effectiveDataset,
      );
      expect(csv, contains('\r\n'));
      expect(csv, startsWith('Data,Descrição,Descrição original,'));
      expect(csv, contains('Padaria Pão de Ontem'));

      final backupStr = buildBackupJson(
        dataset: state.effectiveDataset,
        rules: state.rules,
        adjustments: state.adjustments,
        budgets: state.budgets,
        goals: state.goals,
        alertRules: state.spendingAlertRules,
        modeLabel: 'demo',
      );
      final decoded = jsonDecode(backupStr) as Map<String, dynamic>;
      expect(decoded['app'], 'GranaPaCa');
      expect((decoded['transactions'] as List).length, 72);
      expect((decoded['budgets'] as List).length, 3);
      expect((decoded['goals'] as List).length, 2);

      // Statement OFX & CSV parsing
      const sampleOfx = '''
<OFX><BANKMSGSRSV1><STMTTRNRS><STMTRS><BANKTRANLIST>
<STMTTRN><TRNTYPE>DEBIT<DTPOSTED>20260326<TRNAMT>-45.90<MEMO>Mercado Bairro</STMTTRN>
<STMTTRN><TRNTYPE>CREDIT<DTPOSTED>20260327<TRNAMT>150.00<NAME>Reembolso Viagem</STMTTRN>
</BANKTRANLIST></STMTRS></STMTTRNRS></BANKMSGSRSV1></OFX>''';
      final ofxTxs = parseStatementImport(sampleOfx, accountId: 'aurora-cc');
      expect(ofxTxs.length, 2);
      expect(ofxTxs[0].amountCents, -4590);
      expect(ofxTxs[0].description, 'Mercado Bairro');
      expect(ofxTxs[1].amountCents, 15000);
      expect(ofxTxs[1].kind, TxKind.income);

      const sampleCsv = 'data,descricao,valor\n2026-03-26,Cafe Central,-12.50';
      final csvTxs = parseStatementImport(sampleCsv, accountId: 'aurora-cc');
      expect(csvTxs.length, 1);
      expect(csvTxs.single.amountCents, -1250);
    });

    test('parses natural-language spending alert rules and fires real in-app alert when exceeded', () {
      final state = AppState();
      final initialUnread = state.unreadAlertCount;

      final parsedDelivery = parseSpendingAlertRule(
        'me avise quando delivery passar de R\$ 300',
      );
      expect(parsedDelivery, isNotNull);
      expect(parsedDelivery!.keyword, 'delivery');
      expect(parsedDelivery.thresholdCents, 30000);

      // In demo March 2026, Alimentação spending is ~R$ 1.006 -> threshold R$ 500 triggers!
      final rule = state.addSpendingAlertRuleFromText(
        'me avise quando alimentação passar de R\$ 500',
      );
      expect(rule, isNotNull);
      expect(rule!.category, SpendingCategory.food);
      expect(state.unreadAlertCount, initialUnread + 1);
      expect(
        state.alerts.first.title,
        contains('Alimentação'),
      );
    });

    test(
      'offline cash quick-entry persists outbox in encrypted cache, sends clientMutationId, deduplicates on sync and rejects 4xx (RF-44)',
      () async {
        const cashUuid = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
        const serverUrl = 'https://toca.local';
        var cashPosted = false;
        String? sentClientMutationId;

        final transport = _FakeHttpTransport((req) async {
          if (req.uri.path == '/api/v1/transactions/cash' &&
              req.method == 'POST') {
            final body = jsonDecode(req.body!) as Map<String, dynamic>;
            if (body['description'] == 'ERRO_400') {
              return HttpTransportResponse(
                statusCode: 400,
                body: jsonEncode({
                  'title': 'Lançamento em dinheiro inválido',
                  'detail': 'Descrição rejeitada pelo servidor.',
                  'code': 'invalid_cash_transaction',
                }),
              );
            }
            cashPosted = true;
            sentClientMutationId = body['clientMutationId'] as String?;
            expect(body['description'], 'Feira orgânica');
            expect(body['amountCents'], -3500);
            expect(body['kind'], 'expense');
            expect(sentClientMutationId, isNotNull);
            expect(sentClientMutationId, isNotEmpty);
            return HttpTransportResponse(
              statusCode: 201,
              body: jsonEncode({
                'id': cashUuid,
                'accountId': AppState.cashAccountId,
                'occurredOn': '2026-03-28',
                'description': 'Feira orgânica',
                'amountCents': -3500,
                'kind': 'expense',
                'paymentMethod': 'cash',
                'tags': const ['feira'],
              }),
            );
          }
          if (req.uri.path == '/api/v1/sync/changes') {
            return HttpTransportResponse(
              statusCode: 200,
              body: jsonEncode({
                'nextCursor': 'cur-cash-1',
                'isFullSync': false,
                'serverTime': '2026-03-28T15:00:00Z',
                'connections': const [],
                'accounts': const [],
                'transactions': [
                  {
                    'id': cashUuid,
                    'accountId': AppState.cashAccountId,
                    'occurredOn': '2026-03-28',
                    'description': 'Feira orgânica',
                    'amountCents': -3500,
                    'kind': 'expense',
                    'paymentMethod': 'cash',
                    'tags': const ['feira'],
                  },
                ],
              }),
            );
          }
          return const HttpTransportResponse(statusCode: 200, body: '{}');
        });

        AuthTokens sampleTokens() => AuthTokens(
          accessToken: 'tok-cash',
          refreshToken: 'ref-cash',
          expiresAt: DateTime(2026, 3, 29),
          sessionId: 's-cash',
          owner: const OwnerSummary(
            id: 'o1',
            householdId: 'h1',
            email: 'bia@demo.local',
            displayName: 'Bia',
          ),
        );

        final cacheStorage = InMemoryCacheStorage();
        final keyStorage = InMemoryCacheStorage();
        final cache1 = EncryptedCacheStore(
          storage: cacheStorage,
          keyStorage: keyStorage,
        );
        final client1 = GranaPaCaApiClient(
          transport: transport,
          baseUrl: Uri.parse(serverUrl),
          initialTokens: sampleTokens(),
        );

        final state1 = AppState(
          apiClient: client1,
          encryptedCache: cache1,
          initialMode: AppMode.server,
          initialServerUrl: serverUrl,
          initialOffline: true,
        );

        // Offline cash quick-entry succeeds immediately and persists in encrypted cache.
        final created = await state1.addCashTransaction(
          description: 'Feira orgânica',
          amountCents: 3500,
          date: DateTime(2026, 3, 28),
          category: SpendingCategory.food,
          essentiality: Essentiality.essential,
          tags: const ['feira'],
        );
        expect(created.pendingSync, isTrue);
        expect(created.paymentMethod, PaymentMethod.cash);
        expect(created.tags, contains('feira'));
        expect(state1.pendingOutboxCount, 1);
        expect(cashPosted, isFalse);

        // Simulate cold restart from the same encrypted cache before reconnect.
        final cache2 = EncryptedCacheStore(
          storage: cacheStorage,
          keyStorage: keyStorage,
        );
        final client2 = GranaPaCaApiClient(
          transport: transport,
          baseUrl: Uri.parse(serverUrl),
          initialTokens: sampleTokens(),
        );
        final state2 = AppState(
          apiClient: client2,
          encryptedCache: cache2,
          initialMode: AppMode.server,
          initialServerUrl: serverUrl,
          initialOffline: true,
        );
        expect(await state2.restoreFromEncryptedCache(), isTrue);
        expect(state2.pendingOutboxCount, 1);

        // Reconnecting & syncing flushes outbox, replaces synthetic localId with
        // server UUID and never duplicates when delta returns the same UUID.
        expect(await state2.syncFromServer(), isTrue);
        expect(cashPosted, isTrue);
        expect(state2.pendingOutboxCount, 0);
        final matching = state2.effectiveTransactions
            .where((t) => t.description == 'Feira orgânica')
            .toList();
        expect(matching.length, 1);
        expect(matching.first.pendingSync, isFalse);
        expect(state2.transactionUuidFor(matching.first.id), cashUuid);

        // Validation HTTP 400 must throw and NEVER enqueue into outbox.
        await expectLater(
          () => state2.addCashTransaction(
            description: 'ERRO_400',
            amountCents: 1200,
            date: DateTime(2026, 3, 28),
          ),
          throwsA(isA<ApiException>()),
        );
        expect(state2.pendingOutboxCount, 0);
      },
    );

    test(
      'Paçoca calls /api/v1/assistant/chat with backend #63 schema and cites exact numbers locally in demo mode',
      () async {
        // Demo deterministic Q&A
        final demo = demoDataset();
        final reply = answerFinancialQuestion(
          'Quanto sobrou este mês?',
          demo,
          DateTime(2026, 3),
        );
        expect(reply.periodLabel, 'Março 2026');
        expect(reply.text, contains(r'R$ 2.881,82'));
        expect(reply.text, contains(r'R$ 4.168,18'));
        expect(reply.citedFigures, isNotEmpty);

        // Server mode calls /api/v1/assistant/chat with {message, month}
        var assistantCalled = false;
        final transport = _FakeHttpTransport((req) async {
          if (req.uri.path == '/api/v1/assistant/chat' &&
              req.method == 'POST') {
            assistantCalled = true;
            final body = jsonDecode(req.body!) as Map<String, dynamic>;
            expect(body['message'], 'Quanto sobrou?');
            expect(body['month'], '2026-03');
            expect(body.containsKey('question'), isFalse);
            return HttpTransportResponse(
              statusCode: 200,
              body: jsonEncode({
                'messageId': 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
                'content':
                    'Resposta do servidor: saldo de R\$ 1.000,00 em Março 2026.',
                'periodUsed': '2026-03',
                'numbersCited': const [
                  {
                    'label': 'Saldo',
                    'amountCents': 100000,
                    'formatted': r'R$ 1.000,00',
                  },
                ],
                'providerUsed': 'none',
                'pseudonymized': false,
                'createdAt': '2026-03-28T15:00:00Z',
              }),
            );
          }
          return const HttpTransportResponse(statusCode: 404, body: '{}');
        });

        final client = GranaPaCaApiClient(
          transport: transport,
          baseUrl: Uri.parse('https://toca.local'),
          initialTokens: AuthTokens(
            accessToken: 'tok-ai',
            refreshToken: 'ref-ai',
            expiresAt: DateTime(2026, 3, 29),
            sessionId: 's-ai',
            owner: const OwnerSummary(
              id: 'o1',
              householdId: 'h1',
              email: 'bia@demo.local',
              displayName: 'Bia',
            ),
          ),
        );

        final serverState = AppState(
          apiClient: client,
          initialMode: AppMode.server,
          initialServerUrl: 'https://toca.local',
        );
        final serverReply = await serverState.askAssistant(
          'Quanto sobrou?',
          month: DateTime(2026, 3),
        );
        expect(assistantCalled, isTrue);
        expect(serverReply.id, 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb');
        expect(serverReply.text, contains('Resposta do servidor'));
        expect(serverReply.periodLabel, '2026-03');
        expect(serverReply.citedFigures, contains(r'Saldo: R$ 1.000,00'));
      },
    );

    test(
      'aligns Wave 3 server contracts (UUIDs, signed parts, snake_case adjustments, Planning CRUD, RF-21 offline lock, Receipts/Imports/Export)',
      () async {
        const txUuid = '11111111-1111-4111-8111-111111111111';
        const budgetUuid = '22222222-2222-4222-8222-222222222222';
        const goalUuid = '33333333-3333-4333-8333-333333333333';
        const alertUuid = '44444444-4444-4444-8444-444444444444';
        final calledPaths = <String>[];

        final transport = _FakeHttpTransport((req) async {
          calledPaths.add('${req.method} ${req.uri.path}');
          if (req.uri.path == '/api/v1/sync/changes') {
            return HttpTransportResponse(
              statusCode: 200,
              body: jsonEncode({
                'nextCursor': 'cur-1',
                'isFullSync': true,
                'serverTime': '2026-03-28T12:00:00Z',
                'connections': [
                  {
                    'id': 'conn-1',
                    'institutionName': 'Banco Aurora',
                    'status': 'connected',
                  },
                ],
                'accounts': [
                  {
                    'id': 'acct-1',
                    'connectionId': 'conn-1',
                    'name': 'Conta Corrente',
                    'kind': 'checking',
                    'openingBalanceCents': 500000,
                  },
                ],
                'transactions': [
                  {
                    'id': txUuid,
                    'accountId': 'acct-1',
                    'occurredOn': '2026-03-20',
                    'description': 'Supermercado Bairro',
                    'amountCents': -10000,
                    'kind': 'expense',
                    'category': 'food',
                    'essentiality': 'essential',
                  },
                ],
              }),
            );
          }
          if (req.method == 'POST' &&
              req.uri.path == '/api/v1/transactions/$txUuid/adjustments') {
            final body = jsonDecode(req.body!) as Map<String, dynamic>;
            expect(body['paymentMethod'], 'pix');
            expect(body['isAtypical'], isTrue);
            return HttpTransportResponse(
              statusCode: 200,
              body: jsonEncode({
                'appliedAdjustments': [
                  {
                    'id': 'srv-adj-pm',
                    'transactionId': txUuid,
                    'fieldName': 'payment_method',
                    'oldValue': 'debit',
                    'newValue': 'pix',
                    'createdAt': '2026-03-28T12:05:00Z',
                  },
                  {
                    'id': 'srv-adj-atyp',
                    'transactionId': txUuid,
                    'fieldName': 'is_atypical',
                    'oldValue': 'false',
                    'newValue': 'true',
                    'createdAt': '2026-03-28T12:05:00Z',
                  },
                ],
              }),
            );
          }
          if (req.method == 'PUT' &&
              req.uri.path == '/api/v1/transactions/$txUuid/tags') {
            final body = jsonDecode(req.body!) as Map<String, dynamic>;
            expect(body['tags'], ['mercado']);
            return const HttpTransportResponse(statusCode: 200, body: '{}');
          }
          if (req.method == 'PUT' &&
              req.uri.path == '/api/v1/transactions/$txUuid/splits') {
            final body = jsonDecode(req.body!) as Map<String, dynamic>;
            expect(body.containsKey('parts'), isTrue);
            expect(body.containsKey('splits'), isFalse);
            final parts = body['parts'] as List<dynamic>;
            expect(parts.length, 2);
            expect((parts[0] as Map)['amountCents'], -6000);
            expect((parts[1] as Map)['amountCents'], -4000);
            return const HttpTransportResponse(statusCode: 200, body: '{}');
          }
          if (req.method == 'POST' &&
              req.uri.path == '/api/v1/transactions/bulk-adjustments') {
            final body = jsonDecode(req.body!) as Map<String, dynamic>;
            expect(body['transactionIds'], [txUuid]);
            return HttpTransportResponse(
              statusCode: 200,
              body: jsonEncode({'updatedCount': 1, 'adjustmentsInserted': 1}),
            );
          }
          if (req.method == 'PUT' && req.uri.path == '/api/v1/planning/budgets') {
            final body = jsonDecode(req.body!) as Map<String, dynamic>;
            expect(body['category'], 'food');
            expect(body['monthLimitCents'], 120000);
            expect(body['alertThresholdPercent'], 80);
            return HttpTransportResponse(
              statusCode: 200,
              body: jsonEncode({
                'id': budgetUuid,
                'category': 'food',
                'monthLimitCents': 120000,
                'alertThresholdPercent': 80,
                'isActive': true,
              }),
            );
          }
          if (req.method == 'POST' && req.uri.path == '/api/v1/planning/goals') {
            return HttpTransportResponse(
              statusCode: 201,
              body: jsonEncode({
                'id': goalUuid,
                'name': 'Reserva',
                'targetCents': 500000,
                'currentCents': 100000,
              }),
            );
          }
          if (req.method == 'PATCH' &&
              req.uri.path == '/api/v1/planning/goals/$goalUuid') {
            final body = jsonDecode(req.body!) as Map<String, dynamic>;
            expect(body['addCents'], 50000);
            return HttpTransportResponse(
              statusCode: 200,
              body: jsonEncode({
                'id': goalUuid,
                'name': 'Reserva',
                'targetCents': 500000,
                'currentCents': 150000,
              }),
            );
          }
          if (req.method == 'POST' &&
              req.uri.path == '/api/v1/planning/alert-rules') {
            final body = jsonDecode(req.body!) as Map<String, dynamic>;
            expect(body['expression'], contains('delivery'));
            expect(body['limitCents'], 30000);
            expect(body['merchantKeyword'], 'delivery');
            return HttpTransportResponse(
              statusCode: 201,
              body: jsonEncode({
                'id': alertUuid,
                'expression': body['expression'],
                'merchantKeyword': 'delivery',
                'limitCents': 30000,
                'isActive': true,
              }),
            );
          }
          if (req.method == 'DELETE' &&
              (req.uri.path == '/api/v1/planning/budgets/$budgetUuid' ||
                  req.uri.path == '/api/v1/planning/goals/$goalUuid' ||
                  req.uri.path == '/api/v1/planning/alert-rules/$alertUuid')) {
            return const HttpTransportResponse(statusCode: 204, body: '');
          }
          if (req.method == 'PUT' && req.uri.path == '/api/v1/receipts/consent') {
            final body = jsonDecode(req.body!) as Map<String, dynamic>;
            expect(body['itemAnalysisAccepted'], isTrue);
            return const HttpTransportResponse(statusCode: 200, body: '{}');
          }
          if (req.method == 'POST' &&
              req.uri.path == '/api/v1/receipts/nfce/parse') {
            final body = jsonDecode(req.body!) as Map<String, dynamic>;
            expect(body['xml'], contains('<NFe>'));
            expect(body['transactionId'], txUuid);
            expect(body['save'], isTrue);
            return const HttpTransportResponse(statusCode: 200, body: '{"saved":true}');
          }
          if (req.method == 'POST' && req.uri.path == '/api/v1/imports/csv') {
            final body = jsonDecode(req.body!) as Map<String, dynamic>;
            expect(body['institutionName'], 'Banco Aurora');
            expect(body['accountName'], 'Conta Corrente');
            expect(body['accountKind'], 'checking');
            return const HttpTransportResponse(
              statusCode: 200,
              body: '{"inserted":2}',
            );
          }
          if (req.method == 'GET' &&
              req.uri.path == '/api/v1/export/transactions.csv') {
            return const HttpTransportResponse(
              statusCode: 200,
              body: 'Data,Descrição\r\n',
            );
          }
          if (req.method == 'GET' &&
              req.uri.path == '/api/v1/export/backup.json') {
            return const HttpTransportResponse(
              statusCode: 200,
              body: '{"version":1}',
            );
          }
          return const HttpTransportResponse(statusCode: 404, body: '{}');
        });

        final client = GranaPaCaApiClient(
          transport: transport,
          baseUrl: Uri.parse('https://toca.local'),
          initialTokens: AuthTokens(
            accessToken: 'tok-c',
            refreshToken: 'ref-c',
            expiresAt: DateTime(2026, 3, 29),
            sessionId: 's-c',
            owner: const OwnerSummary(
              id: 'o1',
              householdId: 'h1',
              email: 'bia@demo.local',
              displayName: 'Bia',
            ),
          ),
        );

        final state = AppState(
          apiClient: client,
          encryptedCache: EncryptedCacheStore(
            storage: InMemoryCacheStorage(),
            keyStorage: InMemoryCacheStorage(),
          ),
          initialMode: AppMode.server,
          initialServerUrl: 'https://toca.local',
        );

        expect(await state.syncFromServer(), isTrue);
        final txId = stableTransactionId(txUuid);

        // 1) Adjustments (payment_method + is_atypical + tags)
        state.adjustTransaction(
          txId: txId,
          paymentMethod: PaymentMethod.pix,
          changePaymentMethod: true,
          isAtypical: true,
          changeAtypical: true,
          tags: const ['mercado'],
          changeTags: true,
        );
        await state.flushPendingMutations();
        final adjFields = state.adjustmentsFor(txId).map((a) => a.field).toSet();
        expect(adjFields, contains(AdjustmentField.paymentMethod));
        expect(adjFields, contains(AdjustmentField.atypical));

        // 2) Splits (signed negative parts)
        expect(
          state.replaceSplits(txId, const [
            TxSplit(description: 'Alimentos', amountCents: 6000),
            TxSplit(description: 'Limpeza', amountCents: 4000),
          ]),
          isTrue,
        );
        await state.flushPendingMutations();

        // 3) Bulk adjustments (UUID)
        expect(
          state.applyBulkAdjustments(
            txIds: {txId},
            category: SpendingCategory.shopping,
            changeCategory: true,
          ),
          1,
        );
        await state.flushPendingMutations();

        // 4) Planning CRUD
        state.upsertBudget(
          category: SpendingCategory.food,
          limitCents: 120000,
        );
        await state.flushPendingMutations();
        expect(state.budgets.single.id, budgetUuid);

        state.addGoal(
          name: 'Reserva',
          targetCents: 500000,
          currentCents: 100000,
        );
        await state.flushPendingMutations();
        expect(state.goals.single.id, goalUuid);

        state.contributeToGoal(goalUuid, 50000);
        await state.flushPendingMutations();
        expect(state.goals.single.currentCents, 150000);

        state.addSpendingAlertRuleFromText(
          'me avise quando delivery passar de R\$ 300',
        );
        await state.flushPendingMutations();
        expect(state.spendingAlertRules.single.id, alertUuid);

        state.deleteBudget(budgetUuid);
        state.deleteGoal(goalUuid);
        state.deleteSpendingAlertRule(alertUuid);
        await state.flushPendingMutations();
        expect(state.budgets, isEmpty);
        expect(state.goals, isEmpty);
        expect(state.spendingAlertRules, isEmpty);

        // 5) Receipts consent, NFC-e parse, CSV import & singular exports
        state.acceptReceiptConsent();
        await state.flushPendingMutations();
        await client.submitNfceReceipt(
          rawInput: '<NFe></NFe>',
          transactionId: txUuid,
        );
        await client.importStatement(
          format: 'csv',
          content: '2026-03-20,Teste,-10.00',
          institutionName: 'Banco Aurora',
          accountName: 'Conta Corrente',
        );
        expect(await client.exportTransactionsCsv(), contains('Data,Descrição'));
        expect(await client.exportBackupJson(), '{"version":1}');

        expect(
          calledPaths,
          containsAll([
            'POST /api/v1/transactions/$txUuid/adjustments',
            'PUT /api/v1/transactions/$txUuid/tags',
            'PUT /api/v1/transactions/$txUuid/splits',
            'POST /api/v1/transactions/bulk-adjustments',
            'PUT /api/v1/planning/budgets',
            'POST /api/v1/planning/goals',
            'PATCH /api/v1/planning/goals/$goalUuid',
            'POST /api/v1/planning/alert-rules',
            'PUT /api/v1/receipts/consent',
            'POST /api/v1/receipts/nfce/parse',
            'POST /api/v1/imports/csv',
            'GET /api/v1/export/transactions.csv',
            'GET /api/v1/export/backup.json',
          ]),
        );

        // 6) RF-21 offline lock blocks Planning mutations
        final offlineState = AppState(
          apiClient: client,
          initialMode: AppMode.server,
          initialServerUrl: 'https://toca.local',
          initialOffline: true,
        );
        offlineState.upsertBudget(
          category: SpendingCategory.food,
          limitCents: 100000,
        );
        expect(offlineState.budgets, isEmpty);
        expect(
          offlineState.addGoal(name: 'Offline', targetCents: 10000),
          isNull,
        );
        expect(
          offlineState.addSpendingAlertRuleFromText(
            'me avise quando delivery passar de R\$ 300',
          ),
          isNull,
        );
      },
    );

    test(
      'CSV export neutralizes formula injection on text cells while keeping numeric Valor (R\$) intact',
      () {
        final dataset = Dataset(
          banks: const [Bank('b1', '=CMD|"/C calc"!A0')],
          accounts: const [
            Account(
              id: 'a1',
              bankId: 'b1',
              name: '+Conta',
              kind: AccountKind.checking,
            ),
          ],
          transactions: [
            Transaction(
              id: 1,
              accountId: 'a1',
              date: DateTime(2026, 3, 25),
              description: '  =HYPERLINK("https://evil.example")',
              amountCents: -12050,
              kind: TxKind.expense,
              category: SpendingCategory.other,
              tags: const ['@macro', '-danger'],
            ),
          ],
          today: DateTime(2026, 3, 28),
        );
        final effective = resolveEffectiveTransactions(
          originals: dataset.transactions,
          rules: const [],
          adjustments: const [],
          accountsById: {'a1': dataset.accounts.first},
        );
        final csv = buildTransactionsCsv(effective, dataset);
        final dataLine = csv.trim().split('\r\n')[1];
        expect(dataLine, contains('"\'  =HYPERLINK(""https://evil.example"")"'));
        expect(dataLine, contains('"\'=CMD|""/C calc""!A0"'));
        expect(dataLine, contains("'+Conta"));
        expect(dataLine, contains("'@macro; -danger"));
        // Numeric Valor (R$) must NOT get a leading apostrophe
        expect(dataLine.endsWith('"-120,50"'), isTrue);
      },
    );

    test(
      'BYOK provider switch clears hasApiKey, sends clearApiKey and strips stale Ollama baseUrl',
      () async {
        final payloads = <Map<String, dynamic>>[];
        final transport = _FakeHttpTransport((req) async {
          if (req.method == 'PUT' && req.uri.path == '/api/v1/assistant/provider') {
            final body = jsonDecode(req.body!) as Map<String, dynamic>;
            payloads.add(body);
            final provider = body['provider'] as String;
            final clearKey = (body['clearApiKey'] as bool?) ?? false;
            final hasNewKey = (body['apiKey'] as String?)?.isNotEmpty == true;
            return HttpTransportResponse(
              statusCode: 200,
              body: jsonEncode({
                'provider': provider,
                'model': body['model'] ?? '',
                'baseUrl': body['baseUrl'],
                'hasApiKey': provider == 'none' || provider == 'ollama'
                    ? false
                    : (hasNewKey || !clearKey),
              }),
            );
          }
          return const HttpTransportResponse(statusCode: 404, body: '{}');
        });

        final client = GranaPaCaApiClient(
          transport: transport,
          baseUrl: Uri.parse('https://toca.local'),
          initialTokens: AuthTokens(
            accessToken: 'tok-byok',
            refreshToken: 'ref-byok',
            expiresAt: DateTime(2026, 3, 29),
            sessionId: 's-byok',
            owner: const OwnerSummary(
              id: 'o1',
              householdId: 'h1',
              email: 'bia@demo.local',
              displayName: 'Bia',
            ),
          ),
        );

        final state = AppState(
          apiClient: client,
          initialMode: AppMode.server,
          initialServerUrl: 'https://toca.local',
        );

        // 1) Configure Ollama with local baseUrl
        await state.updateAiProviderConfig(
          const AiProviderConfig(
            provider: AiProviderKind.ollama,
            model: 'qwen2.5:7b',
            endpointUrl: 'http://ollama:11434',
          ),
        );
        expect(payloads.last['baseUrl'], 'http://ollama:11434');
        expect(state.aiProviderConfig.hasApiKey, isFalse);

        // 2) Switch to OpenAI with key: stale Ollama baseUrl MUST NOT be sent
        await state.updateAiProviderConfig(
          const AiProviderConfig(
            provider: AiProviderKind.openai,
            model: 'gpt-4o-mini',
            endpointUrl: 'http://ollama:11434',
          ),
          apiKey: 'fake-provider-token-for-unit-test',
        );
        expect(payloads.last.containsKey('baseUrl'), isFalse);
        expect(payloads.last['apiKey'], 'fake-provider-token-for-unit-test');
        expect(state.aiProviderConfig.hasApiKey, isTrue);

        // 3) Switch to Google without new key: MUST send clearApiKey: true and reset hasApiKey
        await state.updateAiProviderConfig(
          const AiProviderConfig(
            provider: AiProviderKind.google,
            model: 'gemini-2.5-flash-lite',
          ),
        );
        expect(payloads.last['clearApiKey'], isTrue);
        expect(state.aiProviderConfig.hasApiKey, isFalse);

        // 4) Switch back to none: MUST clear model, endpointUrl and API key
        await state.updateAiProviderConfig(
          const AiProviderConfig(provider: AiProviderKind.none),
        );
        expect(payloads.last['clearApiKey'], isTrue);
        expect(payloads.last['model'], '');
        expect(state.aiProviderConfig.hasApiKey, isFalse);
      },
    );

    test(
      'receiptItemsToSplits maintains exact RN-24 sum under heavy discounts and parseBrlToCents rejects overflow',
      () {
        const heavyItems = [
          ReceiptItem(description: 'Item A', amountCents: 15000),
          ReceiptItem(description: 'Item B', amountCents: 12000),
          ReceiptItem(description: 'Item C', amountCents: 11000),
          ReceiptItem(description: 'Item D', amountCents: 7000),
          ReceiptItem(description: 'Item E', amountCents: 5000),
        ];

        // Heavy discount: sum 50000 -> target 1000
        final discounted = receiptItemsToSplits(heavyItems, -1000);
        expect(validateSplitTotal(-1000, discounted), isTrue);
        expect(discounted.every((s) => s.amountCents > 0), isTrue);

        // Extreme discount: 5 items -> target 6 cents (proportional floors < 1)
        final tiny = receiptItemsToSplits(heavyItems, -6);
        expect(validateSplitTotal(-6, tiny), isTrue);
        expect(tiny.every((s) => s.amountCents >= 1), isTrue);

        // More items than cents: 5 items -> target 3 cents
        final ultraTiny = receiptItemsToSplits(heavyItems, -3);
        expect(validateSplitTotal(-3, ultraTiny), isTrue);
        expect(ultraTiny.length, 3);
        expect(ultraTiny.every((s) => s.amountCents == 1), isTrue);

        // Large values without JS/Web integer overflow
        const largeItems = [
          ReceiptItem(description: 'Equipamento 1', amountCents: 400000000),
          ReceiptItem(description: 'Equipamento 2', amountCents: 300000000),
        ];
        final largeSplits = receiptItemsToSplits(largeItems, -500000000);
        expect(validateSplitTotal(-500000000, largeSplits), isTrue);

        // parseBrlToCents overflow protection
        expect(parseBrlToCents('999999999999999999999,99'), isNull);
        expect(parseBrlToCents('100000000000000000,00'), isNull);
        expect(parseBrlToCents('1.234.567,89'), 123456789);
      },
    );
  });

  group('Wave 3 UI Flows: Cash Entry, Filters, Splits, Bulk Edit', () {
    testWidgets(
      'records cash expense from Quick Actions, filters by Payment Method & Tag, '
      'and runs Bulk Edit in Extrato',
      (tester) async {
        await tester.pumpWidget(const GranaPaCaApp());
        await tester.pumpAndSettle();

        // Open Quick Actions FAB -> Lançar gasto em dinheiro
        await tester.tap(find.byTooltip('Ações rápidas'));
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('quick_action_cash_entry')));
        await tester.pumpAndSettle();

        await tester.enterText(
          find.byKey(const Key('cash_amount_field')),
          '42,50',
        );
        await tester.enterText(
          find.byKey(const Key('cash_description_field')),
          'Feira do Domingo',
        );
        final cashSheetScrollable = find
            .descendant(
              of: find.byType(CashEntrySheet),
              matching: find.byType(Scrollable),
            )
            .first;

        final tagsField = find.byKey(const Key('cash_tags_field'));
        await _scrollTo(
          tester,
          tagsField,
          scrollable: cashSheetScrollable,
        );
        await tester.enterText(tagsField, 'feira, organico');

        final saveCashBtn = find.byKey(const Key('cash_save_button'));
        await _scrollTo(
          tester,
          saveCashBtn,
          scrollable: cashSheetScrollable,
        );
        await tester.tap(saveCashBtn);
        await tester.pumpAndSettle();

        // Go to Extrato -> filter by Payment Method = Dinheiro
        await _tapTab(tester, 'Extrato');
        final filterScrollable = find
            .descendant(
              of: find.byKey(const Key('history_filter_row_scroll')),
              matching: find.byType(Scrollable),
            )
            .first;

        final pmFilterBtn = find.byKey(
          const Key('filter_payment_method_button'),
        );
        await tester.scrollUntilVisible(
          pmFilterBtn,
          200,
          scrollable: filterScrollable,
        );
        await tester.ensureVisible(pmFilterBtn);
        await tester.pumpAndSettle();
        await tester.tap(pmFilterBtn);
        await tester.pumpAndSettle();
        final pmCashTile = find.byKey(const Key('pick_pm_cash'));
        await _scrollTo(
          tester,
          pmCashTile,
          scrollable: find.byType(Scrollable).last,
        );
        await tester.tap(pmCashTile);
        await tester.pumpAndSettle();

        expect(find.text('Feira do Domingo'), findsOneWidget);
        expect(find.text('#feira'), findsOneWidget);

        // Filter by Tag = #feira
        final tagFilterBtn = find.byKey(const Key('filter_tag_button'));
        await tester.scrollUntilVisible(
          tagFilterBtn,
          200,
          scrollable: filterScrollable,
        );
        await tester.ensureVisible(tagFilterBtn);
        await tester.pumpAndSettle();
        await tester.tap(tagFilterBtn);
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('pick_tag_feira')));
        await tester.pumpAndSettle();

        expect(find.text('1 transação'), findsOneWidget);
        expect(find.text('Feira do Domingo'), findsOneWidget);

        // Clear filters and test Bulk Edit on 2 transactions
        await tester.tap(find.byKey(const Key('clear_filters_inline')));
        await tester.pumpAndSettle();

        final bulkModeBtn = find.byKey(const Key('history_bulk_mode_button'));
        await tester.scrollUntilVisible(
          bulkModeBtn,
          200,
          scrollable: filterScrollable,
        );
        await tester.ensureVisible(bulkModeBtn);
        await tester.pumpAndSettle();
        await tester.tap(bulkModeBtn);
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('history_bulk_action_bar')), findsOneWidget);

        final checkboxes = find.byType(Checkbox);
        await tester.tap(checkboxes.at(0));
        await tester.tap(checkboxes.at(1));
        await tester.pumpAndSettle();
        expect(find.text('2 selecionada(s)'), findsOneWidget);

        await tester.tap(find.byKey(const Key('history_bulk_apply_button')));
        await tester.pumpAndSettle();

        // Mark selected as atypical in batch
        await tester.tap(find.byKey(const Key('bulk_atypical_dropdown')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Marcar como atípica').last);
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('bulk_confirm_button')));
        await tester.pumpAndSettle();

        expect(find.text('Atípica'), findsWidgets);
      },
    );

    testWidgets(
      'TransactionDetailSheet edits Payment Method, Tags, Atypical flag, and '
      'validates exact-cent Transaction Splits (RN-24)',
      (tester) async {
        await tester.pumpWidget(const GranaPaCaApp());
        await tester.pumpAndSettle();

        await _tapTab(tester, 'Extrato');
        await tester.tap(find.text('Padaria Pão de Ontem').first);
        await tester.pumpAndSettle();

        final sheetScrollable = find
            .descendant(
              of: find.byType(ListView).last,
              matching: find.byType(Scrollable),
            )
            .first;

        // Change Payment Method -> Pix
        final pixChip = find.byKey(const Key('pm_choice_pix'));
        await _scrollTo(tester, pixChip, scrollable: sheetScrollable);
        await tester.tap(pixChip);
        await tester.pumpAndSettle();

        // Toggle Atypical ON
        final atypicalSwitch = find.byKey(const Key('tx_atypical_switch'));
        await _scrollTo(tester, atypicalSwitch, scrollable: sheetScrollable);
        await tester.tap(atypicalSwitch);
        await tester.pumpAndSettle();

        // Add Tag #trabalho
        final tagInput = find.byKey(const Key('tx_tag_input'));
        await _scrollTo(tester, tagInput, scrollable: sheetScrollable);
        await tester.enterText(tagInput, 'trabalho');
        await tester.tap(find.byKey(const Key('tx_tag_add_button')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('tx_tag_chip_trabalho')), findsOneWidget);

        // Save correction
        final saveBtn = find.byKey(const Key('save_correction_button'));
        await _scrollTo(tester, saveBtn, scrollable: sheetScrollable);
        await tester.tap(saveBtn);
        await tester.pumpAndSettle();

        // Open Split Editor -> make sum off by 1 cent -> Save disabled -> fix -> Save enabled!
        final editSplitsBtn = find.byKey(const Key('tx_edit_splits_button'));
        await _scrollTo(tester, editSplitsBtn, scrollable: sheetScrollable);
        await tester.tap(editSplitsBtn);
        await tester.pumpAndSettle();

        expect(find.text('Soma exata fechada'), findsOneWidget);
        final split0 = find.byKey(const Key('split_amount_0'));
        await tester.enterText(split0, '1,00');
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<FilledButton>(find.byKey(const Key('splits_save_button')))
              .onPressed,
          isNull,
        );

        // Close split dialog, reopen with valid 50/50 split and save!
        await tester.tap(find.text('Cancelar'));
        await tester.pumpAndSettle();

        await tester.tap(editSplitsBtn);
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('splits_save_button')));
        await tester.pumpAndSettle();

        expect(find.textContaining('2 parte(s) registrada(s)'), findsOneWidget);
      },
    );
  });

  group('Wave 3 UI Flows: CalendarHeatmap, Gastos Análise & Planejamento', () {
    testWidgets(
      'CalendarHeatmapWidget renders 5 Caramelo shades, outlined empty days, '
      'accessible semantics, and masks R\$ in hideValues mode',
      (tester) async {
        final month = DateTime(2026, 3);
        final cells = dailySpendingHeatmap(demoDataset().transactions, month);

        Widget buildHeatmap(bool hideValues) => MaterialApp(
          theme: granaLightTheme(),
          home: Scaffold(
            body: SingleChildScrollView(
              child: CalendarHeatmapWidget(
                month: month,
                cells: cells,
                hideValues: hideValues,
              ),
            ),
          ),
        );

        // Normal mode: accessible label contains exact value on spending day.
        await tester.pumpWidget(buildHeatmap(false));
        await tester.pumpAndSettle();
        for (var i = 0; i <= 5; i++) {
          expect(find.byKey(Key('heatmap_legend_level_$i')), findsOneWidget);
        }
        // Day 1 has no spending in demo data -> "sem gastos"
        expect(
          find.bySemanticsLabel('Dia 1 de Março 2026: sem gastos'),
          findsOneWidget,
        );
        // Tap day 8 (Aluguel) -> selected detail shows value.
        await tester.tap(find.byKey(const Key('heatmap_day_8')));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const Key('heatmap_selected_day_detail')),
          findsOneWidget,
        );
        expect(find.textContaining('R\$ 1.6'), findsWidgets);

        // Hide values mode: masks visual value AND semantic label!
        await tester.pumpWidget(buildHeatmap(true));
        await tester.pumpAndSettle();
        expect(
          find.bySemanticsLabel('Dia 8 de Março 2026: valor oculto'),
          findsOneWidget,
        );
        expect(find.textContaining('R\$ 1.6'), findsNothing);
        expect(find.text(r'R$ •••'), findsWidgets);
      },
    );

    testWidgets(
      'Gastos shows Análise (Heatmap, 50/30/20, MoM) and Planejamento '
      '(Budgets, Goals contribution, Subscriptions, Custom NL Spending Alert)',
      (tester) async {
        await tester.pumpWidget(const GranaPaCaApp());
        await tester.pumpAndSettle();

        await _tapTab(tester, 'Gastos');

        // Análise tab cards
        final heatmap = find.byKey(const Key('spending_calendar_heatmap'));
        await _scrollTo(tester, heatmap);
        expect(heatmap, findsOneWidget);

        final rule503020 = find.byKey(const Key('spending_503020_card'));
        await _scrollTo(tester, rule503020);
        expect(find.text('Regra 50 / 30 / 20'), findsOneWidget);

        final momCard = find.byKey(const Key('spending_mom_card'));
        await _scrollTo(tester, momCard);
        expect(find.text('Comparação com o mês anterior'), findsOneWidget);

        // Switch to Planejamento tab
        await tester.tap(find.text('Planejamento'));
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('planning_projection_card')), findsOneWidget);
        expect(find.byKey(const Key('planning_budgets_card')), findsOneWidget);

        // Contribute to Reserva de emergência (R$ 15.000 -> +R$ 3.000 => Concluída!)
        final contributeBtn = find.byKey(
          const Key('goal_contribute_goal-demo-emergency'),
        );
        await _scrollTo(tester, contributeBtn);
        await tester.tap(contributeBtn);
        await tester.pumpAndSettle();

        await tester.enterText(
          find.byKey(const Key('goal_contribution_field')),
          '3000,00',
        );
        await tester.tap(
          find.byKey(const Key('goal_contribution_save_button')),
        );
        await tester.pumpAndSettle();
        expect(find.text('Concluída'), findsOneWidget);

        // Subscriptions detected card
        final subsCard = find.byKey(
          const Key('planning_subscriptions_card'),
        );
        await _scrollTo(tester, subsCard);
        expect(find.text('Streaming Cine+'), findsOneWidget);

        // Custom NL spending alert -> fires real in-app alert!
        final alertInput = find.byKey(const Key('spending_alert_input'));
        await _scrollTo(tester, alertInput);
        await tester.enterText(
          alertInput,
          'me avise quando alimentação passar de R\$ 500',
        );
        await tester.tap(find.byKey(const Key('add_spending_alert_button')));
        await tester.pumpAndSettle();

        expect(find.text('Disparado'), findsOneWidget);
        // Unread alerts badge rose from 2 -> 3!
        expect(find.text('3'), findsOneWidget);
      },
    );
  });

  group('Wave 3 UI Flows: Paçoca Assistant Tab & Receipts/Export Screen', () {
    testWidgets(
      'Paçoca answers demo questions with cited period & exact numbers, shows '
      'BYOK server-only notice, and confirms low-confidence suggestion',
      (tester) async {
        await tester.pumpWidget(const GranaPaCaApp());
        await tester.pumpAndSettle();

        await _tapTab(tester, 'Paçoca');
        expect(find.textContaining('Pergunte à Paçoca'), findsOneWidget);

        // Tap quick prompt -> cites March 2026 & R$ 2.881,82!
        await tester.tap(find.byKey(const Key('assistant_quick_leftover')));
        await tester.pumpAndSettle();
        expect(find.textContaining(r'R$ 2.881,82'), findsWidgets);
        expect(find.text('Período: Março 2026'), findsWidgets);

        // Open BYOK AI provider sheet -> explains server-only in demo mode.
        await tester.tap(
          find.byKey(const Key('assistant_provider_config_button')),
        );
        await tester.pumpAndSettle();
        expect(
          find.byKey(const Key('assistant_byok_demo_notice')),
          findsOneWidget,
        );
        final byokScrollable = find
            .descendant(
              of: find.byKey(const Key('assistant_provider_sheet_scroll')),
              matching: find.byType(Scrollable),
            )
            .first;
        final closeByokBtn = find.byKey(const Key('assistant_byok_close_button'));
        await _scrollTo(tester, closeByokBtn, scrollable: byokScrollable);
        await tester.tap(closeByokBtn);
        await tester.pumpAndSettle();

        // Confirm low-confidence suggestion -> creates rule and removes card!
        final confirmBtn = find.byKey(
          const Key('confirm_suggestion_sugg-demo-1'),
        );
        await tester.scrollUntilVisible(
          confirmBtn,
          -200,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.ensureVisible(confirmBtn);
        await tester.pumpAndSettle();
        await tester.tap(confirmBtn);
        await tester.pumpAndSettle();
        expect(
          find.byKey(const Key('suggestion_card_sugg-demo-1')),
          findsNothing,
        );
      },
    );

    testWidgets(
      'ReceiptsExportScreen requires first-time consent, parses NFC-e XML, '
      'applies exact splits, and generates CSV/JSON export previews',
      (tester) async {
        await tester.pumpWidget(const GranaPaCaApp());
        await tester.pumpAndSettle();

        // Navigate via Settings -> Comprovantes, NFC-e e Exportação
        await _tapTab(tester, 'Ajustes');
        final receiptsTile = find.byKey(const Key('settings_backup'));
        await _scrollTo(tester, receiptsTile);
        await tester.tap(receiptsTile);
        await tester.pumpAndSettle();

        // First-time consent prompt visible; parsing blocked before consent.
        expect(find.byKey(const Key('receipt_consent_card')), findsOneWidget);
        final loadSampleBtn = find.byKey(const Key('nfce_load_sample_button'));
        await _scrollTo(tester, loadSampleBtn);
        await tester.tap(loadSampleBtn);
        await tester.pumpAndSettle();

        final parseBtn = find.byKey(const Key('nfce_parse_button'));
        await _scrollTo(tester, parseBtn);
        await tester.tap(parseBtn);
        await tester.pumpAndSettle();
        final errText = find.byKey(const Key('nfce_error_text'));
        await _scrollTo(tester, errText);
        expect(errText, findsOneWidget);

        // Scroll back up and accept consent -> parse succeeds and previews items!
        final acceptBtn = find.byKey(const Key('receipt_consent_accept_button'));
        await tester.scrollUntilVisible(
          acceptBtn,
          -250,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.ensureVisible(acceptBtn);
        await tester.pumpAndSettle();
        await tester.tap(acceptBtn);
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('receipt_consent_card')), findsNothing);

        await _scrollTo(tester, parseBtn);
        await tester.tap(parseBtn);
        await tester.pumpAndSettle();
        final previewCard = find.byKey(const Key('nfce_preview_card'));
        await _scrollTo(tester, previewCard);
        expect(previewCard, findsOneWidget);
        expect(find.text('Arroz Integral 5kg'), findsOneWidget);

        // Apply parsed items as transaction splits (RN-24)
        final applySplitsBtn = find.byKey(
          const Key('nfce_apply_splits_button'),
        );
        await _scrollTo(tester, applySplitsBtn);
        await tester.tap(applySplitsBtn);
        await tester.pumpAndSettle();
        expect(
          find.textContaining('aplicados como divisão'),
          findsOneWidget,
        );

        // Generate CSV & JSON previews
        final csvBtn = find.byKey(const Key('export_csv_button'));
        await _scrollTo(tester, csvBtn);
        await tester.tap(csvBtn);
        await tester.pumpAndSettle();
        final exportPreview = find.byKey(const Key('export_preview_text'));
        await _scrollTo(tester, exportPreview);
        expect(exportPreview, findsOneWidget);
        expect(find.textContaining('Data,Descrição,'), findsOneWidget);

        final jsonBtn = find.byKey(const Key('export_json_button'));
        await tester.scrollUntilVisible(
          jsonBtn,
          -200,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.tap(jsonBtn);
        await tester.pumpAndSettle();
        expect(find.textContaining('"app": "GranaPaCa"'), findsOneWidget);
      },
    );
  });
}
