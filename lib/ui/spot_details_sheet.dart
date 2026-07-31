import 'package:flutter/material.dart';

import '../data/parking_spot.dart';
import '../services/navigation_launcher.dart';
import 'spot_marker.dart';

/// Kohteen tiedot ja navigointipainike.
class SpotDetailsSheet extends StatelessWidget {
  const SpotDetailsSheet({super.key, required this.spot});

  final ParkingSpot spot;

  static Future<void> show(BuildContext context, ParkingSpot spot) {
    return showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => SpotDetailsSheet(spot: spot),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isApproximate = spot.precision == SpotPrecision.area;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(spot.title, style: theme.textTheme.titleLarge),
            const SizedBox(height: 12),

            // Tarkkuus näytetään ensimmäisenä, koska se määrittää miten
            // muuhun tietoon pitää suhtautua.
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isApproximate
                    ? theme.colorScheme.secondaryContainer
                    : theme.colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    isApproximate ? Icons.help_outline : Icons.place_outlined,
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      SpotVisuals.explain(spot.precision),
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Osoite näytetään omana rivinään vain, jos se ei ole jo
            // otsikkona — nimettömillä kohteilla otsikko on osoite.
            if (spot.address != null && spot.address != spot.title)
              _DetailRow(Icons.home_outlined, spot.address!),
            if (spot.capacity != null)
              _DetailRow(
                Icons.local_parking_outlined,
                spot.capacity == 1
                    ? '1 invapaikka'
                    : '${spot.capacity} invapaikkaa',
              ),
            if (spot.fee != null)
              _DetailRow(
                spot.fee! ? Icons.euro_outlined : Icons.money_off_outlined,
                spot.fee! ? 'Maksullinen' : 'Maksuton',
              ),
            if (spot.maxDurationH != null)
              _DetailRow(
                Icons.schedule_outlined,
                'Enintään ${_formatHours(spot.maxDurationH!)}',
              ),
            if (spot.restrictions != null)
              _DetailRow(Icons.info_outline, spot.restrictions!),

            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () async {
                final ok = await NavigationLauncher.navigateTo(spot);
                if (!ok && context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Navigointisovellusta ei voitu avata.'),
                    ),
                  );
                }
              },
              icon: const Icon(Icons.directions),
              label: const Text('Navigoi tähän'),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
              ),
            ),

            const SizedBox(height: 12),
            Text(
              'Lähde: ${kSourceNames[spot.source] ?? spot.source}'
              '${spot.updated != null ? ' · päivitetty ${spot.updated}' : ''}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Tietoja ei ole varmistettu maastossa. Noudata aina paikan päällä '
              'olevia liikennemerkkejä.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _formatHours(double hours) {
    if (hours < 1) return '${(hours * 60).round()} min';
    if (hours == hours.roundToDouble()) return '${hours.round()} h';
    return '$hours h';
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow(this.icon, this.text);

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: Theme.of(context).colorScheme.onSurfaceVariant),
          const SizedBox(width: 12),
          Expanded(child: Text(text, style: Theme.of(context).textTheme.bodyMedium)),
        ],
      ),
    );
  }
}
