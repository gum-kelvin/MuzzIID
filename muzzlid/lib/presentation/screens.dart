import 'model_status.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'state.dart';
import 'strings.dart';
import 'field_home.dart';
import 'register_view.dart';
import 'saved_offline_card.dart';
import 'capture_settings.dart';
import 'ui_parts.dart';
import 'landing_brand.dart';

class FieldScreen extends ConsumerWidget {
  const FieldScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final records = ref.watch(registerProvider);
    final tab = ref.watch(shellTabProvider);
    final title = ['MuzzIID', tr(ref, 'Register'), tr(ref, 'Settings')][tab];
    return Scaffold(
        appBar: AppBar(title: tab == 0 ? const LandingBrand() : Text(title)),
        bottomNavigationBar: NavigationBar(
            selectedIndex: tab,
            onDestinationSelected: (i) {
              ScaffoldMessenger.of(context).hideCurrentSnackBar();
              ref.read(shellTabProvider.notifier).state = i;
            },
            destinations: [
              NavigationDestination(
                  icon: const Icon(Icons.dashboard_outlined),
                  label: tr(ref, 'Field')),
              NavigationDestination(
                  icon: const Icon(Icons.list_alt), label: tr(ref, 'Register')),
              NavigationDestination(
                  icon: const Icon(Icons.settings_outlined),
                  label: tr(ref, 'Settings')),
            ]),
        body: records.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, stack) => pageBody([
                  Text(tr(ref, 'Unable to read local records.')),
                  TextButton(
                      onPressed: () => ref.invalidate(registerProvider),
                      child: Text(tr(ref, 'Try again')))
                ]),
            data: (animals) => switch (tab) {
                  0 => FieldHome(animals: animals),
                  1 => RegisterView(animals: animals),
                  _ => pageBody([
                      const ModelStatusCard(),
                      const SavedOfflineCard(),
                      const CaptureSettings(),
                      section(context, tr(ref, 'Language')),
                      const SizedBox(height: 8),
                      SegmentedButton<String>(
                          segments: const [
                            ButtonSegment(value: 'en', label: Text('English')),
                            ButtonSegment(value: 'lg', label: Text('Luganda'))
                          ],
                          selected: {
                            ref.watch(languageProvider)
                          },
                          onSelectionChanged: (s) => ref
                              .read(languageProvider.notifier)
                              .select(s.first)),
                    ]),
                }));
  }
}
