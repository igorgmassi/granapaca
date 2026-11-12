// Tema do GranaPaCá: Material 3 com os tokens de docs/design/tokens/tokens.json.
// Referência para a Parte 12; o destino final é app/lib/core/theme/.
// Fontes empacotadas (Baloo 2 e Figtree, OFL), nunca baixadas em tempo de execução.
import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';

abstract final class GranaEspaco {
  static const double x1 = 4, x2 = 8, x3 = 12, x4 = 16, x6 = 24, x8 = 32, x12 = 48;
  static const double margemCelular = 16, margemTablet = 24, margemDesktop = 32;
  static const double alvoDeToque = 48;
}

abstract final class GranaRaio {
  static const double chip = 12, campo = 12, cartao = 20, folha = 28, dialogo = 28;
}

abstract final class GranaMovimento {
  static const rapida = Duration(milliseconds: 150);
  static const micro = Duration(milliseconds: 200);
  static const microLonga = Duration(milliseconds: 250);
  static const transicao = Duration(milliseconds: 300);
  static const transicaoLonga = Duration(milliseconds: 400);
  static const contagem = Duration(milliseconds: 900);
  static const chuvaDeMoedas = Duration(milliseconds: 1200);
  static const padrao = Cubic(0.2, 0.0, 0.0, 1.0);
  static const entrada = Cubic(0.05, 0.7, 0.1, 1.0);
  static const saida = Cubic(0.3, 0.0, 0.8, 0.15);

  /// Com "reduzir movimento" ligado, animações viram troca direta.
  static Duration ou(BuildContext context, Duration d) =>
      MediaQuery.disableAnimationsOf(context) ? Duration.zero : d;
}

const _marca = 'Baloo 2';
const _interface = 'Figtree';
const _tnum = [FontFeature.tabularFigures()];

TextStyle _estilo(String familia, double tamanho, double altura, FontWeight peso) =>
    TextStyle(fontFamily: familia, fontSize: tamanho, height: altura / tamanho, fontWeight: peso);

final _textos = TextTheme(
  displayMedium: _estilo(_marca, 40, 48, FontWeight.w600),
  displaySmall: _estilo(_marca, 32, 40, FontWeight.w600),
  headlineLarge: _estilo(_marca, 28, 36, FontWeight.w600),
  headlineMedium: _estilo(_marca, 24, 32, FontWeight.w600),
  headlineSmall: _estilo(_marca, 20, 28, FontWeight.w600),
  titleLarge: _estilo(_interface, 20, 28, FontWeight.w600),
  titleMedium: _estilo(_interface, 16, 24, FontWeight.w600),
  titleSmall: _estilo(_interface, 14, 20, FontWeight.w600),
  bodyLarge: _estilo(_interface, 16, 24, FontWeight.w400),
  bodyMedium: _estilo(_interface, 14, 20, FontWeight.w400),
  bodySmall: _estilo(_interface, 12, 16, FontWeight.w400),
  labelLarge: _estilo(_interface, 14, 20, FontWeight.w600),
  labelMedium: _estilo(_interface, 12, 16, FontWeight.w600),
  labelSmall: _estilo(_interface, 11, 16, FontWeight.w600),
);

