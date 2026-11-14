import 'package:flutter/material.dart';

/// Native rendering of the supplied fingerprint wordmark, without a backdrop.
class LandingBrand extends StatelessWidget {
  const LandingBrand({super.key});

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.fingerprint, color: Color(0xffac804c), size: 34),
          const SizedBox(width: 12),
          Text.rich(
            TextSpan(children: [
              TextSpan(
                text: 'Muzzl',
                style:
                    TextStyle(color: Theme.of(context).colorScheme.onSurface),
              ),
              const TextSpan(
                text: 'ID',
                style: TextStyle(color: Color(0xff916735)),
              ),
            ]),
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  letterSpacing: -.4,
                ),
          ),
        ],
      );
}
