import '../data/remote_backend.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../domain/register.dart';
import 'field_state.dart';
import 'strings.dart';
import 'ui_parts.dart';
import 'enrol_screen.dart';
import 'pre_scan_screen.dart';
import 'profile_screen.dart';
import 'sync_screen.dart';

class FieldHome extends ConsumerWidget {
  final List<Animal> animals;
  const FieldHome({super.key, required this.animals});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activity = ref.watch(activityProvider);
    final recent = <({DateTime time, String label, Animal? animal})>[
      for (final a in animals) (time: a.created, label: 'Enrolment', animal: a),
      for (final a in animals)
        for (final v in a.vaccinations)
          (time: v.recordedAt ?? v.administeredAt, label: v.vaccine, animal: a),
      for (final item in activity.valueOrNull ?? [])
        (time: item.time, label: 'Verification', animal: null),
    ]..sort((a, b) => b.time.compareTo(a.time));
    return pageBody([
      if (remoteMode) const Text('MegaDescriptor remote demonstration'),
      FilledButton.icon(
          onPressed: () => Navigator.push(context,
              MaterialPageRoute(builder: (_) => const PreScanScreen())),
          icon: const Icon(Icons.center_focus_strong),
          label: Text(tr(ref, 'Verify animal'))),
      const SizedBox(height: 12),
      OutlinedButton.icon(
          onPressed: () => Navigator.push(
              context, MaterialPageRoute(builder: (_) => const EnrolScreen())),
          icon: const Icon(Icons.add),
          label: Text(tr(ref, 'Enrol animal'))),
      const SizedBox(height: 32),
      section(context, tr(ref, 'Recent activity')),
      if (recent.isEmpty) Text(tr(ref, 'No recent activity')),
      if (activity.hasError) Text(tr(ref, 'Unable to read local records.')),
      for (final event in recent.take(5))
        ListTile(
            contentPadding: EdgeInsets.zero,
            leading: event.animal == null
                ? const Icon(Icons.center_focus_strong)
                : animalPhoto(event.animal!),
            title: Text(event.animal?.id ?? tr(ref, 'Verification'),
                overflow: TextOverflow.ellipsis),
            subtitle: Text(
                '${stamp(event.time)} · ${event.animal?.owner ?? tr(ref, 'Saved offline')}'),
            trailing: badge(tr(ref, event.label)),
            onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => event.animal == null
                        ? const SyncScreen()
                        : AnimalProfileScreen(animal: event.animal!)))),
    ]);
  }
}
