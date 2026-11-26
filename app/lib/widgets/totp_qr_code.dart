import 'dart:convert';
import 'dart:typed_data';

import 'package:material_ui/material_ui.dart';

/// Pure-Dart ISO/IEC 18004 QR Code matrix generator (Byte mode, Error
/// Correction Level M, Versions 1..10) with zero external dependencies so all
/// Flutter targets render scannable TOTP `otpauth://` QR codes (RF-03).
class QrCodeMatrix {
  const QrCodeMatrix({
    required this.version,
    required this.size,
    required this.maskPattern,
    required this.modules,
  });

  final int version;
  final int size;
  final int maskPattern;
  final List<List<bool>> modules;

  bool isDark(int row, int col) => modules[row][col];

  /// Generates an ISO/IEC 18004 QR matrix (Level M, Byte mode) for [data].
  ///
  /// Supports Versions 1 through 10 (up to 213 UTF-8 bytes at Level M), which
  /// comfortably accommodates any standard `otpauth://totp/...` URI.
  factory QrCodeMatrix.encode(String data) {
    final payload = Uint8List.fromList(utf8.encode(data));
    final spec = _selectVersion(payload.length);
    final dataCodewords = _encodeByteCodewords(payload, spec);
    final finalStream = _interleaveBlocks(dataCodewords, spec);

    final size = 17 + 4 * spec.version;
    final baseModules = List.generate(size, (_) => List<bool>.filled(size, false));
    final isFunction = List.generate(size, (_) => List<bool>.filled(size, false));

    _placeFunctionPatterns(baseModules, isFunction, spec.version);
    _placeDataBits(baseModules, isFunction, finalStream);

    var bestMask = 0;
    var bestPenalty = 1 << 30;
    late List<List<bool>> bestModules;

    for (var mask = 0; mask < 8; mask++) {
      final candidate = [
        for (var r = 0; r < size; r++) List<bool>.from(baseModules[r]),
      ];
      _applyMask(candidate, isFunction, mask);
      _placeFormatInfo(candidate, mask);
      if (spec.version >= 7) {
        _placeVersionInfo(candidate, spec.version);
      }
      final penalty = _evaluatePenalty(candidate);
      if (penalty < bestPenalty) {
        bestPenalty = penalty;
        bestMask = mask;
        bestModules = candidate;
      }
    }

    return QrCodeMatrix(
      version: spec.version,
      size: size,
      maskPattern: bestMask,
      modules: List.unmodifiable([
        for (final row in bestModules) List<bool>.unmodifiable(row),
      ]),
    );
  }

  static _QrVersionSpec _selectVersion(int byteLength) {
    for (final spec in _levelMSpecs) {
      final countBits = spec.version <= 9 ? 8 : 16;
      final headerBits = 4 + countBits;
      final capacityBytes = (spec.totalDataCodewords * 8 - headerBits) ~/ 8;
      if (byteLength <= capacityBytes) {
        return spec;
      }
    }
    throw ArgumentError(
      'Conteúdo muito longo para o QR Code ($byteLength bytes).',
    );
  }

  static Uint8List _encodeByteCodewords(Uint8List data, _QrVersionSpec spec) {
    final bits = <int>[];
    void pushBits(int value, int count) {
      for (var i = count - 1; i >= 0; i--) {
        bits.add((value >> i) & 1);
      }
    }

    // Mode indicator for Byte mode: 0100.
    pushBits(0x4, 4);
    // Character count indicator: 8 bits for versions 1..9, 16 bits for 10..26.
    pushBits(data.length, spec.version <= 9 ? 8 : 16);
    for (final b in data) {
      pushBits(b, 8);
    }

    final totalDataBits = spec.totalDataCodewords * 8;
    // Up to 4 terminator zero bits.
    final terminatorLen = (totalDataBits - bits.length).clamp(0, 4);
    for (var i = 0; i < terminatorLen; i++) {
      bits.add(0);
    }
    // Pad to byte boundary.
    while (bits.length % 8 != 0) {
      bits.add(0);
    }

    final out = Uint8List(spec.totalDataCodewords);
    final filledBytes = bits.length ~/ 8;
    for (var i = 0; i < filledBytes; i++) {
      var byte = 0;
      for (var b = 0; b < 8; b++) {
        byte = (byte << 1) | bits[i * 8 + b];
      }
      out[i] = byte;
    }

    // Pad with alternating 0xEC, 0x11 codewords.
    const padBytes = [0xEC, 0x11];
    for (var i = filledBytes; i < spec.totalDataCodewords; i++) {
      out[i] = padBytes[(i - filledBytes) % 2];
    }
    return out;
  }

