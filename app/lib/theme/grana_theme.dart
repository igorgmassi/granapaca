import 'package:material_ui/material_ui.dart';

import '../finance/model.dart';
import '../finance/taxonomy.dart';

/// Spacing constants for the GranaPaCá design system ("Mata e Fruta").
abstract final class GranaSpacing {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;
  static const double alvoDeToque = 48;
  static const double maxContentWidth = 1200;
}

/// Corner radius constants.
abstract final class GranaRadius {
  static const double chip = 12;
  static const double field = 12;
  static const double card = 20;
  static const double sheet = 28;
  static const double pill = 999;
}

/// Motion helper that respects system reduced-motion preferences.
abstract final class GranaMotion {
  static const Duration fast = Duration(milliseconds: 160);
  static const Duration standard = Duration(milliseconds: 240);

  static Duration duration(BuildContext context, [Duration normal = standard]) =>
      MediaQuery.disableAnimationsOf(context) ? Duration.zero : normal;
}

/// Verified "Mata e Fruta" light ColorScheme.
const ColorScheme granaLightColorScheme = ColorScheme(
  brightness: Brightness.light,
  primary: Color(0xFFA0521A),
  onPrimary: Color(0xFFFFFFFF),
  primaryContainer: Color(0xFFFADCC4),
  onPrimaryContainer: Color(0xFF3D1A03),
  secondary: Color(0xFF7A5A43),
  onSecondary: Color(0xFFFFFFFF),
  secondaryContainer: Color(0xFFF3E3D3),
  onSecondaryContainer: Color(0xFF2E1C0F),
  tertiary: Color(0xFF6E4AA3),
  onTertiary: Color(0xFFFFFFFF),
  tertiaryContainer: Color(0xFFECE1FA),
  onTertiaryContainer: Color(0xFF2A1450),
  error: Color(0xFFB83A22),
  onError: Color(0xFFFFFFFF),
  errorContainer: Color(0xFFFCDDD5),
  onErrorContainer: Color(0xFF4D1307),
  surface: Color(0xFFFBF5EC),
  onSurface: Color(0xFF2A1C12),
  onSurfaceVariant: Color(0xFF6B5546),
  surfaceContainerLowest: Color(0xFFFFFFFF),
  surfaceContainerLow: Color(0xFFFFFFFF),
  surfaceContainer: Color(0xFFF7F0E6),
  surfaceContainerHigh: Color(0xFFF3ECE2),
  surfaceContainerHighest: Color(0xFFF0E7DB),
  outline: Color(0xFF94816E),
  outlineVariant: Color(0xFFE5D9CA),
);

/// Verified "Mata e Fruta" dark ColorScheme.
const ColorScheme granaDarkColorScheme = ColorScheme(
  brightness: Brightness.dark,
  primary: Color(0xFFE8A066),
  onPrimary: Color(0xFF2A1407),
  primaryContainer: Color(0xFF6B3410),
  onPrimaryContainer: Color(0xFFFADCC4),
  secondary: Color(0xFFDCC1A9),
  onSecondary: Color(0xFF3A2717),
  secondaryContainer: Color(0xFF4E3B2C),
  onSecondaryContainer: Color(0xFFF3E3D3),
  tertiary: Color(0xFFB9A0EE),
  onTertiary: Color(0xFF2A1450),
  tertiaryContainer: Color(0xFF4B357A),
  onTertiaryContainer: Color(0xFFECE1FA),
  error: Color(0xFFFF8B73),
  onError: Color(0xFF4A1004),
  errorContainer: Color(0xFF7A2414),
  onErrorContainer: Color(0xFFFFDAD2),
  surface: Color(0xFF17110D),
  onSurface: Color(0xFFF7EFE6),
  onSurfaceVariant: Color(0xFFC4B2A2),
  surfaceContainerLowest: Color(0xFF110C09),
  surfaceContainerLow: Color(0xFF221A14),
  surfaceContainer: Color(0xFF281F18),
  surfaceContainerHigh: Color(0xFF2D241B),
  surfaceContainerHighest: Color(0xFF33291F),
  outline: Color(0xFF86725F),
  outlineVariant: Color(0xFF3F342A),
);

/// Semantic tokens and tabular monetary styles for GranaPaCá.
@immutable
class GranaTokens extends ThemeExtension<GranaTokens> {
  const GranaTokens({
    required this.mata,
    required this.milho,
    required this.sobreMilho,
    required this.rio,
    required this.essencial,
    required this.importante,
    required this.flexivel,
    required this.categoryColors,
    required this.heatmapScale,
    required this.valorDestaque,
    required this.valorGrande,
    required this.valorLinha,
  });

