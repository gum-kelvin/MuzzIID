import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../domain/register.dart';
import '../domain/field_records.dart';
import 'strings.dart';
import 'state.dart';

Widget pageBody(List<Widget> children) => Center(
    child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child:
            ListView(padding: const EdgeInsets.all(24), children: children)));
void problem(BuildContext context) {
  const message = 'Unable to save. Please try again.';
  final language =
      ProviderScope.containerOf(context, listen: false).read(languageProvider);
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(language == 'lg' ? luganda[message] ?? message : message)));
}

String day(DateTime time) =>
    '${time.day.toString().padLeft(2, '0')}/${time.month.toString().padLeft(2, '0')}/${time.year}';
Widget animalPhoto(Animal a, {double size = 48}) =>
    _AnimalPhoto(animal: a, size: size);

class _AnimalPhoto extends StatefulWidget {
  final Animal animal;
  final double size;
  const _AnimalPhoto({required this.animal, required this.size});
  @override
  State<_AnimalPhoto> createState() => _AnimalPhotoState();
}

class _AnimalPhotoState extends State<_AnimalPhoto> {
  Uint8List? bytes;
  bool invalid = false;
  void decode() {
    invalid = false;
    bytes = null;
    try {
      if (widget.animal.muzzleFrames.isNotEmpty) {
        bytes = base64Decode(widget.animal.muzzleFrames.first);
      }
    } on FormatException {
      invalid = true;
    }
  }

  @override
  void initState() {
    super.initState();
    decode();
  }

  @override
  void didUpdateWidget(covariant _AnimalPhoto old) {
    super.didUpdateWidget(old);
    if (old.animal.muzzleFrames.firstOrNull !=
        widget.animal.muzzleFrames.firstOrNull) {
      decode();
    }
  }

  @override
  Widget build(BuildContext context) => ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: bytes == null
          ? SizedBox(
              width: widget.size,
              height: widget.size,
              child: Icon(
                  invalid ? Icons.broken_image_outlined : Icons.pets_outlined))
          : Image.memory(bytes!,
              width: widget.size,
              height: widget.size,
              cacheWidth:
                  (widget.size * MediaQuery.devicePixelRatioOf(context)).ceil(),
              fit: BoxFit.cover,
              errorBuilder: (_, error, stack) => SizedBox(
                  width: widget.size,
                  height: widget.size,
                  child: const Icon(Icons.broken_image_outlined))));
}

Widget section(BuildContext context, String label) => Padding(
    padding: const EdgeInsets.only(top: 28, bottom: 12),
    child: Text(label,
        style: Theme.of(context)
            .textTheme
            .titleMedium
            ?.copyWith(fontWeight: FontWeight.w600)));
Widget detail(IconData icon, String title, String value) => ListTile(
    contentPadding: EdgeInsets.zero,
    leading: Icon(icon),
    title: Text(title),
    subtitle: Text(value));
Widget badge(String text, {bool warning = false}) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
        color: warning ? const Color(0xffffedbb) : const Color(0xffdcecdf),
        borderRadius: BorderRadius.circular(12)),
    child: Text(text,
        style: TextStyle(
            color: warning ? const Color(0xff644900) : const Color(0xff17472e),
            fontSize: 12,
            fontWeight: FontWeight.w600)));

class GpsSummary extends ConsumerWidget {
  final GeoFix? fix;
  final bool loading;
  final VoidCallback onRetry;
  final String? error;
  const GpsSummary(
      {super.key,
      this.fix,
      this.loading = false,
      required this.onRetry,
      this.error});
  @override
  Widget build(BuildContext context, WidgetRef ref) => error == null
      ? const SizedBox.shrink()
      : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(tr(ref, error!),
              style: TextStyle(color: Theme.of(context).colorScheme.error)),
          TextButton(
              onPressed: loading ? null : onRetry,
              child: Text(tr(ref, 'Try again'))),
        ]);
}
