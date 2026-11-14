import 'dart:convert';
import 'dart:math';
import 'package:flutter/services.dart';
import 'package:cryptography/cryptography.dart';
import '../domain/register.dart';
import '../domain/field_records.dart';
import '../domain/verification.dart';
import 'encrypted_register.dart';

abstract interface class EmbeddingEngine {
  Future<Map<String, dynamic>> status();
  Future<List<double>> embed(String jpeg, String version);
}

class AndroidEmbeddingEngine implements EmbeddingEngine {
  static const channel = MethodChannel('com.example.muzzlid/model');
  @override
  Future<Map<String, dynamic>> status() async =>
      Map<String, dynamic>.from(await channel.invokeMapMethod('status') ?? {});
  @override
  Future<List<double>> embed(String jpeg, String version) async {
    final output =
        await channel.invokeMapMethod('embed', {'jpeg': base64Decode(jpeg)});
    if (output?['version'] != version) {
      throw StateError('Model version changed');
    }
    return unitVector((output!['vector'] as List)
        .cast<num>()
        .map((n) => n.toDouble())
        .toList());
  }
}

List<double> unitVector(List<double> vector) {
  if (vector.length != 512 || vector.any((n) => !n.isFinite)) {
    throw const FormatException('Invalid embedding');
  }
  final length = sqrt(vector.fold<double>(0, (s, n) => s + n * n));
  if (length < 1e-12) throw const FormatException('Empty embedding');
  return vector.map((n) => n / length).toList(growable: false);
}

/// Private on-device matching. Templates are rebuilt from encrypted source images
/// when either the model artifact or an animal's frames change.
class LocalModelVerification implements VerificationService {
  LocalModelVerification(this.engine, this.animals,
      {EncryptedSnapshot? templates})
      : templates = templates ?? EncryptedSnapshot('templates.v1');
  final EmbeddingEngine engine;
  final Future<List<Animal>> Function() animals;
  final EncryptedSnapshot templates;
  bool busy = false;
  @override
  Future<VerificationResult> verify(String jpeg, GeoFix gps) async {
    if (busy) return const VerificationResult(VerificationStatus.pending);
    busy = true;
    try {
      final info = await engine.status();
      if (info['ready'] != true || info['calibrated'] != true) {
        return const VerificationResult(VerificationStatus.pending);
      }
      final version = info['version'] as String;
      final high = (info['matchThreshold'] as num).toDouble();
      final low = (info['uncertainThreshold'] as num).toDouble();
      final margin = (info['minimumMargin'] as num).toDouble();
      if (!(low >= -1 &&
          low < high &&
          high <= 1 &&
          margin >= 0 &&
          margin <= 2)) {
        throw const FormatException('Invalid calibration');
      }
      final all = await animals();
      // An empty register or records without source images cannot establish an unknown.
      if (all.isEmpty || all.any((a) => a.muzzleFrames.isEmpty)) {
        return const VerificationResult(VerificationStatus.pending);
      }
      final saved = await templates.read();
      final fresh = <Map<String, dynamic>>[];
      final candidates = <(Animal, double)>[];
      final query = unitVector(await engine.embed(jpeg, version));
      for (final animal in all) {
        final digest =
            (await Sha256().hash(utf8.encode(animal.muzzleFrames.join())))
                .toString();
        final matching = saved.where((e) =>
            e['id'] == animal.id &&
            e['version'] == version &&
            e['digest'] == digest);
        List<double> vector;
        if (matching.isNotEmpty) {
          vector = unitVector((matching.first['vector'] as List)
              .cast<num>()
              .map((n) => n.toDouble())
              .toList());
        } else {
          final sum = List<double>.filled(512, 0);
          for (final frame in animal.muzzleFrames) {
            final sample = unitVector(await engine.embed(frame, version));
            for (var i = 0; i < 512; i++) {
              sum[i] += sample[i];
            }
          }
          vector = unitVector(sum);
        }
        fresh.add({
          'id': animal.id,
          'version': version,
          'digest': digest,
          'vector': vector
        });
        var similarity = 0.0;
        for (var i = 0; i < 512; i++) {
          similarity += query[i] * vector[i];
        }
        candidates.add((animal, similarity.clamp(-1, 1)));
      }
      await templates.save(fresh);
      candidates.sort((a, b) => b.$2.compareTo(a.$2));
      final top = candidates.first;
      final ambiguous =
          candidates.length > 1 && top.$2 - candidates[1].$2 < margin;
      final status = top.$2 >= high
          ? (ambiguous
              ? VerificationStatus.uncertain
              : VerificationStatus.verified)
          : top.$2 >= low
              ? VerificationStatus.uncertain
              : VerificationStatus.unregistered;
      return VerificationResult(status,
          animal: status == VerificationStatus.verified ? top.$1 : null,
          confidence: top.$2,
          research: info['research'] == true);
    } finally {
      busy = false;
    }
  }
}
