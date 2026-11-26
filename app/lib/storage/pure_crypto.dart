import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

/// Raised when encrypted local cache data fails authenticity verification.
class CacheIntegrityException implements Exception {
  const CacheIntegrityException(this.message);

  final String message;

  @override
  String toString() => 'CacheIntegrityException: $message';
}

/// Pure-Dart cryptographic primitives (SHA-256, HMAC-SHA256, PBKDF2-HMAC-SHA256,
/// and authenticated Encrypt-then-MAC stream encryption) with zero external
/// dependencies so every Flutter target builds cleanly.
abstract final class PureCrypto {
  static const int _version = 1;
  static const int _nonceLength = 16;
  static const int _macLength = 32;
  static const int _blockSize = 64;
  static const int _mask32 = 0xFFFFFFFF;

  static final List<int> _primes = _generateFirstPrimes(64);
  static final Uint32List _initialHash = _computeSqrtFractions(8);
  static final Uint32List _roundConstants = _computeCubeRootFractions(64);

  static List<int> _generateFirstPrimes(int count) {
    final result = <int>[];
    var candidate = 2;
    while (result.length < count) {
      var prime = true;
      for (var d = 2; d * d <= candidate; d++) {
        if (candidate % d == 0) {
          prime = false;
          break;
        }
      }
      if (prime) result.add(candidate);
      candidate++;
    }
    return result;
  }

  static Uint32List _computeSqrtFractions(int count) {
    final out = Uint32List(count);
    for (var i = 0; i < count; i++) {
      final root = math.sqrt(_primes[i]);
      final frac = root - root.floorToDouble();
      out[i] = (frac * 4294967296.0).floor() & _mask32;
    }
    return out;
  }

  static Uint32List _computeCubeRootFractions(int count) {
    final out = Uint32List(count);
    for (var i = 0; i < count; i++) {
      final root = _cubeRoot(_primes[i].toDouble());
      final frac = root - root.floorToDouble();
      out[i] = (frac * 4294967296.0).floor() & _mask32;
    }
    return out;
  }

  /// Newton-Raphson cube root for exact IEEE-754 double precision across VM
  /// and Web JS runtimes.
  static double _cubeRoot(double x) {
    var guess = math.pow(x, 1.0 / 3.0).toDouble();
    for (var i = 0; i < 6; i++) {
      guess = (2.0 * guess + x / (guess * guess)) / 3.0;
    }
    return guess;
  }

  static int _rotr32(int value, int shift) =>
      ((value >>> shift) | (value << (32 - shift))) & _mask32;

  /// Generates cryptographically secure random bytes.
  static Uint8List randomBytes(int length) {
    final rng = math.Random.secure();
    final bytes = Uint8List(length);
    for (var i = 0; i < length; i++) {
      bytes[i] = rng.nextInt(256);
    }
    return bytes;
  }

  /// Constant-time comparison preventing timing side-channels.
  static bool constantTimeEquals(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }

