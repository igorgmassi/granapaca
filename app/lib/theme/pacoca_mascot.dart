import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import 'grana_theme.dart';

/// Interactive animation moods for the refined Paçoca mascot during account
/// creation, security checks, and calm insights (Toca Editorial).
enum PacocaMood {
  /// Welcoming pose perched above a card; tracks directional selection via gaze.
  welcome,

  /// Curious leaning pose tracking email/name/URL text input via [gazeX].
  trackingInput,

  /// Privacy gesture: both paws rise smoothly to cover the eyes on password focus.
  coveringEyes,

  /// Shy one-paw peek when the user reveals the password text.
  peekingPassword,

  /// Holding a glowing emerald-and-gold padlock shield during 2FA / PIN / biometrics.
  securityShield,

  /// Serene horizontal head-shake without drama on validation/code error.
  calmError,

  /// Joyful elastic hop with 3 golden-cream coin dots floating upward on completion.
  celebrating,

  /// Compact framed bust portrait for insight cards and assistant header.
  portrait,
}

/// Option B ("Paca Deitada Evoluída") wordmark + lineless resting spotted paca
/// rendered natively in Flutter with crisp Light & Dark contrast.
class GranaPacaLogo extends StatelessWidget {
  const GranaPacaLogo({
    super.key,
    this.compact = false,
    this.showTagline = false,
  });

  final bool compact;
  final bool showTagline;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fontSize = compact ? 22.0 : 30.0;
    final pacaW = compact ? 42.0 : 58.0;
    final pacaH = compact ? 25.0 : 34.0;
    final pacaFill = scheme.primary;
    final spotCutout = scheme.surface;

    return Semantics(
      label: showTagline
          ? 'Grana PaCá. Toda a sua grana, pra cá.'
          : 'Grana PaCá',
      excludeSemantics: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.bottomLeft,
            children: [
              Padding(
                padding: EdgeInsets.only(top: pacaH * 0.62),
                child: Text.rich(
                  TextSpan(
                    style: TextStyle(
                      fontFamily: granaBrandFontFamily,
                      fontSize: fontSize,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.8,
                      height: 1.0,
                    ),
                    children: [
                      TextSpan(
                        text: 'Grana ',
                        style: TextStyle(color: scheme.onSurface),
                      ),
                      TextSpan(
                        text: 'PaCá',
                        style: TextStyle(color: scheme.primary),
                      ),
                    ],
                  ),
                ),
              ),
              Positioned(
                right: compact ? 8 : 12,
                top: 0,
                child: SizedBox(
                  width: pacaW,
                  height: pacaH,
                  child: CustomPaint(
                    painter: _RestingPacaPainter(
                      bodyColor: pacaFill,
                      detailColor: spotCutout,
                    ),
                  ),
                ),
              ),
            ],
          ),
          if (showTagline) ...[
            const SizedBox(height: 4),
            Text(
              'Toda a sua grana, pra cá.',
              style: TextStyle(
                fontSize: compact ? 12 : 14,
                fontWeight: FontWeight.w500,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Standalone Option B resting-paca app mark inside a rounded squircle.
class RestingPacaMark extends StatelessWidget {
  const RestingPacaMark({super.key, this.size = 48});

  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = scheme.brightness == Brightness.dark;
    final bg = isDark ? scheme.surfaceContainerLow : scheme.primary;
    final fg = isDark ? scheme.primary : scheme.surface;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(size * 0.26),
        border: isDark ? Border.all(color: scheme.outlineVariant) : null,
      ),
      padding: EdgeInsets.all(size * 0.14),
      child: CustomPaint(
        painter: _RestingPacaPainter(bodyColor: fg, detailColor: bg),
      ),
    );
  }
}

class _RestingPacaPainter extends CustomPainter {
  const _RestingPacaPainter({
    required this.bodyColor,
    required this.detailColor,
  });

  final Color bodyColor;
  final Color detailColor;

