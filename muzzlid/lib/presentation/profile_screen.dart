import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../domain/register.dart';
import 'state.dart';
import 'strings.dart';
import 'ui_parts.dart';
import 'enrol_screen.dart';
import 'vaccination_screen.dart';

class AnimalProfileScreen extends ConsumerWidget {
  final Animal animal;
  const AnimalProfileScreen({super.key, required this.animal});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(registerProvider).valueOrNull ?? [];
    final a =
        current.firstWhere((a) => a.id == animal.id, orElse: () => animal);
    return Scaffold(
        appBar: AppBar(
            title: Text(a.id, overflow: TextOverflow.ellipsis),
            actions: [
              PopupMenuButton<String>(
                  onSelected: (choice) async {
                    if (choice == 'edit') {
                      Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => EnrolScreen(animal: a)));
                      return;
                    }
                    final yes = await showDialog<bool>(
                        context: context,
                        builder: (c) => AlertDialog(
                                title: Text(tr(ref, 'Delete local record?')),
                                actions: [
                                  TextButton(
                                      onPressed: () => Navigator.pop(c, false),
                                      child: Text(tr(ref, 'Cancel'))),
                                  TextButton(
                                      onPressed: () => Navigator.pop(c, true),
                                      child: Text(tr(ref, 'Delete')))
                                ]));
                    if (yes == true) {
                      try {
                        await ref.read(registerProvider.notifier).remove(a.id);
                        if (context.mounted) Navigator.pop(context);
                      } catch (_) {
                        if (context.mounted) problem(context);
                      }
                    }
                  },
                  itemBuilder: (_) => [
                        PopupMenuItem(
                            value: 'edit', child: Text(tr(ref, 'Edit animal'))),
                        if (current.any((item) => item.id == a.id))
                          PopupMenuItem(
                              value: 'delete', child: Text(tr(ref, 'Delete')))
                      ])
            ]),
        bottomNavigationBar: SafeArea(
            top: false,
            child: Padding(
                padding: const EdgeInsets.all(16),
                child: FilledButton.icon(
                    onPressed: () {
                      ScaffoldMessenger.of(context).hideCurrentSnackBar();
                      Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => VaccinationScreen(animal: a)));
                    },
                    icon: const Icon(Icons.add),
                    label: Text(tr(ref, 'Add vaccination'))))),
        body: pageBody([
          Center(child: animalPhoto(a, size: 180)),
          const SizedBox(height: 16),
          Align(
              alignment: Alignment.center,
              child: badge(
                  tr(
                      ref,
                      a.syncState == 'acknowledged'
                          ? 'Synced'
                          : 'Pending sync'),
                  warning: a.syncState != 'acknowledged')),
          section(context, tr(ref, 'Owner')),
          detail(Icons.person_outline, tr(ref, 'Owner name'), a.owner),
          section(context, tr(ref, 'Registered')),
          detail(Icons.schedule, tr(ref, 'Recorded'), stamp(a.created)),
          detail(Icons.location_on_outlined, tr(ref, 'Location'),
              '${a.location}\n${a.gps?.label ?? tr(ref, 'GPS not recorded')}'),
          section(context, tr(ref, 'Vaccinations')),
          if (a.vaccinations.isEmpty) Text(tr(ref, 'No vaccination records')),
          if (a.vaccines.isNotEmpty)
            detail(
                Icons.history, tr(ref, 'Legacy vaccination notes'), a.vaccines),
          for (final v in a.vaccinations)
            Card(
                child: ListTile(
                    leading: const Icon(Icons.vaccines_outlined),
                    title: Text(tr(ref, v.vaccine)),
                    subtitle: Text(
                        '${tr(ref, 'Given')} ${day(v.administeredAt)}${v.validUntil == null ? '' : '\n${tr(ref, 'Valid until')} ${day(v.validUntil!)}'}${v.batch.isEmpty ? '' : '\n${tr(ref, 'Batch number')} ${v.batch}'}'))),
        ]));
  }
}
