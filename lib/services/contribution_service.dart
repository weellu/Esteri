import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../config.dart';

/// Mitä käyttäjä kertoo maastosta.
enum SubmissionKind {
  /// Uusi invapaikka, jota aineistossa ei ole.
  newSpot('new'),

  /// Aineistossa oleva paikka on olemassa.
  present('present'),

  /// Aineistossa olevaa paikkaa ei löydy.
  missing('missing'),

  /// Paikka on olemassa, mutta ruutu on muualla kuin kartan piste.
  ///
  /// Yleisin tapaus on pysäköintialueen keskipiste, joka voi olla satoja
  /// metrejä siitä ruudusta, jota autoilija etsii. Lähettäjän sijainti on
  /// tällöin väite kohteen sijainnista eikä vain todiste läsnäolosta.
  relocate('relocate');

  const SubmissionKind(this.wire);

  final String wire;
}

/// Yksi lähetys. Sijainti tulee kutsujalta, ei tästä palvelusta: käyttöliittymä
/// tarvitsee mittauksen joka tapauksessa näyttääkseen tarkkuuden ja
/// käsitelläkseen puuttuvan luvan, eikä samaa mittausta kannata tehdä kahdesti.
@immutable
class Submission {
  const Submission({
    required this.kind,
    required this.lat,
    required this.lon,
    this.accuracyM,
    this.targetUid,
    this.note,
    this.capacity,
  });

  final SubmissionKind kind;
  final double lat;
  final double lon;
  final double? accuracyM;
  final String? targetUid;
  final String? note;

  /// Invaruutujen määrä ilmoituskohdassa, tai null jos käyttäjä ei kertonut.
  /// Kelpaa uudelle paikalle ja vahvistukselle — jälkimmäisellä se on korjaus,
  /// kun määrä on muuttunut tai laskettu väärin.
  final int? capacity;

  Map<String, Object?> toJson(String device) => {
    'kind': kind.wire,
    'lat': lat,
    'lon': lon,
    if (accuracyM != null) 'accuracy_m': accuracyM,
    if (targetUid != null) 'target_uid': targetUid,
    if (note != null && note!.isNotEmpty) 'note': note,
    if (capacity != null) 'capacity': capacity,
    'device': device,
    'app_version': Config.appVersion,
  };

  static Submission? fromJson(Map<String, Object?> json) {
    SubmissionKind? kind;
    for (final candidate in SubmissionKind.values) {
      if (candidate.wire == json['kind']) kind = candidate;
    }
    final lat = json['lat'];
    final lon = json['lon'];
    if (kind == null || lat is! num || lon is! num) return null;
    return Submission(
      kind: kind,
      lat: lat.toDouble(),
      lon: lon.toDouble(),
      accuracyM: (json['accuracy_m'] as num?)?.toDouble(),
      targetUid: json['target_uid'] as String?,
      note: json['note'] as String?,
      capacity: (json['capacity'] as num?)?.toInt(),
    );
  }
}

/// Mitä lähetykselle tapahtui.
enum SubmissionOutcome {
  /// Palvelin otti vastaan.
  sent,

  /// Palvelin tunnisti saman laitteen aiemman ilmoituksen samasta kohdasta.
  duplicate,

  /// Verkkoa ei ollut. Lähetys jäi laitteen jonoon ja yritetään uudelleen.
  queued,

  /// Vuorokauden lähetysraja tuli täyteen.
  tooMany,

  /// Palvelin hylkäsi lähetyksen pysyvästi — uudelleenyritys ei auta.
  rejected,

  /// Taustapalvelua ei ole määritetty tähän käännökseen.
  unavailable,
}

/// Käyttäjien ilmoitusten lähetys.
///
/// **Lähetys ei ole osa lukupolkua.** Kartta, haku ja navigointi toimivat
/// kokonaan ilman tätä palvelua, koska aineisto tulee staattisena tiedostona.
/// Siksi epäonnistunut lähetys ei ole virhetila vaan jonoon jäänyt viesti:
/// sovellusta käytetään liikkeellä, ja kellarissa tai katvealueella verkon
/// puute on normaali olotila eikä sen pidä näyttää rikkoutumiselta.
class ContributionService {
  ContributionService._(
    this._prefs,
    this._client,
    this._baseUrl,
    this._deviceId,
    this._acted,
  );

  static const String _deviceKey = 'contribution_device_id';
  static const String _pendingKey = 'contribution_pending';
  static const String _actedKey = 'contribution_acted_uids';

  /// Yläraja laitteen jonolle. Jos verkkoa ei ole ollut pitkään, vanhimmat
  /// ilmoitukset ovat myös vanhentuneinta tietoa — ja rajaton jono kasvaisi
  /// hiljaa asetustiedostossa.
  static const int maxPending = 50;

  static const Duration _timeout = Duration(seconds: 15);

  final SharedPreferences _prefs;
  final http.Client _client;

  /// Taustapalvelun osoite. Annettavissa erikseen, jotta lähetyslogiikan voi
  /// testata ilman käännösaikaista vakiota — samasta syystä kuin karttanäkymä
  /// riippuu `SpotRepository`sta eikä suoraan SQLitestä.
  final String _baseUrl;

  final String _deviceId;

  /// Kohteet, joista tämä laite on jo lähettänyt ilmoituksen. Käyttöliittymä
  /// näyttää ne kuitattuina, jottei käyttäjä painele samaa nappia turhaan.
  final Set<String> _acted;

