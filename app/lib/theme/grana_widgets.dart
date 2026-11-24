import 'package:material_ui/material_ui.dart';

import '../demo/demo_data.dart';
import '../finance/model.dart';
import '../finance/queries.dart';
import '../finance/taxonomy.dart';
import 'grana_theme.dart';

/// Displays a monetary value in pt-BR with tabular figures.
/// When [hideValues] is true, renders `R$ •••` visually and announces
/// `valor oculto` to screen readers (RF-05).
class MoneyText extends StatelessWidget {
  const MoneyText({
    super.key,
    required this.cents,
    required this.hideValues,
    this.style,
    this.showPlusSign = false,
    this.useUnicodeMinus = false,
    this.colorOverride,
    this.textAlign,
    this.maxLines = 1,
  });

  final int cents;
  final bool hideValues;
  final TextStyle? style;
  final bool showPlusSign;
  final bool useUnicodeMinus;
  final Color? colorOverride;
  final TextAlign? textAlign;
  final int maxLines;

  String _format() {
    if (cents > 0 && showPlusSign) {
      return '+${formatBrl(cents)}';
    }
    if (cents < 0 && useUnicodeMinus) {
      return '−${formatBrl(cents.abs())}';
    }
    return formatBrl(cents);
  }

  @override
  Widget build(BuildContext context) {
    final baseStyle = style ?? GranaTokens.of(context).valorLinha;
    final resolvedStyle = baseStyle.copyWith(
      color: colorOverride ?? baseStyle.color,
      fontFeatures: GranaTokens.tabularFeatures,
    );

    if (hideValues) {
      return Semantics(
        container: true,
        label: 'valor oculto',
        excludeSemantics: true,
        child: Text(
          r'R$ •••',
          style: resolvedStyle,
          textAlign: textAlign,
          maxLines: maxLines,
          overflow: TextOverflow.ellipsis,
        ),
      );
    }

    return Text(
      _format(),
      style: resolvedStyle,
      textAlign: textAlign,
      maxLines: maxLines,
      overflow: TextOverflow.ellipsis,
    );
  }
}

/// Judgment-free essentiality badge with dot indicator + written label.
class EssentialityBadge extends StatelessWidget {
  const EssentialityBadge({
    super.key,
    required this.essentiality,
    this.compact = false,
  });

  final Essentiality essentiality;
  final bool compact;

  String get _dots {
    switch (essentiality) {
      case Essentiality.essential:
        return '●●●';
      case Essentiality.important:
        return '●●○';
      case Essentiality.flexible:
        return '●○○';
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = GranaTokens.of(context);
    final color = tokens.colorForEssentiality(essentiality);
    final text = compact ? _dots : '$_dots ${essentiality.label}';

    return Semantics(
      label: essentiality.label,
      excludeSemantics: compact,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(GranaRadius.chip),
          border: Border.all(color: color.withValues(alpha: 0.35)),
        ),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: color,
          ),
        ),
      ),
    );
  }
}

/// Written movement type badge so type is never conveyed by color alone (RF-19).
class TxKindBadge extends StatelessWidget {
  const TxKindBadge({super.key, required this.kind});

  final TxKind kind;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tokens = GranaTokens.of(context);

    final Color bg;
    final Color fg;
    switch (kind) {
      case TxKind.income:
        bg = tokens.mata.withValues(alpha: 0.14);
        fg = tokens.mata;
      case TxKind.expense:
        bg = scheme.surfaceContainerHighest;
        fg = scheme.onSurfaceVariant;
      case TxKind.refund:
        bg = tokens.rio.withValues(alpha: 0.14);
        fg = tokens.rio;
      case TxKind.ownTransfer:
      case TxKind.billPayment:
      case TxKind.investment:
      case TxKind.redemption:
      case TxKind.cashWithdrawal:
        bg = scheme.secondaryContainer;
        fg = scheme.onSecondaryContainer;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(GranaRadius.chip),
      ),
      child: Text(
        kind.label,
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: fg),
      ),
    );
  }
}

/// Fixed banner displayed on every screen in demo mode (RF-63).
class DemoBanner extends StatelessWidget {
  const DemoBanner({super.key, this.onExploreGuide});

