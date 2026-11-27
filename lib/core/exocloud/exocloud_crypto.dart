import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// A recovery key that doesn't decode, or doesn't match the account's.
class BadRecoveryKeyException implements Exception {
  const BadRecoveryKeyException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// A backup that won't decrypt: a different key, or damaged bytes.
class ExoCloudDecryptException implements Exception {
  const ExoCloudDecryptException();
}

/// ExoCloud's end-to-end encryption. Every backup is sealed on the phone
/// with AES-256-GCM under the account's ExoCloud key — 32 random bytes that
/// live only on the user's phones and in their recovery key. ExoSynk's
/// server stores ciphertext it can't read.
///
/// File format: `EXC1` · 12-byte nonce · ciphertext · 16-byte tag.
class ExoCloudCrypto {
  static const keyLength = 32;
  static final _magic = ascii.encode('EXC1');
  static final _aes = AesGcm.with256bits();

  /// Crockford base32: no I, L, O or U, so nothing is easy to misread.
  static const _alphabet = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';

  static Uint8List newKey() {
    final random = Random.secure();
    return Uint8List.fromList(
      List<int>.generate(keyLength, (_) => random.nextInt(256)),
    );
  }

  static Future<Uint8List> encrypt(List<int> plain, List<int> key) async {
    final box = await _aes.encrypt(plain, secretKey: SecretKey(key));
    return Uint8List.fromList([
      ..._magic,
      ...box.nonce,
      ...box.cipherText,
      ...box.mac.bytes,
    ]);
  }

  static Future<Uint8List> decrypt(List<int> sealed, List<int> key) async {
    const nonceLength = 12, macLength = 16;
    if (sealed.length < _magic.length + nonceLength + macLength ||
        !_startsWithMagic(sealed)) {
      throw const ExoCloudDecryptException();
    }
    final body = sealed.sublist(_magic.length);
    final box = SecretBox(
      body.sublist(nonceLength, body.length - macLength),
      nonce: body.sublist(0, nonceLength),
      mac: Mac(body.sublist(body.length - macLength)),
    );
    try {
      return Uint8List.fromList(
        await _aes.decrypt(box, secretKey: SecretKey(key)),
      );
    } on SecretBoxAuthenticationError {
      throw const ExoCloudDecryptException();
    }
  }

  static bool _startsWithMagic(List<int> bytes) {
    for (var i = 0; i < _magic.length; i++) {
      if (bytes[i] != _magic[i]) return false;
    }
    return true;
  }

  /// What `account_settings.exocloud_key_check` holds: an HMAC of a fixed
  /// label under the key. A new phone recomputes it to check a typed
  /// recovery key; it says nothing about the key itself.
  static Future<String> keyCheck(List<int> key) async {
    final mac = await Hmac.sha256().calculateMac(
      utf8.encode('conectr-exocloud-key-check-v1'),
      secretKey: SecretKey(key),
    );
    return base64Url.encode(mac.bytes).replaceAll('=', '');
  }

  /// The key as the user writes it down: 52 base32 characters in groups of
  /// four, e.g. `7K3Q-...`.
  static String toRecoveryKey(List<int> key) {
    final out = StringBuffer();
    var buffer = 0, bits = 0, count = 0;
    void emit(int index) {
      if (count > 0 && count % 4 == 0) out.write('-');
      out.write(_alphabet[index]);
      count++;
    }

    for (final byte in key) {
      buffer = (buffer << 8) | byte;
      bits += 8;
      while (bits >= 5) {
        bits -= 5;
        emit((buffer >> bits) & 31);
      }
      buffer &= (1 << bits) - 1;
    }
    if (bits > 0) emit((buffer << (5 - bits)) & 31);
    return out.toString();
  }

  /// Reads a typed recovery key. Forgiving: any case, spaces or dashes,
  /// and the letters people mistake for digits (O→0, I/L→1).
  static Uint8List fromRecoveryKey(String typed) {
    final cleaned = typed
        .toUpperCase()
        .replaceAll(RegExp(r'[\s-]'), '')
        .replaceAll('O', '0')
        .replaceAll(RegExp('[IL]'), '1');
    final expected = (keyLength * 8 / 5).ceil();
    if (cleaned.length != expected) {
      throw BadRecoveryKeyException(
        'A recovery key has $expected letters and digits; this has '
        '${cleaned.length}.',
      );
    }
    final out = <int>[];
    var buffer = 0, bits = 0;
    for (final char in cleaned.split('')) {
      final value = _alphabet.indexOf(char);
      if (value < 0) {
        throw BadRecoveryKeyException('"$char" isn\'t in a recovery key.');
      }
      buffer = (buffer << 5) | value;
      bits += 5;
      if (bits >= 8) {
        bits -= 8;
        out.add((buffer >> bits) & 0xFF);
      }
      buffer &= (1 << bits) - 1;
    }
    return Uint8List.fromList(out.sublist(0, keyLength));
  }
}
