import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:granapaca/demo/demo_data.dart';
import 'package:granapaca/finance/model.dart';
import 'package:granapaca/finance/planning_queries.dart';
import 'package:granapaca/finance/queries.dart';
import 'package:granapaca/finance/taxonomy.dart';
import 'package:granapaca/main.dart';
import 'package:granapaca/screens/cash_entry_sheet.dart';
import 'package:granapaca/screens/local_account_sheet.dart';
import 'package:granapaca/screens/receipts_export_screen.dart';
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
}
