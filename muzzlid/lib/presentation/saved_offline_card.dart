import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'field_state.dart';
import 'state.dart';
import 'strings.dart';
import 'sync_screen.dart';

class SavedOfflineCard extends ConsumerWidget {
  const SavedOfflineCard({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final animals = ref.watch(registerProvider).valueOrNull ?? [];
    final activity = ref.watch(activityProvider).valueOrNull ?? [];
    final pending = animals.where((a) => a.syncState != 'acknowledged').length +
        activity.where((a) => a.status == 'pending').length;
    return Card(
        child: ListTile(
      leading: const Icon(Icons.cloud_off_outlined),
      title: Text(tr(ref, 'Saved offline')),
      subtitle: Text('$pending · ${tr(ref, 'Pending sync')}'),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => Navigator.push(
          context, MaterialPageRoute(builder: (_) => const SyncScreen())),
    ));
  }
}
