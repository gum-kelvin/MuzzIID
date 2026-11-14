import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../domain/register.dart';
import '../domain/field_records.dart';
import 'state.dart';
import 'strings.dart';
import 'field_state.dart';
import 'scanner_screen.dart';
import 'vaccine_editor.dart';
import 'ui_parts.dart';
import 'receipt_screen.dart';

final captureFramesProvider =
    Provider<Future<List<String>?> Function(BuildContext)>((ref) => (context) =>
        Navigator.push<List<String>>(
            context, MaterialPageRoute(builder: (_) => const ScannerScreen())));

class EnrolScreen extends ConsumerStatefulWidget {
  final Animal? animal;
  const EnrolScreen({super.key, this.animal});
  @override
  ConsumerState<EnrolScreen> createState() => _EnrolState();
}

class _EnrolState extends ConsumerState<EnrolScreen> {
  final form = GlobalKey<FormState>();
  late final owner = TextEditingController(text: widget.animal?.owner ?? '');
  late final place = TextEditingController(text: widget.animal?.location ?? '');
  late GeoFix? gps = widget.animal?.gps;
  late List<String> frames = [...?widget.animal?.muzzleFrames];
  int step = 0;
  bool locating = false, saving = false;
  String? gpsError;
  bool vaccineGiven = false;
  Set<String> selected = {};
  DateTime date = DateUtils.dateOnly(DateTime.now());
  bool get editing => widget.animal != null;
  @override
  void initState() {
    super.initState();
    if (gps == null) Future.microtask(locate);
  }

