import 'dart:async';
import 'dart:convert';
import 'dart:io';
import '../domain/register.dart';

const remoteMode = bool.fromEnvironment('REMOTE_BIOMETRICS');
const backendUrl = String.fromEnvironment('BACKEND_URL',
    defaultValue: 'http://127.0.0.1:8000');

class BackendException implements Exception {
  final String message;
  BackendException(this.message);
  @override
  String toString() => message;
}

class RemoteBackend {
  final String url;
  final Duration timeout;
  RemoteBackend(
      {this.url = backendUrl, this.timeout = const Duration(seconds: 120)});
  Future<dynamic> request(String method, String path, [Object? body]) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    try {
      return await (() async {
        final request = await client.openUrl(method, Uri.parse('$url$path'));
        if (body != null) {
          request.headers.contentType = ContentType.json;
          request.write(jsonEncode(body));
        }
        final response = await request.close();
        final text = await utf8.decoder.bind(response).join();
        final data = text.isEmpty ? null : jsonDecode(text);
        if (response.statusCode >= 400) {
          throw BackendException(
              'Backend ${response.statusCode}: ${data is Map ? data['detail'] : text}');
        }
        return data;
      })()
          .timeout(timeout);
    } on TimeoutException {
      throw BackendException(
          'Backend timed out. Check server status before retrying enrollment.');
    } on SocketException {
      throw BackendException(
          'Backend connection lost. Check USB, adb reverse and server.');
    } on HttpException {
      throw BackendException(
          'Backend connection interrupted. Check server and USB forwarding.');
    } on FormatException {
      throw BackendException(
          'Backend returned an invalid response. Check backend URL and server logs.');
    } finally {
      client.close(force: true);
    }
  }

  Future<Map<String, dynamic>> recognize(String jpeg) async =>
      Map<String, dynamic>.from(
          await request('POST', '/recognize', {'image': jpeg}));
}

/// Reads every authoritative record from the server. Never writes remote cattle
/// to the encrypted local registry or compares against local-mode templates.
class RemoteRegister implements RegisterRepository {
  final RemoteBackend backend;
  RemoteRegister([RemoteBackend? backend])
      : backend = backend ?? RemoteBackend();
  List<Animal> _snapshot = [];
  @override
  Future<List<Animal>> read() async {
    final records = (await backend.request('GET', '/animals') as List)
        .map((j) => Animal.fromJson(Map<String, dynamic>.from(j)))
        .toList();
    _snapshot = records;
    return records;
  }

  @override
  Future<void> save(List<Animal> animals) async {
    final existing = {for (final a in _snapshot) a.id: a};
    for (final animal in animals) {
      final old = existing.remove(animal.id);
      final path = '/animals/${Uri.encodeComponent(animal.id)}';
      if (old == null) {
        await backend.request('POST', '/enroll',
            {'record': animal.toJson(), 'images': animal.muzzleFrames});
      } else {
        if (old.owner != animal.owner || old.location != animal.location) {
          await backend.request('PATCH', path, animal.toJson());
        }
        for (final dose in animal.vaccinations) {
          if (!old.vaccinations.any((v) => v.id == dose.id)) {
            await backend.request('POST', '$path/vaccinations', dose.toJson());
          }
        }
      }
    }
    for (final id in existing.keys) {
      await backend.request('DELETE', '/animals/${Uri.encodeComponent(id)}');
    }
  }
}
