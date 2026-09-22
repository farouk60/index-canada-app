import 'package:flutter_test/flutter_test.dart';
import 'package:index_canada/data/canadian_cities.dart';

void main() {
  group('kCanadianCities', () {
    test('contient les principaux marchés canadiens', () {
      expect(
        kCanadianCities,
        containsAll([
          'Montréal, QC',
          'Toronto, ON',
          'Vancouver, BC',
          'Calgary, AB',
          'Ottawa, ON',
          'Halifax, NS',
          'Winnipeg, MB',
        ]),
      );
    });

    test('ne contient aucun doublon exact', () {
      expect(kCanadianCities.toSet().length, kCanadianCities.length);
    });

    test('respecte le format ville et province ou territoire', () {
      final cityFormat = RegExp(r'^.+, [A-Z]{2}$');
      final malformed = kCanadianCities
          .where((city) => !cityFormat.hasMatch(city))
          .toList();

      expect(malformed, isEmpty);
    });

    test('offre une couverture nationale substantielle', () {
      expect(kCanadianCities.length, greaterThan(300));

      final regionCodes = kCanadianCities
          .map((city) => city.substring(city.length - 2))
          .toSet();
      expect(
        regionCodes,
        containsAll({
          'AB',
          'BC',
          'MB',
          'NB',
          'NL',
          'NS',
          'NT',
          'NU',
          'ON',
          'PE',
          'QC',
          'SK',
          'YT',
        }),
      );
    });
  });
}
