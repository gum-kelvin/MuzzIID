import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'field_state.dart';
import 'strings.dart';

class CaptureSettings extends ConsumerWidget {
  const CaptureSettings({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(settingsProvider);
    final detectorReady = ref.watch(detectorStatusProvider).valueOrNull == true;
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      value: !detectorReady || config.valueOrNull?['guided'] == true,
      onChanged: !detectorReady || !config.hasValue
          ? null
          : (v) => ref.read(settingsProvider.notifier).set('guided', v),
      title: Text(tr(ref, 'Guided capture reticle')),
      subtitle: Text(tr(
          ref,
          detectorReady
              ? 'Use manual framing instead of automatic detection.'
              : 'Guided capture is required until a detector is available.')),
    );
  }
}