  static Uint8List _interleaveBlocks(Uint8List data, _QrVersionSpec spec) {
    final dataBlocks = <Uint8List>[];
    final ecBlocks = <Uint8List>[];
    final generator = _rsGeneratorPoly(spec.ecCodewordsPerBlock);

    var offset = 0;
    for (var i = 0; i < spec.group1Blocks; i++) {
      final block = Uint8List.sublistView(
        data,
        offset,
        offset + spec.group1DataCodewords,
      );
      offset += spec.group1DataCodewords;
      dataBlocks.add(block);
      ecBlocks.add(_rsRemainder(block, generator));
    }
    for (var i = 0; i < spec.group2Blocks; i++) {
      final block = Uint8List.sublistView(
        data,
        offset,
        offset + spec.group2DataCodewords,
      );
      offset += spec.group2DataCodewords;
      dataBlocks.add(block);
      ecBlocks.add(_rsRemainder(block, generator));
    }

    final maxDataLen = spec.group2Blocks > 0
        ? spec.group2DataCodewords
        : spec.group1DataCodewords;
    final totalBytes =
        spec.totalDataCodewords +
        (spec.group1Blocks + spec.group2Blocks) * spec.ecCodewordsPerBlock;
    final interleaved = Uint8List(totalBytes);
    var pos = 0;

    for (var col = 0; col < maxDataLen; col++) {
      for (final block in dataBlocks) {
        if (col < block.length) {
          interleaved[pos++] = block[col];
        }
      }
    }
    for (var col = 0; col < spec.ecCodewordsPerBlock; col++) {
      for (final ec in ecBlocks) {
        interleaved[pos++] = ec[col];
      }
    }
    return interleaved;
  }

  // GF(256) multiplication modulo x^8 + x^4 + x^3 + x^2 + 1 (0x11D).
  static int _gfMul(int a, int b) {
    var x = a;
    var y = b;
    var result = 0;
    for (var i = 0; i < 8; i++) {
      if ((y & 1) != 0) result ^= x;
      final highBit = (x & 0x80) != 0;
      x = (x << 1) & 0xFF;
      if (highBit) x ^= 0x1D;
      y >>= 1;
    }
    return result;
  }

  static List<int> _rsGeneratorPoly(int degree) {
    var poly = <int>[1];
    var root = 1;
    for (var i = 0; i < degree; i++) {
      final next = List<int>.filled(poly.length + 1, 0);
      for (var j = 0; j < poly.length; j++) {
        next[j] ^= poly[j];
        next[j + 1] ^= _gfMul(poly[j], root);
      }
      poly = next;
      root = _gfMul(root, 2);
    }
    return poly;
  }

  static Uint8List _rsRemainder(Uint8List data, List<int> generator) {
    final degree = generator.length - 1;
    final rem = Uint8List(degree);
    for (final byte in data) {
      final factor = byte ^ rem[0];
      for (var i = 0; i < degree - 1; i++) {
        rem[i] = rem[i + 1] ^ _gfMul(generator[i + 1], factor);
      }
      rem[degree - 1] = _gfMul(generator[degree], factor);
    }
    return rem;
  }