  final Color mata;
  final Color milho;
  final Color sobreMilho;
  final Color rio;
  final Color essencial;
  final Color importante;
  final Color flexivel;
  final Map<SpendingCategory, Color> categoryColors;

  /// Sequential 5-shade Caramelo scale for the spending calendar heatmap
  /// (intensity 1..5; intensity 0 uses transparent fill + outlineVariant border).
  final List<Color> heatmapScale;
  final TextStyle valorDestaque;
  final TextStyle valorGrande;
  final TextStyle valorLinha;

  static const List<FontFeature> tabularFeatures = [
    FontFeature.tabularFigures(),
  ];

  static const GranaTokens light = GranaTokens(
    mata: Color(0xFF2A7550),
    milho: Color(0xFFE5A62B),
    sobreMilho: Color(0xFF2A1C12),
    rio: Color(0xFF22649C),
    essencial: Color(0xFF6F340E),
    importante: Color(0xFFA65E28),
    flexivel: Color(0xFFC17C3E),
    categoryColors: {
      SpendingCategory.housing: Color(0xFF8B3E05),
      SpendingCategory.transport: Color(0xFF277BD0),
      SpendingCategory.food: Color(0xFFA78511),
      SpendingCategory.health: Color(0xFF267E4E),
      SpendingCategory.shopping: Color(0xFFFE903C),
      SpendingCategory.education: Color(0xFF7F4B9D),
      SpendingCategory.leisure: Color(0xFFD54573),
      SpendingCategory.services: Color(0xFF02A8AA),
      SpendingCategory.other: Color(0xFFA3958A),
    },
    heatmapScale: [
      Color(0xFFFADCC4),
      Color(0xFFEBB68C),
      Color(0xFFD48952),
      Color(0xFFB8662B),
      Color(0xFF8B3E05),
    ],
    valorDestaque: TextStyle(
      fontSize: 32,
      fontWeight: FontWeight.w700,
      letterSpacing: -0.5,
      height: 1.15,
      color: Color(0xFF2A1C12),
      fontFeatures: tabularFeatures,
    ),
    valorGrande: TextStyle(
      fontSize: 22,
      fontWeight: FontWeight.w700,
      letterSpacing: -0.3,
      height: 1.2,
      color: Color(0xFF2A1C12),
      fontFeatures: tabularFeatures,
    ),
    valorLinha: TextStyle(
      fontSize: 15,
      fontWeight: FontWeight.w600,
      height: 1.3,
      color: Color(0xFF2A1C12),
      fontFeatures: tabularFeatures,
    ),
  );

  static const GranaTokens dark = GranaTokens(
    mata: Color(0xFF6CC596),
    milho: Color(0xFFF3C35A),
    sobreMilho: Color(0xFF2A1C12),
    rio: Color(0xFF7DB9EA),
    essencial: Color(0xFFF5CBA4),
    importante: Color(0xFFDA955C),
    flexivel: Color(0xFFB5733C),
    categoryColors: {
      SpendingCategory.housing: Color(0xFF9D4005),
      SpendingCategory.transport: Color(0xFF2B7DDA),
      SpendingCategory.food: Color(0xFF8D741C),
      SpendingCategory.health: Color(0xFF31AD6D),
      SpendingCategory.shopping: Color(0xFFD67B16),
      SpendingCategory.education: Color(0xFF7A56B0),
      SpendingCategory.leisure: Color(0xFFCE436A),
      SpendingCategory.services: Color(0xFF008E97),
      SpendingCategory.other: Color(0xFF8A7D73),
    },
    heatmapScale: [
      Color(0xFF422715),
      Color(0xFF66381A),
      Color(0xFF8F4E22),
      Color(0xFFC27438),
      Color(0xFFE8A066),
    ],
    valorDestaque: TextStyle(
      fontSize: 32,
      fontWeight: FontWeight.w700,
      letterSpacing: -0.5,
      height: 1.15,
      color: Color(0xFFF7EFE6),
      fontFeatures: tabularFeatures,
    ),
    valorGrande: TextStyle(
      fontSize: 22,
      fontWeight: FontWeight.w700,
      letterSpacing: -0.3,
      height: 1.2,
      color: Color(0xFFF7EFE6),
      fontFeatures: tabularFeatures,
    ),
    valorLinha: TextStyle(
      fontSize: 15,
      fontWeight: FontWeight.w600,
      height: 1.3,
      color: Color(0xFFF7EFE6),
      fontFeatures: tabularFeatures,
    ),
  );

  static GranaTokens of(BuildContext context) =>
      Theme.of(context).extension<GranaTokens>() ?? light;

