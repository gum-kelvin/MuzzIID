// ignore_for_file: avoid_relative_lib_imports, avoid_print
import 'dart:convert';
import 'package:cryptography/cryptography.dart';
import '../lib/data/snapshot_codec.dart';

Future<void> main() async {
  final key = await AesGcm.with256bits().newSecretKey();
  final bytes = await key.extractBytes();
  final record = {
    'owner': 'Test private owner',
    'frames': ['jpeg'],
    'gps': {'latitude': -.607}
  };
  final ciphertext = await encodeSnapshot([record], bytes);
  if (utf8
      .decode(ciphertext, allowMalformed: true)
      .contains('Test private owner')) {
    throw StateError('Cleartext leaked');
  }
  final restored = await decodeSnapshot(ciphertext, bytes);
  if (restored.single['owner'] != record['owner']) {
    throw StateError('Encrypted round trip failed');
  }
  final tampered = List<int>.from(ciphertext);
  tampered[tampered.length - 1] ^= 1;
  var rejected = false;
  try {
    await decodeSnapshot(tampered, bytes);
  } on SecretBoxAuthenticationError {
    rejected = true;
  }
  if (!rejected) throw StateError('Tampered ciphertext accepted');
  print(
      'PASS: isolate encryption/decryption, confidentiality and tamper rejection');
}
