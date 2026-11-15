import '../data/remote_backend.dart';
import 'model_status.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../domain/field_records.dart';
import 'field_state.dart';
import 'scanner_screen.dart';
import 'strings.dart';
import 'ui_parts.dart';

class PreScanScreen extends ConsumerStatefulWidget {
  const PreScanScreen({super.key});
  @override
  ConsumerState<PreScanScreen> createState() => _PreScanState();
}

class _PreScanState extends ConsumerState<PreScanScreen> {
  final checks = [false, false, false];
  GeoFix? gps;
  bool locating = false;
  String? error;
  @override
  void initState() {
    super.initState();
    if (!remoteMode) Future.microtask(locate);
  }

  Future<void> locate() async {
    if (locating) return;
    setState(() => locating = true);
    try {
      final fix = await ref.read(locationServiceProvider).locate();
      if (mounted) {
        setState(() {
          gps = fix;
          error = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => error = e is StateError
            ? e.message.toString()
            : 'Unable to get GPS. Try again.');
      }
    } finally {
      if (mounted) setState(() => locating = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: Text(tr(ref, 'Before you scan'))),
      body: pageBody([
        const Icon(Icons.center_focus_strong,
            size: 80, color: Color(0xff245c40)),
        const SizedBox(height: 24),
        GpsSummary(fix: gps, loading: locating, error: error, onRetry: locate),
        const SizedBox(height: 16),
        for (var i = 0; i < 3; i++)
          CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: checks[i],
              onChanged: (v) => setState(() => checks[i] = v!),
              title: Text(tr(
                  ref,
                  [
                    'Wipe the muzzle dry',
                    'Hold phone about 20 cm away',
                    'Good light, steady animal'
                  ][i]))),
        const SizedBox(height: 24),
        if (remoteMode)
          const Text(
              'Remote MegaDescriptor CPU demo. GPS optional. Printed photos are supported; no liveness check.')
        else
          const ModelStatusCard(),
        const SizedBox(height: 16),
        FilledButton(
            onPressed: checks.every((v) => v) &&
                    (remoteMode || gps != null) &&
                    !locating
                ? () async {
                    if (!remoteMode && !gps!.fresh(DateTime.now())) {
                      await locate();
                      return;
                    }
                    if (context.mounted) {
                      Navigator.pushReplacement(
                          context,
                          MaterialPageRoute(
                              builder: (_) => ScannerScreen(
                                  enrol: false,
                                  scanGps: gps,
                                  initialClean: true)));
                    }
                  }
                : null,
            child: Text(tr(ref, 'Start scanning'))),
      ]));
}
