import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../config.dart';

/// Avaimen testauksen tulos.
enum MapKeyStatus { ok, unauthorized, networkError }

class MapKeyCheck {
  const MapKeyCheck(this.status, [this.detail]);

  final MapKeyStatus status;
  final String? detail;

  bool get isOk => status == MapKeyStatus.ok;

  String get message => switch (status) {
        MapKeyStatus.ok => 'Avain toimii.',
        MapKeyStatus.unauthorized =>
          'Palvelin hylkäsi avaimen${detail == null ? '' : ' ($detail)'}. '
              'Tarkista että kopioit sen kokonaan.',
        MapKeyStatus.networkError =>
          'Avainta ei voitu tarkistaa: ${detail ?? 'verkkovirhe'}. '
              'Avain tallennettiin silti.',
      };
}

/// Säilöö MML:n API-avaimen ja kertoo kartalle, milloin se muuttuu.
///
/// Avain on käyttäjän omaa dataa eikä sitä lähetetä minnekään muualle kuin
/// Maanmittauslaitoksen tiilipalveluun.
class MapKeyStore extends ChangeNotifier {
  MapKeyStore._(this._key);

  static const String _prefsKey = 'mml_api_key';

  String _key;

  String get key => _key;
  bool get hasKey => _key.isNotEmpty;

  static Future<MapKeyStore> load() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_prefsKey);
    return MapKeyStore._(stored ?? Config.defaultMmlApiKey);
  }

  Future<void> save(String value) async {
    final trimmed = value.trim();
    if (trimmed == _key) return;
    _key = trimmed;
    final prefs = await SharedPreferences.getInstance();
    if (trimmed.isEmpty) {
      await prefs.remove(_prefsKey);
    } else {
      await prefs.setString(_prefsKey, trimmed);
    }
    notifyListeners();
  }

  /// Hae yksi tiili ja katso, kelpaako avain. Verkkovirhettä ei tulkita
  /// vääräksi avaimeksi — käyttäjä voi olla kentän ulkopuolella.
  static Future<MapKeyCheck> verify(String value) async {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return const MapKeyCheck(MapKeyStatus.unauthorized, 'tyhjä avain');
    }
    try {
      final response = await http
          .get(Uri.parse(Config.mmlProbeTileUrl(trimmed)))
          .timeout(const Duration(seconds: 15));
      if (response.statusCode == 200) {
        final type = response.headers['content-type'] ?? '';
        if (type.startsWith('image/')) return const MapKeyCheck(MapKeyStatus.ok);
        return MapKeyCheck(MapKeyStatus.unauthorized, 'palvelin palautti $type');
      }
      if (response.statusCode == 401 || response.statusCode == 403) {
        return MapKeyCheck(MapKeyStatus.unauthorized, 'HTTP ${response.statusCode}');
      }
      return MapKeyCheck(MapKeyStatus.networkError, 'HTTP ${response.statusCode}');
    } catch (error) {
      return MapKeyCheck(MapKeyStatus.networkError, error.toString());
    }
  }
}
