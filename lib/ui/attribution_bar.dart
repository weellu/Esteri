import 'package:flutter/material.dart';

import 'licenses_screen.dart';

/// Pysyvästi näkyvä attribuutio kartan alalaidassa.
///
/// OSM:n ODbL edellyttää, että tekijät ja lisenssi mainitaan selkeästi
/// selattavan kartan yhteydessä. Siksi tämä ei ole piilotettu valikon taakse
/// vaan on aina näkyvissä; koko lisenssiluettelo avautuu napauttamalla.
class AttributionBar extends StatelessWidget {
  const AttributionBar({super.key, required this.showMapTiles});

  /// Taustakartan attribuutio näytetään vain kun tiiliä oikeasti näytetään.
  final bool showMapTiles;

  static const double height = 22;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final parts = [
      if (showMapTiles) 'Kartta © Maanmittauslaitos',
      'Paikat © OpenStreetMap-tekijät (ODbL), Väylävirasto ja kunnat',
    ];

    return Semantics(
      button: true,
      label: 'Lisenssit ja lähteet',
      container: true,
      excludeSemantics: true,
      child: GestureDetector(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const LicensesScreen()),
        ),
        child: Container(
          height: height,
          alignment: Alignment.center,
          color: theme.colorScheme.surface.withValues(alpha: 0.82),
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Text(
            parts.join(' · '),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }
}
