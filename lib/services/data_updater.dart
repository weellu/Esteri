import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../config.dart';
import '../data/spot_data_source.dart';
import '../data/spot_database.dart';

enum UpdateStatus {
  /// Levyllä oleva aineisto on jo yhtä tuore tai tuoreempi.
  upToDate,

  /// Uusi aineisto ladattiin ja otettiin käyttöön.
  updated,

  /// Päivitystä ei voitu hakea (verkko alhaalla tai palvelin ei vastaa).
  unavailable,

  /// Julkaistu aineisto hylättiin tarkistuksissa. Vanha jää voimaan.
  rejected,
}

class UpdateResult {
  const UpdateResult(this.status, {this.message, this.version, this.count});

  final UpdateStatus status;
  final String? message;
  final String? version;
  final int? count;

  bool get installedSomething => status == UpdateStatus.updated;
}

/// Manifestin arviointi: ladataanko uusi aineisto vai ei.
///
/// Erillään verkosta ja levystä, jotta päätössäännöt ovat testattavissa
/// sellaisenaan — ne ratkaisevat, milloin toimiva aineisto saa korvautua.
class ManifestEvaluation {
  const ManifestEvaluation.download({required this.version, required this.count})
      : status = null,
        message = null;

  const ManifestEvaluation.stop(
    UpdateStatus this.status, {
    this.message,
    this.version,
    this.count,
  });

  /// Null tarkoittaa, että aineisto ladataan.
  final UpdateStatus? status;
  final String? message;
  final String? version;
  final int? count;

  bool get shouldDownload => status == null;
}

/// Päätä manifestin perusteella, ladataanko uusi aineisto.
ManifestEvaluation evaluateManifest(Object? decoded, String? installedVersion) {
  if (decoded is! Map) {
    return const ManifestEvaluation.stop(
      UpdateStatus.rejected,
      message: 'Manifestia ei ymmärretty.',
    );
  }

  final version = decoded['generated_at'];
  final schema = decoded['schema_version'];
  final count = decoded['count'];
  if (version is! String || schema is! int || count is! int) {
    return const ManifestEvaluation.stop(
      UpdateStatus.rejected,
      message: 'Manifestista puuttuu tietoja.',
    );
  }

  if (schema != Config.supportedSchemaVersion) {
    // Uudempi skeema voi tarkoittaa muuttuneita kenttiä, joita tämä
    // sovellusversio ei osaa lukea oikein.
    return ManifestEvaluation.stop(
      UpdateStatus.rejected,
      message: 'Julkaistu aineisto vaatii uudemman sovellusversion.',
      version: version,
    );
  }

  if (count < Config.minAcceptableSpotCount) {
    return ManifestEvaluation.stop(
      UpdateStatus.rejected,
      message: 'Julkaistussa aineistossa on vain $count kohdetta.',
      version: version,
    );
  }

  // Versiot ovat ISO-8601-aikaleimoja UTC:ssä, joten merkkijonovertailu
  // vastaa aikajärjestystä.
  if (installedVersion != null && installedVersion.compareTo(version) >= 0) {
    return ManifestEvaluation.stop(UpdateStatus.upToDate, version: installedVersion);
  }

  return ManifestEvaluation.download(version: version, count: count);
}

/// Tarkista ladattu tiedosto ennen kuin se korvaa toimivan aineiston.
/// Palauttaa virheen kuvauksen, tai null jos tiedosto kelpaa.
Future<String?> validateDatabaseFile(File file, {required int expectedCount}) async {
  Database? db;
  try {
    db = await openDatabase(file.path, readOnly: true);
    final meta = {
      for (final row in await db.query('meta'))
        row['key'] as String: row['value'] as String,
    };
    if (meta['schema_version'] != '${Config.supportedSchemaVersion}') {
      return 'Ladatun aineiston skeemaversio ei täsmää.';
    }
    // Rivit lasketaan tiedostosta eikä luoteta metatietoon: katkennut lataus
    // voi jättää metan paikalleen mutta rivit vajaiksi.
    final result = await db.rawQuery('SELECT COUNT(*) AS n FROM spots');
    final actual = result.first['n'] as int;
    if (actual != expectedCount) {
      return 'Ladatussa aineistossa $actual kohdetta, odotettiin $expectedCount.';
    }
    if (actual < Config.minAcceptableSpotCount) {
      return 'Ladatussa aineistossa vain $actual kohdetta.';
    }
    return null;
  } catch (error) {
    return 'Ladattu tiedosto ei ole kelvollinen tietokanta.';
  } finally {
    await db?.close();
  }
}

