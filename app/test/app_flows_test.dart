import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:granapaca/main.dart';
import 'package:granapaca/state/preferences_store.dart';

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

void main() {
  group('RF-05 Hide values', () {
    testWidgets(
      'masks values with R\$ •••, exposes valor oculto semantics, shows '
      'percentages only on charts, and persists across app restarts',
      (tester) async {
        final store = InMemoryPreferencesStore();

        await tester.pumpWidget(GranaPaCaApp(preferencesStore: store));
        await tester.pumpAndSettle();

        expect(find.text(r'R$ 2.881,82'), findsOneWidget);

        // Toggle hide values ON via AppBar eye icon.
        await tester.tap(find.byKey(const Key('toggle_hide_values')));
        await tester.pumpAndSettle();

        expect(find.text(r'R$ 2.881,82'), findsNothing);
        expect(find.text(r'R$ •••'), findsWidgets);
        expect(find.bySemanticsLabel('valor oculto'), findsWidgets);
        expect(store.readHideValues(), isTrue);

        // Navigate to Gastos: center shows R$ •••, legend/ranking show % only.
        await _tapTab(tester, 'Gastos');

        expect(find.text(r'R$ •••'), findsWidgets);
        expect(find.textContaining('%'), findsWidgets);
        // March Moradia spending is R$ 1.808,00+ -> must not leak in legend/ranking.
        expect(find.textContaining('1.8'), findsNothing);

        // Simulate closing and reopening the app with the same store.
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        await tester.pumpWidget(GranaPaCaApp(preferencesStore: store));
        await tester.pumpAndSettle();

        expect(find.text(r'R$ 2.881,82'), findsNothing);
        expect(find.text(r'R$ •••'), findsWidgets);
        expect(find.bySemanticsLabel('valor oculto'), findsWidgets);
      },
    );
  });

  group('RF-16, RF-17, RF-20 Início, Bank Detail, Credit Cards & Empty State', () {
    testWidgets(
      'opens Bank Detail from Início, switches Todos vs banks, and displays '
      'credit card last 4 digits, open/closed bills and installments',
      (tester) async {
        await tester.pumpWidget(const GranaPaCaApp());
        await tester.pumpAndSettle();

        final auroraCard = find.byKey(const Key('bank_card_aurora'));
        await _scrollTo(
          tester,
          auroraCard,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.tap(auroraCard);
        await tester.pumpAndSettle();

        // Scroll to Credit Cards section on Bank Detail screen.
        final cardDigits = find.text('Final •••• 4821');
        await _scrollTo(
          tester,
          cardDigits,
          scrollable: find.byType(Scrollable).first,
        );
        expect(cardDigits, findsOneWidget);

        final marchBill = find.byKey(const Key('card_bill_2026_3'));
        await _scrollTo(
          tester,
          marchBill,
          scrollable: find.byType(Scrollable).first,
        );
        expect(find.text('Aberta'), findsOneWidget);
        expect(find.text('Fechada'), findsWidgets);

        // Open March 2026 bill and verify installment label.
        await tester.tap(marchBill);
        await tester.pumpAndSettle();

        final billItem = find.descendant(
          of: find.byType(BottomSheet),
          matching: find.text('Notebook Loja Byte'),
        );
        await _scrollTo(tester, billItem);
        expect(billItem, findsOneWidget);
        expect(
          find.descendant(
            of: find.byType(BottomSheet),
            matching: find.text('Parcela 5 de 10'),
          ),
          findsOneWidget,
        );

        // Edit the purchase directly from the bill sheet and verify the bill
        // modal updates reactively when returning.
        await tester.tap(billItem);
        await tester.pumpAndSettle();
        final detailScrollable = find
            .descendant(
              of: find.byType(ListView).last,
              matching: find.byType(Scrollable),
            )
            .first;
        final descField = find.byKey(const Key('tx_description_field'));
        await _scrollTo(tester, descField, scrollable: detailScrollable);
        await tester.enterText(descField, 'Notebook Trabalho');
        await tester.pumpAndSettle();
        final saveBtn = find.byKey(const Key('save_correction_button'));
        await _scrollTo(tester, saveBtn, scrollable: detailScrollable);
        await tester.tap(saveBtn);
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('Fechar').last);
        await tester.pumpAndSettle();

        expect(
          find.descendant(
            of: find.byType(BottomSheet),
            matching: find.text('Notebook Trabalho'),
          ),
          findsOneWidget,
        );

        // Close bill sheet.
        await tester.tap(find.byTooltip('Fechar'));
        await tester.pumpAndSettle();

        // Scroll back to top of Bank Detail and switch to Banco Siriema.
        final siriemaChip = find.byKey(const Key('bank_switch_siriema'));
        await tester.scrollUntilVisible(
          siriemaChip,
          -300,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.tap(siriemaChip);
        await tester.pumpAndSettle();
        expect(find.text('Final •••• 4821'), findsNothing);
        await _scrollTo(
          tester,
          find.text('Movimentações de Banco Siriema'),
          scrollable: find.byType(Scrollable).first,
        );
        expect(find.text('Movimentações de Banco Siriema'), findsOneWidget);

        // Scroll back to top and switch to Todos.
        final allChip = find.byKey(const Key('bank_switch_all'));
        await tester.scrollUntilVisible(
          allChip,
          -300,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.tap(allChip);
        await tester.pumpAndSettle();
        expect(find.text('Todos os bancos'), findsOneWidget);
        await _scrollTo(
          tester,
          find.text('Final •••• 4821'),
          scrollable: find.byType(Scrollable).first,
        );
        expect(find.text('Final •••• 4821'), findsOneWidget);
      },
    );

    testWidgets(
      'shows welcoming invite instead of zeros when no banks are connected (RF-16)',
      (tester) async {
        await tester.pumpWidget(
          const GranaPaCaApp(simulateNoConnections: true),
        );
        await tester.pumpAndSettle();

        expect(find.text('Conecte seus bancos para começar'), findsOneWidget);
        expect(find.text('Saldo do mês'), findsNothing);
        expect(find.text(r'R$ 0,00'), findsNothing);
      },
    );
  });

  group('RF-18, RF-19 Extrato search, combined filters, written types & pagination', () {
    testWidgets(
      'displays written movement types, accent-insensitive search, empty '
      'filter state with clear button, and incremental pagination',
      (tester) async {
        await tester.pumpWidget(const GranaPaCaApp());
        await tester.pumpAndSettle();

        await _tapTab(tester, 'Extrato');

        // Written movement type badges visible.
        expect(find.text('Gasto'), findsWidgets);

        // Accent-insensitive search finds Padaria Pão de Ontem.
        await tester.enterText(
          find.byKey(const Key('history_search_field')),
          'pao',
        );
        await tester.pumpAndSettle();
        expect(find.text('Padaria Pão de Ontem'), findsWidgets);
        expect(find.text('2 transações'), findsOneWidget);

        // Search with no matches shows empty state + Limpar filtros.
        await tester.enterText(
          find.byKey(const Key('history_search_field')),
          'termo inexistente xyz',
        );
        await tester.pumpAndSettle();
        expect(find.text('Nenhuma transação encontrada'), findsOneWidget);

        final clearBtn = find.widgetWithText(FilledButton, 'Limpar filtros');
        await _scrollTo(tester, clearBtn);
        await tester.tap(clearBtn);
        await tester.pumpAndSettle();

        // All 72 transactions across all months are matched; pagination shows
        // 25 initially with a Carregar mais button.
        expect(find.text('72 transações'), findsOneWidget);
        final loadMore = find.byKey(const Key('load_more_history'));
        await tester.scrollUntilVisible(
          loadMore,
          400,
          scrollable: find.byType(Scrollable).last,
        );
        expect(loadMore, findsOneWidget);
        await tester.tap(loadMore);
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          loadMore,
          400,
          scrollable: find.byType(Scrollable).last,
        );
        expect(find.textContaining('22 restantes'), findsOneWidget);
      },
    );
  });

  group('RF-34, RF-35, RF-36 Gastos donut, ranking, drilldown & empty period', () {
    testWidgets(
      'matches Extrato totals, drills down on category tap, and shows empty '
      'state for periods without spending',
      (tester) async {
        await tester.pumpWidget(const GranaPaCaApp());
        await tester.pumpAndSettle();

        await _tapTab(tester, 'Gastos');

        // Default March 2026 total spending matches demo summary (R$ 4.168,18).
        expect(find.text(r'R$ 4.168,18'), findsOneWidget);
        expect(find.text('Distribuição por categoria'), findsOneWidget);

        // Tap Moradia in donut legend -> opens Extrato pre-filtered by Moradia.
        final moradiaLegend = find.byKey(const Key('donut_legend_housing'));
        await _scrollTo(
          tester,
          moradiaLegend,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.tap(moradiaLegend);
        await tester.pumpAndSettle();

        // Now on Extrato with Moradia filter active and only housing items.
        expect(find.text('Aluguel'), findsOneWidget);
        expect(find.text('Conta de luz'), findsOneWidget);
        expect(find.text('2 transações'), findsOneWidget);

        // Go back to Gastos and test "Demais categorias" drilldown.
        await _tapTab(tester, 'Gastos');
        final restLegend = find.byKey(const Key('donut_legend_rest'));
        await _scrollTo(
          tester,
          restLegend,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.tap(restLegend);
        await tester.pumpAndSettle();

        final restChip = find.byKey(const Key('filter_chip_categories'));
        expect(restChip, findsOneWidget);
        expect(find.text('3 transações'), findsOneWidget);
        expect(find.text('Aluguel'), findsNothing);
        expect(find.text('Livraria Página Virada'), findsOneWidget);

        // Remove the multi-category chip and verify all March spending returns.
        await tester.tap(
          find.descendant(of: restChip, matching: find.byType(Icon)),
        );
        await tester.pumpAndSettle();
        expect(restChip, findsNothing);
        expect(find.text('16 transações'), findsOneWidget);

        // Go back to Gastos and select Abr/2026 (empty month).
        await _tapTab(tester, 'Gastos');

        await tester.tap(find.byKey(const Key('spending_month_2026_4')));
        await tester.pumpAndSettle();

        expect(find.text('Sem gastos neste período'), findsOneWidget);
      },
    );
  });

  group('RF-24, RF-25, RF-26, RF-27 Corrections, undo & rules management', () {
    testWidgets(
      'edits category independently with reason, creates rule for similar '
      'transactions, supports undo, and manages rules in Settings',
      (tester) async {
        await tester.pumpWidget(const GranaPaCaApp());
        await tester.pumpAndSettle();

        // Open Extrato and search for Padaria Pão de Ontem (2 items in March).
        await _tapTab(tester, 'Extrato');

        await tester.enterText(
          find.byKey(const Key('history_search_field')),
          'padaria',
        );
        await tester.pumpAndSettle();
        expect(find.text('Padaria Pão de Ontem'), findsNWidgets(2));

        // Open first Padaria transaction detail sheet.
        await tester.tap(find.text('Padaria Pão de Ontem').first);
        await tester.pumpAndSettle();

        final sheetScrollable = find
            .descendant(
              of: find.byType(ListView).last,
              matching: find.byType(Scrollable),
            )
            .first;

        // Immutable bank record shown.
        expect(find.text('Dados originais do banco'), findsOneWidget);

        // Edit description & category (Alimentação -> Lazer) without touching
        // essentiality (stays Essencial), with optional reason.
        final descField = find.byKey(const Key('tx_description_field'));
        await _scrollTo(tester, descField, scrollable: sheetScrollable);
        await tester.enterText(descField, 'Café da Esquina');
        await tester.pumpAndSettle();

        final lazerChip = find.byKey(const Key('cat_choice_leisure'));
        await _scrollTo(tester, lazerChip, scrollable: sheetScrollable);
        await tester.tap(lazerChip);
        await tester.pumpAndSettle();

        final reasonField = find.byKey(const Key('tx_reason_field'));
        await _scrollTo(tester, reasonField, scrollable: sheetScrollable);
        await tester.enterText(reasonField, 'Encontro com amigos');
        await tester.pumpAndSettle();

        final saveBtn = find.byKey(const Key('save_correction_button'));
        await _scrollTo(tester, saveBtn, scrollable: sheetScrollable);
        await tester.tap(saveBtn);
        await tester.pumpAndSettle();

        // Prompt to apply to similar transactions appears.
        expect(find.text('Aplicar às transações semelhantes?'), findsOneWidget);
        await tester.tap(find.text('Aplicar a todas'));
        await tester.pumpAndSettle();

        // Adjustment history shows entries + Desfazer button.
        final undoButtons = find.widgetWithText(OutlinedButton, 'Desfazer');
        await _scrollTo(tester, undoButtons.first, scrollable: sheetScrollable);
        expect(undoButtons, findsWidgets);
        expect(find.textContaining('Motivo: Encontro com amigos'), findsWidgets);

        // Undo the latest adjustment and verify history records undo.
        await tester.tap(undoButtons.first);
        await tester.pumpAndSettle();
        expect(find.text('· Desfazer'), findsOneWidget);

        // Close sheet and verify search matches BOTH original ('padaria') and
        // corrected ('cafe') descriptions!
        await tester.tap(find.byTooltip('Fechar'));
        await tester.pumpAndSettle();

        await tester.enterText(
          find.byKey(const Key('history_search_field')),
          'cafe',
        );
        await tester.pumpAndSettle();
        expect(find.text('Café da Esquina'), findsOneWidget);

        // Navigate to Ajustes -> Gerenciar regras.
        await _tapTab(tester, 'Ajustes');
        final rulesTile = find.byKey(const Key('settings_manage_rules'));
        await _scrollTo(
          tester,
          rulesTile,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.tap(rulesTile);
        await tester.pumpAndSettle();

        expect(find.text('Minhas regras'), findsOneWidget);
        expect(find.text('Padaria Pão de Ontem'), findsOneWidget);
        expect(find.text('Aplica-se a 6 transação(ões)'), findsOneWidget);

        // Toggle rule off and delete it.
        await tester.tap(find.byKey(const Key('rule_switch_user-rule-1')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('rule_delete_user-rule-1')));
        await tester.pumpAndSettle();
        expect(
          find.text('Nenhuma regra personalizada ainda'),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'shows Undo button only on the latest active adjustment per field',
      (tester) async {
        await tester.pumpWidget(const GranaPaCaApp());
        await tester.pumpAndSettle();

        await _tapTab(tester, 'Extrato');
        await tester.enterText(
          find.byKey(const Key('history_search_field')),
          'padaria',
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('Padaria Pão de Ontem').first);
        await tester.pumpAndSettle();

        final sheetScrollable = find
            .descendant(
              of: find.byType(ListView).last,
              matching: find.byType(Scrollable),
            )
            .first;

        // First category adjustment: Alimentação -> Lazer (adj-1)
        final lazerChip = find.byKey(const Key('cat_choice_leisure'));
        await _scrollTo(tester, lazerChip, scrollable: sheetScrollable);
        await tester.tap(lazerChip);
        await tester.pumpAndSettle();

        final saveBtn = find.byKey(const Key('save_correction_button'));
        await _scrollTo(tester, saveBtn, scrollable: sheetScrollable);
        await tester.tap(saveBtn);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Só esta'));
        await tester.pumpAndSettle();

        // Second category adjustment on the same field: Lazer -> Saúde (adj-2)
        final healthChip = find.byKey(const Key('cat_choice_health'));
        await _scrollTo(tester, healthChip, scrollable: sheetScrollable);
        await tester.tap(healthChip);
        await tester.pumpAndSettle();

        await _scrollTo(tester, saveBtn, scrollable: sheetScrollable);
        await tester.tap(saveBtn);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Só esta'));
        await tester.pumpAndSettle();

        // Only the latest adjustment (adj-2) should show the Desfazer button.
        final undo2 = find.byKey(const Key('undo_adj-2'));
        await _scrollTo(tester, undo2, scrollable: sheetScrollable);
        expect(undo2, findsOneWidget);
        expect(find.byKey(const Key('undo_adj-1')), findsNothing);
        expect(find.widgetWithText(OutlinedButton, 'Desfazer'), findsOneWidget);

        // Undoing adj-2 exposes Desfazer on adj-1 (now the active adjustment).
        await tester.tap(undo2);
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('undo_adj-2')), findsNothing);
        expect(find.byKey(const Key('undo_adj-1')), findsOneWidget);
        expect(find.widgetWithText(OutlinedButton, 'Desfazer'), findsOneWidget);
      },
    );
  });

  group('RF-08 Profile guide & RF-63 Demo first-access trail', () {
    testWidgets(
      'walks all 9 demo steps with locked server/login/2FA, multi-select, '
      'skip, rule review with unchecking, and preserves manual adjustments',
      (tester) async {
        await tester.pumpWidget(const GranaPaCaApp());
        await tester.pumpAndSettle();

        // First make a manual essentiality adjustment on one 'Posto Estrada Real'
        // transaction so we can verify profile rules never overwrite it!
        await _tapTab(tester, 'Extrato');
        await tester.enterText(
          find.byKey(const Key('history_search_field')),
          'posto estrada',
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Posto Estrada Real').first);
        await tester.pumpAndSettle();

        final sheetScrollable = find
            .descendant(
              of: find.byType(ListView).last,
              matching: find.byType(Scrollable),
            )
            .first;
        final flexChip = find.byKey(const Key('ess_choice_flexible'));
        await _scrollTo(tester, flexChip, scrollable: sheetScrollable);
        await tester.tap(flexChip);
        await tester.pumpAndSettle();

        final saveBtn = find.byKey(const Key('save_correction_button'));
        await _scrollTo(tester, saveBtn, scrollable: sheetScrollable);
        await tester.tap(saveBtn);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Só esta'));
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('Fechar'));
        await tester.pumpAndSettle();

        // Launch full 9-step first-access trail from DemoBanner.
        await tester.tap(find.text('Primeiro acesso'));
        await tester.pumpAndSettle();

        // Step 1: Welcome
        expect(find.text('Etapa 1 de 9'), findsOneWidget);
        expect(find.text('Boas-vindas ao GranaPaCá'), findsOneWidget);
        await tester.tap(find.byKey(const Key('onboarding_continue_button')));
        await tester.pumpAndSettle();

        // Step 2: Server (prefilled & locked)
        expect(find.text('Etapa 2 de 9'), findsOneWidget);
        expect(find.text('https://demo.granapaca.local'), findsOneWidget);
        await tester.tap(find.byKey(const Key('onboarding_continue_button')));
        await tester.pumpAndSettle();

        // Step 3: Login (prefilled & locked)
        expect(find.text('Etapa 3 de 9'), findsOneWidget);
        expect(find.text('bia@demo.local'), findsOneWidget);
        await tester.tap(find.byKey(const Key('onboarding_continue_button')));
        await tester.pumpAndSettle();

        // Step 4: Authenticator (prefilled & locked)
        expect(find.text('Etapa 4 de 9'), findsOneWidget);
        expect(find.text('123 456'), findsOneWidget);
        await tester.tap(find.byKey(const Key('onboarding_continue_button')));
        await tester.pumpAndSettle();

        // Step 5: Occupation (multi-select Motorista de app + Desenvolvedor)
        expect(find.text('Etapa 5 de 9'), findsOneWidget);
        await tester.tap(find.text('Motorista de app'));
        await tester.tap(find.text('Desenvolvedor'));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('onboarding_continue_button')));
        await tester.pumpAndSettle();

        // Step 6: Home (skip via Pular por agora)
        expect(find.text('Etapa 6 de 9'), findsOneWidget);
        await tester.tap(find.byKey(const Key('onboarding_skip_button')));
        await tester.pumpAndSettle();

        // Step 7: Transport (select Aplicativo)
        expect(find.text('Etapa 7 de 9'), findsOneWidget);
        await tester.tap(find.text('Aplicativo'));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('onboarding_continue_button')));
        await tester.pumpAndSettle();

        // Step 8: Review rules with explanations; uncheck one rule
        expect(find.text('Etapa 8 de 9'), findsOneWidget);
        expect(
          find.textContaining('Combustível é custo direto de trabalho'),
          findsOneWidget,
        );
        final notebookRule = find.byKey(
          const Key('review_rule_profile-dev-notebook'),
        );
        await _scrollTo(
          tester,
          notebookRule,
          scrollable: find.byType(Scrollable).last,
        );
        await tester.tap(notebookRule);
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('onboarding_apply_rules')));
        await tester.pumpAndSettle();

        // Step 9: Connect banks
        expect(find.text('Etapa 9 de 9'), findsOneWidget);
        expect(find.text('Conectar bancos'), findsOneWidget);
        await tester.tap(find.byKey(const Key('onboarding_finish_button')));
        await tester.pumpAndSettle();

        // Back in Extrato filtered to 'posto estrada' (March has 1 manual Flexível).
        expect(find.text('●○○ Flexível'), findsOneWidget);

        // Clear period filter to check Jan/Feb Posto Estrada Real became Essencial!
        await tester.tap(find.byKey(const Key('filter_period_button')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Todos os meses'));
        await tester.pumpAndSettle();
        expect(find.text('●●● Essencial'), findsNWidgets(2));
        expect(find.text('●○○ Flexível'), findsOneWidget);
      },
    );

    testWidgets(
      'supports skipping on rule review in both full trail and profileOnly mode '
      'without overwriting existing rules',
      (tester) async {
        await tester.pumpWidget(const GranaPaCaApp());
        await tester.pumpAndSettle();

        // Full trail: reach reviewRules (step 8) and skip without applying.
        await tester.tap(find.text('Primeiro acesso'));
        await tester.pumpAndSettle();
        for (var i = 0; i < 4; i++) {
          await tester.tap(find.byKey(const Key('onboarding_continue_button')));
          await tester.pumpAndSettle();
        }
        expect(find.text('Etapa 5 de 9'), findsOneWidget);
        await tester.tap(find.text('Motorista de app'));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('onboarding_continue_button')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('onboarding_continue_button')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('onboarding_continue_button')));
        await tester.pumpAndSettle();

        expect(find.text('Etapa 8 de 9'), findsOneWidget);
        await tester.tap(find.byKey(const Key('onboarding_skip_button')));
        await tester.pumpAndSettle();

        expect(find.text('Etapa 9 de 9'), findsOneWidget);
        expect(find.text('Conectar bancos'), findsOneWidget);
        await tester.tap(find.byKey(const Key('onboarding_finish_button')));
        await tester.pumpAndSettle();

        // Confirm no profile rules were saved.
        await _tapTab(tester, 'Ajustes');
        final rulesTile = find.byKey(const Key('settings_manage_rules'));
        await _scrollTo(
          tester,
          rulesTile,
          scrollable: find.byType(Scrollable).first,
        );
        expect(find.text('Nenhuma regra ativa'), findsOneWidget);

        // Apply one rule in profileOnly mode.
        final guideTile = find.byKey(const Key('settings_redo_profile_guide'));
        await _scrollTo(
          tester,
          guideTile,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.tap(guideTile);
        await tester.pumpAndSettle();

        expect(find.text('Etapa 1 de 4'), findsOneWidget);
        await tester.tap(find.text('Motorista de app'));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('onboarding_continue_button')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('onboarding_continue_button')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('onboarding_continue_button')));
        await tester.pumpAndSettle();

        expect(find.text('Etapa 4 de 4'), findsOneWidget);
        await tester.tap(find.byKey(const Key('onboarding_apply_rules')));
        await tester.pumpAndSettle();
        expect(find.text('1 regra(s) ativa(s)'), findsOneWidget);

        // Re-open profileOnly mode, select extra option, then skip on reviewRules.
        await _scrollTo(
          tester,
          guideTile,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.tap(guideTile);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Desenvolvedor'));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('onboarding_continue_button')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('onboarding_continue_button')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('onboarding_continue_button')));
        await tester.pumpAndSettle();

        expect(find.text('Etapa 4 de 4'), findsOneWidget);
        await tester.tap(find.byKey(const Key('onboarding_skip_button')));
        await tester.pumpAndSettle();

        // Guide closed and existing rule count remained 1.
        expect(find.text('Etapa 4 de 4'), findsNothing);
        expect(guideTile, findsOneWidget);
        expect(find.text('1 regra(s) ativa(s)'), findsOneWidget);
      },
    );
  });

  group('RF-56 Alerts & RF-63 Fixed demo banner + server-only dialog', () {
    testWidgets(
      'keeps demo banner across screens, marks alerts read, and explains '
      'server-only features',
      (tester) async {
        await tester.pumpWidget(const GranaPaCaApp());
        await tester.pumpAndSettle();

        // Demo banner on Início, Extrato, Gastos, Ajustes.
        for (final tab in ['Extrato', 'Gastos', 'Ajustes', 'Início']) {
          await _tapTab(tester, tab);
          expect(find.textContaining('Modo demonstração'), findsOneWidget);
        }

        // Unread alerts badge starts at 2.
        expect(find.text('2'), findsOneWidget);
        await tester.tap(find.byKey(const Key('alerts_button')));
        await tester.pumpAndSettle();

        expect(
          find.text('Autorização do Banco Aurora vence em 15 dias'),
          findsOneWidget,
        );
        await tester.tap(
          find.byKey(const Key('alert_tile_alert-aurora-consent')),
        );
        await tester.pumpAndSettle();

        // Navigated to Banco Aurora detail screen.
        expect(find.text('Banco Aurora'), findsWidgets);
        await _scrollTo(
          tester,
          find.text('Final •••• 4821'),
          scrollable: find.byType(Scrollable).first,
        );
        expect(find.text('Final •••• 4821'), findsOneWidget);

        // Pop back to Alerts and back to shell: unread badge is now 1!
        await tester.pageBack();
        await tester.pumpAndSettle();
        await tester.pageBack();
        await tester.pumpAndSettle();
        expect(find.text('1'), findsOneWidget);

        // Server-only dialog in Settings.
        await _tapTab(tester, 'Ajustes');
        final serverTile = find.byKey(const Key('settings_server_config'));
        await _scrollTo(
          tester,
          serverTile,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.tap(serverTile);
        await tester.pumpAndSettle();

        expect(
          find.textContaining('instância self-hosted do GranaPaCá'),
          findsOneWidget,
        );
        await tester.tap(find.text('Entendi'));
        await tester.pumpAndSettle();
      },
    );
  });

  group('Responsive layout', () {
    testWidgets('renders mobile NavigationBar without overflow on 390x844', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(const GranaPaCaApp());
      await tester.pumpAndSettle();

      expect(find.byType(NavigationBar), findsOneWidget);
      for (final tab in ['Extrato', 'Gastos', 'Ajustes', 'Início']) {
        await _tapTab(tester, tab);
        expect(find.textContaining('Modo demonstração'), findsOneWidget);
      }
    });

    testWidgets('renders desktop 2-column layout without overflow on 1280x800', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(const GranaPaCaApp());
      await tester.pumpAndSettle();

      expect(find.byType(NavigationRail), findsOneWidget);
      expect(find.text('Onde foi o dinheiro'), findsOneWidget);
      await _tapTab(tester, 'Gastos');
      expect(find.text('Distribuição por categoria'), findsOneWidget);
      expect(find.text('Ranking de categorias'), findsOneWidget);
    });
  });
}