/// Tokens da marca que o ColorScheme do Material 3 não tem.
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
    required this.grafico,
    required this.outros,
    required this.valorDestaque,
    required this.valorGrande,
    required this.valorLinha,
    required this.falaPacoca,
  });

  /// Receitas e valores positivos.
  final Color mata;

  /// Destaques e avisos; sempre com [sobreMilho] por cima, nunca sozinho como ícone.
  final Color milho, sobreMilho;

  /// Informações e links.
  final Color rio;

  /// Escala de essencialidade; sempre com o nome do nível ou as pintas.
  final Color essencial, importante, flexivel;

  /// Cores dos grupos na ordem fixa da rosca: Moradia, Transporte, Alimentação,
  /// Saúde, Compras, Educação, Lazer, Assinaturas e serviços.
  final List<Color> grafico;
  final Color outros;

  /// Valores em Figtree com algarismos tabulares; os centavos usam [TextStyle.fontSize] menor.
  final TextStyle valorDestaque, valorGrande, valorLinha;
  final TextStyle falaPacoca;

  static final claro = GranaTokens(
    mata: const Color(0xFF2A7550),
    milho: const Color(0xFFE5A62B),
    sobreMilho: const Color(0xFF2A1C12),
    rio: const Color(0xFF22649C),
    essencial: const Color(0xFF6F340E),
    importante: const Color(0xFFA65E28),
    flexivel: const Color(0xFFC17C3E),
    grafico: const [
      Color(0xFF8B3E05), Color(0xFF277BD0), Color(0xFFA78511), Color(0xFF267E4E),
      Color(0xFFFE903C), Color(0xFF7F4B9D), Color(0xFFD54573), Color(0xFF02A8AA),
    ],
    outros: const Color(0xFFA3958A),
    valorDestaque: _estilo(_interface, 40, 48, FontWeight.w600).copyWith(fontFeatures: _tnum),
    valorGrande: _estilo(_interface, 24, 32, FontWeight.w600).copyWith(fontFeatures: _tnum),
    valorLinha: _estilo(_interface, 16, 24, FontWeight.w600).copyWith(fontFeatures: _tnum),
    falaPacoca: _estilo(_marca, 18, 26, FontWeight.w500),
  );

  static final escuro = claro.copyWith(
    mata: const Color(0xFF6CC596),
    milho: const Color(0xFFF3C35A),
    rio: const Color(0xFF7DB9EA),
    essencial: const Color(0xFFF5CBA4),
    importante: const Color(0xFFDA955C),
    flexivel: const Color(0xFFB5733C),
    grafico: const [
      Color(0xFF9D4005), Color(0xFF2B7DDA), Color(0xFF8D741C), Color(0xFF31AD6D),
      Color(0xFFD67B16), Color(0xFF7A56B0), Color(0xFFCE436A), Color(0xFF008E97),
    ],
    outros: const Color(0xFF8A7D73),
  );

  @override
  GranaTokens copyWith({
    Color? mata, Color? milho, Color? sobreMilho, Color? rio,
    Color? essencial, Color? importante, Color? flexivel,
    List<Color>? grafico, Color? outros,
    TextStyle? valorDestaque, TextStyle? valorGrande, TextStyle? valorLinha, TextStyle? falaPacoca,
  }) =>
      GranaTokens(
        mata: mata ?? this.mata,
        milho: milho ?? this.milho,
        sobreMilho: sobreMilho ?? this.sobreMilho,
        rio: rio ?? this.rio,
        essencial: essencial ?? this.essencial,
        importante: importante ?? this.importante,
        flexivel: flexivel ?? this.flexivel,
        grafico: grafico ?? this.grafico,
        outros: outros ?? this.outros,
        valorDestaque: valorDestaque ?? this.valorDestaque,
        valorGrande: valorGrande ?? this.valorGrande,
        valorLinha: valorLinha ?? this.valorLinha,
        falaPacoca: falaPacoca ?? this.falaPacoca,
      );

  @override
  GranaTokens lerp(GranaTokens? other, double t) {
    if (other == null) return this;
    Color c(Color a, Color b) => Color.lerp(a, b, t)!;
    TextStyle s(TextStyle a, TextStyle b) => TextStyle.lerp(a, b, t)!;
    return GranaTokens(
      mata: c(mata, other.mata),
      milho: c(milho, other.milho),
      sobreMilho: c(sobreMilho, other.sobreMilho),
      rio: c(rio, other.rio),
      essencial: c(essencial, other.essencial),
      importante: c(importante, other.importante),
      flexivel: c(flexivel, other.flexivel),
      grafico: [for (var i = 0; i < grafico.length; i++) c(grafico[i], other.grafico[i])],
      outros: c(outros, other.outros),
      valorDestaque: s(valorDestaque, other.valorDestaque),
      valorGrande: s(valorGrande, other.valorGrande),
      valorLinha: s(valorLinha, other.valorLinha),
      falaPacoca: s(falaPacoca, other.falaPacoca),
    );
  }
}

const _claro = ColorScheme(
  brightness: Brightness.light,
  primary: Color(0xFFA0521A), onPrimary: Color(0xFFFFFFFF),
  primaryContainer: Color(0xFFFADCC4), onPrimaryContainer: Color(0xFF3D1A03),
  secondary: Color(0xFF7A5A43), onSecondary: Color(0xFFFFFFFF),
  secondaryContainer: Color(0xFFF3E3D3), onSecondaryContainer: Color(0xFF2E1C0F),
  tertiary: Color(0xFF6E4AA3), onTertiary: Color(0xFFFFFFFF),
  tertiaryContainer: Color(0xFFECE1FA), onTertiaryContainer: Color(0xFF2A1450),
  error: Color(0xFFB83A22), onError: Color(0xFFFFFFFF),
  errorContainer: Color(0xFFFCDDD5), onErrorContainer: Color(0xFF4D1307),
  surface: Color(0xFFFBF5EC), onSurface: Color(0xFF2A1C12), onSurfaceVariant: Color(0xFF6B5546),
  surfaceDim: Color(0xFFE3D6C6), surfaceBright: Color(0xFFFFFCF8),
  surfaceContainerLowest: Color(0xFFFFFFFF), surfaceContainerLow: Color(0xFFFFFFFF),
  surfaceContainer: Color(0xFFF7F0E6), surfaceContainerHigh: Color(0xFFF3ECE2),
  surfaceContainerHighest: Color(0xFFF0E7DB),
  outline: Color(0xFF94816E), outlineVariant: Color(0xFFE5D9CA),
  inverseSurface: Color(0xFF3B2D23), onInverseSurface: Color(0xFFF7EFE6), inversePrimary: Color(0xFFE8A066),
  shadow: Color(0xFF000000), scrim: Color(0xFF000000), surfaceTint: Color(0xFFA0521A),
);

