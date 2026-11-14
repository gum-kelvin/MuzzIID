import 'dart:convert';
import 'dart:io';
import 'snapshot_codec.dart';
import 'record_hydration.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';
import '../domain/register.dart';
import '../domain/scan_queue.dart';

/// Atomic encrypted snapshot; key stays in Android Keystore/iOS Keychain.
class EncryptedSnapshot {
  final String filename;
  EncryptedSnapshot(this.filename);
  Future<SecretKey>? _cachedKey;
  final _cipher = AesGcm.with256bits();
  final _vault = const FlutterSecureStorage();
  Future<SecretKey> _key() =>
      _cachedKey ??= _loadKey().catchError((Object error, StackTrace stack) {
        _cachedKey = null;
        Error.throwWithStackTrace(error, stack);
      });
  Future<SecretKey> _loadKey() async {
    var encoded = await _vault.read(key: 'key-$filename');
    if (encoded == null) {
      if (await (await _file()).exists()) {
        throw StateError(
            'Encryption key unavailable; existing data was not changed');
      }
      final key = await _cipher.newSecretKey();
      encoded = base64Encode(await key.extractBytes());
      await _vault.write(key: 'key-$filename', value: encoded);
    }
    return SecretKey(base64Decode(encoded));
  }

  Future<File> _file() async =>
      File('${(await getApplicationSupportDirectory()).path}/$filename');
  Future<List<dynamic>> read() async {
    final file = await _file();
    if (!await file.exists()) return [];
    final bytes = await file.readAsBytes();
    final keyBytes = await (await _key()).extractBytes();
    return decodeSnapshot(bytes, keyBytes);
  }

  Future<void> save(List<Map<String, dynamic>> records) async {
    final keyBytes = await (await _key()).extractBytes();
    final bytes = await encodeSnapshot(records, keyBytes);
    final file = await _file();
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsBytes(bytes, flush: true);
    await temporary.rename(file.path);
  }
}

class EncryptedRegister implements RegisterRepository {
  final EncryptedSnapshot _store;
  EncryptedRegister({String filename = 'register.v1'})
      : _store = EncryptedSnapshot(filename);
  @override
  Future<List<Animal>> read() async => hydrateAnimals(await _store.read());
  @override
  Future<void> save(List<Animal> animals) =>
      _store.save(animals.map((a) => a.toJson()).toList());
}

class EncryptedScanQueue implements ScanQueueRepository {
  final _store = EncryptedSnapshot('scans.v1');
  @override
  Future<List<PendingScan>> read() async => (await _store.read())
      .map((j) => PendingScan.fromJson(Map<String, dynamic>.from(j)))
      .toList();
  @override
  Future<void> save(List<PendingScan> scans) =>
      _store.save(scans.map((s) => s.toJson()).toList());
}