  Future<void> locate() async {
    if (locating) return;
    setState(() => locating = true);
    try {
      final fix = await ref.read(locationServiceProvider).locate();
      if (mounted) {
        setState(() {
          gps = fix;
          gpsError = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => gpsError = e is StateError
            ? e.message.toString()
            : 'Unable to get GPS. Try again.');
      }
    } finally {
      if (mounted) setState(() => locating = false);
    }
  }

  @override
  void dispose() {
    owner.dispose();
    place.dispose();
    super.dispose();
  }

  Future<void> capture() async {
    final result = await ref.read(captureFramesProvider)(context);
    if (result != null && mounted && result.length == 5) {
      setState(() {
        frames = result;
        step = 2;
      });
    }
  }

  Future<void> next() async {
    if (!form.currentState!.validate()) return;
    if (gps == null || (!editing && !gps!.fresh(DateTime.now()))) {
      await locate();
      return;
    }
    if (editing) {
      await save();
      return;
    }
    setState(() => step = 1);
    await capture();
  }

  Future<void> save() async {
    if (gps == null || (!editing && frames.length != 5)) return;
    if (!editing && !gps!.fresh(DateTime.now())) {
      await locate();
      return;
    }
    if (vaccineGiven && selected.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(tr(ref, 'Choose a vaccine'))));
      return;
    }
    setState(() => saving = true);
    try {
      final now = DateTime.now().toUtc();
      final id = widget.animal?.id ?? 'LOCAL-${now.microsecondsSinceEpoch}';
      final record = editing
          ? widget.animal!.copyWith(
              owner: owner.text.trim(),
              district: place.text.trim(),
              gps: gps,
              syncState: 'pending',
              syncError: '')
          : Animal(
              id: id,
              owner: owner.text.trim(),
              district: place.text.trim(),
              created: now,
              gps: gps,
              receiptId: id,
              muzzleFrames: frames,
              vaccinations: buildVaccinations(
                  vaccineGiven ? selected : {}, date, id, gps));
      if (editing) {
        await ref.read(registerProvider.notifier).updateDetails(widget.animal!,
            owner: owner.text.trim(), location: place.text.trim(), gps: gps);
      } else {
        await ref.read(registerProvider.notifier).put(record);
      }
      if (!mounted) return;
      if (editing) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(tr(ref, 'Saved offline'))));
        Navigator.pop(context);
      } else {
        Navigator.pushReplacement(context,
            MaterialPageRoute(builder: (_) => ReceiptScreen(animal: record)));
      }
    } catch (_) {
      if (mounted) problem(context);
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
      canPop: step == 0 || editing,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) setState(() => step--);
      },
      child: Scaffold(
        appBar: AppBar(
            title: Text(tr(ref, editing ? 'Edit animal' : 'Enrol animal')),
            actions: [
              if (!editing)
                Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text('${step + 1} / 3'))
            ]),
        body: Form(
            key: form,
            child: pageBody([
              if (!editing) ...[
                LinearProgressIndicator(value: (step + 1) / 3),
                const SizedBox(height: 24)
              ],
              if (step == 0) ...[
                if (editing)
                  badge(
                      '${tr(ref, 'Saved offline')} · ${tr(ref, 'Pending sync')}',
                      warning: true),
                Text(tr(ref, 'Who owns this animal?'),
                    style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 20),
                TextFormField(
                    key: const ValueKey('Owner name'),
                    controller: owner,
                    maxLength: 120,
                    decoration: InputDecoration(
                        labelText: tr(ref, 'Owner name'),
                        prefixIcon: const Icon(Icons.person_outline)),
                    validator: (v) => v == null || v.trim().isEmpty
                        ? tr(ref, 'Required')
                        : null),
                const SizedBox(height: 12),
                TextFormField(
                    key: const ValueKey('Place label'),
                    controller: place,
                    maxLength: 120,
                    decoration: InputDecoration(
                        labelText: tr(ref, 'Place label (optional)'),
                        prefixIcon:
                            const Icon(Icons.edit_location_alt_outlined))),
                const SizedBox(height: 16),
                GpsSummary(
                    fix: gps,
                    loading: locating,
                    onRetry: locate,
                    error: gpsError),
                detail(Icons.schedule, tr(ref, 'Time recorded automatically'),
                    stamp(widget.animal?.created ?? DateTime.now())),
                const SizedBox(height: 24),
                FilledButton(
                    onPressed: saving || locating ? null : next,
                    child: Text(tr(ref,
                        editing ? 'Save changes' : 'Next: capture muzzle'))),
              ],
              if (step == 1) ...[
                Text(tr(ref, 'Capture five clear frames'),
                    style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 16),
                Text(tr(
                    ref, 'Wipe the muzzle dry and keep it inside the guide.')),
                const SizedBox(height: 24),
                FilledButton.icon(
                    onPressed: capture,
                    icon: const Icon(Icons.camera_alt_outlined),
                    label: Text(tr(ref, 'Capture muzzle'))),
                TextButton(
                    onPressed: () => setState(() => step = 0),
                    child: Text(tr(ref, 'Back'))),
              ],
              if (step == 2) ...[
                Text(tr(ref, 'Vaccination & review'),
                    style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 16),
                SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(tr(ref, 'Vaccine given today?')),
                    value: vaccineGiven,
                    onChanged: (v) => setState(() => vaccineGiven = v)),
                if (vaccineGiven)
                  VaccineEditor(
                      selected: selected,
                      date: date,
                      onSelection: (v) => setState(() => selected = v),
                      onDate: (v) => setState(() => date = v)),
                section(context, tr(ref, 'Review')),
                Card(
                    child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(children: [
                          detail(Icons.person_outline, tr(ref, 'Owner name'),
                              owner.text),
                          detail(
                              Icons.location_on_outlined,
                              tr(ref, 'Location'),
                              '${place.text}\n${gps?.label ?? ''}'),
                          detail(
                              Icons.schedule,
                              tr(ref, 'Time recorded automatically'),
                              stamp(DateTime.now())),
                          Wrap(spacing: 6, runSpacing: 6, children: [
                            for (final frame in frames)
                              ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: Image.memory(base64Decode(frame),
                                      width: 48, height: 48, fit: BoxFit.cover))
                          ]),
                          const SizedBox(height: 12),
                          Text(tr(ref, '5-frame burst complete')),
                        ]))),
                const SizedBox(height: 24),
                FilledButton(
                    onPressed: saving ? null : save,
                    child: Text(tr(ref, 'Save enrolment'))),
                TextButton(
                    onPressed: saving ? null : () => setState(() => step = 0),
                    child: Text(tr(ref, 'Edit details'))),
              ],
              if (saving) const LinearProgressIndicator(),
            ])),
      ));
}
