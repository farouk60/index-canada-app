import 'package:flutter_test/flutter_test.dart';
import 'package:index_canada/models/wix_offer_models.dart';

void main() {
  group('WixOffer', () {
    test('parse les champs Wix et les dates ISO', () {
      final offer = WixOffer.fromWixData({
        '_id': 'offer-1',
        'title': 'Offre de bienvenue',
        'titleEn': 'Welcome offer',
        'description': 'Description française',
        'descriptionEn': 'English description',
        'image': 'offer.png',
        'link': 'https://example.com/offer',
        'startDate': '2026-01-01T00:00:00.000Z',
        'endDate': '2099-12-31T23:59:59.000Z',
        'isExclusive': true,
        'isRecommended': true,
        'partnerId': 'partner-1',
      });

      expect(offer.id, 'offer-1');
      expect(offer.startDate, DateTime.utc(2026));
      expect(offer.endDate, DateTime.utc(2099, 12, 31, 23, 59, 59));
      expect(offer.isExclusive, isTrue);
      expect(offer.isRecommended, isTrue);
      expect(offer.isValidAt(DateTime.utc(2026, 6)), isTrue);
    });

    test('utilise le français si une traduction anglaise est absente', () {
      final offer = WixOffer.fromWixData({
        'title': 'Rabais',
        'description': 'Détails',
      });

      expect(offer.getTitleInLanguage('en'), 'Rabais');
      expect(offer.getDescriptionInLanguage('en'), 'Détails');
      expect(offer.getTitleInLanguage('fr'), 'Rabais');
    });

    test('signale une offre expirée', () {
      final offer = WixOffer.fromWixData({
        'endDate': '2000-01-01T00:00:00.000Z',
      });

      final reference = DateTime.utc(2026);
      expect(offer.isValidAt(reference), isFalse);
      expect(offer.isExpiringSoonAt(reference), isFalse);
    });

    test('détecte une expiration dans les sept prochains jours', () {
      final reference = DateTime.utc(2026, 6, 1, 12);
      final soon = WixOffer.fromWixData({
        'endDate': reference.add(const Duration(days: 3)).toIso8601String(),
      });
      final later = WixOffer.fromWixData({
        'endDate': reference.add(const Duration(days: 10)).toIso8601String(),
      });

      expect(soon.isExpiringSoonAt(reference), isTrue);
      expect(later.isExpiringSoonAt(reference), isFalse);
    });

    test('masque une offre avant sa date de début', () {
      final offer = WixOffer.fromWixData({
        'startDate': '2026-07-01T00:00:00.000Z',
        'endDate': '2026-08-01T00:00:00.000Z',
      });

      expect(offer.isValidAt(DateTime.utc(2026, 6, 30)), isFalse);
      expect(offer.isValidAt(DateTime.utc(2026, 7, 1)), isTrue);
    });

    test('normalise les médias, booléens et traductions venant de Wix', () {
      final offer = WixOffer.fromWixData({
        'title': 'Rabais',
        'description': 'Détails',
        'image': {'src': 'https://cdn.example.com/offer.jpg'},
        'isExclusive': '1',
        'isRecommended': 1,
      });

      expect(offer.titleEn, 'Rabais');
      expect(offer.descriptionEn, 'Détails');
      expect(offer.image, 'https://cdn.example.com/offer.jpg');
      expect(offer.isExclusive, isTrue);
      expect(offer.isRecommended, isTrue);
    });

    test('ignore une date invalide sans faire échouer le parsing', () {
      final offer = WixOffer.fromWixData({
        'startDate': 'date-invalide',
        'endDate': 'date-invalide',
      });

      expect(offer.startDate, isNull);
      expect(offer.endDate, isNull);
      expect(offer.isValid, isTrue);
    });
  });
}
