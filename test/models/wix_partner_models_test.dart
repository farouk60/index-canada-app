import 'package:flutter_test/flutter_test.dart';
import 'package:index_canada/models/wix_partner_models.dart';

void main() {
  group('WixPartner', () {
    test('parse les données, sérialise et choisit la bannière', () {
      final partner = WixPartner.fromJson({
        '_id': 'partner-1',
        'title': 'Banque Exemple',
        'titleEn': 'Example Bank',
        'description': 'Description française',
        'descriptionEn': 'English description',
        'logo': 'https://cdn.example.com/logo.png',
        'banner': 'https://cdn.example.com/banner.png',
        'category': 'banque',
        'website': 'https://example.com',
        'isOfficial': true,
        'isFeatured': true,
        'displayOrder': 2,
        'isActive': true,
        'createdAt': '2026-01-15T12:00:00.000Z',
      });

      expect(partner.getTitleInLanguage('en'), 'Example Bank');
      expect(partner.getDescriptionInLanguage('fr'), 'Description française');
      expect(partner.shouldDisplay, isTrue);
      expect(partner.isActiveFeatured, isTrue);
      expect(partner.primaryImageUrl, 'https://cdn.example.com/banner.png');
      expect(partner.createdAt, DateTime.utc(2026, 1, 15, 12));

      final serialized = partner.toJson();
      expect(serialized['_id'], 'partner-1');
      expect(serialized['createdAt'], '2026-01-15T12:00:00.000Z');
    });

    test('applique les valeurs par défaut et les replis bilingues', () {
      final partner = WixPartner.fromJson({
        'id': 'partner-2',
        'title': 'Télécom Exemple',
        'description': 'Connexion mobile',
        'logo': 'https://cdn.example.com/logo.png',
      });

      expect(partner.titleEn, 'Télécom Exemple');
      expect(partner.descriptionEn, 'Connexion mobile');
      expect(partner.isOfficial, isTrue);
      expect(partner.isActive, isTrue);
      expect(partner.primaryImageUrl, partner.logo);
    });

    test('masque un partenaire inactif ou non officiel', () {
      final inactive = WixPartner.fromJson({
        'title': 'Inactif',
        'isActive': false,
      });
      final unofficial = WixPartner.fromJson({
        'title': 'Non officiel',
        'isOfficial': false,
      });

      expect(inactive.shouldDisplay, isFalse);
      expect(inactive.isActiveFeatured, isFalse);
      expect(unofficial.shouldDisplay, isFalse);
    });

    test('convertit vers le modèle Partner compatible', () {
      final partner = WixPartner.fromJson({
        '_id': 'partner-3',
        'title': 'Assurance Exemple',
        'titleEn': 'Example Insurance',
        'description': 'Protection',
        'descriptionEn': 'Coverage',
        'logo': 'logo.png',
        'category': 'assurance',
        'website': 'https://example.com',
        'displayOrder': 4,
      }).toPartner();

      expect(partner.id, 'partner-3');
      expect(partner.getNameInLanguage('en'), 'Example Insurance');
      expect(partner.priority, 4);
      expect(partner.offers, isEmpty);
    });

    test('normalise les variantes de types renvoyées par Wix', () {
      final partner = WixPartner.fromJson({
        '_id': 42,
        'title': 'Partenaire robuste',
        'titleEn': '  ',
        'description': 'Description de repli',
        'descriptionEn': '',
        'logo': {'src': 'wix:image://v1/logo/logo.png'},
        'banner': {'url': 'https://cdn.example.com/banner.png'},
        'isOfficial': 'true',
        'isFeatured': 1,
        'isActive': 'false',
        'displayOrder': '7',
      });

      expect(partner.id, '42');
      expect(partner.titleEn, 'Partenaire robuste');
      expect(partner.descriptionEn, 'Description de repli');
      expect(partner.logo, 'wix:image://v1/logo/logo.png');
      expect(partner.banner, 'https://cdn.example.com/banner.png');
      expect(partner.isOfficial, isTrue);
      expect(partner.isFeatured, isTrue);
      expect(partner.isActive, isFalse);
      expect(partner.displayOrder, 7);
    });
  });

  group('PartnerCategory', () {
    test('retrouve une catégorie connue et la traduit', () {
      final category = PartnerCategory.getCategoryById('emploi')!;

      expect(category.getNameInLanguage('fr'), 'Emploi');
      expect(category.getNameInLanguage('en'), 'Employment');
    });

    test('retourne null pour une catégorie inconnue', () {
      expect(PartnerCategory.getCategoryById('inconnue'), isNull);
    });

    test('normalise la casse et les espaces des identifiants', () {
      expect(PartnerCategory.getCategoryById(' EMPLOI ')?.id, 'emploi');
    });
  });
}
