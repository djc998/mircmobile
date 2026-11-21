/// End-to-end encryption for shared pictures (AES-256-GCM).
///
/// Format of the uploaded bytes: 12-byte nonce, ciphertext, 16-byte tag.
/// The browser viewer in `server/picture-host` decrypts the same format
/// with WebCrypto.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

final _aes = AesGcm.with256bits();

/// Encrypts [plain] with a new random key. Returns the bytes to upload and
/// the key for the link.
Future<({Uint8List sealed, String key})> sealPicture(Uint8List plain) async {
  final secret = await _aes.newSecretKey();
  final box = await _aes.encrypt(plain, secretKey: secret);
  final keyBytes = await secret.extractBytes();
  return (
    sealed: Uint8List.fromList(box.concatenation()),
    key: base64Url.encode(keyBytes).replaceAll('=', ''),
  );
}

/// Decrypts bytes made by [sealPicture]. Throws if the key is wrong or the
/// bytes were changed.
Future<Uint8List> openPicture(Uint8List sealed, String key) async {
  final keyBytes = base64Url.decode(base64Url.normalize(key));
  final box = SecretBox.fromConcatenation(
    sealed,
    nonceLength: _aes.nonceLength,
    macLength: _aes.macAlgorithm.macLength,
  );
  final plain = await _aes.decrypt(box, secretKey: SecretKey(keyBytes));
  return Uint8List.fromList(plain);
}