  /// Computes a SHA-256 digest over [input].
  static Uint8List sha256(Uint8List input) {
    final bitLen = input.length * 8;
    final padRemainder = (input.length + 9) % _blockSize;
    final padZeros = padRemainder == 0 ? 0 : _blockSize - padRemainder;
    final padded = Uint8List(input.length + 1 + padZeros + 8);
    padded.setRange(0, input.length, input);
    padded[input.length] = 0x80;

    // 64-bit big-endian bit length (split into high/low 32-bit words so web
    // double arithmetic stays exact).
    final hi = bitLen ~/ 4294967296;
    final lo = bitLen & _mask32;
    final lenOffset = padded.length - 8;
    padded[lenOffset] = (hi >>> 24) & 0xFF;
    padded[lenOffset + 1] = (hi >>> 16) & 0xFF;
    padded[lenOffset + 2] = (hi >>> 8) & 0xFF;
    padded[lenOffset + 3] = hi & 0xFF;
    padded[lenOffset + 4] = (lo >>> 24) & 0xFF;
    padded[lenOffset + 5] = (lo >>> 16) & 0xFF;
    padded[lenOffset + 6] = (lo >>> 8) & 0xFF;
    padded[lenOffset + 7] = lo & 0xFF;

    var h0 = _initialHash[0];
    var h1 = _initialHash[1];
    var h2 = _initialHash[2];
    var h3 = _initialHash[3];
    var h4 = _initialHash[4];
    var h5 = _initialHash[5];
    var h6 = _initialHash[6];
    var h7 = _initialHash[7];

    final schedule = Uint32List(64);

    for (var offset = 0; offset < padded.length; offset += _blockSize) {
      for (var i = 0; i < 16; i++) {
        final idx = offset + i * 4;
        schedule[i] =
            ((padded[idx] << 24) |
                (padded[idx + 1] << 16) |
                (padded[idx + 2] << 8) |
                padded[idx + 3]) &
            _mask32;
      }
      for (var i = 16; i < 64; i++) {
        final w15 = schedule[i - 15];
        final w2 = schedule[i - 2];
        final s0 = _rotr32(w15, 7) ^ _rotr32(w15, 18) ^ (w15 >>> 3);
        final s1 = _rotr32(w2, 17) ^ _rotr32(w2, 19) ^ (w2 >>> 10);
        schedule[i] = (schedule[i - 16] + s0 + schedule[i - 7] + s1) & _mask32;
      }

      var a = h0;
      var b = h1;
      var c = h2;
      var d = h3;
      var e = h4;
      var f = h5;
      var g = h6;
      var h = h7;

      for (var i = 0; i < 64; i++) {
        final sum1 = _rotr32(e, 6) ^ _rotr32(e, 11) ^ _rotr32(e, 25);
        final ch = (e & f) ^ ((~e & _mask32) & g);
        final temp1 = (h + sum1 + ch + _roundConstants[i] + schedule[i]) & _mask32;
        final sum0 = _rotr32(a, 2) ^ _rotr32(a, 13) ^ _rotr32(a, 22);
        final maj = (a & b) ^ (a & c) ^ (b & c);
        final temp2 = (sum0 + maj) & _mask32;

        h = g;
        g = f;
        f = e;
        e = (d + temp1) & _mask32;
        d = c;
        c = b;
        b = a;
        a = (temp1 + temp2) & _mask32;
      }

      h0 = (h0 + a) & _mask32;
      h1 = (h1 + b) & _mask32;
      h2 = (h2 + c) & _mask32;
      h3 = (h3 + d) & _mask32;
      h4 = (h4 + e) & _mask32;
      h5 = (h5 + f) & _mask32;
      h6 = (h6 + g) & _mask32;
      h7 = (h7 + h) & _mask32;
    }

    final digest = Uint8List(32);
    final words = [h0, h1, h2, h3, h4, h5, h6, h7];
    for (var i = 0; i < 8; i++) {
      final w = words[i];
      digest[i * 4] = (w >>> 24) & 0xFF;
      digest[i * 4 + 1] = (w >>> 16) & 0xFF;
      digest[i * 4 + 2] = (w >>> 8) & 0xFF;
      digest[i * 4 + 3] = w & 0xFF;
    }
    return digest;
  }

  /// Computes HMAC-SHA256 for [key] and [message].
  static Uint8List hmacSha256(Uint8List key, Uint8List message) {
    final normalizedKey = Uint8List(_blockSize);
    if (key.length > _blockSize) {
      final hashed = sha256(key);
      normalizedKey.setRange(0, hashed.length, hashed);
    } else {
      normalizedKey.setRange(0, key.length, key);
    }

    final innerInput = Uint8List(_blockSize + message.length);
    final outerInput = Uint8List(_blockSize + 32);
    for (var i = 0; i < _blockSize; i++) {
      innerInput[i] = normalizedKey[i] ^ 0x36;
      outerInput[i] = normalizedKey[i] ^ 0x5C;
    }
    innerInput.setRange(_blockSize, innerInput.length, message);

    final innerHash = sha256(innerInput);
    outerInput.setRange(_blockSize, outerInput.length, innerHash);
    return sha256(outerInput);
  }

  /// Derives a 32-byte key via PBKDF2-HMAC-SHA256 (single block, 32 bytes).
  static Uint8List pbkdf2Sha256({
    required Uint8List password,
    required Uint8List salt,
    int iterations = 10000,
  }) {
    final saltBlock = Uint8List(salt.length + 4);
    saltBlock.setRange(0, salt.length, salt);
    saltBlock[salt.length + 3] = 1;

    var u = hmacSha256(password, saltBlock);
    final result = Uint8List.fromList(u);
    for (var i = 1; i < iterations; i++) {
      u = hmacSha256(password, u);
      for (var j = 0; j < result.length; j++) {
        result[j] ^= u[j];
      }
    }
    return result;
  }

  /// Encrypts [plaintext] using a fresh 16-byte nonce, domain-separated keys
  /// for HMAC-SHA256-CTR stream encryption and Encrypt-then-MAC authentication.
  static Uint8List seal({
    required Uint8List plaintext,
    required Uint8List masterKey,
    Uint8List? associatedData,
    Uint8List? nonceOverride,
  }) {
    if (masterKey.length < 16) {
      throw ArgumentError.value(
        masterKey.length,
        'masterKey',
        'Master key must be at least 16 bytes.',
      );
    }
    final nonce = nonceOverride ?? randomBytes(_nonceLength);
    if (nonce.length != _nonceLength) {
      throw ArgumentError.value(
        nonce.length,
        'nonceOverride',
        'Nonce must be $_nonceLength bytes.',
      );
    }
    final aad = associatedData ?? Uint8List(0);
    final encKey = _deriveSubkey(masterKey, 'granapaca-cache-enc-v1', nonce);
    final macKey = _deriveSubkey(masterKey, 'granapaca-cache-mac-v1', nonce);

    final ciphertext = _xorKeystream(plaintext, encKey, nonce);
    final mac = _computeTag(
      macKey: macKey,
      version: _version,
      nonce: nonce,
      aad: aad,
      ciphertext: ciphertext,
    );

    final out = Uint8List(1 + _nonceLength + ciphertext.length + _macLength);
    out[0] = _version;
    out.setRange(1, 1 + _nonceLength, nonce);
    out.setRange(1 + _nonceLength, 1 + _nonceLength + ciphertext.length, ciphertext);
    out.setRange(out.length - _macLength, out.length, mac);
    return out;
  }