  final VoidCallback? onExploreGuide;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.tertiaryContainer,
      child: SafeArea(
        top: false,
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: GranaSpacing.lg,
            vertical: GranaSpacing.sm,
          ),
          child: Row(
            children: [
              Icon(
                Icons.science_outlined,
                size: 18,
                color: scheme.onTertiaryContainer,
              ),
              const SizedBox(width: GranaSpacing.sm),
              Expanded(
                child: Text(
                  'Modo demonstração: todos os dados são fictícios.',
                  style: TextStyle(
                    color: scheme.onTertiaryContainer,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (onExploreGuide != null) ...[
                const SizedBox(width: GranaSpacing.sm),
                TextButton(
                  onPressed: onExploreGuide,
                  style: TextButton.styleFrom(
                    foregroundColor: scheme.onTertiaryContainer,
                    minimumSize: const Size(0, 36),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text('Primeiro acesso'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Banner shown whenever the app is connected to a self-hosted server but
/// currently reading from the encrypted local cache without connectivity
/// (RF-21).
class OfflineBanner extends StatelessWidget {
  const OfflineBanner({
    super.key,
    required this.lastSyncedAt,
    this.onRetry,
  });

  final DateTime? lastSyncedAt;
  final VoidCallback? onRetry;

  String _formatLastSync(DateTime dt) {
    final local = dt.toLocal();
    final dd = local.day.toString().padLeft(2, '0');
    final mm = local.month.toString().padLeft(2, '0');
    final hh = local.hour.toString().padLeft(2, '0');
    final min = local.minute.toString().padLeft(2, '0');
    return '$dd/$mm às $hh:$min';
  }

  @override
  Widget build(BuildContext context) {
    final tokens = GranaTokens.of(context);
    final label = lastSyncedAt == null
        ? 'Sem conexão com o servidor · exibindo dados salvos'
        : 'Sem conexão com o servidor · última sincronização em '
              '${_formatLastSync(lastSyncedAt!)}';

    return Material(
      key: const Key('offline_banner'),
      color: tokens.milho.withValues(alpha: 0.28),
      child: SafeArea(
        top: false,
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: GranaSpacing.lg,
            vertical: GranaSpacing.sm,
          ),
          child: Row(
            children: [
              Icon(
                Icons.cloud_off_outlined,
                size: 18,
                color: tokens.sobreMilho,
              ),
              const SizedBox(width: GranaSpacing.sm),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    color: tokens.sobreMilho,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (onRetry != null) ...[
                const SizedBox(width: GranaSpacing.sm),
                TextButton(
                  key: const Key('offline_banner_retry'),
                  onPressed: onRetry,
                  style: TextButton.styleFrom(
                    foregroundColor: tokens.sobreMilho,
                    minimumSize: const Size(0, 36),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text('Reconectar'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Clean empty state with icon, title, subtitle, and optional actions.
class EmptyStateView extends StatelessWidget {
  const EmptyStateView({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.actionLabel,
    this.onAction,
    this.secondaryActionLabel,
    this.onSecondaryAction,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;
  final String? secondaryActionLabel;
  final VoidCallback? onSecondaryAction;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(GranaSpacing.xl),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: scheme.primaryContainer,
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 30, color: scheme.onPrimaryContainer),
              ),
              const SizedBox(height: GranaSpacing.lg),
              Text(
                title,
                textAlign: TextAlign.center,
                style: textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: GranaSpacing.sm),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              if (actionLabel != null && onAction != null) ...[
                const SizedBox(height: GranaSpacing.xl),
                FilledButton(onPressed: onAction, child: Text(actionLabel!)),
              ],
              if (secondaryActionLabel != null &&
                  onSecondaryAction != null) ...[
                const SizedBox(height: GranaSpacing.sm),
                OutlinedButton(
                  onPressed: onSecondaryAction,
                  child: Text(secondaryActionLabel!),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Reusable transaction row with bank accent bar, category badge, written
/// movement type, essentiality indicator, installment tag, and tabular amount.
class TransactionRow extends StatelessWidget {
  const TransactionRow({
    super.key,
    required this.tx,
    required this.account,
    required this.bank,
    required this.hideValues,
    this.onTap,
    this.leading,
  });

  final EffectiveTransaction tx;
  final Account account;
  final Bank bank;
  final bool hideValues;
  final VoidCallback? onTap;
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tokens = GranaTokens.of(context);
    final bankColor = Color(bank.colorValue);

    final categoryColor = tx.category != null
        ? tokens.colorForCategory(tx.category!)
        : (tx.kind == TxKind.income ? tokens.mata : scheme.secondary);
    final icon = tx.category != null
        ? iconForCategory(tx.category!)
        : iconForTxKind(tx.kind);

    final amountColor = tx.kind == TxKind.income
        ? tokens.mata
        : (tx.kind == TxKind.refund ? tokens.rio : scheme.onSurface);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(GranaRadius.chip),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: GranaSpacing.alvoDeToque),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: GranaSpacing.md,
            vertical: GranaSpacing.md,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (leading != null) ...[
                leading!,
                const SizedBox(width: GranaSpacing.xs),
              ],
              // 4px bank accent strip
              Container(
                width: 4,
                height: 44,
                decoration: BoxDecoration(
                  color: bankColor,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: GranaSpacing.md),
              // Category / kind circle icon
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: categoryColor.withValues(alpha: 0.14),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 20, color: categoryColor),
              ),
              const SizedBox(width: GranaSpacing.md),
              // Description + metadata badges
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            tx.description,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: scheme.onSurface,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (tx.hasManualAdjustments) ...[
                          const SizedBox(width: 4),
                          Tooltip(
                            message: 'Ajustada manualmente',
                            child: Icon(
                              Icons.edit_note_rounded,
                              size: 16,
                              color: scheme.primary,
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${formatShortDate(tx.date)} · ${account.name} · '
                      '${bank.name} · ${tx.paymentMethod.label}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        TxKindBadge(kind: tx.kind),
                        if (tx.category != null)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: categoryColor.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(
                                GranaRadius.chip,
                              ),
                            ),
                            child: Text(
                              tx.category!.label,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: categoryColor,
                              ),
                            ),
                          )
                        else if (isSpendingKind(tx.kind))
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: tokens.milho.withValues(alpha: 0.22),
                              borderRadius: BorderRadius.circular(
                                GranaRadius.chip,
                              ),
                            ),
                            child: Text(
                              'Sem categoria',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: tokens.sobreMilho,
                              ),
                            ),
                          ),
                        if (tx.essentiality != null)
                          EssentialityBadge(essentiality: tx.essentiality!),
                        if (tx.installment != null &&
                            tx.installmentCount != null)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: scheme.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(
                                GranaRadius.chip,
                              ),
                            ),
                            child: Text(
                              'Parcela ${tx.installment} de ${tx.installmentCount}',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        if (tx.isAtypical)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: scheme.tertiaryContainer,
                              borderRadius: BorderRadius.circular(
                                GranaRadius.chip,
                              ),
                            ),
                            child: Text(
                              'Atípica',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: scheme.onTertiaryContainer,
                              ),
                            ),
                          ),
                        if (tx.splits.isNotEmpty)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: tokens.rio.withValues(alpha: 0.14),
                              borderRadius: BorderRadius.circular(
                                GranaRadius.chip,
                              ),
                            ),
                            child: Text(
                              'Dividida (${tx.splits.length})',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: tokens.rio,
                              ),
                            ),
                          ),
                        if (tx.pendingSync)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: tokens.milho.withValues(alpha: 0.25),
                              borderRadius: BorderRadius.circular(
                                GranaRadius.chip,
                              ),
                            ),
                            child: Text(
                              'Pendente de envio',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: tokens.sobreMilho,
                              ),
                            ),
                          ),
                        for (final tag in tx.tags)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: scheme.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(
                                GranaRadius.chip,
                              ),
                            ),
                            child: Text(
                              '#$tag',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: GranaSpacing.md),
              MoneyText(
                cents: tx.amountCents,
                hideValues: hideValues,
                showPlusSign: tx.kind == TxKind.income,
                useUnicodeMinus: true,
                colorOverride: amountColor,
                style: tokens.valorLinha,
                textAlign: TextAlign.end,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Dialog explaining server-only capabilities in demo mode (RF-63).
Future<void> showServerOnlyDialog(BuildContext context, String featureName) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      icon: Icon(
        Icons.dns_outlined,
        color: Theme.of(dialogContext).colorScheme.primary,
      ),
      title: Text(featureName),
      content: const Text(
        'Este recurso só funciona na sua instância self-hosted do GranaPaCá. '
        'No modo demonstração, o app roda apenas com dados fictícios e não se '
        'conecta a bancos reais nem a servidores externos.',
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('Entendi'),
        ),
      ],
    ),
  );
}
