import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../domain/register.dart';
import '../domain/field_records.dart';
import 'state.dart';
import 'field_state.dart';
import 'strings.dart';
import 'ui_parts.dart';
import 'vaccine_editor.dart';

class VaccinationScreen extends ConsumerStatefulWidget {
  final Animal animal;
  const VaccinationScreen({super.key, required this.animal});
  @override
  ConsumerState<VaccinationScreen> createState() => _VaccinationState();
}

class _VaccinationState extends ConsumerState<VaccinationScreen> {
  Set<String> selected = {};
  DateTime date = DateUtils.dateOnly(DateTime.now());
  DateTime? until;
  GeoFix? gps;
  bool locating = false, saving = false;
  String? gpsError;
  Future<GeoFix?>? locationRequest;
  final batch = TextEditingController();
  @override
  void initState() {
    super.initState();
    Future.microtask(locate);
  }

  @override
  void dispose() {
    batch.dispose();
    super.dispose();
  }

  Future<GeoFix?> locate() => locationRequest ??= fetchLocation();
  Future<GeoFix?> fetchLocation() async {
    if (mounted) setState(() => locating = true);
    try {
      final fix = await ref.read(locationServiceProvider).locate();
      if (mounted) {
        setState(() {
          gps = fix;
          gpsError = null;
        });
      }
      return fix;
    } catch (e) {
      if (mounted) {
        setState(() => gpsError = e is StateError
            ? e.message.toString()
            : 'Unable to get GPS. Try again.');
      }
      return null;
    } finally {
      locationRequest = null;
      if (mounted) setState(() => locating = false);
    }
  }

  Future<void> save() async {
    if (saving || selected.isEmpty) return;
    if (until != null && until!.isBefore(date)) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(tr(ref, 'Validity must be after administration'))));
      return;
    }
    setState(() => saving = true);
    try {
      if (gps == null || !gps!.fresh(DateTime.now())) {
        final fix = await locate();
        if (fix == null) return;
      }
      if (!mounted) return;
      final item = Vaccination(
          id: 'VAC-${DateTime.now().microsecondsSinceEpoch}',
          vaccine: selected.single,
          administeredAt: date,
          recordedAt: DateTime.now().toUtc(),
          validUntil: until,
          batch: batch.text.trim(),
          gps: gps);
      await ref
          .read(registerProvider.notifier)
          .addVaccination(widget.animal, item);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(tr(ref, 'Saved offline'))));
        Navigator.pop(context);
      }
    } catch (_) {
      if (mounted) problem(context);
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: Text(tr(ref, 'Add vaccination'))),
      body: pageBody([
        ListTile(
            leading: animalPhoto(widget.animal),
            title: Text(widget.animal.id),
            subtitle: Text(widget.animal.owner)),
        section(context, tr(ref, 'Vaccine')),
        VaccineEditor(
            selected: selected,
            date: date,
            onSelection: (v) =>
                setState(() => selected = v.isEmpty ? {} : {v.last}),
            onDate: (v) => setState(() => date = v)),
        ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(tr(ref, 'Valid until (optional)')),
            subtitle:
                Text(until == null ? tr(ref, 'Not specified') : day(until!)),
            trailing: until == null
                ? null
                : IconButton(
                    tooltip: tr(ref, 'Clear'),
                    onPressed: () => setState(() => until = null),
                    icon: const Icon(Icons.clear)),
            onTap: () async {
              final value = await showDatePicker(
                  context: context,
                  initialDate: until ?? date,
                  firstDate: date,
                  lastDate: DateTime.now().add(const Duration(days: 3650)),
                  cancelText: tr(ref, 'Cancel'),
                  confirmText: tr(ref, 'Done'),
                  helpText: tr(ref, 'Valid until'));
              if (value != null) setState(() => until = value);
            }),
        const SizedBox(height: 16),
        TextField(
            controller: batch,
            maxLength: 80,
            decoration:
                InputDecoration(labelText: tr(ref, 'Batch number (optional)'))),
        GpsSummary(
            fix: gps, loading: locating, error: gpsError, onRetry: locate),
        const SizedBox(height: 24),
        FilledButton(
            onPressed: saving || selected.isEmpty ? null : save,
            child: Text(tr(ref, 'Save vaccination'))),
        if (saving) const LinearProgressIndicator(),
      ]));
}