  static void _placeFunctionPatterns(
    List<List<bool>> modules,
    List<List<bool>> isFunction,
    int version,
  ) {
    final size = modules.length;

    void setFn(int r, int c, bool dark) {
      if (r < 0 || c < 0 || r >= size || c >= size) return;
      modules[r][c] = dark;
      isFunction[r][c] = true;
    }

    // Finder patterns (7x7) + 1-module white separators.
    void drawFinder(int top, int left) {
      for (var dr = -1; dr <= 7; dr++) {
        for (var dc = -1; dc <= 7; dc++) {
          final r = top + dr;
          final c = left + dc;
          if (r < 0 || c < 0 || r >= size || c >= size) continue;
          final inOuter = dr >= 0 && dr <= 6 && dc >= 0 && dc <= 6;
          final dark =
              inOuter &&
              (dr == 0 ||
                  dr == 6 ||
                  dc == 0 ||
                  dc == 6 ||
                  (dr >= 2 && dr <= 4 && dc >= 2 && dc <= 4));
          setFn(r, c, dark);
        }
      }
    }

    drawFinder(0, 0);
    drawFinder(0, size - 7);
    drawFinder(size - 7, 0);

    // Timing patterns (row 6 and col 6).
    for (var i = 8; i < size - 8; i++) {
      final dark = i.isEven;
      if (!isFunction[6][i]) setFn(6, i, dark);
      if (!isFunction[i][6]) setFn(i, 6, dark);
    }

    // Alignment patterns (versions >= 2).
    final centers = _alignmentCenters[version] ?? const <int>[];
    for (final rCenter in centers) {
      for (final cCenter in centers) {
        if (isFunction[rCenter][cCenter]) continue;
        for (var dr = -2; dr <= 2; dr++) {
          for (var dc = -2; dc <= 2; dc++) {
            final dist = dr.abs() > dc.abs() ? dr.abs() : dc.abs();
            setFn(rCenter + dr, cCenter + dc, dist != 1);
          }
        }
      }
    }

    // Reserve format information strips + mandatory dark module.
    for (var i = 0; i <= 8; i++) {
      if (i != 6) {
        isFunction[8][i] = true;
        isFunction[i][8] = true;
      }
    }
    for (var i = 0; i < 8; i++) {
      isFunction[8][size - 1 - i] = true;
      isFunction[size - 1 - i][8] = true;
    }
    setFn(size - 8, 8, true);

    // Reserve version information blocks (versions >= 7).
    if (version >= 7) {
      for (var i = 0; i < 6; i++) {
        for (var j = 0; j < 3; j++) {
          isFunction[i][size - 11 + j] = true;
          isFunction[size - 11 + j][i] = true;
        }
      }
    }
  }

  static void _placeDataBits(
    List<List<bool>> modules,
    List<List<bool>> isFunction,
    Uint8List stream,
  ) {
    final size = modules.length;
    var bitIndex = 0;
    final totalBits = stream.length * 8;
    var upward = true;

    for (var right = size - 1; right >= 1; right -= 2) {
      if (right == 6) right = 5; // Skip vertical timing pattern column.
      for (var step = 0; step < size; step++) {
        final row = upward ? (size - 1 - step) : step;
        for (var colOffset = 0; colOffset < 2; colOffset++) {
          final col = right - colOffset;
          if (isFunction[row][col]) continue;
          var dark = false;
          if (bitIndex < totalBits) {
            dark = ((stream[bitIndex >> 3] >> (7 - (bitIndex & 7))) & 1) != 0;
            bitIndex++;
          }
          modules[row][col] = dark;
        }
      }
      upward = !upward;
    }
  }

  static void _applyMask(
    List<List<bool>> modules,
    List<List<bool>> isFunction,
    int mask,
  ) {
    final size = modules.length;
    for (var r = 0; r < size; r++) {
      for (var c = 0; c < size; c++) {
        if (isFunction[r][c]) continue;
        final invert = switch (mask) {
          0 => (r + c) % 2 == 0,
          1 => r % 2 == 0,
          2 => c % 3 == 0,
          3 => (r + c) % 3 == 0,
          4 => ((r ~/ 2) + (c ~/ 3)) % 2 == 0,
          5 => ((r * c) % 2 + (r * c) % 3) == 0,
          6 => (((r * c) % 2 + (r * c) % 3) % 2) == 0,
          7 => (((r + c) % 2 + (r * c) % 3) % 2) == 0,
          _ => false,
        };
        if (invert) {
          modules[r][c] = !modules[r][c];
        }
      }
    }
  }

  static void _placeFormatInfo(List<List<bool>> modules, int mask) {
    // Error Correction Level M format indicator bits: 00 (0).
    final data = (0x0 << 3) | (mask & 0x7);
    var rem = data;
    for (var i = 0; i < 10; i++) {
      rem = (rem << 1) ^ (((rem >> 9) & 1) * 0x537);
    }
    final bits = ((data << 10) | rem) ^ 0x5412;
    final size = modules.length;

    bool bit(int index) => ((bits >> index) & 1) != 0;

    // Top-left vertical strip (bits 0..5, 7, 8).
    for (var i = 0; i <= 5; i++) {
      modules[i][8] = bit(i);
    }
    modules[7][8] = bit(6);
    modules[8][8] = bit(7);
    modules[8][7] = bit(8);
    for (var i = 9; i < 15; i++) {
      modules[8][14 - i] = bit(i);
    }

    // Top-right horizontal strip (bits 0..7) & bottom-left vertical (bits 8..14).
    for (var i = 0; i < 8; i++) {
      modules[8][size - 1 - i] = bit(i);
    }
    for (var i = 8; i < 15; i++) {
      modules[size - 15 + i][8] = bit(i);
    }
    modules[size - 8][8] = true;
  }

