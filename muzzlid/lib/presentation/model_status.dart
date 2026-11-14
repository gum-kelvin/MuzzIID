import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'field_state.dart';
import 'strings.dart';

class ModelStatusCard extends ConsumerWidget {
  const ModelStatusCard({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => Card(
        child: Padding(
            padding: const EdgeInsets.all(16),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(tr(ref, 'On-device verification'),
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              ref.watch(modelStatusProvider).when(
                    loading: () => const LinearProgressIndicator(),
                    error: (error, stack) => Text(tr(ref,
                        'Model could not load. Check the model configuration.')),
                    data: (status) => Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (status['modelName'] is String) ...[
                            Text(status['modelName'] as String,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600)),
                            const SizedBox(height: 8),
                          ],
                          Text(tr(
                              ref,
                              status['ready'] != true
                                  ? 'Model not installed. Scans can still be saved privately.'
                                  : status['calibrated'] != true
                                      ? 'Model installed. Calibration is required before identification.'
                                      : status['research'] == true
                                          ? 'Research model ready. Results need field validation.'
                                          : 'Model ready. Verification compares against records saved on this device.'))
                        ]),
                  ),
              const SizedBox(height: 8),
              TextButton.icon(
                  onPressed: () {
                    ref.invalidate(modelStatusProvider);
                    ref.invalidate(detectorStatusProvider);
                  },
                  icon: const Icon(Icons.refresh),
                  label: Text(tr(ref, 'Check model'))),
            ])),
      );
}
