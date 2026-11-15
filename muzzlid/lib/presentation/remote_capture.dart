import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import '../data/remote_backend.dart';
import '../domain/register.dart';
import 'profile_screen.dart';

Future<String?> cropMuzzle(BuildContext context, String jpeg) =>
    Navigator.push<String>(
        context, MaterialPageRoute(builder: (_) => MuzzleCrop(jpeg: jpeg)));

class MuzzleCrop extends StatefulWidget {
  final String jpeg;
  const MuzzleCrop({super.key, required this.jpeg});
  @override
  State<MuzzleCrop> createState() => _MuzzleCropState();
}

class _MuzzleCropState extends State<MuzzleCrop> {
  double left = 0, top = 0, width = 1, height = 1;
  late final bytes = base64Decode(widget.jpeg);
  late final decoded = img.decodeImage(bytes);
  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: const Text('Crop muzzle')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        const Text(
            'Keep the entire muzzle pattern. Adjust the green rectangle, or use the whole image.'),
        AspectRatio(
            aspectRatio: 1,
            child: LayoutBuilder(builder: (context, box) {
              final decoded = this.decoded;
              if (decoded == null) return const Text('Invalid image');
              final size = applyBoxFit(
                      BoxFit.contain,
                      Size(decoded.width.toDouble(), decoded.height.toDouble()),
                      box.biggest)
                  .destination;
              return Center(
                  child: SizedBox(
                      width: size.width,
                      height: size.height,
                      child: Stack(children: [
                        Image.memory(bytes,
                            width: size.width,
                            height: size.height,
                            fit: BoxFit.fill),
                        Positioned(
                            left: left * size.width,
                            top: top * size.height,
                            width: width * size.width,
                            height: height * size.height,
                            child: IgnorePointer(
                                child: Container(
                                    decoration: BoxDecoration(
                                        border: Border.all(
                                            color: Colors.greenAccent,
                                            width: 3)))))
                      ])));
            })),
        const Text('Left'),
        Slider(
            value: left,
            max: 1 - width,
            onChanged: (v) => setState(() => left = v)),
        const Text('Top'),
        Slider(
            value: top,
            max: 1 - height,
            onChanged: (v) => setState(() => top = v)),
        const Text('Width'),
        Slider(
            value: width,
            min: .1,
            onChanged: (v) => setState(() {
                  width = v;
                  if (left + v > 1) left = 1 - v;
                })),
        const Text('Height'),
        Slider(
            value: height,
            min: .1,
            onChanged: (v) => setState(() {
                  height = v;
                  if (top + v > 1) top = 1 - v;
                })),
        FilledButton(
            onPressed: () {
              final image = decoded;
              if (image == null) return;
              final crop = img.copyCrop(image,
                  x: (left * image.width).round(),
                  y: (top * image.height).round(),
                  width: (width * image.width).round(),
                  height: (height * image.height).round());
              Navigator.pop(
                  context, base64Encode(img.encodeJpg(crop, quality: 95)));
            },
            child: const Text('Use crop')),
      ]));
}

Future<List<String>?> galleryFrames(BuildContext context, int count) async {
  final frames = <String>[];
  for (var i = 0; i < count; i++) {
    final data = await const MethodChannel('com.example.muzzlid/gallery')
        .invokeMethod<Uint8List>('pick');
    if (data == null || !context.mounted) return null;
    final decoded = img.decodeImage(data);
    if (decoded == null) {
      throw BackendException('Invalid or corrupt gallery image');
    }
    final oriented = img.bakeOrientation(decoded);
    final crop = await cropMuzzle(
        context, base64Encode(img.encodeJpg(oriented, quality: 95)));
    if (crop == null || !context.mounted) return null;
    frames.add(crop);
  }
  return frames;
}

class RemoteIdentification extends StatefulWidget {
  final String frame;
  const RemoteIdentification({super.key, required this.frame});
  @override
  State<RemoteIdentification> createState() => _RemoteIdentificationState();
}

class _RemoteIdentificationState extends State<RemoteIdentification> {
  late Future<Map<String, dynamic>> result =
      RemoteBackend().recognize(widget.frame);
  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: const Text('Remote identification')),
      body: FutureBuilder<Map<String, dynamic>>(
          future: result,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                CircularProgressIndicator(),
                Text('Comparing with MegaDescriptor on laptop CPU')
              ]));
            }
            if (snapshot.hasError) {
              return Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text('${snapshot.error}'),
                FilledButton(
                    onPressed: () => setState(
                        () => result = RemoteBackend().recognize(widget.frame)),
                    child: const Text('Retry'))
              ]));
            }
            final data = snapshot.requireData;
            final accepted =
                data['decision'] == 'accepted' && data['animal'] != null;
            return ListView(padding: const EdgeInsets.all(24), children: [
              Text('${data['decision']}',
                  style: Theme.of(context).textTheme.headlineMedium),
              Text('Cosine similarity: ${data['score'] ?? 'empty registry'}'),
              const Text(
                  'Research demonstration. Similarity is not a probability. Uncertain scans require review.'),
              if (accepted)
                FilledButton(
                    onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => AnimalProfileScreen(
                                animal: Animal.fromJson(
                                    Map<String, dynamic>.from(
                                        data['animal']))))),
                    child: const Text('View accepted animal and vaccinations')),
            ]);
          }));
}
