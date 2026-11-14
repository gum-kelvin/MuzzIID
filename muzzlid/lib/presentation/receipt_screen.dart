import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../domain/register.dart';
import 'strings.dart';
import 'ui_parts.dart';
import 'enrol_screen.dart';
import 'state.dart';

class ReceiptScreen extends ConsumerWidget {
  final Animal animal;
  const ReceiptScreen({super.key, required this.animal});
  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
      appBar: AppBar(title: Text(tr(ref, 'Receipt'))),
      body: pageBody([
        const SizedBox(height: 24),
        const Icon(Icons.cloud_off_outlined,
            size: 56, color: Color(0xff986f00)),
        const SizedBox(height: 16),
        Center(
            child: Text(tr(ref, 'Saved offline'),
                style: Theme.of(context).textTheme.headlineMedium)),
        const SizedBox(height: 16),
        Center(child: badge(tr(ref, 'Pending sync'), warning: true)),
        const SizedBox(height: 16),
        Text(tr(ref,
            'Your record is stored on this device. Upload will require a connected sync service.')),
        section(context, tr(ref, 'Receipt ID')),
        SelectableText(animal.receiptId),
        detail(Icons.person_outline, tr(ref, 'Owner name'), animal.owner),
        detail(Icons.location_on_outlined, tr(ref, 'Location'),
            '${animal.location}\n${animal.gps?.label ?? ''}'),
        detail(Icons.schedule, tr(ref, 'Recorded'), stamp(animal.created)),
        for (final v in animal.vaccinations)
          detail(Icons.vaccines_outlined, tr(ref, v.vaccine),
              day(v.administeredAt)),
        const SizedBox(height: 24),
        FilledButton.icon(
            onPressed: () => Navigator.pushReplacement(context,
                MaterialPageRoute(builder: (_) => const EnrolScreen())),
            icon: const Icon(Icons.add),
            label: Text(tr(ref, 'Enrol another'))),
        const SizedBox(height: 12),
        OutlinedButton(
            onPressed: () {
              ref.read(shellTabProvider.notifier).state = 0;
              Navigator.popUntil(context, (r) => r.isFirst);
            },
            child: Text(tr(ref, 'Back to Field'))),
      ]));
}
