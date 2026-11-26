import 'package:material_ui/material_ui.dart';

import '../finance/model.dart';
import '../finance/taxonomy.dart';

/// Spacing constants for the GranaPaCá design system ("Toca Editorial").
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
  static const Duration fast = Duration(milliseconds: 150);
  static const Duration standard = Duration(milliseconds: 240);
  static const Duration lookTrack = Duration(milliseconds: 120);
  static const Duration coverEyes = Duration(milliseconds: 220);
  static const Duration peek = Duration(milliseconds: 180);
  static const Duration calmError = Duration(milliseconds: 320);
  static const Duration celebrate = Duration(milliseconds: 520);

  static Duration duration(BuildContext context, [Duration normal = standard]) =>
      MediaQuery.disableAnimationsOf(context) ? Duration.zero : normal;
}

/// Brand display font family (headings & Paçoca voice).
const String granaBrandFontFamily = 'Plus Jakarta Sans';

/// UI & tabular numeric font family.
const String granaUiFontFamily = 'Inter';

TextStyle _granaTextStyle(
  String family,
  double size,
  double lineHeight,
  FontWeight weight,
) => TextStyle(
  fontFamily: family,
  fontSize: size,
  height: lineHeight / size,
  fontWeight: weight,
);

final TextTheme _granaBaseTextTheme = TextTheme(
  displayMedium: _granaTextStyle(granaBrandFontFamily, 36, 44, FontWeight.w700),
  displaySmall: _granaTextStyle(granaBrandFontFamily, 30, 38, FontWeight.w700),
  headlineLarge: _granaTextStyle(granaBrandFontFamily, 26, 34, FontWeight.w700),
  headlineMedium: _granaTextStyle(
    granaBrandFontFamily,
    22,
    30,
    FontWeight.w700,
  ),
  headlineSmall: _granaTextStyle(granaBrandFontFamily, 18, 26, FontWeight.w600),
  titleLarge: _granaTextStyle(granaUiFontFamily, 20, 28, FontWeight.w600),
  titleMedium: _granaTextStyle(granaUiFontFamily, 16, 24, FontWeight.w600),
  titleSmall: _granaTextStyle(granaUiFontFamily, 14, 20, FontWeight.w600),
  bodyLarge: _granaTextStyle(granaUiFontFamily, 16, 24, FontWeight.w400),
  bodyMedium: _granaTextStyle(granaUiFontFamily, 14, 20, FontWeight.w400),
  bodySmall: _granaTextStyle(granaUiFontFamily, 12, 16, FontWeight.w400),
  labelLarge: _granaTextStyle(granaUiFontFamily, 14, 20, FontWeight.w600),
  labelMedium: _granaTextStyle(granaUiFontFamily, 12, 16, FontWeight.w600),
  labelSmall: _granaTextStyle(granaUiFontFamily, 11, 16, FontWeight.w600),
);

/// Verified "Toca Editorial" light ColorScheme (WCAG AA 54/54 pairs).
const ColorScheme granaLightColorScheme = ColorScheme(
  brightness: Brightness.light,
  primary: Color(0xFFA84C19),
  onPrimary: Color(0xFFFFFFFF),
  primaryContainer: Color(0xFFFADCC7),
  onPrimaryContainer: Color(0xFF3D1804),
  secondary: Color(0xFF6F5A4A),
  onSecondary: Color(0xFFFFFFFF),
  secondaryContainer: Color(0xFFF2EAE1),
  onSecondaryContainer: Color(0xFF2B1F16),
  tertiary: Color(0xFF6B489E),
  onTertiary: Color(0xFFFFFFFF),
  tertiaryContainer: Color(0xFFECE1FA),
  onTertiaryContainer: Color(0xFF2A1450),
  error: Color(0xFFB53720),
  onError: Color(0xFFFFFFFF),
  errorContainer: Color(0xFFFCDDD5),
  onErrorContainer: Color(0xFF4D1307),
  surface: Color(0xFFFAF8F5),
  onSurface: Color(0xFF231C16),
  onSurfaceVariant: Color(0xFF63564B),
  surfaceDim: Color(0xFFEAE4DC),
  surfaceBright: Color(0xFFFFFFFF),
  surfaceContainerLowest: Color(0xFFFFFFFF),
  surfaceContainerLow: Color(0xFFFFFFFF),
  surfaceContainer: Color(0xFFF6F3EE),
  surfaceContainerHigh: Color(0xFFF1EDE7),
  surfaceContainerHighest: Color(0xFFECE8E1),
  outline: Color(0xFF8A7B6D),
  outlineVariant: Color(0xFFE8E2DA),
  inverseSurface: Color(0xFF2F2721),
  onInverseSurface: Color(0xFFF5F1EC),
  inversePrimary: Color(0xFFE5965C),
  shadow: Color(0xFF000000),
  scrim: Color(0xFF000000),
  surfaceTint: Color(0xFFA84C19),
);

