import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'state.dart';
import 'field_state.dart';
import 'strings.dart';
import 'ui_parts.dart';
import 'profile_screen.dart';

class SyncScreen extends ConsumerWidget {
  const SyncScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final records = ref.watch(registerProvider),
        scans = ref.watch(activityProvider);
    return Scaffold(
        appBar: AppBar(title: Text(tr(ref, 'Sync status'))),
        body: records.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, stack) =>
              Center(child: Text(tr(ref, 'Unable to read local records.'))),
          data: (animals) {
            final pendingScans = (scans.valueOrNull ?? [])
                .where((s) => s.status == 'pending')
                .toList(growable: false);
            final rows = <Widget Function()>[
              () => Text(tr(ref, 'Saved offline'),
                  style: Theme.of(context).textTheme.headlineSmall),
              () => const SizedBox(height: 12),
              () => Text(
                  '${animals.where((a) => a.syncState != 'acknowledged').length + pendingScans.length} ${tr(ref, 'waiting to upload')}'),
              () => const SizedBox(height: 16),
              () => Text(tr(ref,
                  'Sync service is not connected. Your records stay on this device.')),
              () => const SizedBox(height: 16),
              () => FilledButton.icon(
                  onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                          content: Text(tr(ref,
                              'Sync service is not connected. Your records stay on this device.')))),
                  icon: const Icon(Icons.sync),
                  label: Text(tr(ref, 'Sync now'))),
              if (animals.any((a) => a.syncState == 'conflict'))
                () => section(context, tr(ref, 'Needs attention')),
              for (final a in animals.where((a) => a.syncState == 'conflict'))
                () => ListTile(
                    leading: const Icon(Icons.warning_amber),
                    title: Text(a.owner),
                    subtitle:
                        Text(tr(ref, 'Duplicate conflict requires review')),
                    onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => AnimalProfileScreen(animal: a)))),
              () => section(context, tr(ref, 'Waiting')),
              for (final a in animals.where((a) =>
                  a.syncState != 'acknowledged' && a.syncState != 'conflict'))
                () => ListTile(
                    leading: animalPhoto(a),
                    title: Text(a.owner),
                    subtitle: Text(a.id),
                    trailing: badge(
                        tr(
                            ref,
                            a.syncState == 'failed'
                                ? 'Failed'
                                : 'Pending sync'),
                        warning: true),
                    onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => AnimalProfileScreen(animal: a)))),
              if (scans.isLoading) () => const LinearProgressIndicator(),
              if (scans.hasError)
                () => Text(tr(ref, 'Unable to read local records.')),
              for (var index = 0; index < pendingScans.length; index++)
                () => ListTile(
                    leading: const Icon(Icons.center_focus_strong),
                    title: Text(tr(ref, 'Verification pending')),
                    trailing: badge(tr(ref, 'Pending sync'), warning: true)),
              if (animals.any((a) => a.syncState == 'acknowledged'))
                () => section(context, tr(ref, 'Synced')),
              for (final a
                  in animals.where((a) => a.syncState == 'acknowledged'))
                () => ListTile(
                    title: Text(a.owner),
                    subtitle: Text(a.id),
                    trailing: badge(tr(ref, 'Synced'))),
            ];
            return Center(
                child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 640),
                    child: ListView.builder(
                        padding: const EdgeInsets.all(24),
                        itemCount: rows.length,
                        itemBuilder: (_, index) => rows[index]())));
          },
        ));
  }
}
