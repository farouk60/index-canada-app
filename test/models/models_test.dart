import 'package:flutter_test/flutter_test.dart';
import 'package:index_canada/models.dart';

void main() {
  group('SousCategorie', () {
    test('extrait les images Wix et applique les traductions', () {
      final category = SousCategorie.fromJson({
        '_id': 'cat-1',
        'title': 'Comptables',
        'titleEn': 'Accountants',
        'image': {
          'media': {'url': 'https://cdn.example.com/fr.jpg'},
        },
        'imageEn': {'src': 'https://cdn.example.com/en.jpg'},
      });

      expect(category.id, 'cat-1');
      expect(category.image, 'https://cdn.example.com/fr.jpg');
      expect(category.getTitleInLanguage('en'), 'Accountants');
      expect(category.getTitleInLanguage('fr'), 'Comptables');
      expect(
        category.getImageInLanguage('en'),
        'https://cdn.example.com/en.jpg',
      );
    });

    test(
      'utilise les valeurs françaises lorsque les champs anglais manquent',
      () {
        final category = SousCategorie.fromJson({
          'title': 'Avocats',
          'imageUrl': 'https://cdn.example.com/avocats.jpg',
        });

        expect(category.titleEn, 'Avocats');
        expect(category.getTitleInLanguage('en'), 'Avocats');
        expect(category.getImageInLanguage('en'), category.image);
      },
    );
  });

  group('Professionnel', () {
    test('normalise les principaux formats de données Wix', () {
      final professional = Professionnel.fromJson({
        '_id': 'pro-1',
        'title': 'Cabinet Exemple',
        'subtitle': 'Fiscalité',
        'ville': 'Montréal',
        'address': {
          'streetAddress': {'formattedAddressLine': '10 rue Exemple'},
        },
        'numroDeTlphone': '5145550101',
        'image': {'src': 'https://cdn.example.com/profile.jpg'},
        'sousCatgorie': {'_id': 'cat-1'},
        'plan': 'Premium',
        'averageRating': 4,
        'reviewCount': 12,
        'couponTitle': '<strong>20&nbsp;%</strong> &amp; plus',
        'couponTitleEn': '20% off',
        'couponCode': 2026,
        'couponExpirationDate': '2030-05-01T00:00:00.000Z',
        'galerieImage1': 'https://cdn.example.com/gallery-1.jpg',
        'galerieImage2': 'https://cdn.example.com/gallery-2.jpg',
        'mediagallery': ['https://cdn.example.com/legacy.jpg'],
        'subscriptionExpiryDate': {'\$date': 1893456000000},
      });

      expect(professional.id, 'pro-1');
      expect(professional.address, '10 rue Exemple');
      expect(professional.image, 'https://cdn.example.com/profile.jpg');
      expect(professional.sousCategorie, 'cat-1');
      expect(professional.averageRating, 4.0);
      expect(professional.couponTitle, '20 % & plus');
      expect(professional.couponCode, '2026');
      expect(professional.couponExpirationDate, DateTime.utc(2030, 5));
      expect(professional.subscriptionExpiryDate, isNotNull);
      expect(professional.isFeatured, isTrue);

      // Les champs individuels ont priorité sur l'ancienne mediagallery.
      expect(professional.getAllGalleryImages(), [
        'https://cdn.example.com/gallery-1.jpg',
        'https://cdn.example.com/gallery-2.jpg',
      ]);
    });

    test("déduplique et filtre les images de l'ancienne galerie", () {
      final professional = Professionnel.fromJson({
        '_id': 'pro-2',
        'title': 'Clinique Exemple',
        'mediagallery': [
          'https://cdn.example.com/one.jpg',
          <String, dynamic>{'src': 'https://cdn.example.com/one.jpg'},
          <String, dynamic>{'url': 'https://cdn.example.com/two.jpg'},
          <String, dynamic>{'src': ''},
        ],
      });

      expect(professional.getAllGalleryImages(), [
        'https://cdn.example.com/one.jpg',
        'https://cdn.example.com/two.jpg',
      ]);
      expect(professional.getGalleryImageCount(), 2);
      expect(professional.hasGalleryImages(), isTrue);
      expect(professional.isFeatured, isFalse);
    });

    test(
      'normalise une galerie Wix composée de Maps sans conversion forcée',
      () {
        final professional = Professionnel.fromJson({
          '_id': 'pro-wix-gallery',
          'title': 'Galerie Wix',
          'gallery': [
            <String, dynamic>{'src': 'wix:image://v1/photo-id/photo.jpg'},
            <String, dynamic>{'fileUrl': 'https://cdn.example.com/second.jpg'},
          ],
        });

        expect(professional.getAllGalleryImages(), [
          'wix:image://v1/photo-id/photo.jpg',
          'https://cdn.example.com/second.jpg',
        ]);
      },
    );

    test('applique le repli bilingue des coupons', () {
      final professional = Professionnel.fromJson({
        '_id': 'pro-3',
        'title': 'Service Exemple',
        'couponTitleEn': 'Welcome offer',
        'couponDescriptionEn': 'For newcomers',
      });

      expect(professional.getCouponTitleInLanguage('fr'), 'Welcome offer');
      expect(
        professional.getCouponDescriptionInLanguage('fr'),
        'For newcomers',
      );
    });
  });

  group('Review', () {
    test('convertit une note textuelle en entier', () {
      final review = Review.fromJson({
        '_id': 'review-1',
        'professionalId': 'pro-1',
        'auteurNom': 'Camille',
        'rating': '5',
        'message': 'Excellent service',
        'title': 'Recommandé',
      });

      expect(review.rating, 5);
      expect(review.professionalId, 'pro-1');
    });

    test('retourne zéro lorsque la note est invalide', () {
      expect(Review.fromJson({'rating': 'inconnue'}).rating, 0);
    });
  });
}