  static void _placeVersionInfo(List<List<bool>> modules, int version) {
    var rem = version;
    for (var i = 0; i < 12; i++) {
      rem = (rem << 1) ^ (((rem >> 11) & 1) * 0x1F25);
    }
    final bits = (version << 12) | rem;
    final size = modules.length;

    for (var i = 0; i < 18; i++) {
      final dark = ((bits >> i) & 1) != 0;
      final a = size - 11 + (i % 3);
      final b = i ~/ 3;
      modules[b][a] = dark;
      modules[a][b] = dark;
    }
  }

  static int _evaluatePenalty(List<List<bool>> modules) {
    final size = modules.length;
    var penalty = 0;

    // Rule 1: adjacent runs of 5+ same-colored modules.
    for (var r = 0; r < size; r++) {
      var runColor = modules[r][0];
      var runLen = 1;
      for (var c = 1; c < size; c++) {
        if (modules[r][c] == runColor) {
          runLen++;
        } else {
          if (runLen >= 5) penalty += 3 + (runLen - 5);
          runColor = modules[r][c];
          runLen = 1;
        }
      }
      if (runLen >= 5) penalty += 3 + (runLen - 5);
    }
    for (var c = 0; c < size; c++) {
      var runColor = modules[0][c];
      var runLen = 1;
      for (var r = 1; r < size; r++) {
        if (modules[r][c] == runColor) {
          runLen++;
        } else {
          if (runLen >= 5) penalty += 3 + (runLen - 5);
          runColor = modules[r][c];
          runLen = 1;
        }
      }
      if (runLen >= 5) penalty += 3 + (runLen - 5);
    }

    // Rule 2: 2x2 solid blocks.
    for (var r = 0; r < size - 1; r++) {
      for (var c = 0; c < size - 1; c++) {
        final v = modules[r][c];
        if (v == modules[r][c + 1] &&
            v == modules[r + 1][c] &&
            v == modules[r + 1][c + 1]) {
          penalty += 3;
        }
      }
    }

    // Rule 3: finder-like 1:1:3:1:1 patterns with 4 light modules on either side.
    bool matchesPattern(List<bool> line, int start) {
      const p1 = [true, false, true, true, true, false, true, false, false, false, false];
      const p2 = [false, false, false, false, true, false, true, true, true, false, true];
      var m1 = true;
      var m2 = true;
      for (var i = 0; i < 11; i++) {
        if (line[start + i] != p1[i]) m1 = false;
        if (line[start + i] != p2[i]) m2 = false;
        if (!m1 && !m2) return false;
      }
      return m1 || m2;
    }

    for (var r = 0; r < size; r++) {
      for (var c = 0; c <= size - 11; c++) {
        if (matchesPattern(modules[r], c)) penalty += 40;
      }
    }
    final colBuf = List<bool>.filled(size, false);
    for (var c = 0; c < size; c++) {
      for (var r = 0; r < size; r++) {
        colBuf[r] = modules[r][c];
      }
      for (var r = 0; r <= size - 11; r++) {
        if (matchesPattern(colBuf, r)) penalty += 40;
      }
    }

    // Rule 4: balance of dark vs light modules.
    var darkCount = 0;
    for (final row in modules) {
      for (final cell in row) {
        if (cell) darkCount++;
      }
    }
    final total = size * size;
    final k = ((darkCount * 20 - total * 10).abs()) ~/ total;
    penalty += k * 10;

    return penalty;
  }