  Color colorForCategory(SpendingCategory category) =>
      categoryColors[category] ?? const Color(0xFFA3958A);

  Color colorForOptionalCategory(SpendingCategory? category) =>
      category != null ? colorForCategory(category) : const Color(0xFF7D6E63);

  Color colorForEssentiality(Essentiality essentiality) {
    switch (essentiality) {
      case Essentiality.essential:
        return essencial;
      case Essentiality.important:
        return importante;
      case Essentiality.flexible:
        return flexivel;
    }
  }

  /// Returns the Caramelo shade for intensity `1..5`, or `null` for `0`
  /// (empty day).
  Color? colorForHeatmapIntensity(int intensity) {
    if (intensity <= 0 || heatmapScale.isEmpty) return null;
    final idx = (intensity - 1).clamp(0, heatmapScale.length - 1);
    return heatmapScale[idx];
  }

  @override
  GranaTokens copyWith({
    Color? mata,
    Color? milho,
    Color? sobreMilho,
    Color? rio,
    Color? essencial,
    Color? importante,
    Color? flexivel,
    Map<SpendingCategory, Color>? categoryColors,
    List<Color>? heatmapScale,
    TextStyle? valorDestaque,
    TextStyle? valorGrande,
    TextStyle? valorLinha,
  }) => GranaTokens(
    mata: mata ?? this.mata,
    milho: milho ?? this.milho,
    sobreMilho: sobreMilho ?? this.sobreMilho,
    rio: rio ?? this.rio,
    essencial: essencial ?? this.essencial,
    importante: importante ?? this.importante,
    flexivel: flexivel ?? this.flexivel,
    categoryColors: categoryColors ?? this.categoryColors,
    heatmapScale: heatmapScale ?? this.heatmapScale,
    valorDestaque: valorDestaque ?? this.valorDestaque,
    valorGrande: valorGrande ?? this.valorGrande,
    valorLinha: valorLinha ?? this.valorLinha,
  );

  @override
  GranaTokens lerp(ThemeExtension<GranaTokens>? other, double t) {
    if (other is! GranaTokens) return this;
    return GranaTokens(
      mata: Color.lerp(mata, other.mata, t) ?? mata,
      milho: Color.lerp(milho, other.milho, t) ?? milho,
      sobreMilho: Color.lerp(sobreMilho, other.sobreMilho, t) ?? sobreMilho,
      rio: Color.lerp(rio, other.rio, t) ?? rio,
      essencial: Color.lerp(essencial, other.essencial, t) ?? essencial,
      importante: Color.lerp(importante, other.importante, t) ?? importante,
      flexivel: Color.lerp(flexivel, other.flexivel, t) ?? flexivel,
      categoryColors: {
        for (final c in SpendingCategory.values)
          c:
              Color.lerp(categoryColors[c], other.categoryColors[c], t) ??
              categoryColors[c]!,
      },
      heatmapScale: [
        for (var i = 0; i < heatmapScale.length; i++)
          Color.lerp(
                heatmapScale[i],
                i < other.heatmapScale.length
                    ? other.heatmapScale[i]
                    : heatmapScale[i],
                t,
              ) ??
              heatmapScale[i],
      ],
      valorDestaque:
          TextStyle.lerp(valorDestaque, other.valorDestaque, t) ??
          valorDestaque,
      valorGrande:
          TextStyle.lerp(valorGrande, other.valorGrande, t) ?? valorGrande,
      valorLinha: TextStyle.lerp(valorLinha, other.valorLinha, t) ?? valorLinha,
    );
  }
}

IconData iconForCategory(SpendingCategory category) {
  switch (category) {
    case SpendingCategory.housing:
      return Icons.home_outlined;
    case SpendingCategory.food:
      return Icons.restaurant_outlined;
    case SpendingCategory.transport:
      return Icons.directions_car_outlined;
    case SpendingCategory.health:
      return Icons.favorite_outline;
    case SpendingCategory.education:
      return Icons.menu_book_outlined;
    case SpendingCategory.leisure:
      return Icons.local_activity_outlined;
    case SpendingCategory.shopping:
      return Icons.shopping_bag_outlined;
    case SpendingCategory.services:
      return Icons.subscriptions_outlined;
    case SpendingCategory.other:
      return Icons.category_outlined;
  }
}

IconData iconForOptionalCategory(SpendingCategory? category) =>
    category != null ? iconForCategory(category) : Icons.help_outline_rounded;