/// Verified "Toca Noturna" dark ColorScheme (WCAG AA 54/54 pairs).
const ColorScheme granaDarkColorScheme = ColorScheme(
  brightness: Brightness.dark,
  primary: Color(0xFFE5965C),
  onPrimary: Color(0xFF211106),
  primaryContainer: Color(0xFF69320F),
  onPrimaryContainer: Color(0xFFFADCC7),
  secondary: Color(0xFFD6C3B3),
  onSecondary: Color(0xFF362619),
  secondaryContainer: Color(0xFF3B3129),
  onSecondaryContainer: Color(0xFFF2EAE1),
  tertiary: Color(0xFFB9A0EE),
  onTertiary: Color(0xFF2A1450),
  tertiaryContainer: Color(0xFF4B357A),
  onTertiaryContainer: Color(0xFFECE1FA),
  error: Color(0xFFFF8B73),
  onError: Color(0xFF4A1004),
  errorContainer: Color(0xFF7A2414),
  onErrorContainer: Color(0xFFFFDAD2),
  surface: Color(0xFF14110F),
  onSurface: Color(0xFFF5F1EC),
  onSurfaceVariant: Color(0xFFB5A89C),
  surfaceDim: Color(0xFF14110F),
  surfaceBright: Color(0xFF342E29),
  surfaceContainerLowest: Color(0xFF0E0C0A),
  surfaceContainerLow: Color(0xFF1E1A17),
  surfaceContainer: Color(0xFF241F1B),
  surfaceContainerHigh: Color(0xFF2A241F),
  surfaceContainerHighest: Color(0xFF312A24),
  outline: Color(0xFF8A7A6C),
  outlineVariant: Color(0xFF2E2823),
  inverseSurface: Color(0xFFF5F1EC),
  onInverseSurface: Color(0xFF231C16),
  inversePrimary: Color(0xFFA84C19),
  shadow: Color(0xFF000000),
  scrim: Color(0xFF000000),
  surfaceTint: Color(0xFFE5965C),
);