  static Future<ContributionService> load({
    http.Client? client,
    String? baseUrl,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    var device = prefs.getString(_deviceKey);
    if (device == null) {
      device = newDeviceId();
      await prefs.setString(_deviceKey, device);
    }
    return ContributionService._(
      prefs,
      client ?? http.Client(),
      baseUrl ?? Config.contributionApiBase,
      device,
      (prefs.getStringList(_actedKey) ?? const []).toSet(),
    );
  }

  /// Onko lähetys käytettävissä. Ilman taustapalvelun osoitetta ei ole:
  /// nappi, joka lähettää olemattomaan osoitteeseen, on huonompi kuin ei
  /// nappia lainkaan.
  bool get enabled => _baseUrl.isNotEmpty;

  /// Satunnainen UUID v4.
  ///
  /// Ei laitteen omaa tunnusta: se olisi henkilötieto ja seuraisi käyttäjää
  /// sovelluksesta toiseen. Tämä tunniste syntyy ensimmäisellä käynnistyksellä,
  /// katoaa sovelluksen poistossa eikä kerro laitteesta mitään. Sitä käytetään
  /// vain saman laitteen toistojen karsintaan, jottei yksi käyttäjä voi
  /// vahvistaa samaa paikkaa kymmentä kertaa.
  @visibleForTesting
  static String newDeviceId() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40; // versio 4
    bytes[8] = (bytes[8] & 0x3f) | 0x80; // variantti
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }

  String get deviceId => _deviceId;

  bool hasActedOn(String uid) => _acted.contains(uid);

  int get pendingCount =>
      (_prefs.getStringList(_pendingKey) ?? const []).length;

  Future<SubmissionOutcome> submit(Submission submission) async {
    if (!enabled) return SubmissionOutcome.unavailable;

    final outcome = await _post(submission);

    if (outcome == SubmissionOutcome.queued) {
      await _enqueue(submission);
    }
    if (outcome != SubmissionOutcome.rejected &&
        outcome != SubmissionOutcome.unavailable) {
      await _markActed(submission.targetUid);
    }
    return outcome;
  }

  Future<SubmissionOutcome> _post(Submission submission) async {
    try {
      final response = await _client
          .post(
            Uri.parse('$_baseUrl/v1/submissions'),
            headers: const {'content-type': 'application/json'},
            body: jsonEncode(submission.toJson(_deviceId)),
          )
          .timeout(_timeout);

      if (response.statusCode == 202) {
        final decoded = jsonDecode(utf8.decode(response.bodyBytes));
        final status = decoded is Map ? decoded['status'] : null;
        return status == 'duplicate'
            ? SubmissionOutcome.duplicate
            : SubmissionOutcome.sent;
      }
      if (response.statusCode == 429) return SubmissionOutcome.tooMany;
      if (response.statusCode >= 400 && response.statusCode < 500) {
        // Muotovirhe ei korjaannu odottamalla, joten sitä ei jonoteta.
        debugPrint(
          'Lähetys hylättiin: HTTP ${response.statusCode} ${response.body}',
        );
        return SubmissionOutcome.rejected;
      }
      return SubmissionOutcome.queued; // 5xx — palvelimen ohimenevä vika
    } catch (error) {
      debugPrint('Lähetys ei mennyt läpi: $error');
      return SubmissionOutcome.queued;
    }
  }

  Future<void> _enqueue(Submission submission) async {
    final pending = _prefs.getStringList(_pendingKey) ?? <String>[];
    pending.add(jsonEncode(submission.toJson(_deviceId)));
    if (pending.length > maxPending) {
      pending.removeRange(0, pending.length - maxPending);
    }
    await _prefs.setStringList(_pendingKey, pending);
  }

  Future<void> _markActed(String? uid) async {
    if (uid == null || !_acted.add(uid)) return;
    await _prefs.setStringList(_actedKey, _acted.toList());
  }

  /// Yritä lähettää jonoon jääneet ilmoitukset.
  ///
  /// Kutsutaan käynnistyksessä ja onnistuneen lähetyksen jälkeen. Palauttaa
  /// läpi menneiden määrän. Jonoon jäävät ne, joita ei vieläkään saatu perille;
  /// pysyvästi hylätyt poistetaan, jotta jono ei jumitu yhteen kelvottomaan
  /// ilmoitukseen.
  Future<int> flushPending() async {
    if (!enabled) return 0;

    final pending = _prefs.getStringList(_pendingKey) ?? const <String>[];
    if (pending.isEmpty) return 0;

    final remaining = <String>[];
    var sent = 0;
    var stop = false;

    for (final raw in pending) {
      if (stop) {
        remaining.add(raw);
        continue;
      }

      final decoded = jsonDecode(raw);
      final submission = decoded is Map<String, Object?>
          ? Submission.fromJson(decoded)
          : null;
      if (submission == null) continue; // kelvoton rivi: pudotetaan

      final outcome = await _post(submission);
      switch (outcome) {
        case SubmissionOutcome.sent:
        case SubmissionOutcome.duplicate:
          sent++;
        case SubmissionOutcome.rejected:
          break; // ei yritetä uudelleen
        case SubmissionOutcome.queued:
        case SubmissionOutcome.tooMany:
        case SubmissionOutcome.unavailable:
          // Verkko on poikki tai raja täynnä: loputkin epäonnistuisivat samoin.
          // Jatkaminen tuottaisi vain viisikymmentä turhaa pyyntöä ja
          // vastaavan viiveen käyttöliittymään.
          remaining.add(raw);
          stop = true;
      }
    }

    await _prefs.setStringList(_pendingKey, remaining);
    if (sent > 0) debugPrint('Jonosta lähetettiin $sent ilmoitusta.');
    return sent;
  }

  void dispose() => _client.close();
}
