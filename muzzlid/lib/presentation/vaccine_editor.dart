import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../domain/field_records.dart';
import 'strings.dart';
import 'ui_parts.dart';

const vaccineChoices = ['FMD', 'Lumpy skin', 'Brucellosis', 'Anthrax', 'Other'];

class VaccineEditor extends ConsumerWidget {
  final Set<String> selected;
  final DateTime date;
  final ValueChanged<Set<String>> onSelection;
  final ValueChanged<DateTime> onDate;
  const VaccineEditor(
      {super.key,
      required this.selected,
      required this.date,
      required this.onSelection,
      required this.onDate});
  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final name in vaccineChoices)
            FilterChip(
                label: Text(tr(ref, name)),
                selected: selected.contains(name),
                onSelected: (value) {
                  final next = {...selected};
                  value ? next.add(name) : next.remove(name);
                  onSelection(next);
                })
        ]),
        const SizedBox(height: 12),
        ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.calendar_today_outlined),
            title: Text(tr(ref, 'Date administered')),
            subtitle: Text(day(date)),
            onTap: () async {
              final chosen = await showDatePicker(
                  context: context,
                  initialDate: date,
                  firstDate: DateTime(2000),
                  lastDate: DateTime.now(),
                  cancelText: tr(ref, 'Cancel'),
                  confirmText: tr(ref, 'Done'),
                  helpText: tr(ref, 'Date administered'));
              if (chosen != null) onDate(chosen);
            }),
      ]);
}

List<Vaccination> buildVaccinations(
        Set<String> vaccines, DateTime date, String receipt, GeoFix? gps) =>
    [
      for (final name in vaccines)
        Vaccination(
            id: '$receipt-$name',
            vaccine: name,
            administeredAt: date,
            recordedAt: DateTime.now().toUtc(),
            gps: gps)
    ];