/// Semantic tokens and tabular monetary styles for GranaPaCá ("Toca Editorial").
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
    required this.falaPacoca,
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
  final TextStyle falaPacoca;

  static const List<FontFeature> tabularFeatures = [
    FontFeature.tabularFigures(),
  ];

  static const GranaTokens light = GranaTokens(
    mata: Color(0xFF1D6B48),
    milho: Color(0xFFE5A62B),
    sobreMilho: Color(0xFF231C16),
    rio: Color(0xFF22649C),
    essencial: Color(0xFF6F340E),
    importante: Color(0xFFA65E28),
    flexivel: Color(0xFFBC7638),
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
      Color(0xFFE4A777),
      Color(0xFFD28B52),
      Color(0xFFB86E33),
      Color(0xFF93511B),
      Color(0xFF67330C),
    ],
    valorDestaque: TextStyle(
      fontFamily: granaUiFontFamily,
      fontSize: 38,
      fontWeight: FontWeight.w700,
      height: 46 / 38,
      color: Color(0xFF231C16),
      fontFeatures: tabularFeatures,
    ),
    valorGrande: TextStyle(
      fontFamily: granaUiFontFamily,
      fontSize: 24,
      fontWeight: FontWeight.w600,
      height: 32 / 24,
      color: Color(0xFF231C16),
      fontFeatures: tabularFeatures,
    ),
    valorLinha: TextStyle(
      fontFamily: granaUiFontFamily,
      fontSize: 16,
      fontWeight: FontWeight.w600,
      height: 24 / 16,
      color: Color(0xFF231C16),
      fontFeatures: tabularFeatures,
    ),
    falaPacoca: TextStyle(
      fontFamily: granaBrandFontFamily,
      fontSize: 16,
      fontWeight: FontWeight.w500,
      height: 24 / 16,
      color: Color(0xFF231C16),
    ),
  );

  static const GranaTokens dark = GranaTokens(
    mata: Color(0xFF62C493),
    milho: Color(0xFFF3C35A),
    sobreMilho: Color(0xFF231C16),
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
      Color(0xFF7A4A26),
      Color(0xFF9C5E2E),
      Color(0xFFBE7638),
      Color(0xFFDA955C),
      Color(0xFFF5CBA4),
    ],
    valorDestaque: TextStyle(
      fontFamily: granaUiFontFamily,
      fontSize: 38,
      fontWeight: FontWeight.w700,
      height: 46 / 38,
      color: Color(0xFFF5F1EC),
      fontFeatures: tabularFeatures,
    ),
    valorGrande: TextStyle(
      fontFamily: granaUiFontFamily,
      fontSize: 24,
      fontWeight: FontWeight.w600,
      height: 32 / 24,
      color: Color(0xFFF5F1EC),
      fontFeatures: tabularFeatures,
    ),
    valorLinha: TextStyle(
      fontFamily: granaUiFontFamily,
      fontSize: 16,
      fontWeight: FontWeight.w600,
      height: 24 / 16,
      color: Color(0xFFF5F1EC),
      fontFeatures: tabularFeatures,
    ),
    falaPacoca: TextStyle(
      fontFamily: granaBrandFontFamily,
      fontSize: 16,
      fontWeight: FontWeight.w500,
      height: 24 / 16,
      color: Color(0xFFF5F1EC),
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
    TextStyle? falaPacoca,
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
    falaPacoca: falaPacoca ?? this.falaPacoca,
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
      falaPacoca:
          TextStyle.lerp(falaPacoca, other.falaPacoca, t) ?? falaPacoca,
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
  final textTheme = _granaBaseTextTheme.apply(
    bodyColor: scheme.onSurface,
    displayColor: scheme.onSurface,
  );
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
    fontFamily: granaUiFontFamily,
    textTheme: textTheme,
    extensions: [tokens],
    appBarTheme: AppBarTheme(
      elevation: 0,
      scrolledUnderElevation: 0,
      backgroundColor: scheme.surface,
      foregroundColor: scheme.onSurface,
      centerTitle: false,
      titleTextStyle: textTheme.titleLarge?.copyWith(
        fontWeight: FontWeight.w700,
        letterSpacing: -0.3,
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
      selectedColor: scheme.secondaryContainer,
      backgroundColor: scheme.surfaceContainer,
      labelStyle: TextStyle(color: scheme.onSurface),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surfaceContainerLowest,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(GranaRadius.field),
        borderSide: BorderSide(color: scheme.outline),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(GranaRadius.field),
        borderSide: BorderSide(color: scheme.outline),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(GranaRadius.field),
        borderSide: BorderSide(color: scheme.primary, width: 2),
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
      backgroundColor: scheme.surfaceContainer,
      indicatorColor: scheme.secondaryContainer,
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
      backgroundColor: scheme.surfaceContainer,
      indicatorColor: scheme.secondaryContainer,
      selectedIconTheme: IconThemeData(color: scheme.onSecondaryContainer),
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
