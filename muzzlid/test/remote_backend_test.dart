import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:muzzlid/data/remote_backend.dart';

void main() {
  test('connection loss returns an actionable backend error', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final port = server.port;
    await server.close(force: true);
    final backend = RemoteBackend(url: 'http://127.0.0.1:$port');
    await expectLater(
        backend.request('GET', '/health'),
        throwsA(isA<BackendException>()
            .having((e) => e.message, 'message', contains('connection lost'))));
  });
  test('timeout closes the request and returns an actionable backend error',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final subscription = server.listen((request) {});
    try {
      final backend = RemoteBackend(
          url: 'http://127.0.0.1:${server.port}',
          timeout: const Duration(milliseconds: 50));
      await expectLater(
          backend.request('GET', '/health'),
          throwsA(isA<BackendException>()
              .having((e) => e.message, 'message', contains('timed out'))));
    } finally {
      await server.close(force: true);
      await subscription.cancel();
    }
  });
}