  @override
  void paint(Canvas canvas, Size size) {
    final sx = size.width / 200;
    final sy = size.height / 132;
    canvas.save();
    canvas.scale(sx, sy);

    final bodyPaint = Paint()
      ..color = bodyColor
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;

    // Lineless curled resting spotted paca matching docs/design/logo/gerar-logo.mjs.
    final path = Path()
      ..moveTo(14, 96)
      ..cubicTo(9, 66, 30, 36, 76, 32)
      ..cubicTo(93, 30, 107, 29, 116, 22)
      ..cubicTo(114, 11, 121, 4, 129, 7)
      ..cubicTo(133, 9, 135, 13, 136, 17)
      ..cubicTo(141, 10, 148, 8, 154, 14)
      ..cubicTo(157, 18, 156, 24, 153, 28)
      ..cubicTo(172, 32, 191, 44, 192, 59)
      ..cubicTo(193, 73, 181, 81, 165, 81)
      ..cubicTo(154, 81, 146, 78, 137, 76)
      ..cubicTo(142, 84, 142, 95, 133, 103)
      ..cubicTo(122, 113, 101, 116, 74, 116)
      ..cubicTo(39, 116, 18, 109, 14, 96)
      ..close();
    canvas.drawPath(path, bodyPaint);

    final spotPaint = Paint()
      ..color = detailColor
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;

    const spots = [
      (48.0, 61.0, 7.2, 4.2, -0.31),
      (71.0, 53.0, 7.8, 4.4, -0.21),
      (95.0, 51.0, 7.2, 4.1, -0.10),
      (42.0, 79.0, 7.6, 4.4, -0.24),
      (67.0, 73.0, 8.2, 4.6, -0.17),
    ];
    for (final (x, y, rx, ry, rot) in spots) {
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(rot);
      canvas.drawOval(
        Rect.fromCenter(center: Offset.zero, width: rx * 2, height: ry * 2),
        spotPaint,
      );
      canvas.restore();
    }

    final strokePaint = Paint()
      ..color = detailColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5.0
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true;

    // Peaceful closed eye arc
    final eye = Path()
      ..moveTo(145, 50)
      ..quadraticBezierTo(154, 57, 163, 50);
    canvas.drawPath(eye, strokePaint);

    // Subtle tucked front paw fold
    final pawFold = Path()
      ..moveTo(96, 99)
      ..cubicTo(110, 99, 124, 93, 131, 82);
    canvas.drawPath(pawFold, strokePaint..strokeWidth = 4.5);

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _RestingPacaPainter oldDelegate) =>
      oldDelegate.bodyColor != bodyColor ||
      oldDelegate.detailColor != detailColor;
}

/// Interactive animated widget for the refined Paçoca mascot (soft lineless
/// illustrated style, gently elongated Brazilian paca snout, NO fanny pack).
///
/// All animations use finite settling durations so reduced-motion preferences
/// (`MediaQuery.disableAnimationsOf`) and widget tests (`pumpAndSettle`) work
/// cleanly without infinite tickers.
class AnimatedPacocaMascot extends StatefulWidget {
  const AnimatedPacocaMascot({
    super.key,
    required this.mood,
    this.gazeX = 0.0,
    this.gazeY = 0.0,
    this.securityProgress = 0.0,
    this.errorSignal = 0,
    this.size = 132,
    this.semanticLabel,
  });

  final PacocaMood mood;

  /// Horizontal gaze / head direction from `-1.0` (left) to `1.0` (right).
  final double gazeX;

  /// Vertical gaze offset from `-1.0` (up) to `1.0` (down).
  final double gazeY;

  /// Progress `0.0..1.0` illuminating the 3 spots on the security shield.
  final double securityProgress;

  /// Incrementing counter that triggers a calm head-shake pulse when changed.
  final int errorSignal;

  /// Square layout size (height in logical pixels; width scales proportionally).
  final double size;

  /// Optional accessibility label; when omitted, defaults to a descriptive
  /// Portuguese state summary for the current [mood].
  final String? semanticLabel;