IconData iconForPaymentMethod(PaymentMethod method) {
  switch (method) {
    case PaymentMethod.pix:
      return Icons.bolt_rounded;
    case PaymentMethod.debit:
      return Icons.account_balance_wallet_outlined;
    case PaymentMethod.credit:
      return Icons.credit_card_outlined;
    case PaymentMethod.cash:
      return Icons.payments_outlined;
    case PaymentMethod.boleto:
      return Icons.qr_code_2_outlined;
    case PaymentMethod.transfer:
      return Icons.swap_horiz_rounded;
    case PaymentMethod.other:
      return Icons.more_horiz_rounded;
  }
}

IconData iconForTxKind(TxKind kind) {
  switch (kind) {
    case TxKind.expense:
      return Icons.arrow_upward_rounded;
    case TxKind.income:
      return Icons.arrow_downward_rounded;
    case TxKind.ownTransfer:
      return Icons.swap_horiz_rounded;
    case TxKind.billPayment:
      return Icons.credit_card_outlined;
    case TxKind.refund:
      return Icons.replay_rounded;
    case TxKind.investment:
      return Icons.trending_up_rounded;
    case TxKind.redemption:
      return Icons.savings_outlined;
    case TxKind.cashWithdrawal:
      return Icons.payments_outlined;
  }
}

ThemeData _buildTheme(ColorScheme scheme, GranaTokens tokens) {
  final pillButtonStyle = ButtonStyle(
    shape: const WidgetStatePropertyAll(StadiumBorder()),
    minimumSize: const WidgetStatePropertyAll(
      Size(GranaSpacing.alvoDeToque, GranaSpacing.alvoDeToque),
    ),
    padding: const WidgetStatePropertyAll(
      EdgeInsets.symmetric(horizontal: 20, vertical: 12),
    ),
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: scheme.surface,
    extensions: [tokens],
    appBarTheme: AppBarTheme(
      elevation: 0,
      scrolledUnderElevation: 0,
      backgroundColor: scheme.surface,
      foregroundColor: scheme.onSurface,
      centerTitle: false,
      titleTextStyle: TextStyle(
        color: scheme.onSurface,
        fontSize: 20,
        fontWeight: FontWeight.w700,
      ),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(GranaRadius.card),
        side: BorderSide(color: scheme.outlineVariant),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(style: pillButtonStyle),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: pillButtonStyle.copyWith(
        side: WidgetStatePropertyAll(BorderSide(color: scheme.outline)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(style: pillButtonStyle),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        minimumSize: const Size(
          GranaSpacing.alvoDeToque,
          GranaSpacing.alvoDeToque,
        ),
      ),
    ),
    chipTheme: ChipThemeData(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(GranaRadius.chip),
      ),
      side: BorderSide(color: scheme.outlineVariant),
      selectedColor: scheme.primaryContainer,
      backgroundColor: scheme.surfaceContainer,
      labelStyle: TextStyle(color: scheme.onSurface),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surfaceContainer,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(GranaRadius.field),
        borderSide: BorderSide(color: scheme.outlineVariant),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(GranaRadius.field),
        borderSide: BorderSide(color: scheme.outlineVariant),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(GranaRadius.field),
        borderSide: BorderSide(color: scheme.primary, width: 1.5),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      elevation: 0,
      backgroundColor: scheme.surfaceContainerLow,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(GranaRadius.sheet),
        ),
      ),
    ),
    dialogTheme: DialogThemeData(
      elevation: 0,
      backgroundColor: scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(GranaRadius.sheet),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      elevation: 0,
      backgroundColor: scheme.surfaceContainerLow,
      indicatorColor: scheme.primaryContainer,
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        final selected = states.contains(WidgetState.selected);
        return TextStyle(
          fontSize: 12,
          fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          color: selected ? scheme.onSurface : scheme.onSurfaceVariant,
        );
      }),
    ),
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: scheme.surfaceContainerLow,
      indicatorColor: scheme.primaryContainer,
      selectedIconTheme: IconThemeData(color: scheme.onPrimaryContainer),
      unselectedIconTheme: IconThemeData(color: scheme.onSurfaceVariant),
      selectedLabelTextStyle: TextStyle(
        color: scheme.onSurface,
        fontWeight: FontWeight.w700,
      ),
      unselectedLabelTextStyle: TextStyle(
        color: scheme.onSurfaceVariant,
        fontWeight: FontWeight.w500,
      ),
    ),
    dividerTheme: DividerThemeData(
      color: scheme.outlineVariant,
      thickness: 1,
      space: 1,
    ),
  );
}

ThemeData granaLightTheme() =>
    _buildTheme(granaLightColorScheme, GranaTokens.light);

ThemeData granaDarkTheme() =>
    _buildTheme(granaDarkColorScheme, GranaTokens.dark);
