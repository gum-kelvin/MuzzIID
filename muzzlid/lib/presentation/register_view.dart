import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../domain/register.dart';
import 'strings.dart';
import 'ui_parts.dart';
import 'enrol_screen.dart';
import 'profile_screen.dart';

class RegisterView extends ConsumerStatefulWidget {
  final List<Animal> animals;
  const RegisterView({super.key, required this.animals});
  @override
  ConsumerState<RegisterView> createState() => _RegisterViewState();
}

class _RegisterViewState extends ConsumerState<RegisterView> {
  String query = '', filter = 'All';
  bool included(Animal a) {
    if (!'${a.id} ${a.owner} ${a.location}'
        .toLowerCase()
        .contains(query.toLowerCase())) {
      return false;
    }
    final due = a.vaccinations.any((v) =>
        v.validUntil != null &&
        v.validUntil!.difference(DateTime.now()).inDays <= 30);
    return switch (filter) {
      'Vaccinated' => a.vaccinations.isNotEmpty,
      'Due soon' => due,
      'None' => a.vaccinations.isEmpty,
      _ => true
    };
  }

  @override
  Widget build(BuildContext context) {
    final matches = widget.animals.where(included).toList(growable: false);
    return Center(
        child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: ListView.builder(
                padding: const EdgeInsets.all(24),
                itemCount: matches.length + 2,
                itemBuilder: (context, index) {
                  if (index == 0) {
                    return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          TextField(
                              key: const ValueKey('Register search'),
                              onChanged: (v) => setState(() => query = v),
                              decoration: InputDecoration(
                                  prefixIcon: const Icon(Icons.search),
                                  labelText:
                                      tr(ref, 'Search ID, owner or location'))),
                          const SizedBox(height: 12),
                          Wrap(spacing: 8, runSpacing: 4, children: [
                            for (final value in [
                              'All',
                              'Vaccinated',
                              'Due soon',
                              'None'
                            ])
                              ChoiceChip(
                                  label: Text(tr(ref, value)),
                                  selected: filter == value,
                                  onSelected: (_) =>
                                      setState(() => filter = value))
                          ]),
                          const SizedBox(height: 20),
                          if (matches.isEmpty)
                            Text(tr(
                                ref,
                                widget.animals.isEmpty
                                    ? 'No animals registered yet.'
                                    : 'No matching animals')),
                        ]);
                  }
                  if (index == matches.length + 1) {
                    return Padding(
                        padding: const EdgeInsets.only(top: 24),
                        child: FilledButton(
                            onPressed: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                    builder: (_) => const EnrolScreen())),
                            child: Text(tr(ref, 'Enrol animal'))));
                  }
                  final a = matches[index - 1];
                  return Card(
                      key: ValueKey(a.id),
                      child: ListTile(
                          leading: animalPhoto(a),
                          title: Text(a.id, overflow: TextOverflow.ellipsis),
                          subtitle: Text(
                              '${a.owner}\n${a.location.isEmpty ? a.gps?.label ?? '' : a.location} · ${day(a.created)}'),
                          isThreeLine: true,
                          trailing: badge(tr(
                              ref,
                              a.vaccinations.isEmpty
                                  ? 'No vaccine'
                                  : 'Vaccinated')),
                          onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) =>
                                      AnimalProfileScreen(animal: a)))));
                })));
  }
}