  static const List<_QrVersionSpec> _levelMSpecs = [
    _QrVersionSpec(version: 1, totalDataCodewords: 16, ecCodewordsPerBlock: 10, group1Blocks: 1, group1DataCodewords: 16),
    _QrVersionSpec(version: 2, totalDataCodewords: 28, ecCodewordsPerBlock: 16, group1Blocks: 1, group1DataCodewords: 28),
    _QrVersionSpec(version: 3, totalDataCodewords: 44, ecCodewordsPerBlock: 26, group1Blocks: 1, group1DataCodewords: 44),
    _QrVersionSpec(version: 4, totalDataCodewords: 64, ecCodewordsPerBlock: 18, group1Blocks: 2, group1DataCodewords: 32),
    _QrVersionSpec(version: 5, totalDataCodewords: 86, ecCodewordsPerBlock: 24, group1Blocks: 2, group1DataCodewords: 43),
    _QrVersionSpec(version: 6, totalDataCodewords: 108, ecCodewordsPerBlock: 16, group1Blocks: 4, group1DataCodewords: 27),
    _QrVersionSpec(version: 7, totalDataCodewords: 124, ecCodewordsPerBlock: 18, group1Blocks: 4, group1DataCodewords: 31),
    _QrVersionSpec(version: 8, totalDataCodewords: 154, ecCodewordsPerBlock: 22, group1Blocks: 2, group1DataCodewords: 38, group2Blocks: 2, group2DataCodewords: 39),
    _QrVersionSpec(version: 9, totalDataCodewords: 182, ecCodewordsPerBlock: 22, group1Blocks: 3, group1DataCodewords: 36, group2Blocks: 2, group2DataCodewords: 37),
    _QrVersionSpec(version: 10, totalDataCodewords: 216, ecCodewordsPerBlock: 26, group1Blocks: 4, group1DataCodewords: 43, group2Blocks: 1, group2DataCodewords: 44),
  ];

  static const Map<int, List<int>> _alignmentCenters = {
    1: [],
    2: [6, 18],
    3: [6, 22],
    4: [6, 26],
    5: [6, 30],
    6: [6, 34],
    7: [6, 22, 38],
    8: [6, 24, 42],
    9: [6, 26, 46],
    10: [6, 28, 50],
  };
}

class _QrVersionSpec {
  const _QrVersionSpec({
    required this.version,
    required this.totalDataCodewords,
    required this.ecCodewordsPerBlock,
    required this.group1Blocks,
    required this.group1DataCodewords,
    this.group2Blocks = 0,
    this.group2DataCodewords = 0,
  });

  final int version;
  final int totalDataCodewords;
  final int ecCodewordsPerBlock;
  final int group1Blocks;
  final int group1DataCodewords;
  final int group2Blocks;
  final int group2DataCodewords;
}

/// Renders a crisp, high-contrast TOTP QR Code with a mandatory 4-module white
/// quiet zone so authenticator apps scan reliably in both light and dark themes.
class TotpQrCodeView extends StatelessWidget {
  const TotpQrCodeView({
    super.key,
    required this.data,
    this.size = 200,
    this.semanticLabel = 'QR Code para configurar o aplicativo autenticador',
  });

  final String data;
  final double size;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    final matrix = QrCodeMatrix.encode(data);
    return Semantics(
      image: true,
      label: semanticLabel,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
        ),
        padding: const EdgeInsets.all(8),
        child: CustomPaint(
          painter: _QrCodePainter(matrix),
        ),
      ),
    );
  }
}

class _QrCodePainter extends CustomPainter {
  const _QrCodePainter(this.matrix);

  final QrCodeMatrix matrix;

  static const int _quietZoneModules = 4;

  @override
  void paint(Canvas canvas, Size size) {
    final totalModules = matrix.size + _quietZoneModules * 2;
    final moduleSize = size.shortestSide / totalModules;
    final offsetX = (size.width - moduleSize * totalModules) / 2;
    final offsetY = (size.height - moduleSize * totalModules) / 2;

    final bgPaint = Paint()..color = Colors.white;
    canvas.drawRect(Offset.zero & size, bgPaint);

    final fgPaint = Paint()
      ..color = const Color(0xFF14110F)
      ..isAntiAlias = false;

    for (var r = 0; r < matrix.size; r++) {
      for (var c = 0; c < matrix.size; c++) {
        if (!matrix.isDark(r, c)) continue;
        final left = offsetX + (c + _quietZoneModules) * moduleSize;
        final top = offsetY + (r + _quietZoneModules) * moduleSize;
        canvas.drawRect(
          Rect.fromLTWH(left, top, moduleSize + 0.25, moduleSize + 0.25),
          fgPaint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_QrCodePainter oldDelegate) =>
      oldDelegate.matrix.version != matrix.version ||
      oldDelegate.matrix.maskPattern != matrix.maskPattern ||
      oldDelegate.matrix.modules != matrix.modules;
}