  @override
  State<AnimatedPacocaMascot> createState() => _AnimatedPacocaMascotState();
}

class _AnimatedPacocaMascotState extends State<AnimatedPacocaMascot>
    with TickerProviderStateMixin {
  late final AnimationController _poseController;
  late final AnimationController _gazeController;
  late final AnimationController _shakeController;
  late final AnimationController _celebrateController;

  double _fromCover = 0;
  double _toCover = 0;
  double _fromPeek = 0;
  double _toPeek = 0;
  double _fromShield = 0;
  double _toShield = 0;

  double _fromGazeX = 0;
  double _toGazeX = 0;
  double _fromGazeY = 0;
  double _toGazeY = 0;

  @override
  void initState() {
    super.initState();
    _poseController = AnimationController(
      vsync: this,
      duration: GranaMotion.coverEyes,
      value: 1,
    );
    _gazeController = AnimationController(
      vsync: this,
      duration: GranaMotion.lookTrack,
      value: 1,
    );
    _shakeController = AnimationController(
      vsync: this,
      duration: GranaMotion.calmError,
    );
    _celebrateController = AnimationController(
      vsync: this,
      duration: GranaMotion.celebrate,
    );

    _applyTargetsInstant();
  }

  void _applyTargetsInstant() {
    _toCover = _targetCover(widget.mood);
    _fromCover = _toCover;
    _toPeek = _targetPeek(widget.mood);
    _fromPeek = _toPeek;
    _toShield = _targetShield(widget.mood);
    _fromShield = _toShield;
    _toGazeX = widget.gazeX.clamp(-1.0, 1.0);
    _fromGazeX = _toGazeX;
    _toGazeY = widget.gazeY.clamp(-1.0, 1.0);
    _fromGazeY = _toGazeY;
    if (widget.mood == PacocaMood.celebrating) {
      _celebrateController.value = 1;
    }
  }

  static double _targetCover(PacocaMood m) =>
      (m == PacocaMood.coveringEyes || m == PacocaMood.peekingPassword) ? 1 : 0;

  static double _targetPeek(PacocaMood m) =>
      m == PacocaMood.peekingPassword ? 1 : 0;

  static double _targetShield(PacocaMood m) =>
      m == PacocaMood.securityShield ? 1 : 0;

  double _lerp(double a, double b, double t) => a + (b - a) * t;

  @override
  void didUpdateWidget(covariant AnimatedPacocaMascot oldWidget) {
    super.didUpdateWidget(oldWidget);
    final disableAnimations = MediaQuery.disableAnimationsOf(context);

    final nextCover = _targetCover(widget.mood);
    final nextPeek = _targetPeek(widget.mood);
    final nextShield = _targetShield(widget.mood);
    final poseChanged =
        nextCover != _toCover || nextPeek != _toPeek || nextShield != _toShield;

    if (poseChanged) {
      final t = Curves.easeOutCubic.transform(_poseController.value);
      _fromCover = _lerp(_fromCover, _toCover, t);
      _fromPeek = _lerp(_fromPeek, _toPeek, t);
      _fromShield = _lerp(_fromShield, _toShield, t);
      _toCover = nextCover;
      _toPeek = nextPeek;
      _toShield = nextShield;

      if (disableAnimations) {
        _poseController.value = 1;
      } else {
        _poseController.duration = widget.mood == PacocaMood.peekingPassword
            ? GranaMotion.peek
            : GranaMotion.coverEyes;
        _poseController.forward(from: 0);
      }
    }

    final clampedX = widget.gazeX.clamp(-1.0, 1.0);
    final clampedY = widget.gazeY.clamp(-1.0, 1.0);
    if (clampedX != _toGazeX || clampedY != _toGazeY) {
      final t = Curves.easeOut.transform(_gazeController.value);
      _fromGazeX = _lerp(_fromGazeX, _toGazeX, t);
      _fromGazeY = _lerp(_fromGazeY, _toGazeY, t);
      _toGazeX = clampedX;
      _toGazeY = clampedY;
      if (disableAnimations) {
        _gazeController.value = 1;
      } else {
        _gazeController.forward(from: 0);
      }
    }

    final shouldShake =
        widget.errorSignal != oldWidget.errorSignal ||
        (widget.mood == PacocaMood.calmError &&
            oldWidget.mood != PacocaMood.calmError);
    if (shouldShake) {
      if (disableAnimations) {
        _shakeController.value = 0;
      } else {
        _shakeController.forward(from: 0);
      }
    }

    if (widget.mood == PacocaMood.celebrating &&
        oldWidget.mood != PacocaMood.celebrating) {
      if (disableAnimations) {
        _celebrateController.value = 1;
      } else {
        _celebrateController.forward(from: 0);
      }
    } else if (widget.mood != PacocaMood.celebrating &&
        oldWidget.mood == PacocaMood.celebrating) {
      _celebrateController.value = 0;
    }
  }

  @override
  void dispose() {
    _poseController.dispose();
    _gazeController.dispose();
    _shakeController.dispose();
    _celebrateController.dispose();
    super.dispose();
  }

  String get _defaultSemanticLabel {
    if (widget.semanticLabel != null) return widget.semanticLabel!;
    switch (widget.mood) {
      case PacocaMood.welcome:
        return 'Paçoca dando boas-vindas';
      case PacocaMood.trackingInput:
        return 'Paçoca acompanhando o preenchimento';
      case PacocaMood.coveringEyes:
        return 'Paçoca tampando os olhos por privacidade na senha';
      case PacocaMood.peekingPassword:
        return 'Paçoca dando uma espiadinha com uma pata';
      case PacocaMood.securityShield:
        return 'Paçoca segurando um escudo com cadeado';
      case PacocaMood.calmError:
        return 'Paçoca sinalizando calma para revisar os dados';
      case PacocaMood.celebrating:
        return 'Paçoca comemorando com moedinhas';
      case PacocaMood.portrait:
        return 'Retrato da Paçoca';
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tokens = GranaTokens.of(context);
    final reducedMotion = MediaQuery.disableAnimationsOf(context);
    final isPortrait = widget.mood == PacocaMood.portrait;

    return Semantics(
      label: _defaultSemanticLabel,
      image: true,
      child: AnimatedBuilder(
        animation: Listenable.merge([
          _poseController,
          _gazeController,
          _shakeController,
          _celebrateController,
        ]),
        builder: (context, _) {
          final poseT = Curves.easeOutCubic.transform(_poseController.value);
          final gazeT = Curves.easeOut.transform(_gazeController.value);
          final cover = _lerp(_fromCover, _toCover, poseT);
          final peek = _lerp(_fromPeek, _toPeek, poseT);
          final shield = _lerp(_fromShield, _toShield, poseT);
          final gx = _lerp(_fromGazeX, _toGazeX, gazeT);
          final gy = _lerp(_fromGazeY, _toGazeY, gazeT);

          final shakeProgress = _shakeController.value;
          final shakeOffset = reducedMotion || shakeProgress == 0
              ? 0.0
              : math.sin(shakeProgress * math.pi * 4) *
                    (1 - shakeProgress) *
                    8.0;

          final celebrateT = widget.mood == PacocaMood.celebrating
              ? _celebrateController.value
              : 0.0;

          return SizedBox(
            width: isPortrait ? widget.size : widget.size * 1.35,
            height: widget.size,
            child: CustomPaint(
              painter: _PacocaPainter(
                mood: widget.mood,
                coverProgress: cover,
                peekProgress: peek,
                shieldProgress: shield,
                securityProgress: widget.securityProgress.clamp(0.0, 1.0),
                gazeX: gx,
                gazeY: gy,
                shakeOffset: shakeOffset,
                celebrateProgress: celebrateT,
                reducedMotion: reducedMotion,
                shieldColor: tokens.mata,
                goldColor: tokens.milho,
                portraitBg: scheme.secondaryContainer,
                borderColor: scheme.outlineVariant,
              ),
            ),
          );
        },
      ),
    );
  }
}

class _PacocaPainter extends CustomPainter {
  const _PacocaPainter({
    required this.mood,
    required this.coverProgress,
    required this.peekProgress,
    required this.shieldProgress,
    required this.securityProgress,
    required this.gazeX,
    required this.gazeY,
    required this.shakeOffset,
    required this.celebrateProgress,
    required this.reducedMotion,
    required this.shieldColor,
    required this.goldColor,
    required this.portraitBg,
    required this.borderColor,
  });

  final PacocaMood mood;
  final double coverProgress;
  final double peekProgress;
  final double shieldProgress;
  final double securityProgress;
  final double gazeX;
  final double gazeY;
  final double shakeOffset;
  final double celebrateProgress;
  final bool reducedMotion;
  final Color shieldColor;
  final Color goldColor;
  final Color portraitBg;
  final Color borderColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (mood == PacocaMood.portrait) {
      _paintPortrait(canvas, size);
      return;
    }

    // Coordinate canvas normalized around width 180, height 136 with base at y=132.
    final scale = math.min(size.width / 180, size.height / 136);
    canvas.save();
    canvas.translate(size.width / 2, size.height - 4 * scale);
    canvas.scale(scale, scale);

    final hopY = reducedMotion
        ? 0.0
        : -math.sin(celebrateProgress * math.pi) * 14.0;

    // 1. Floating coin dots during celebration
    if (celebrateProgress > 0.05) {
      _paintCelebrationCoins(canvas, celebrateProgress);
    }

    canvas.save();
    canvas.translate(0, hopY);

    // 2. Soft lineless torso (NO fanny pack — clean continuous cream belly + neat flank spots)
    _paintTorso(canvas);

    // 3. Raised celebration arms behind/beside body
    if (celebrateProgress > 0.05) {
      _paintCelebratingArms(canvas, celebrateProgress);
    }

    // 4. Head with gently elongated Brazilian paca snout, soft cheeks, ears & eyes
    final headDx = gazeX * 5.5 + shakeOffset * 0.65;
    final headDy = gazeY * 3.0;
    final headRot = gazeX * 0.08 + shakeOffset * 0.012;
    canvas.save();
    canvas.translate(headDx, headDy);
    canvas.rotate(headRot);
    _paintHead(canvas);
    canvas.restore();

    // 5. Interactive paws (resting on card edge -> covering eyes -> shy one-paw peek)
    if (celebrateProgress < 0.2 && shieldProgress < 0.5) {
      _paintInteractivePaws(canvas, headDx, headDy);
    }

    // 6. Glowing emerald & gold padlock shield during 2FA / PIN / security step
    if (shieldProgress > 0.02) {
      _paintSecurityShield(canvas, shieldProgress);
    }

    canvas.restore();
    canvas.restore();
  }

  void _paintPortrait(Canvas canvas, Size size) {
    final radius = math.min(size.width, size.height) / 2;
    final center = Offset(size.width / 2, size.height / 2);

    canvas.drawCircle(center, radius, Paint()..color = portraitBg);
    canvas.drawCircle(
      center,
      radius - 0.75,
      Paint()
        ..color = borderColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2,
    );

    canvas.save();
    canvas.clipPath(
      Path()..addOval(Rect.fromCircle(center: center, radius: radius - 1)),
    );
    final s = radius / 50;
    canvas.translate(center.dx, center.dy + radius * 1.28);
    canvas.scale(s, s);
    _paintTorso(canvas);
    _paintHead(canvas);
    canvas.restore();
  }

  void _paintTorso(Canvas canvas) {
    final furRect = const Rect.fromLTWH(-46, -58, 92, 62);
    final furPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFFD68D54), Color(0xFFC1723B), Color(0xFFA95E2C)],
      ).createShader(furRect);

    final torso = Path()
      ..moveTo(-45, 0)
      ..cubicTo(-49, -34, -36, -56, 0, -56)
      ..cubicTo(36, -56, 49, -34, 45, 0)
      ..close();
    canvas.drawPath(torso, furPaint);

    // Clean, uninterrupted warm cream belly (no fanny pack!)
    final bellyRect = Rect.fromCenter(
      center: const Offset(0, -16),
      width: 50,
      height: 50,
    );
    final bellyPaint = Paint()
      ..shader = const RadialGradient(
        center: Alignment(0, -0.3),
        radius: 0.9,
        colors: [Color(0xFFFAF0DF), Color(0xFFF1DCBE)],
      ).createShader(bellyRect);
    canvas.drawOval(bellyRect, bellyPaint);

    // Neat paca oval cream spots along both caramel flanks
    final spotPaint = Paint()..color = const Color(0xFFF8E8CF);
    const flankSpots = [
      (-39.0, -35.0, 4.4, 7.6, -0.22),
      (-32.0, -16.0, 4.0, 6.8, -0.14),
      (39.0, -35.0, 4.4, 7.6, 0.22),
      (32.0, -16.0, 4.0, 6.8, 0.14),
    ];
    for (final (x, y, rx, ry, rot) in flankSpots) {
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(rot);
      canvas.drawOval(
        Rect.fromCenter(center: Offset.zero, width: rx * 2, height: ry * 2),
        spotPaint,
      );
      canvas.restore();
    }
  }

  void _paintHead(Canvas canvas) {
    // Small rounded ears set softly along the paca crown
    _paintEar(canvas, const Offset(-33, -99), -0.34);
    _paintEar(canvas, const Offset(33, -99), 0.34);

    // Head base with soft radial brushwork gradient + rounded fuller lower paca cheeks
    final headRect = const Rect.fromLTWH(-46, -112, 92, 78);
    final headPaint = Paint()
      ..shader = const RadialGradient(
        center: Alignment(0, -0.35),
        radius: 0.95,
        colors: [Color(0xFFDF985E), Color(0xFFC87A42), Color(0xFFB16430)],
      ).createShader(headRect);

    final headPath = Path()
      ..moveTo(-42, -72)
      ..cubicTo(-44, -99, -25, -111, 0, -111)
      ..cubicTo(25, -111, 44, -99, 42, -72)
      ..cubicTo(45, -52, 30, -36, 0, -35)
      ..cubicTo(-30, -36, -45, -52, -42, -72)
      ..close();
    canvas.drawPath(headPath, headPaint);

    // Subtle soft crown spot accents for warmth
    final crownHighlight = Paint()
      ..color = const Color(0xFFE7A972).withValues(alpha: 0.35);
    canvas.drawOval(
      Rect.fromCenter(center: const Offset(0, -96), width: 32, height: 14),
      crownHighlight,
    );

    // Gently elongated rounded Brazilian paca muzzle/snout
    final snoutRect = Rect.fromCenter(
      center: Offset(gazeX * 2.2, -52.5),
      width: 48,
      height: 31,
    );
    final snoutPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFFFCF2E2), Color(0xFFF1DBC0)],
      ).createShader(snoutRect);
    canvas.drawOval(snoutRect, snoutPaint);

    // Soft peach rounded paca nose sitting slightly lower along the elongated snout
    final noseCenter = Offset(gazeX * 3.0, -59.5);
    final noseRect = Rect.fromCenter(center: noseCenter, width: 19, height: 12.5);
    canvas.drawOval(
      noseRect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFEF9E84), Color(0xFFD97C63)],
        ).createShader(noseRect),
    );
    // Tiny warm nose highlight
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(noseCenter.dx - 3, noseCenter.dy - 2.4),
        width: 5.5,
        height: 2.6,
      ),
      Paint()..color = const Color(0xFFFFD8C9).withValues(alpha: 0.7),
    );

    // Gentle friendly smile (or calm thoughtful mouth on calmError)
    final mouthPaint = Paint()
      ..color = const Color(0xFF3A2011)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.1
      ..strokeCap = StrokeCap.round;

    final mouthCx = gazeX * 2.4;
    if (mood == PacocaMood.calmError) {
      canvas.drawLine(
        Offset(mouthCx, -53),
        Offset(mouthCx, -49),
        mouthPaint,
      );
      final calmMouth = Path()
        ..moveTo(mouthCx - 7, -47)
        ..quadraticBezierTo(mouthCx, -49, mouthCx + 7, -47);
      canvas.drawPath(calmMouth, mouthPaint);
    } else if (celebrateProgress > 0.25) {
      // Happy open grin
      final grin = Path()
        ..moveTo(mouthCx - 9, -49)
        ..quadraticBezierTo(mouthCx, -39, mouthCx + 9, -49)
        ..close();
      canvas.drawPath(grin, Paint()..color = const Color(0xFF5D2614));
      canvas.drawPath(
        Path()
          ..moveTo(mouthCx - 10, -49.5)
          ..quadraticBezierTo(mouthCx, -45.5, mouthCx + 10, -49.5),
        mouthPaint,
      );
    } else {
      canvas.drawLine(
        Offset(mouthCx, -53),
        Offset(mouthCx, -49),
        mouthPaint,
      );
      final smile = Path()
        ..moveTo(mouthCx - 8.5, -49)
        ..quadraticBezierTo(mouthCx, -43.5, mouthCx + 8.5, -49);
      canvas.drawPath(smile, mouthPaint);
    }

    // Delicate paca whiskers
    final whiskerPaint = Paint()
      ..color = const Color(0xFF8C532B).withValues(alpha: 0.55)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(
      Path()
        ..moveTo(-30, -56)
        ..quadraticBezierTo(-45, -58, -56, -53)
        ..moveTo(-30, -50)
        ..quadraticBezierTo(-44, -49, -54, -44)
        ..moveTo(30, -56)
        ..quadraticBezierTo(45, -58, 56, -53)
        ..moveTo(30, -50)
        ..quadraticBezierTo(44, -49, 54, -44),
      whiskerPaint,
    );

    // Expressive dark eyes with bright catchlights (or happy curved eyes on celebration)
    if (celebrateProgress > 0.25) {
      final happyEye = Paint()
        ..color = const Color(0xFF2B180D)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.2
        ..strokeCap = StrokeCap.round;
      canvas.drawPath(
        Path()
          ..moveTo(-25, -76)
          ..quadraticBezierTo(-18, -84, -11, -76)
          ..moveTo(11, -76)
          ..quadraticBezierTo(18, -84, 25, -76),
        happyEye,
      );
    } else {
      _paintEye(canvas, const Offset(-18, -77), gazeX * 3.4, gazeY * 2.6);
      _paintEye(canvas, const Offset(18, -77), gazeX * 3.4, gazeY * 2.6);

      // Gentle empathetic eyebrows on calmError
      if (mood == PacocaMood.calmError) {
        final browPaint = Paint()
          ..color = const Color(0xFF7B421D)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.4
          ..strokeCap = StrokeCap.round;
        canvas.drawLine(const Offset(-25, -90), const Offset(-12, -93), browPaint);
        canvas.drawLine(const Offset(25, -90), const Offset(12, -93), browPaint);
      }
    }
  }

  void _paintEar(Canvas canvas, Offset center, double rotation) {
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(rotation);
    canvas.drawOval(
      Rect.fromCenter(center: Offset.zero, width: 22, height: 20),
      Paint()..color = const Color(0xFFB56632),
    );
    canvas.drawOval(
      Rect.fromCenter(center: const Offset(0, 1.5), width: 13, height: 11.5),
      Paint()..color = const Color(0xFFEDA68D),
    );
    canvas.restore();
  }

  void _paintEye(Canvas canvas, Offset center, double px, double py) {
    final eyeCenter = Offset(center.dx + px * 0.45, center.dy + py * 0.45);
    canvas.drawOval(
      Rect.fromCenter(center: eyeCenter, width: 14.5, height: 17.5),
      Paint()..color = const Color(0xFF28160B),
    );
    // Primary bright catchlight
    canvas.drawCircle(
      Offset(eyeCenter.dx - 2.2 + px * 0.35, eyeCenter.dy - 3.6 + py * 0.35),
      2.8,
      Paint()..color = const Color(0xFFFFFFFF),
    );
    // Secondary tiny sparkle
    canvas.drawCircle(
      Offset(eyeCenter.dx + 2.5 + px * 0.2, eyeCenter.dy + 3.0 + py * 0.2),
      1.2,
      Paint()..color = const Color(0xFFFFFFFF).withValues(alpha: 0.7),
    );
  }

  void _paintInteractivePaws(Canvas canvas, double headDx, double headDy) {
    final pawPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFFDD955D), Color(0xFFC07039)],
      ).createShader(const Rect.fromLTWH(-46, -92, 92, 98));

    // Left paw smoothly travels from resting on the card edge (y=0) up over left eye (-18, -77)
    final leftLift = coverProgress;
    // Right paw lowers halfway when peekingPassword is active!
    final rightLift = coverProgress * (1 - peekProgress * 0.56);

    _paintSinglePaw(
      canvas,
      pawPaint,
      isLeft: true,
      lift: leftLift,
      headDx: headDx,
      headDy: headDy,
    );
    _paintSinglePaw(
      canvas,
      pawPaint,
      isLeft: false,
      lift: rightLift,
      headDx: headDx,
      headDy: headDy,
    );
  }

  void _paintSinglePaw(
    Canvas canvas,
    Paint pawPaint, {
    required bool isLeft,
    required double lift,
    required double headDx,
    required double headDy,
  }) {
    final dir = isLeft ? -1.0 : 1.0;
    if (lift < 0.05) {
      // Resting comfortably gripping the top edge of the form card
      canvas.drawOval(
        Rect.fromCenter(center: Offset(dir * 29, 0), width: 25, height: 14),
        pawPaint,
      );
      return;
    }

    // Sweeping soft rounded arm rising from shoulder to gently cover the eye
    final tipX = dir * (29 * (1 - lift) + 17 * lift) + headDx * lift;
    final tipY = 0 * (1 - lift) + (-76) * lift + headDy * lift;
    final baseX = dir * 36;
    final baseY = -10.0;

    final arm = Path()
      ..moveTo(baseX - dir * 7, baseY)
      ..cubicTo(
        baseX + dir * 10,
        baseY - 30 * lift,
        tipX + dir * 13,
        tipY + 20,
        tipX + dir * 4,
        tipY - 10,
      )
      ..cubicTo(
        tipX - dir * 8,
        tipY - 13,
        tipX - dir * 13,
        tipY + 4,
        tipX - dir * 8,
        tipY + 18,
      )
      ..cubicTo(
        tipX - dir * 2,
        tipY + 34,
        baseX - dir * 14,
        baseY - 10,
        baseX - dir * 7,
        baseY,
      )
      ..close();
    canvas.drawPath(arm, pawPaint);

    // Subtle soft toe lines on the back of the paw
    final toePaint = Paint()
      ..color = const Color(0xFF9E5526).withValues(alpha: 0.45)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      Offset(tipX - dir * 2, tipY - 8),
      Offset(tipX - dir * 1, tipY - 1),
      toePaint,
    );
    canvas.drawLine(
      Offset(tipX + dir * 3, tipY - 7),
      Offset(tipX + dir * 4, tipY),
      toePaint,
    );
  }

  void _paintSecurityShield(Canvas canvas, double t) {
    canvas.save();
    final scale = 0.6 + 0.4 * t;
    canvas.translate(0, -16 + (1 - t) * 18);
    canvas.scale(scale, scale);

    // Soft outer glow
    canvas.drawCircle(
      const Offset(0, 2),
      28,
      Paint()..color = shieldColor.withValues(alpha: 0.18 * t),
    );

    // Holding paws wrapping neatly around the shield sides
    final pawPaint = Paint()..color = const Color(0xFFDA9259);
    canvas.drawOval(
      Rect.fromCenter(center: const Offset(-22, 2), width: 16, height: 12),
      pawPaint,
    );
    canvas.drawOval(
      Rect.fromCenter(center: const Offset(22, 2), width: 16, height: 12),
      pawPaint,
    );

    // Emerald shield body with golden rim
    final shieldPath = Path()
      ..moveTo(0, -25)
      ..lineTo(22, -17)
      ..lineTo(22, 2)
      ..cubicTo(22, 16, 11, 25, 0, 30)
      ..cubicTo(-11, 25, -22, 16, -22, 2)
      ..lineTo(-22, -17)
      ..close();
    canvas.drawPath(shieldPath, Paint()..color = shieldColor);
    canvas.drawPath(
      shieldPath,
      Paint()
        ..color = goldColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.6,
    );

    // Golden padlock inside shield
    final shackle = Path()
      ..moveTo(-5, -3)
      ..lineTo(-5, -8)
      ..arcToPoint(const Offset(5, -8), radius: const Radius.circular(5))
      ..lineTo(5, -3);
    canvas.drawPath(
      shackle,
      Paint()
        ..color = goldColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.6
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(-8.5, -3, 17, 14),
        const Radius.circular(3.5),
      ),
      Paint()..color = goldColor,
    );
    canvas.drawCircle(
      const Offset(0, 4),
      2.3,
      Paint()..color = const Color(0xFF23160E),
    );

    // 3 progress spots along the lower shield rim lighting up with securityProgress
    final litCount = (securityProgress * 3).ceil().clamp(0, 3);
    for (var i = 0; i < 3; i++) {
      final cx = (i - 1) * 8.0;
      final isLit = i < litCount;
      canvas.drawCircle(
        Offset(cx, 18),
        2.3,
        Paint()
          ..color = isLit
              ? const Color(0xFFFAF0DF)
              : const Color(0xFFFAF0DF).withValues(alpha: 0.32),
      );
    }

    canvas.restore();
  }

  void _paintCelebratingArms(Canvas canvas, double t) {
    final armPaint = Paint()..color = const Color(0xFFD99259);
    for (final dir in const [-1.0, 1.0]) {
      canvas.save();
      canvas.translate(dir * 42, -48 - t * 6);
      canvas.rotate(dir * (0.65 + t * 0.25));
      canvas.drawOval(
        Rect.fromCenter(center: Offset.zero, width: 16, height: 32),
        armPaint,
      );
      canvas.restore();
    }
  }

  void _paintCelebrationCoins(Canvas canvas, double t) {
    final floatY = reducedMotion ? 0.0 : -t * 14.0;
    final opacity = t.clamp(0.0, 1.0);
    const coins = [
      (-60.0, -84.0, 8.0),
      (56.0, -96.0, 9.5),
      (64.0, -52.0, 6.2),
    ];
    for (final (x, y, r) in coins) {
      final center = Offset(x, y + floatY);
      canvas.drawCircle(
        center,
        r,
        Paint()..color = goldColor.withValues(alpha: 0.88 * opacity),
      );
      canvas.drawCircle(
        center,
        r * 0.58,
        Paint()
          ..color = const Color(0xFFFAF0DF).withValues(alpha: 0.7 * opacity)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _PacocaPainter old) =>
      old.mood != mood ||
      old.coverProgress != coverProgress ||
      old.peekProgress != peekProgress ||
      old.shieldProgress != shieldProgress ||
      old.securityProgress != securityProgress ||
      old.gazeX != gazeX ||
      old.gazeY != gazeY ||
      old.shakeOffset != shakeOffset ||
      old.celebrateProgress != celebrateProgress ||
      old.reducedMotion != reducedMotion ||
      old.shieldColor != shieldColor ||
      old.goldColor != goldColor ||
      old.portraitBg != portraitBg ||
      old.borderColor != borderColor;
}

/// Minimal 5-dot Toca Editorial step indicator (using the brand's spot motif).
class EditorialStepDots extends StatelessWidget {
  const EditorialStepDots({
    super.key,
    required this.total,
    required this.currentIndex,
  });

  final int total;
  final int currentIndex;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      label: 'Etapa ${currentIndex + 1} de $total',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < total; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            AnimatedContainer(
              duration: GranaMotion.duration(context, GranaMotion.fast),
              width: i == currentIndex ? 18 : 7,
              height: 7,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(GranaRadius.pill),
                color: i == currentIndex
                    ? scheme.primary
                    : i < currentIndex
                    ? scheme.onSurfaceVariant.withValues(alpha: 0.55)
                    : scheme.outlineVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
