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

    test('offline cash quick-entry queues outbox mutation and flushes on syncFromServer (RF-44)', () async {
      var cashPosted = false;
      final transport = _FakeHttpTransport((req) async {
        if (req.uri.path == '/api/v1/transactions/cash' &&
            req.method == 'POST') {
          cashPosted = true;
          final body = jsonDecode(req.body!) as Map<String, dynamic>;
          expect(body['description'], 'Feira orgânica');
          expect(body['amountCents'], -3500);
          expect(body['paymentMethod'], 'cash');
          return HttpTransportResponse(
            statusCode: 201,
            body: jsonEncode({
              'id': 9001,
              'accountId': AppState.cashAccountId,
              'occurredOn': '2026-03-28',
              'description': 'Feira orgânica',
              'amountCents': -3500,
              'kind': 'expense',
              'paymentMethod': 'cash',
              'isCashEntry': true,
            }),
          );
        }
        if (req.uri.path == '/api/v1/sync/changes') {
          return HttpTransportResponse(
            statusCode: 200,
            body: jsonEncode({
              'nextCursor': 'cur-cash-1',
              'hasMore': false,
              'syncedAt': '2026-03-28T15:00:00Z',
              'banks': const [],
              'accounts': const [],
              'transactions': const [],
            }),
          );
        }
        return const HttpTransportResponse(statusCode: 200, body: '{}');
      });

      final client = GranaPaCaApiClient(
        transport: transport,
        baseUrl: Uri.parse('https://toca.local'),
        initialTokens: AuthTokens(
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
        ),
      );

      final state = AppState(
        apiClient: client,
        initialMode: AppMode.server,
        initialServerUrl: 'https://toca.local',
        initialOffline: true,
      );

      // Offline cash quick-entry succeeds immediately and queues an outbox mutation.
      final created = await state.addCashTransaction(
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
      expect(state.pendingOutboxCount, 1);
      expect(cashPosted, isFalse);

      // Reconnecting & syncing flushes outbox and clears pendingSync.
      expect(await state.syncFromServer(), isTrue);
      expect(cashPosted, isTrue);
      expect(state.pendingOutboxCount, 0);
      expect(state.effectiveById(created.id).pendingSync, isFalse);
    });

    test('Paçoca calls /api/v1/assistant/chat in server mode and cites exact numbers locally in demo mode', () async {
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

      // Server mode calls /api/v1/assistant/chat
      var assistantCalled = false;
      final transport = _FakeHttpTransport((req) async {
        if (req.uri.path == '/api/v1/assistant/chat' && req.method == 'POST') {
          assistantCalled = true;
          return HttpTransportResponse(
            statusCode: 200,
            body: jsonEncode({
              'id': 'srv-reply-1',
              'answer': 'Resposta do servidor: saldo de R\$ 1.000,00 em Março 2026.',
              'periodLabel': 'Março 2026',
              'citedFigures': const [r'Saldo: R$ 1.000,00'],
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
      expect(serverReply.text, contains('Resposta do servidor'));
    });
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