  /// Verifies the MAC in constant time and decrypts [sealed] bytes.
  static Uint8List open({
    required Uint8List sealed,
    required Uint8List masterKey,
    Uint8List? associatedData,
  }) {
    const minLength = 1 + _nonceLength + _macLength;
    if (sealed.length < minLength) {
      throw const CacheIntegrityException(
        'Cache local corrompido ou incompleto.',
      );
    }
    final version = sealed[0];
    if (version != _version) {
      throw const CacheIntegrityException(
        'Versão do cache criptografado não suportada.',
      );
    }

    final nonce = Uint8List.sublistView(sealed, 1, 1 + _nonceLength);
    final ciphertext = Uint8List.sublistView(
      sealed,
      1 + _nonceLength,
      sealed.length - _macLength,
    );
    final providedMac = Uint8List.sublistView(
      sealed,
      sealed.length - _macLength,
    );

    final aad = associatedData ?? Uint8List(0);
    final encKey = _deriveSubkey(masterKey, 'granapaca-cache-enc-v1', nonce);
    final macKey = _deriveSubkey(masterKey, 'granapaca-cache-mac-v1', nonce);

    final expectedMac = _computeTag(
      macKey: macKey,
      version: version,
      nonce: nonce,
      aad: aad,
      ciphertext: ciphertext,
    );
    if (!constantTimeEquals(expectedMac, providedMac)) {
      throw const CacheIntegrityException(
        'A verificação de integridade do cache local falhou.',
      );
    }

    return _xorKeystream(ciphertext, encKey, nonce);
  }

  static Uint8List _deriveSubkey(
    Uint8List masterKey,
    String domainLabel,
    Uint8List nonce,
  ) {
    final labelBytes = utf8.encode(domainLabel);
    final input = Uint8List(labelBytes.length + nonce.length);
    input.setRange(0, labelBytes.length, labelBytes);
    input.setRange(labelBytes.length, input.length, nonce);
    return hmacSha256(masterKey, input);
  }

  static Uint8List _xorKeystream(
    Uint8List data,
    Uint8List encKey,
    Uint8List nonce,
  ) {
    final out = Uint8List(data.length);
    final counterInput = Uint8List(nonce.length + 4);
    counterInput.setRange(0, nonce.length, nonce);

    var offset = 0;
    var counter = 0;
    while (offset < data.length) {
      counterInput[nonce.length] = (counter >>> 24) & 0xFF;
      counterInput[nonce.length + 1] = (counter >>> 16) & 0xFF;
      counterInput[nonce.length + 2] = (counter >>> 8) & 0xFF;
      counterInput[nonce.length + 3] = counter & 0xFF;

      final streamBlock = hmacSha256(encKey, counterInput);
      final remaining = data.length - offset;
      final take = remaining < streamBlock.length ? remaining : streamBlock.length;
      for (var i = 0; i < take; i++) {
        out[offset + i] = data[offset + i] ^ streamBlock[i];
      }
      offset += take;
      counter++;
    }
    return out;
  }

  static Uint8List _computeTag({
    required Uint8List macKey,
    required int version,
    required Uint8List nonce,
    required Uint8List aad,
    required Uint8List ciphertext,
  }) {
    final macInput = Uint8List(1 + nonce.length + 4 + aad.length + ciphertext.length);
    var pos = 0;
    macInput[pos++] = version;
    macInput.setRange(pos, pos + nonce.length, nonce);
    pos += nonce.length;
    macInput[pos++] = (aad.length >>> 24) & 0xFF;
    macInput[pos++] = (aad.length >>> 16) & 0xFF;
    macInput[pos++] = (aad.length >>> 8) & 0xFF;
    macInput[pos++] = aad.length & 0xFF;
    macInput.setRange(pos, pos + aad.length, aad);
    pos += aad.length;
    macInput.setRange(pos, pos + ciphertext.length, ciphertext);
    return hmacSha256(macKey, macInput);
  }

  /// Formats [bytes] as lowercase hexadecimal for unit test inspection.
  static String toHex(Uint8List bytes) {
    final sb = StringBuffer();
    for (final b in bytes) {
      sb.write(b.toRadixString(16).padLeft(2, '0'));
    }
    return sb.toString();
  }
}
