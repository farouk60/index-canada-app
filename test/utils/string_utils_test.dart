import 'package:flutter_test/flutter_test.dart';
import 'package:index_canada/utils/string_utils.dart';

void main() {
  group('normalizeForSorting', () {
    test('normalise la casse, les accents et les ligatures', () {
      expect(
        normalizeForSorting('Éléphant Æsir, cœur Ñandú'),
        'elephant aesir, coeur nandu',
      );
    });

    test('préserve les caractères qui ne servent pas au tri accentué', () {
      expect(normalizeForSorting('Montréal-Est #2'), 'montreal-est #2');
    });
  });

  group('normalizeForSearch', () {
    test('retire la ponctuation et compacte les espaces', () {
      expect(
        normalizeForSearch('  Café-du coin!!! \n Montréal  '),
        'cafe du coin montreal',
      );
    });

    test('retourne une chaîne vide pour une saisie sans termes', () {
      expect(normalizeForSearch(' -- !!! '), isEmpty);
    });
  });

  group('tokenizeWithoutStopWords', () {
    test('ignore les mots vides français et anglais', () {
      final normalized = normalizeForSearch(
        'Le café de Montréal and the bakery',
      );

      expect(tokenizeWithoutStopWords(normalized), [
        'cafe',
        'montreal',
        'bakery',
      ]);
    });

    test('accepte un ensemble personnalisé de mots vides', () {
      expect(
        tokenizeWithoutStopWords(
          'service montreal rapide',
          stopWords: const {'service', 'rapide'},
        ),
        ['montreal'],
      );
    });

    test('gère une chaîne vide', () {
      expect(tokenizeWithoutStopWords(''), isEmpty);
    });
  });

  group('levenshteinDistance', () {
    test('calcule les insertions, suppressions et substitutions', () {
      expect(levenshteinDistance('chat', 'chats'), 1);
      expect(levenshteinDistance('chats', 'chat'), 1);
      expect(levenshteinDistance('chat', 'chut'), 1);
      expect(levenshteinDistance('kitten', 'sitting', maxDistance: 3), 3);
    });

    test(
      'utilise la sortie rapide lorsque les longueurs sont trop éloignées',
      () {
        expect(levenshteinDistance('a', 'abcdefgh', maxDistance: 2), 3);
      },
    );

    test('retourne zéro pour deux valeurs identiques', () {
      expect(levenshteinDistance('plombier', 'plombier'), 0);
    });
  });

  group('fuzzyTokenMatch', () {
    test('accepte une sous-chaîne dans les deux directions', () {
      expect(fuzzyTokenMatch('comptable', 'compt'), isTrue);
      expect(fuzzyTokenMatch('dent', 'dentiste'), isTrue);
    });

    test('tolère une faute de frappe courte', () {
      expect(fuzzyTokenMatch('plombier', 'plonbier'), isTrue);
    });

    test('rejette les termes sans proximité suffisante', () {
      expect(fuzzyTokenMatch('avocat', 'plombier'), isFalse);
      expect(fuzzyTokenMatch('', 'avocat'), isFalse);
    });
  });
}