/// Aineiston päivitys julkaistusta tiedostosta.
///
/// Pipeline ajetaan viikoittain ja tulos julkaistaan staattisena tiedostona,
/// joten datapäivitys ei vaadi sovelluspäivitystä. Tämä on Flutterissa
/// erityisen arvokasta, koska OTA-päivityksiä ei ole.
///
/// Päivitys on tarkoituksellisen varovainen: **vanha aineisto korvataan vain
/// jos uusi läpäisee kaikki tarkistukset.** Käyttäjä ei saa koskaan jäädä
/// huonompaan tilanteeseen kuin ennen päivitystä, koska sovellusta käytetään
/// liikkeellä eikä epäonnistumista voi korjata paikan päällä.
class DataUpdater {
  DataUpdater({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  static const Duration _timeout = Duration(seconds: 30);

  Future<UpdateResult> update(SpotDataSource source) async {
    final Object? manifest;
    try {
      final response =
          await _client.get(Uri.parse(Config.dataManifestUrl)).timeout(_timeout);
      if (response.statusCode != 200) {
        return UpdateResult(
          UpdateStatus.unavailable,
          message: 'Palvelin vastasi virheellä ${response.statusCode}.',
        );
      }
      manifest = jsonDecode(utf8.decode(response.bodyBytes, allowMalformed: true));
    } catch (error) {
      return const UpdateResult(
        UpdateStatus.unavailable,
        message: 'Päivitystä ei voitu hakea: verkkovirhe.',
      );
    }

    final evaluation =
        evaluateManifest(manifest, await SpotDatabase.installedVersion());
    if (!evaluation.shouldDownload) {
      return UpdateResult(
        evaluation.status!,
        message: evaluation.message,
        version: evaluation.version,
      );
    }

    final version = evaluation.version!;
    final count = evaluation.count!;

    final File temp;
    try {
      final target = await SpotDatabase.localPath();
      temp = File(p.join(p.dirname(target), 'invapaikat.download'));
      final response =
          await _client.get(Uri.parse(Config.dataSqliteUrl)).timeout(_timeout);
      if (response.statusCode != 200) {
        return UpdateResult(
          UpdateStatus.unavailable,
          message: 'Aineiston lataus epäonnistui (HTTP ${response.statusCode}).',
        );
      }
      await temp.writeAsBytes(response.bodyBytes, flush: true);
    } catch (error) {
      return const UpdateResult(
        UpdateStatus.unavailable,
        message: 'Aineiston lataus epäonnistui.',
      );
    }

    final problem = await validateDatabaseFile(temp, expectedCount: count);
    if (problem != null) {
      await _discard(temp);
      return UpdateResult(UpdateStatus.rejected, message: problem, version: version);
    }

    try {
      await source.installDownloaded(temp, version);
    } catch (error) {
      await _discard(temp);
      return const UpdateResult(
        UpdateStatus.rejected,
        message: 'Aineiston käyttöönotto epäonnistui. Vanha aineisto jäi voimaan.',
      );
    }

    debugPrint('Invapaikka-aineisto päivitetty verkosta: $version ($count kohdetta)');
    return UpdateResult(UpdateStatus.updated, version: version, count: count);
  }

  Future<void> _discard(File file) async {
    try {
      if (file.existsSync()) await file.delete();
    } catch (_) {
      // Väliaikaistiedoston siivous ei saa kaataa päivitystä.
    }
  }

  void dispose() => _client.close();
}
