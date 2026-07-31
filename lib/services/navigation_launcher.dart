import 'dart:io';

import 'package:url_launcher/url_launcher.dart';

import '../data/parking_spot.dart';

/// Avaa puhelimen oman karttasovelluksen reittiohjeisiin.
///
/// Tämä ei vaadi API-avainta millään alustalla — toisin kuin sovelluksen
/// sisäinen kartta.
class NavigationLauncher {
  const NavigationLauncher._();

  static Future<bool> navigateTo(ParkingSpot spot) async {
    final lat = spot.lat;
    final lon = spot.lon;
    final label = Uri.encodeComponent(spot.title);

    // iOS: maps.apple.com avaa Apple Mapsin (tai käyttäjän oletuskarttasovelluksen,
    // jos sellainen on asetettu). Android: geo:-URI antaa käyttäjän valita
    // asennetuista navigointisovelluksista.
    final candidates = Platform.isIOS
        ? [
            Uri.parse('https://maps.apple.com/?daddr=$lat,$lon&dirflg=d'),
            Uri.parse('https://www.google.com/maps/dir/?api=1&destination=$lat,$lon'),
          ]
        : [
            Uri.parse('geo:$lat,$lon?q=$lat,$lon($label)'),
            Uri.parse('https://www.google.com/maps/dir/?api=1&destination=$lat,$lon'),
          ];

    for (final uri in candidates) {
      if (await canLaunchUrl(uri)) {
        if (await launchUrl(uri, mode: LaunchMode.externalApplication)) {
          return true;
        }
      }
    }
    return false;
  }

  static Future<bool> openUrl(String url) async {
    final uri = Uri.parse(url);
    if (!await canLaunchUrl(uri)) return false;
    return launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}
