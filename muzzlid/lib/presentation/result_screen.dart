import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../domain/verification.dart';
import '../domain/field_records.dart';
import 'strings.dart';
import 'ui_parts.dart';
import 'pre_scan_screen.dart';
import 'profile_screen.dart';
import 'vaccination_screen.dart';
import 'enrol_screen.dart';

class ResultScreen extends ConsumerWidget {
  final VerificationResult result;
  final String frame;
  final GeoFix gps;
  final DateTime time;
  const ResultScreen(
      {super.key,
      required this.result,
      required this.frame,
      required this.gps,
      required this.time});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = result.status;
    final animal = result.animal;
    final title = switch (status) {
      VerificationStatus.verified => 'Verified match',
      VerificationStatus.uncertain => 'Low confidence',
      VerificationStatus.unregistered => 'No local match',
      VerificationStatus.pending => 'Verification pending'
    };
    return Scaffold(
        appBar: AppBar(title: Text(tr(ref, title))),
        body: pageBody([
          Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                  color: status == VerificationStatus.verified
                      ? const Color(0xffdcecdf)
                      : const Color(0xffffedbb),
                  borderRadius: BorderRadius.circular(16)),
              child: Row(children: [
                Icon(status == VerificationStatus.verified
                    ? Icons.verified_outlined
                    : Icons.info_outline),
                const SizedBox(width: 12),
                Expanded(
                    child: Text(tr(ref, title),
                        style: Theme.of(context).textTheme.titleLarge))
              ])),
          const SizedBox(height: 16),
          if (result.research)
            Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Text(tr(ref,
                    'Research model result. Confirm animal identity manually.'))),
          ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Image.memory(base64Decode(frame),
                  height: 200, fit: BoxFit.cover)),
          if (result.confidence != null)
            Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                    '${tr(ref, 'Similarity')}: ${(result.confidence! * 100).toStringAsFixed(1)}%')),
          if (status == VerificationStatus.pending)
            Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Text(tr(ref,
                    'Scan saved locally. A configured model and complete local reference images are needed for verification.'))),
          if (status == VerificationStatus.unregistered)
            Text(tr(ref,
                'No match in this device’s register. The animal may be registered elsewhere.')),
          if (status == VerificationStatus.uncertain) ...[
            section(context, tr(ref, 'Try again for a clearer scan')),
            Text(tr(ref, 'Wipe moisture, mud or saliva off the muzzle.')),
            Text(tr(ref, 'Turn away from direct sun or deep shadow.')),
            Text(tr(ref, 'Keep the head still and fill the frame.'))
          ],
          if (animal != null) ...[
            section(context, tr(ref, 'Animal ID')),
            SelectableText(animal.id),
            detail(Icons.person_outline, tr(ref, 'Owner name'), animal.owner),
            for (final v in animal.vaccinations)
              detail(Icons.vaccines_outlined, tr(ref, v.vaccine),
                  day(v.administeredAt))
          ],
          detail(Icons.schedule, tr(ref, 'Recorded'), stamp(time)),
          detail(Icons.location_on_outlined, tr(ref, 'Location'), gps.label),
          const SizedBox(height: 24),
          if (status == VerificationStatus.verified && animal != null) ...[
            FilledButton.icon(
                onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => VaccinationScreen(animal: animal))),
                icon: const Icon(Icons.add),
                label: Text(tr(ref, 'Add vaccination'))),
            const SizedBox(height: 8),
            OutlinedButton(
                onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => AnimalProfileScreen(animal: animal))),
                child: Text(tr(ref, 'Full profile'))),
          ],
          if (status == VerificationStatus.unregistered)
            FilledButton.icon(
                onPressed: () => Navigator.pushReplacement(context,
                    MaterialPageRoute(builder: (_) => const EnrolScreen())),
                icon: const Icon(Icons.add),
                label: Text(tr(ref, 'Enrol this animal'))),
          if (status != VerificationStatus.verified)
            OutlinedButton(
                onPressed: () => Navigator.pushReplacement(context,
                    MaterialPageRoute(builder: (_) => const PreScanScreen())),
                child: Text(tr(ref, 'Scan again'))),
          if (status == VerificationStatus.uncertain)
            OutlinedButton(
                onPressed: () => Navigator.pushReplacement(context,
                    MaterialPageRoute(builder: (_) => const EnrolScreen())),
                child: Text(tr(ref, 'Enrol as new animal'))),
          const SizedBox(height: 8),
          TextButton(
              onPressed: () => Navigator.popUntil(context, (r) => r.isFirst),
              child: Text(tr(ref, 'Done'))),
        ]));
  }
}