const _escuro = ColorScheme(
  brightness: Brightness.dark,
  primary: Color(0xFFE8A066), onPrimary: Color(0xFF2A1407),
  primaryContainer: Color(0xFF6B3410), onPrimaryContainer: Color(0xFFFADCC4),
  secondary: Color(0xFFDCC1A9), onSecondary: Color(0xFF3A2717),
  secondaryContainer: Color(0xFF4E3B2C), onSecondaryContainer: Color(0xFFF3E3D3),
  tertiary: Color(0xFFB9A0EE), onTertiary: Color(0xFF2A1450),
  tertiaryContainer: Color(0xFF4B357A), onTertiaryContainer: Color(0xFFECE1FA),
  error: Color(0xFFFF8B73), onError: Color(0xFF4A1004),
  errorContainer: Color(0xFF7A2414), onErrorContainer: Color(0xFFFFDAD2),
  surface: Color(0xFF17110D), onSurface: Color(0xFFF7EFE6), onSurfaceVariant: Color(0xFFC4B2A2),
  surfaceDim: Color(0xFF17110D), surfaceBright: Color(0xFF3D3229),
  surfaceContainerLowest: Color(0xFF110C09), surfaceContainerLow: Color(0xFF221A14),
  surfaceContainer: Color(0xFF281F18), surfaceContainerHigh: Color(0xFF2D241B),
  surfaceContainerHighest: Color(0xFF33291F),
  outline: Color(0xFF86725F), outlineVariant: Color(0xFF3F342A),
  inverseSurface: Color(0xFFF7EFE6), onInverseSurface: Color(0xFF2A1C12), inversePrimary: Color(0xFFA0521A),
  shadow: Color(0xFF000000), scrim: Color(0xFF000000), surfaceTint: Color(0xFFE8A066),
);

/// Tema do app. Uso: MaterialApp(theme: granaTema(Brightness.light), darkTheme: granaTema(Brightness.dark)).
ThemeData granaTema(Brightness brilho) {
  final cores = brilho == Brightness.light ? _claro : _escuro;
  final tokens = brilho == Brightness.light ? GranaTokens.claro : GranaTokens.escuro;
  final textos = _textos.apply(bodyColor: cores.onSurface, displayColor: cores.onSurface);
  const pilula = StadiumBorder();
  const tamanhoBotao = Size(64, GranaEspaco.alvoDeToque);

  return ThemeData(
    useMaterial3: true,
    colorScheme: cores,
    scaffoldBackgroundColor: cores.surface,
    fontFamily: _interface,
    textTheme: textos,
    materialTapTargetSize: MaterialTapTargetSize.padded,
    extensions: [tokens],
    cardTheme: CardThemeData(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: cores.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(GranaRaio.cartao),
        side: BorderSide(color: cores.outlineVariant),
      ),
    ),
    chipTheme: ChipThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(GranaRaio.chip)),
      labelStyle: textos.labelLarge,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(minimumSize: tamanhoBotao, shape: pilula, textStyle: textos.labelLarge),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(minimumSize: tamanhoBotao, shape: pilula, textStyle: textos.labelLarge),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(minimumSize: tamanhoBotao, shape: pilula, textStyle: textos.labelLarge),
    ),
    inputDecorationTheme: InputDecorationTheme(
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(GranaRaio.campo),
        borderSide: BorderSide(color: cores.outline),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(GranaRaio.campo),
        borderSide: BorderSide(color: cores.outline),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(GranaRaio.campo),
        borderSide: BorderSide(color: cores.primary, width: 2),
      ),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: cores.surfaceContainerLow,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(GranaRaio.folha)),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: cores.surfaceContainerLow,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(GranaRaio.dialogo)),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: cores.surfaceContainer,
      indicatorColor: cores.secondaryContainer,
      labelTextStyle: WidgetStatePropertyAll(textos.labelMedium),
    ),
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: cores.surfaceContainer,
      indicatorColor: cores.secondaryContainer,
    ),
    dividerTheme: DividerThemeData(color: cores.outlineVariant, thickness: 1, space: 1),
  );
}
