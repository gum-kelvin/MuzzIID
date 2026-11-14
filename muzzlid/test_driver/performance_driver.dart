import 'dart:convert';
import 'dart:io';
import 'package:integration_test/integration_test_driver_extended.dart';

Future<void> main() => integrationDriver(responseDataCallback: (data) async {
      final destination = File('test-results/camera-device-profile.json');
      await destination.parent.create(recursive: true);
      await destination
          .writeAsString(const JsonEncoder.withIndent('  ').convert(data));
    });
