import 'dart:convert';
import 'dart:isolate';
import 'package:cryptography/cryptography.dart';

// Top-level helpers keep isolate messages free of widget/plugin/file handles.
Future<List<int>> encodeSnapshot(
        List<Map<String, dynamic>> records, List<int> keyBytes) =>
    Isolate.run(() async {
      final box = await AesGcm.with256bits().encrypt(
          utf8.encode(jsonEncode(records)),
          secretKey: SecretKey(keyBytes));
      return box.concatenation();
    });
Future<List<dynamic>> decodeSnapshot(List<int> bytes, List<int> keyBytes) =>
    Isolate.run(() async {
      final box =
          SecretBox.fromConcatenation(bytes, nonceLength: 12, macLength: 16);
      final clear = await AesGcm.with256bits()
          .decrypt(box, secretKey: SecretKey(keyBytes));
      return jsonDecode(utf8.decode(clear)) as List;
    });
