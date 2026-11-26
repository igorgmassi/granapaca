import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

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
import 'package:granapaca/screens/app_lock_screen.dart';
import 'package:granapaca/screens/app_shell.dart';
import 'package:granapaca/screens/cash_entry_sheet.dart';
import 'package:granapaca/screens/local_account_sheet.dart';
import 'package:granapaca/screens/receipts_export_screen.dart';
import 'package:granapaca/security/app_lock.dart';
import 'package:granapaca/state/app_state.dart';
import 'package:granapaca/state/demo_profiles.dart';
import 'package:granapaca/state/preferences_store.dart';
import 'package:granapaca/storage/cache_storage.dart';
import 'package:granapaca/storage/cache_storage_io.dart';
import 'package:granapaca/storage/encrypted_cache.dart';

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

void main() {
  group('AppMode.localDevice — Encrypted On-Device Storage & Backup Loop', () {
    test(
      'persists banks, accounts, transactions, OFX/CSV imports, adjustments, '
      'rules, splits, budgets, goals, alerts, and receipt consent with ZERO '
      'plaintext on disk and restores cleanly after simulated restart',
      () async {
        final dir = Directory.systemTemp.createTempSync('granapaca_local_dev_');
        addTearDown(() => dir.deleteSync(recursive: true));

        final fileStorage = FileCacheStorage(dir);
        final key = Uint8List.fromList(
          List.generate(32, (i) => (i * 11 + 5) & 0xFF),
        );
        final cache = EncryptedCacheStore(storage: fileStorage, masterKey: key);
        final prefs = InMemoryPreferencesStore();

        final state = AppState(
          preferencesStore: prefs,
          encryptedCache: cache,
        );

        // Start clean local device mode with optional initial bank.
        await state.startLocalDeviceMode(
          initialBankName: 'Banco do Bairro',
          initialAccountName: 'Conta principal',
          openingBalanceCents: 250000,
        );

        expect(state.mode, AppMode.localDevice);
        expect(state.isLocalDeviceMode, isTrue);
        expect(state.isDemoMode, isFalse);
        expect(state.isServerMode, isFalse);
        expect(state.isOffline, isFalse);
        expect(state.canEditTransactions, isTrue);
        expect(prefs.readAppMode(), AppMode.localDevice.name);
        // Includes Carteira cash account + Banco do Bairro checking account.
        expect(state.originalDataset.accounts.length, 2);

        // Add a second local account (credit card with last 4 digits).
        final cardAccount = await state.addLocalBankAccount(
          bankName: 'Cooperativa Sol',
          accountName: 'Cartão Sol',
          kind: AccountKind.creditCard,
          lastFourDigits: '9104',
        );
        expect(cardAccount.kind, AccountKind.creditCard);
        expect(cardAccount.lastFourDigits, '9104');

        final checkingAccount = state.originalDataset.accounts.firstWhere(
          (a) => a.kind == AccountKind.checking,
        );

        // Record manual entries with Pix, Crédito, and Dinheiro.
        final pixTx = await state.addManualTransaction(
          description: 'Mercado da Esquina',
          amountCents: 18540,
          date: DateTime(2026, 3, 12),
          accountId: checkingAccount.id,
          paymentMethod: PaymentMethod.pix,
          category: SpendingCategory.food,
          essentiality: Essentiality.essential,
          tags: const ['mercado'],
        );
        expect(pixTx.paymentMethod, PaymentMethod.pix);
        expect(pixTx.amountCents, -18540);

        final cardTx = await state.addManualTransaction(
          description: 'Farmácia Central',
          amountCents: 6420,
          date: DateTime(2026, 3, 14),
          accountId: cardAccount.id,
          paymentMethod: PaymentMethod.credit,
          category: SpendingCategory.health,
          essentiality: Essentiality.essential,
        );
        expect(cardTx.paymentMethod, PaymentMethod.credit);

        // Import OFX and CSV statements directly into local checking account.
        const sampleOfx = '''
<OFX><BANKMSGSRSV1><STMTTRNRS><STMTRS><BANKTRANLIST>
<STMTTRN><TRNTYPE>DEBIT<DTPOSTED>20260318<TRNAMT>-49.90<MEMO>Padaria Pao Quente</STMTTRN>
</BANKTRANLIST></STMTRS></STMTTRNRS></BANKMSGSRSV1></OFX>''';
        const sampleCsv = 'data,descricao,valor\n2026-03-19,Posto Horizonte,-120.00';

        final ofxParsed = parseStatementImport(
          sampleOfx,
          accountId: checkingAccount.id,
        );
        final csvParsed = parseStatementImport(
          sampleCsv,
          accountId: checkingAccount.id,
        );
        expect(state.importStatementTransactions(ofxParsed), 1);
        expect(state.importStatementTransactions(csvParsed), 1);

        // Apply adjustment, rule, profile rule, split, budget, goal, alert rule, consent.
        state.adjustTransaction(
          txId: pixTx.id,
          description: 'Mercado da Esquina Centro',
          changeDescription: true,
          reason: 'Nome mais claro',
        );
        state.createUserRuleFromTransaction(
          txId: cardTx.id,
          category: SpendingCategory.health,
          essentiality: Essentiality.essential,
        );
        state.applyProfileRules(
          const ProfileAnswers(occupations: {ProfileOccupation.developer}),
          buildRulesFromProfile(
            const ProfileAnswers(occupations: {ProfileOccupation.developer}),
          ),
        );
        expect(
          state.replaceSplits(pixTx.id, const [
            TxSplit(
              id: 'sp-1',
              description: 'Alimentos',
              amountCents: 15000,
              category: SpendingCategory.food,
              essentiality: Essentiality.essential,
            ),
            TxSplit(
              id: 'sp-2',
              description: 'Limpeza',
              amountCents: 3540,
              category: SpendingCategory.housing,
              essentiality: Essentiality.essential,
            ),
          ]),
          isTrue,
        );
        state.upsertBudget(
          category: SpendingCategory.food,
          limitCents: 100000,
        );
        state.addGoal(
          name: 'Reserva pessoal',
          targetCents: 500000,
          currentCents: 120000,
        );
        state.addSpendingAlertRuleFromText(
          'me avise quando alimentação passar de R\$ 100',
        );
        state.acceptReceiptConsent();

        await state.flushLocalPersistence();

        // Verify ZERO plaintext leaks on disk!
        final rawCiphertext = await cache.readRawCiphertext();
        expect(rawCiphertext, isNotNull);
        final rawLatin1 = latin1.decode(rawCiphertext!);
        expect(rawLatin1.contains('Banco do Bairro'), isFalse);
        expect(rawLatin1.contains('Cooperativa Sol'), isFalse);
        expect(rawLatin1.contains('Mercado da Esquina'), isFalse);
        expect(rawLatin1.contains('Padaria Pao Quente'), isFalse);
        expect(rawLatin1.contains('Reserva pessoal'), isFalse);

        // Cryptographic AAD isolation: server URL cannot decrypt local://device data!
        await expectLater(
          cache.loadSnapshot(expectedServerUrl: 'https://outro.local'),
          throwsA(isA<CacheIntegrityException>()),
        );

        // Simulate full app restart with brand-new AppState sharing cache & prefs.
        final restarted = AppState(
          preferencesStore: prefs,
          encryptedCache: EncryptedCacheStore(
            storage: fileStorage,
            masterKey: key,
          ),
        );
        expect(await restarted.restoreLocalDeviceFromCache(), isTrue);
        expect(restarted.isLocalDeviceMode, isTrue);
        expect(restarted.originalDataset.banks.length, 3); // Carteira + 2 banks
        expect(restarted.originalDataset.accounts.length, 3);
        expect(restarted.originalDataset.transactions.length, 4);
        expect(
          restarted.effectiveById(pixTx.id).description,
          'Mercado da Esquina Centro',
        );
        expect(restarted.effectiveById(pixTx.id).splits.length, 2);
        expect(restarted.rules.length, greaterThanOrEqualTo(3));
        expect(restarted.budgets.single.limitCents, 100000);
        expect(restarted.goals.single.name, 'Reserva pessoal');
        expect(restarted.spendingAlertRules.length, 1);
        expect(restarted.receiptConsentAccepted, isTrue);

        // Full JSON backup export -> restore into a completely fresh device!
        final backupJson = buildBackupJson(
          dataset: restarted.effectiveDataset,
          rules: restarted.rules,
          adjustments: restarted.adjustments,
          budgets: restarted.budgets,
          goals: restarted.goals,
          alertRules: restarted.spendingAlertRules,
          modeLabel: restarted.mode.name,
          receiptConsentAccepted: restarted.receiptConsentAccepted,
        );

        final freshDeviceCache = EncryptedCacheStore(
          storage: InMemoryCacheStorage(),
        );
        final freshDevice = AppState(
          preferencesStore: InMemoryPreferencesStore(),
          encryptedCache: freshDeviceCache,
        );

        final restoredCount = await freshDevice.restoreFromBackupJson(
          backupJson,
        );
        expect(restoredCount, 4);
        expect(freshDevice.isLocalDeviceMode, isTrue);
        expect(freshDevice.originalDataset.banks.length, 3);
        expect(freshDevice.budgets.single.limitCents, 100000);
        expect(freshDevice.goals.single.currentCents, 120000);
        expect(freshDevice.receiptConsentAccepted, isTrue);
        expect(await freshDeviceCache.readRawCiphertext(), isNotNull);

        // Invalid backup throws clear FormatException.
        await expectLater(
          freshDevice.restoreFromBackupJson('{"invalido": true}'),
          throwsA(isA<FormatException>()),
        );
      },
    );
  });

  group('Zero-Cost Offline Paçoca Q&A Engine', () {
    final demo = demoDataset();
    final march = DateTime(2026, 3);
    final demoBudgets = const [
      Budget(
        id: 'b1',
        category: SpendingCategory.food,
        limitCents: 120000,
      ),
      Budget(
        id: 'b2',
        category: SpendingCategory.housing,
        limitCents: 200000,
      ),
    ];
    final demoGoals = [
      Goal(
        id: 'g1',
        name: 'Reserva de emergência',
        targetCents: 1800000,
        currentCents: 1500000,
      ),
    ];

    test('recognizes Portuguese month names and targets that exact month', () {
      final febTxs = demo.transactions.where(
        (t) => t.date.year == 2026 && t.date.month == 2,
      );
      final febFoodCents = categoryRanking(febTxs)
          .firstWhere((c) => c.category == SpendingCategory.food)
          .cents;

      final reply = answerFinancialQuestion(
        'Quanto gastei com alimentação em fevereiro?',
        demo,
        march,
      );
      expect(reply.periodLabel, 'Fevereiro 2026');
      expect(reply.text, contains('Fevereiro 2026'));
      expect(reply.text, contains('Alimentação'));
      expect(reply.text, contains(formatBrl(febFoodCents)));

      final janReply = answerFinancialQuestion(
        'Resumo de janeiro',
        demo,
        march,
      );
      expect(janReply.periodLabel, 'Janeiro 2026');
      expect(janReply.text, contains('Janeiro 2026'));
      expect(
        janReply.text,
        contains(formatBrl(summary(demo, DateTime(2026, 1)).spentCents)),
      );
    });

    test('answers category-specific questions with exact totals and share', () {
      final marchTxs = demo.transactions.where(
        (t) => t.date.year == 2026 && t.date.month == 3,
      );
      final ranking = {
        for (final c in categoryRanking(marchTxs)) c.category: c.cents,
      };

      final food = answerFinancialQuestion(
        'Quanto gastei com alimentação?',
        demo,
        march,
      );
      expect(food.text, contains('Alimentação'));
      expect(food.text, contains(formatBrl(ranking[SpendingCategory.food]!)));

      final housing = answerFinancialQuestion(
        'Quanto gastei com moradia?',
        demo,
        march,
      );
      expect(housing.text, contains('Moradia'));
      expect(
        housing.text,
        contains(formatBrl(ranking[SpendingCategory.housing]!)),
      );

      final transport = answerFinancialQuestion(
        'Quanto gastei com transporte?',
        demo,
        march,
      );
      expect(transport.text, contains('Transporte'));
      expect(
        transport.text,
        contains(formatBrl(ranking[SpendingCategory.transport]!)),
      );

      final health = answerFinancialQuestion(
        'Quanto gastei com saúde?',
        demo,
        march,
      );
      expect(health.text, contains('Saúde'));
      expect(
        health.text,
        contains(formatBrl(ranking[SpendingCategory.health]!)),
      );
    });

    test('answers merchant-specific questions without conflating full categories', () {
      final marchTxs = demo.transactions.where(
        (t) => t.date.year == 2026 && t.date.month == 3,
      );
      final marketSum = marchTxs
          .where((t) => t.description.contains('Supermercado'))
          .fold(0, (acc, t) => acc + t.amountCents.abs());
      final bakerySum = marchTxs
          .where((t) => t.description.contains('Padaria'))
          .fold(0, (acc, t) => acc + t.amountCents.abs());
      final pharmacySum = marchTxs
          .where((t) => t.description.contains('Farmácia'))
          .fold(0, (acc, t) => acc + t.amountCents.abs());
      final rideshareSum = marchTxs
          .where((t) => t.description.contains('Corrida'))
          .fold(0, (acc, t) => acc + t.amountCents.abs());

      final market = answerFinancialQuestion(
        'Quanto gastei no supermercado?',
        demo,
        march,
      );
      expect(market.text, contains('Supermercado Bom Preço'));
      expect(market.text, contains(formatBrl(marketSum)));
      // Must NOT conflate with full Alimentação total!
      expect(market.text, isNot(contains('Padaria')));

      final bakery = answerFinancialQuestion(
        'Quanto gastei na padaria?',
        demo,
        march,
      );
      expect(bakery.text, contains('Padaria Pão de Ontem'));
      expect(bakery.text, contains(formatBrl(bakerySum)));

      final pharmacy = answerFinancialQuestion(
        'Quanto gastei na farmácia?',
        demo,
        march,
      );
      expect(pharmacy.text, contains('Farmácia Vida Plena'));
      expect(pharmacy.text, contains(formatBrl(pharmacySum)));

      final uber = answerFinancialQuestion(
        'Quanto gastei com uber?',
        demo,
        march,
      );
      expect(uber.text, contains('Corrida de app'));
      expect(uber.text, contains(formatBrl(rideshareSum)));

      final streaming = answerFinancialQuestion(
        'Quanto gastei com streaming?',
        demo,
        march,
      );
      expect(streaming.text, contains('Streaming Cine+'));
    });

    test('answers biggest expenses, budgets, and goals accurately', () {
      final biggest = answerFinancialQuestion(
        'Quais foram meus maiores gastos?',
        demo,
        march,
      );
      expect(biggest.text, contains('Aluguel'));
      expect(biggest.text, contains('Supermercado Bom Preço'));
      expect(biggest.text, contains('Notebook Loja Byte'));
      expect(biggest.citedFigures, isNotEmpty);

      final topShort = answerFinancialQuestion('top gastos', demo, march);
      expect(topShort.text, contains('Aluguel'));

      final budgetReply = answerFinancialQuestion(
        'Como está meu orçamento?',
        demo,
        march,
        budgets: demoBudgets,
        goals: demoGoals,
      );
      expect(budgetReply.text, contains('Orçamentos de Março 2026'));
      expect(budgetReply.text, contains('Alimentação'));
      expect(budgetReply.text, contains('Moradia'));
      expect(budgetReply.text, isNot(contains('Reserva de emergência')));

      final goalReply = answerFinancialQuestion(
        'Como está minha reserva?',
        demo,
        march,
        budgets: demoBudgets,
        goals: demoGoals,
      );
      expect(goalReply.text, contains('Reserva de emergência'));
      expect(goalReply.text, contains(r'R$ 15.000,00'));
      expect(goalReply.text, contains(r'R$ 18.000,00'));
    });
  });

  group('UI Flows: 3-Path Mode Picker, Local Device UX & Free AI Presets', () {
    testWidgets(
      'ServerAuthScreen displays all 3 beginner-friendly paths and enters '
      'localDevice mode with zero DemoBanner / OfflineBanner',
      (tester) async {
        await tester.pumpWidget(const GranaPaCaApp(startInServerAuth: true));
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('mode_local_device_card')), findsOneWidget);
        expect(find.text('Usar só neste aparelho'), findsOneWidget);
        expect(find.text('Recomendado para começar'), findsOneWidget);
        expect(find.text('Conectar ao meu servidor'), findsOneWidget);
        expect(find.text('Explorar a demonstração'), findsWidgets);

        await tester.tap(find.byKey(const Key('start_local_device_button')));
        await tester.pumpAndSettle();

        // Inside AppShell in localDevice mode: ZERO DemoBanner & ZERO OfflineBanner!
        expect(find.textContaining('Modo demonstração'), findsNothing);
        expect(find.byKey(const Key('offline_banner')), findsNothing);
        expect(
          find.byKey(const Key('local_mode_quickstart_card')),
          findsOneWidget,
        );

        // Add local bank account in 2 taps via Quickstart card.
        await tester.tap(
          find.byKey(const Key('quickstart_add_account_button')),
        );
        await tester.pumpAndSettle();

        await tester.enterText(
          find.byKey(const Key('local_bank_name_field')),
          'Banco do Bairro',
        );
        await tester.enterText(
          find.byKey(const Key('local_account_name_field')),
          'Conta Corrente',
        );
        final addAcctScroll = find
            .descendant(
              of: find.byType(AddLocalAccountSheet),
              matching: find.byType(Scrollable),
            )
            .first;
        final saveAcctBtn = find.byKey(const Key('local_account_save_button'));
        await _scrollTo(tester, saveAcctBtn, scrollable: addAcctScroll);
        await tester.tap(saveAcctBtn);
        await tester.pumpAndSettle();

        final newBankText = find.text('Banco do Bairro');
        await _scrollTo(tester, newBankText);
        expect(newBankText, findsWidgets);

        // Open manual entry sheet -> choose Pix payment method & save!
        await tester.tap(find.byTooltip('Ações rápidas'));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('quick_action_cash_entry')));
        await tester.pumpAndSettle();

        await tester.enterText(
          find.byKey(const Key('cash_amount_field')),
          '75,00',
        );
        await tester.enterText(
          find.byKey(const Key('cash_description_field')),
          'Supermercado Vila Nova',
        );
        final entryScroll = find
            .descendant(
              of: find.byType(CashEntrySheet),
              matching: find.byType(Scrollable),
            )
            .first;
        final pixChip = find.byKey(const Key('entry_pm_pix'));
        await _scrollTo(tester, pixChip, scrollable: entryScroll);
        await tester.tap(pixChip);
        await tester.pumpAndSettle();

        final saveEntryBtn = find.byKey(const Key('cash_save_button'));
        await _scrollTo(tester, saveEntryBtn, scrollable: entryScroll);
        await tester.tap(saveEntryBtn);
        await tester.pumpAndSettle();

        // Verify saved transaction appears in Extrato with Pix label.
        await _tapTab(tester, 'Extrato');
        expect(find.text('Supermercado Vila Nova'), findsOneWidget);
        expect(find.textContaining('Pix'), findsWidgets);

        // Verify Settings shows friendly local status & migration option.
        await _tapTab(tester, 'Ajustes');
        final statusTile = find.byKey(const Key('settings_local_mode_status'));
        await _scrollTo(tester, statusTile);
        expect(
          find.text('Modo local · dados cifrados só neste aparelho'),
          findsOneWidget,
        );
        final migrateTile = find.byKey(const Key('settings_server_config'));
        await _scrollTo(tester, migrateTile);
        expect(find.text('Migrar para servidor próprio'), findsOneWidget);

        // Verify ReceiptsExportScreen Export JSON + Restore Backup JSON loop!
        final backupTile = find.byKey(const Key('settings_backup'));
        await _scrollTo(tester, backupTile);
        await tester.tap(backupTile);
        await tester.pumpAndSettle();

        expect(find.byType(ReceiptsExportScreen), findsOneWidget);
        final exportJsonBtn = find.byKey(const Key('export_json_button'));
        await _scrollTo(tester, exportJsonBtn);
        await tester.tap(exportJsonBtn);
        await tester.pumpAndSettle();

        final previewFinder = find.byKey(const Key('export_preview_text'));
        await _scrollTo(tester, previewFinder);
        final exportedJson =
            tester.widget<SelectableText>(previewFinder).data!;
        expect(exportedJson, contains('Supermercado Vila Nova'));

        final restoreBtn = find.byKey(const Key('restore_json_backup_button'));
        await tester.scrollUntilVisible(
          restoreBtn,
          -200,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.ensureVisible(restoreBtn);
        await tester.pumpAndSettle();
        await tester.tap(restoreBtn);
        await tester.pumpAndSettle();

        await tester.enterText(
          find.byKey(const Key('restore_backup_json_field')),
          exportedJson,
        );
        await tester.tap(find.byKey(const Key('restore_backup_confirm_button')));
        await tester.pumpAndSettle();

        expect(
          find.textContaining('Backup restaurado com sucesso'),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'HomeScreen empty-connections state exposes "Usar só neste aparelho (sem servidor)"',
      (tester) async {
        await tester.pumpWidget(
          const GranaPaCaApp(simulateNoConnections: true),
        );
        await tester.pumpAndSettle();

        final localBtn = find.byKey(const Key('empty_home_use_local_device'));
        expect(localBtn, findsOneWidget);
        expect(
          find.text('Usar só neste aparelho (sem servidor)'),
          findsOneWidget,
        );
        await tester.tap(localBtn);
        await tester.pumpAndSettle();

        expect(find.textContaining('Modo demonstração'), findsNothing);
        expect(
          find.byKey(const Key('local_mode_quickstart_card')),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'AssistantScreen shows zero-cost local banner and Configurar IA presets '
      'sheet with Paçoca local, Gemini Flash Free, Groq, OpenRouter, and Ollama',
      (tester) async {
        final prefs = InMemoryPreferencesStore();
        final cache = EncryptedCacheStore(storage: InMemoryCacheStorage());

        await tester.pumpWidget(
          GranaPaCaApp(
            preferencesStore: prefs,
            encryptedCache: cache,
            initialMode: AppMode.localDevice,
          ),
        );
        await tester.pumpAndSettle();

        await _tapTab(tester, 'Paçoca');
        expect(
          find.byKey(const Key('assistant_local_free_banner')),
          findsOneWidget,
        );
        expect(find.text('Configurar IA'), findsOneWidget);

        await tester.tap(
          find.byKey(const Key('assistant_provider_config_button')),
        );
        await tester.pumpAndSettle();

        final sheetScroll = find
            .descendant(
              of: find.byKey(const Key('assistant_provider_sheet_scroll')),
              matching: find.byType(Scrollable),
            )
            .first;

        expect(
          find.textContaining('Grátis · sem conta · 100% offline'),
          findsWidgets,
        );

        final geminiCard = find.byKey(const Key('ai_preset_card_google'));
        await _scrollTo(tester, geminiCard, scrollable: sheetScroll);
        expect(
          find.textContaining('Google Gemini Flash (Plano gratuito sem cartão)'),
          findsOneWidget,
        );
        expect(find.textContaining('gemini-2.5-flash-lite'), findsOneWidget);
        expect(find.textContaining('pseudonimização'), findsWidgets);

        final groqCard = find.byKey(const Key('ai_preset_card_groq'));
        await _scrollTo(tester, groqCard, scrollable: sheetScroll);
        expect(
          find.textContaining('Groq (Plano gratuito · compatível OpenAI)'),
          findsOneWidget,
        );
        expect(find.textContaining('llama-3.3-70b-versatile'), findsOneWidget);

        final openRouterCard = find.byKey(
          const Key('ai_preset_card_openrouter'),
        );
        await _scrollTo(tester, openRouterCard, scrollable: sheetScroll);
        expect(
          find.textContaining('OpenRouter (Modelos gratuitos :free)'),
          findsOneWidget,
        );
        expect(
          find.textContaining('meta-llama/llama-3.3-70b-instruct:free'),
          findsOneWidget,
        );

        final ollamaCard = find.byKey(const Key('ai_preset_card_ollama'));
        await _scrollTo(tester, ollamaCard, scrollable: sheetScroll);
        expect(
          find.textContaining('Ollama local (Grátis · 100% privado no seu PC)'),
          findsOneWidget,
        );
        expect(find.textContaining('qwen2.5:7b'), findsWidgets);
      },
    );
  });

  group('Local-device cold-start, PIN unlock & progressive lockout', () {
    Future<void> enterPin(WidgetTester tester, String digits) async {
      for (final ch in digits.split('')) {
        final keyFinder = find.byKey(Key('pin_key_$ch'));
        await tester.ensureVisible(keyFinder);
        await tester.tap(keyFinder);
        await tester.pump();
      }
      await tester.pumpAndSettle();
    }

    testWidgets(
      'cold start in localDevice with PIN restores encrypted vault on unlock '
      'and explicit initialMode: demo is not hijacked',
      (tester) async {
        final prefs = InMemoryPreferencesStore();
        final dataStorage = InMemoryCacheStorage();
        final keyStorage = InMemoryCacheStorage();
        final initialCache = EncryptedCacheStore(
          storage: dataStorage,
          keyStorage: keyStorage,
        );
        final setupLock = AppLockController(
          preferencesStore: prefs,
          hashIterations: 50,
        );

        final firstSession = AppState(
          preferencesStore: prefs,
          encryptedCache: initialCache,
          appLock: setupLock,
        );
        await firstSession.startLocalDeviceMode(
          openingBalanceCents: 25000,
        );
        final checking = await firstSession.addLocalBankAccount(
          bankName: 'Banco do Bairro',
          accountName: 'Conta corrente',
          kind: AccountKind.checking,
          openingBalanceCents: 180000,
        );
        await firstSession.addManualTransaction(
          date: DateTime(2026, 2, 18),
          description: 'Padaria do Bairro',
          amountCents: 3200,
          accountId: checking.id,
          paymentMethod: PaymentMethod.pix,
          category: SpendingCategory.food,
        );
        await firstSession.appLock.configurePin('135791');
        // Wait for async PIN-wrapping callback before locking DEK in memory.
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        initialCache.lockInMemory();
        firstSession.dispose();

        // Explicit initialMode: AppMode.demo must NOT be hijacked by saved
        // localDevice preference.
        final noPinPrefs = InMemoryPreferencesStore();
        await noPinPrefs.writeAppMode(AppMode.localDevice.name);
        await tester.pumpWidget(
          GranaPaCaApp(
            key: const ValueKey('explicit_demo_app'),
            preferencesStore: noPinPrefs,
            initialMode: AppMode.demo,
          ),
        );
        await tester.pumpAndSettle();
        expect(find.textContaining('Modo demonstração'), findsWidgets);

        // Cold start in localDevice with PIN-wrapped encrypted vault:
        final coldCache = EncryptedCacheStore(
          storage: dataStorage,
          keyStorage: keyStorage,
        );
        final coldLock = AppLockController(
          preferencesStore: prefs,
          hashIterations: 50,
        );
        await tester.pumpWidget(
          GranaPaCaApp(
            key: const ValueKey('cold_local_device_app'),
            preferencesStore: prefs,
            encryptedCache: coldCache,
            appLock: coldLock,
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byType(AppLockScreen), findsOneWidget);
        expect(find.byType(AppShell), findsNothing);
        expect(find.text('Banco do Bairro'), findsNothing);

        await enterPin(tester, '135791');
        // Allow async unwrap + vault restore to settle.
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 80)),
        );
        await tester.pumpAndSettle();

        expect(find.byType(AppLockScreen), findsNothing);
        expect(find.byType(AppShell), findsOneWidget);
        final bankFinder = find.text('Banco do Bairro');
        await _scrollTo(tester, bankFinder);
        expect(bankFinder, findsOneWidget);
      },
    );

    testWidgets(
      '5 failed PIN attempts in localDevice keep vault intact with progressive '
      'cooldown and allow explicit double-confirmed reset',
      (tester) async {
        var now = DateTime(2026, 2, 20, 10, 0, 0);
        final prefs = InMemoryPreferencesStore();
        final dataStorage = InMemoryCacheStorage();
        final keyStorage = InMemoryCacheStorage();
        final cache = EncryptedCacheStore(
          storage: dataStorage,
          keyStorage: keyStorage,
        );
        final setupLock = AppLockController(
          preferencesStore: prefs,
          clock: () => now,
          hashIterations: 50,
        );

        final firstSession = AppState(
          preferencesStore: prefs,
          encryptedCache: cache,
          appLock: setupLock,
        );
        await firstSession.startLocalDeviceMode();
        await firstSession.addLocalBankAccount(
          bankName: 'Banco Cofre Seguro',
          accountName: 'Poupança',
          kind: AccountKind.savings,
          openingBalanceCents: 90000,
        );
        await firstSession.appLock.configurePin('246810');
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        cache.lockInMemory();
        firstSession.dispose();

        final coldCache = EncryptedCacheStore(
          storage: dataStorage,
          keyStorage: keyStorage,
        );
        final coldLock = AppLockController(
          preferencesStore: prefs,
          clock: () => now,
          hashIterations: 50,
        );
        await tester.pumpWidget(
          GranaPaCaApp(
            preferencesStore: prefs,
            encryptedCache: coldCache,
            appLock: coldLock,
          ),
        );
        await tester.pumpAndSettle();

        // 5 consecutive wrong PINs trigger cooldown without wiping vault or
        // letting the user past AppLockScreen.
        for (var i = 0; i < 5; i++) {
          await enterPin(tester, '000000');
        }
        expect(coldLock.isLocked, isTrue);
        expect(coldLock.isInCooldown, isTrue);
        expect(coldLock.lockoutRounds, 1);
        expect(coldLock.remainingCooldown.inSeconds, 30);
        expect(find.byType(AppLockScreen), findsOneWidget);
        expect(find.byType(AppShell), findsNothing);
        expect(await coldCache.readRawCiphertext(), isNotNull);

        // Even the correct PIN is blocked during cooldown.
        expect(coldLock.verifyPin('246810'), isFalse);
        expect(coldLock.isLocked, isTrue);

        // Once cooldown expires, valid PIN unlocks and restores vault.
        now = now.add(const Duration(seconds: 31));
        expect(coldLock.isInCooldown, isFalse);

        // Explicit double-confirmed reset wipes vault ONLY after checkbox +
        // typing APAGAR.
        final resetBtn = find.byKey(const Key('local_forgot_pin_reset_button'));
        await tester.ensureVisible(resetBtn);
        await tester.tap(resetBtn);
        await tester.pumpAndSettle();

        final confirmButton = find.byKey(
          const Key('confirm_local_vault_wipe_button'),
        );
        expect(
          tester.widget<FilledButton>(confirmButton).onPressed,
          isNull,
        );

        await tester.tap(
          find.byKey(const Key('local_wipe_confirm_checkbox')),
        );
        await tester.enterText(
          find.byKey(const Key('local_wipe_confirm_field')),
          'APAGAR',
        );
        await tester.pumpAndSettle();

        expect(
          tester.widget<FilledButton>(confirmButton).onPressed,
          isNotNull,
        );
        await tester.tap(confirmButton);
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        await tester.pumpAndSettle();

        expect(coldLock.isLocked, isFalse);
        expect(coldLock.isEnabled, isFalse);
        expect(find.byType(AppShell), findsOneWidget);
        expect(find.text('Banco Cofre Seguro'), findsNothing);
      },
    );
  });

  group('Backend #69 AI provider contracts, TLS validation & ADR-030 notice', () {
    test(
      'fetchAiProviderPresets, fetchAiProviderConfig, updateAiProviderConfig '
      'and validateAiProviderBaseUrl follow backend #69 contract',
      () async {
        final requests = <HttpTransportRequest>[];
        var nextStatus = 200;
        var nextBody = '{}';
        final transport = _FakeAiHttpTransport((request) async {
          requests.add(request);
          if (request.method == 'GET' &&
              request.uri.path == '/api/v1/assistant/presets') {
            return HttpTransportResponse(
              statusCode: 200,
              body: jsonEncode({
                'items': [
                  {
                    'provider': 'ollama',
                    'label': 'Ollama local',
                    'defaultModel': 'qwen2.5:7b',
                    'defaultBaseUrl': 'http://host.docker.internal:11434/',
                    'isFree': true,
                    'requiresApiKey': false,
                    'isExternalCloud': false,
                  },
                  {
                    'provider': 'openai_compatible',
                    'label': 'Endpoint compatível OpenAI',
                    'defaultModel': 'llama-3.3-70b-versatile',
                    'defaultBaseUrl': 'http://host.docker.internal:1234/v1/',
                    'isFree': true,
                    'requiresApiKey': false,
                    'isExternalCloud': true,
                  },
                ],
              }),
            );
          }
          if (request.method == 'GET' &&
              request.uri.path == '/api/v1/assistant/provider') {
            return HttpTransportResponse(
              statusCode: 200,
              body: jsonEncode({
                'provider': 'openai_compatible',
                'model': 'local-llm',
                'baseUrl': 'https://llm.exemplo.com/v1/',
                'hasApiKey': true,
              }),
            );
          }
          return HttpTransportResponse(statusCode: nextStatus, body: nextBody);
        });

        final client = GranaPaCaApiClient(
          baseUrl: Uri.parse('https://casa.exemplo.local'),
          transport: transport,
          initialTokens: AuthTokens(
            accessToken: 'test-access-token',
            refreshToken: 'test-refresh-token',
            expiresAt: DateTime(2030, 1, 1),
            sessionId: 'sess-1',
            owner: const OwnerSummary(
              id: 'owner-1',
              householdId: 'hh-1',
              email: 'bia@exemplo.local',
              displayName: 'Bia',
            ),
          ),
        );

        final presets = await client.fetchAiProviderPresets();
        expect(presets, hasLength(2));
        expect(presets[0].provider, AiProviderKind.ollama);
        expect(
          presets[0].defaultBaseUrl,
          'http://host.docker.internal:11434/',
        );
        expect(presets[1].provider, AiProviderKind.openaiCompatible);

        final loaded = await client.fetchAiProviderConfig();
        expect(loaded.provider, AiProviderKind.openaiCompatible);
        expect(loaded.endpointUrl, 'https://llm.exemplo.com/v1/');
        expect(loaded.hasApiKey, isTrue);

        // TLS / SSRF rules matching backend #69.
        expect(
          () => GranaPaCaApiClient.validateAiProviderBaseUrl(
            provider: AiProviderKind.openaiCompatible,
            rawUrl: 'http://evil.example/v1/',
          ),
          throwsA(isA<ApiException>()),
        );
        expect(
          () => GranaPaCaApiClient.validateAiProviderBaseUrl(
            provider: AiProviderKind.ollama,
            rawUrl: 'http://169.254.169.254/latest/meta-data',
          ),
          throwsA(isA<ApiException>()),
        );
        expect(
          () => GranaPaCaApiClient.validateAiProviderBaseUrl(
            provider: AiProviderKind.groq,
            rawUrl: 'http://localhost:11434/v1/',
          ),
          throwsA(isA<ApiException>()),
        );
        expect(
          GranaPaCaApiClient.validateAiProviderBaseUrl(
            provider: AiProviderKind.openaiCompatible,
            rawUrl: 'http://localhost:1234/v1/',
          ).host,
          'localhost',
        );
        expect(
          GranaPaCaApiClient.validateAiProviderBaseUrl(
            provider: AiProviderKind.ollama,
            rawUrl: 'http://host.docker.internal:11434/',
          ).host,
          'host.docker.internal',
        );

        // AppState integration: error from server MUST NOT mutate local config,
        // and provider/endpoint change clears hasApiKey + sends clearApiKey.
        final state = AppState(
          apiClient: client,
          initialMode: AppMode.server,
          initialServerUrl: 'https://casa.exemplo.local',
          preferencesStore: InMemoryPreferencesStore(),
          encryptedCache: EncryptedCacheStore(storage: InMemoryCacheStorage()),
        );

        nextStatus = 200;
        nextBody = jsonEncode({
          'provider': 'groq',
          'model': 'llama-3.3-70b-versatile',
          'hasApiKey': true,
        });
        await state.updateAiProviderConfig(
          const AiProviderConfig(
            provider: AiProviderKind.groq,
            model: 'llama-3.3-70b-versatile',
          ),
          apiKey: 'fake-provider-token-for-unit-test',
        );
        expect(state.aiProviderConfig.provider, AiProviderKind.groq);
        expect(state.aiProviderConfig.hasApiKey, isTrue);

        // Server 400 error keeps previous Groq config intact.
        nextStatus = 400;
        nextBody = jsonEncode({'message': 'Endpoint rejeitado pelo servidor.'});
        await expectLater(
          state.updateAiProviderConfig(
            const AiProviderConfig(
              provider: AiProviderKind.openaiCompatible,
              model: 'local-llm',
              endpointUrl: 'https://llm.exemplo.com/v1/',
            ),
          ),
          throwsA(isA<ApiException>()),
        );
        expect(state.aiProviderConfig.provider, AiProviderKind.groq);
        expect(state.aiProviderConfig.hasApiKey, isTrue);

        // Switching provider without new key sends clearApiKey: true and
        // resets hasApiKey to false.
        nextStatus = 200;
        nextBody = jsonEncode({
          'provider': 'openai_compatible',
          'model': 'local-llm',
          'baseUrl': 'http://localhost:1234/v1/',
          'hasApiKey': false,
        });
        await state.updateAiProviderConfig(
          const AiProviderConfig(
            provider: AiProviderKind.openaiCompatible,
            model: 'local-llm',
            endpointUrl: 'http://localhost:1234/v1/',
          ),
        );
        final lastPut = requests.last;
        expect(lastPut.method, 'PUT');
        expect(lastPut.uri.path, '/api/v1/assistant/provider');
        final sentBody = jsonDecode(lastPut.body!) as Map<String, dynamic>;
        expect(sentBody['provider'], 'openai_compatible');
        expect(sentBody['baseUrl'], 'http://localhost:1234/v1/');
        expect(sentBody['clearApiKey'], isTrue);
        expect(state.aiProviderConfig.provider, AiProviderKind.openaiCompatible);
        expect(state.aiProviderConfig.hasApiKey, isFalse);

        state.dispose();
      },
    );

    testWidgets(
      'AssistantScreen shows ADR-030 external free-tier retention notice in '
      'server mode',
      (tester) async {
        final client = GranaPaCaApiClient(
          baseUrl: Uri.parse('https://casa.exemplo.local'),
          transport: _FakeAiHttpTransport(
            (_) async => const HttpTransportResponse(statusCode: 200, body: '{}'),
          ),
          initialTokens: AuthTokens(
            accessToken: 'test-access-token',
            refreshToken: 'test-refresh-token',
            expiresAt: DateTime(2030, 1, 1),
            sessionId: 'sess-1',
            owner: const OwnerSummary(
              id: 'owner-1',
              householdId: 'hh-1',
              email: 'bia@exemplo.local',
              displayName: 'Bia',
            ),
          ),
        );

        await tester.pumpWidget(
          GranaPaCaApp(
            apiClient: client,
            initialMode: AppMode.server,
            initialServerUrl: 'https://casa.exemplo.local',
            preferencesStore: InMemoryPreferencesStore(),
            encryptedCache: EncryptedCacheStore(storage: InMemoryCacheStorage()),
          ),
        );
        await tester.pumpAndSettle();

        await _tapTab(tester, 'Paçoca');
        await tester.tap(
          find.byKey(const Key('assistant_provider_config_button')),
        );
        await tester.pumpAndSettle();

        final sheetScroll = find
            .descendant(
              of: find.byKey(const Key('assistant_provider_sheet_scroll')),
              matching: find.byType(Scrollable),
            )
            .first;
        final groqOption = find.byKey(const Key('ai_provider_groq'));
        await _scrollTo(tester, groqOption, scrollable: sheetScroll);
        await tester.tap(groqOption);
        await tester.pumpAndSettle();

        final notice = find.byKey(const Key('ai_cloud_privacy_notice'));
        await _scrollTo(tester, notice, scrollable: sheetScroll);
        expect(notice, findsOneWidget);
        expect(find.textContaining('política de retenção'), findsWidgets);
        expect(find.textContaining('camadas gratuitas externas'), findsOneWidget);
      },
    );
  });

  group('parseBrlToCents, strict calendar dates & atomic backup rollback', () {
    test('parseBrlToCents avoids 1000x/10000x corruption and rejects malformed', () {
      expect(parseBrlToCents('0.125'), 13);
      expect(parseBrlToCents('1.2345'), 123);
      expect(parseBrlToCents('1.23.45'), isNull);
      expect(parseBrlToCents('1.200'), 120000);
      expect(parseBrlToCents('1.234.567'), 123456700);
      expect(parseBrlToCents('1,234,567.89'), 123456789);
      expect(parseBrlToCents('999999999999999999999,99'), isNull);
    });

    test(
      'parseStatementImport rejects impossible calendar dates in OFX and CSV',
      () {
        const ofx = '''
<OFX>
<STMTTRN>
<DTPOSTED>20260231120000
<TRNAMT>-50.00
<MEMO>DATA IMPOSSIVEL OFX
</STMTTRN>
<STMTTRN>
<DTPOSTED>20260228120000
<TRNAMT>-42.50
<MEMO>COMPRA VALIDA OFX
</STMTTRN>
</OFX>
''';
        final ofxParsed = parseStatementImport(ofx, accountId: 'acct-1');
        expect(ofxParsed, hasLength(1));
        expect(ofxParsed.single.date, DateTime(2026, 2, 28));
        expect(ofxParsed.single.description, 'COMPRA VALIDA OFX');

        const csv = '''
Data;Descricao;Valor
31/02/2026;DATA IMPOSSIVEL PTBR;-30,00
2026-02-31;DATA IMPOSSIVEL ISO;-40,00
28/02/2026;COMPRA VALIDA CSV;-19,90
''';
        final csvParsed = parseStatementImport(csv, accountId: 'acct-1');
        expect(csvParsed, hasLength(1));
        expect(csvParsed.single.date, DateTime(2026, 2, 28));
        expect(csvParsed.single.amountCents, -1990);
      },
    );

    test(
      'parseBackupJson always throws FormatException on invalid types/version/RN-24',
      () {
        expect(
          () => parseBackupJson('{"app":"GranaPaCa","transactions":"invalido"}'),
          throwsA(isA<FormatException>()),
        );
        expect(
          () => parseBackupJson('{"app":"GranaPaCa","version":99,"banks":[]}'),
          throwsA(isA<FormatException>()),
        );
        expect(
          () => parseBackupJson(
            '{"app":"GranaPaCa","version":1,"banks":[],"receiptConsentAccepted":"yes"}',
          ),
          throwsA(isA<FormatException>()),
        );
        expect(
          () => parseBackupJson(
            jsonEncode({
              'app': 'GranaPaCa',
              'version': 1,
              'banks': [
                {'id': 'b1', 'name': 'Banco Aurora', 'colorValue': 4287315461},
              ],
              'accounts': [
                {
                  'id': 'a1',
                  'bankId': 'b1',
                  'name': 'Conta',
                  'kind': 'checking',
                  'openingBalanceCents': 0,
                },
              ],
              'transactions': [
                {
                  'id': 1,
                  'accountId': 'a1',
                  'date': '2026-02-10T00:00:00.000',
                  'description': 'Compra dividida inválida',
                  'amountCents': -10000,
                  'kind': 'expense',
                  'splits': [
                    {
                      'id': 's1',
                      'description': 'Mercado',
                      'category': 'food',
                      'amountCents': 5000,
                    },
                  ],
                },
              ],
            }),
          ),
          throwsA(isA<FormatException>()),
        );
      },
    );

    test(
      'restoreFromBackupJson rolls back atomically when encrypted persistence fails',
      () async {
        final prefs = InMemoryPreferencesStore();
        final storage = _ToggleableFailingStorage();
        final cache = EncryptedCacheStore(storage: storage);
        final state = AppState(
          preferencesStore: prefs,
          encryptedCache: cache,
        );
        await state.startLocalDeviceMode(openingBalanceCents: 10000);
        await state.addLocalBankAccount(
          bankName: 'Banco Original',
          accountName: 'Conta Original',
          kind: AccountKind.checking,
          openingBalanceCents: 50000,
        );

        final backupFromOther = AppState(
          preferencesStore: InMemoryPreferencesStore(),
          encryptedCache: EncryptedCacheStore(storage: InMemoryCacheStorage()),
        );
        await backupFromOther.startLocalDeviceMode();
        await backupFromOther.addLocalBankAccount(
          bankName: 'Banco Novo Do Backup',
          accountName: 'Conta Nova',
          kind: AccountKind.checking,
          openingBalanceCents: 999900,
        );
        final backupJson = buildBackupJson(
          dataset: backupFromOther.effectiveDataset,
          rules: backupFromOther.rules,
          adjustments: backupFromOther.adjustments,
          budgets: backupFromOther.budgets,
          goals: backupFromOther.goals,
          alertRules: backupFromOther.spendingAlertRules,
          modeLabel: backupFromOther.mode.name,
          receiptConsentAccepted: backupFromOther.receiptConsentAccepted,
        );
        backupFromOther.dispose();

        // Force storage write failure during restore.
        storage.failWrites = true;
        await expectLater(
          state.restoreFromBackupJson(backupJson),
          throwsA(isA<StateError>()),
        );

        // Every state field must remain intact from before the failed restore.
        expect(state.mode, AppMode.localDevice);
        expect(
          state.originalDataset.banks.any((b) => b.name == 'Banco Original'),
          isTrue,
        );
        expect(
          state.originalDataset.banks.any(
            (b) => b.name == 'Banco Novo Do Backup',
          ),
          isFalse,
        );
        state.dispose();
      },
    );
  });
}

class _FakeAiHttpTransport extends HttpTransport {
  _FakeAiHttpTransport(this._handler);

  final Future<HttpTransportResponse> Function(HttpTransportRequest request)
  _handler;

  @override
  Future<HttpTransportResponse> send(HttpTransportRequest request) =>
      _handler(request);
}

class _ToggleableFailingStorage extends InMemoryCacheStorage {
  bool failWrites = false;

  @override
  Future<void> writeBytes(String key, Uint8List data) async {
    if (failWrites) {
      throw StateError('Simulated disk write failure');
    }
    return super.writeBytes(key, data);
  }
}
