import 'package:flutter_test/flutter_test.dart';
import 'package:esteri/data/parking_spot.dart';

void main() {
  group('SpotPrecision.parse', () {
    test('tunnistaa kaikki pipelinen tuottamat arvot', () {
      expect(SpotPrecision.parse('space'), SpotPrecision.space);
      expect(SpotPrecision.parse('sign'), SpotPrecision.sign);
      expect(SpotPrecision.parse('area'), SpotPrecision.area);
    });

    test('tuntematon arvo tulkitaan epätarkimmaksi, ei tarkimmaksi', () {
      // Jos aineistoon tulee uusi tarkkuustaso, on turvallisempaa luvata
      // käyttäjälle liian vähän kuin liikaa.
      expect(SpotPrecision.parse('jotain-uutta'), SpotPrecision.area);
    });
  });

  group('ParkingSpot.fromRow', () {
    Map<String, Object?> row({
      Object? fee,
      Object? capacity,
      Object? name,
      Object? address,
      String precision = 'space',
      // Vahvistussarakkeet annetaan erikseen, jotta perusrivi pysyy sellaisena
      // kuin se on vanhemmassa aineistotiedostossa: sarakkeita ei ole lainkaan.
      Map<String, Object?> extra = const {},
    }) =>
        {
          'id': 1,
          'uid': 'osm:node/1',
          'source': 'osm',
          'lat': 60.17,
          'lon': 24.94,
          'precision': precision,
          'capacity': capacity,
          'name': name,
          'address': address,
          'restrictions': null,
          'max_duration_h': null,
          'fee': fee,
          'updated': null,
          ...extra,
        };

    test('lukee kentät oikein', () {
      final spot = ParkingSpot.fromRow(row(capacity: 3, name: 'Tori'));
      expect(spot.uid, 'osm:node/1');
      expect(spot.capacity, 3);
      expect(spot.name, 'Tori');
      expect(spot.position.latitude, closeTo(60.17, 1e-9));
      expect(spot.position.longitude, closeTo(24.94, 1e-9));
    });

    test('fee=0 luetaan epätodeksi eikä puuttuvaksi', () {
      expect(ParkingSpot.fromRow(row(fee: 0)).fee, isFalse);
    });

    test('fee=1 luetaan todeksi', () {
      expect(ParkingSpot.fromRow(row(fee: 1)).fee, isTrue);
    });

    test('fee=null jää tuntemattomaksi', () {
      expect(ParkingSpot.fromRow(row()).fee, isNull);
    });

    group('title', () {
      test('käyttää nimeä ensisijaisesti', () {
        expect(ParkingSpot.fromRow(row(name: 'Stockmann', address: 'Aleksi 1')).title,
            'Stockmann');
      });

      test('putoaa osoitteeseen kun nimi puuttuu', () {
        expect(ParkingSpot.fromRow(row(address: 'Hämeenkatu 1')).title, 'Hämeenkatu 1');
      });

      test('tyhjä nimi ei kelpaa otsikoksi', () {
        expect(ParkingSpot.fromRow(row(name: '', address: 'Hämeenkatu 1')).title,
            'Hämeenkatu 1');
      });

      test('ilman nimeä ja osoitetta otsikko kertoo tarkkuuden', () {
        // Suurimmalla osalla aineistosta ei ole kumpaakaan, joten tämä on
        // se otsikko, jonka käyttäjä useimmiten näkee.
        expect(ParkingSpot.fromRow(row(precision: 'space')).title,
            'Invapysäköintipaikka');
        expect(ParkingSpot.fromRow(row(precision: 'sign')).title,
            'Invapysäköinnin liikennemerkki');
        expect(ParkingSpot.fromRow(row(precision: 'area')).title,
            'Pysäköintialue, jolla invapaikkoja');
      });

      test('käyttäjän ilmoittamaa ei kuvata pysäköintialueeksi', () {
        // Ilmoituksen sijainti on epätarkka, joten se tallentuu alueena —
        // mutta "Pysäköintialue, jolla invapaikkoja" olisi silti väärä lupaus
        // yhdestä ilmoitetusta ruudusta.
        final spot = ParkingSpot.fromRow(
          row(precision: 'area', extra: {'verification': 'reported'}),
        );
        expect(spot.title, 'Käyttäjän ilmoittama invapaikka');
      });
    });

    group('vahvistuskentät', () {
      test('puuttuvat sarakkeet luetaan avoimeksi aineistoksi', () {
        // Sarakkeet lisättiin skeemaversiota nostamatta, joten vanhassa
        // tiedostossa niitä ei ole lainkaan. Se ei saa kaataa lukemista
        // eikä merkitä kohteita vahvistamattomiksi.
        final spot = ParkingSpot.fromRow(row());
        expect(spot.verification, SpotVerification.curated);
        expect(spot.confirmations, 0);
        expect(spot.disputes, 0);
      });

      test('lukee vahvistusten ja kiistojen määrät', () {
        final spot = ParkingSpot.fromRow(row(extra: {
          'verification': 'confirmed',
          'confirmations': 3,
          'disputes': 1,
        }));
        expect(spot.verification, SpotVerification.confirmed);
        expect(spot.confirmations, 3);
        expect(spot.disputes, 1);
      });
    });
  });

  group('SpotVerification.parse', () {
    test('tyhjä arvo tarkoittaa avointa aineistoa', () {
      expect(SpotVerification.parse(null), SpotVerification.curated);
    });

    test('tunnistaa pipelinen tuottamat arvot', () {
      expect(SpotVerification.parse('reported'), SpotVerification.reported);
      expect(SpotVerification.parse('confirmed'), SpotVerification.confirmed);
    });

    test('tuntematon arvo tulkitaan vahvistamattomaksi, ei varmaksi', () {
      // Päinvastainen oletus lupaisi käyttäjälle varmuutta, jota tämä
      // sovellusversio ei osaa todentaa.
      expect(SpotVerification.parse('jotain-uutta'), SpotVerification.reported);
    });

    test('vain avoin aineisto ei ole käyttäjiltä peräisin', () {
      expect(SpotVerification.curated.isFromUsers, isFalse);
      expect(SpotVerification.reported.isFromUsers, isTrue);
      expect(SpotVerification.confirmed.isFromUsers, isTrue);
    });
  });

  group('lähdenimet', () {
    test('jokaisella pipelinen lähteellä on näyttönimi', () {
      for (final source in [
        'osm',
        'digiroad',
        'tampere',
        'turku',
        'helsinki',
        'users',
      ]) {
        expect(kSourceNames[source], isNotNull, reason: 'puuttuu: $source');
      }
    });
  });
}
