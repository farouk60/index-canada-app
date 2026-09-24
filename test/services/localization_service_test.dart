import 'package:flutter_test/flutter_test.dart';
import 'package:index_canada/services/localization_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'pluralise les compteurs d’avis et de galerie en français et anglais',
    () async {
      SharedPreferences.setMockInitialValues({});
      final localization = LocalizationService();
      addTearDown(() => localization.setLanguage('fr'));

      await localization.setLanguage('fr');
      expect(localization.reviewCountLabel(0), '0 avis');
      expect(localization.reviewCountLabel(1), '1 avis');
      expect(localization.clientReviewsLabel(1), 'Avis client (1)');
      expect(
        localization.galleryPreviewLabel(2),
        'Ouvrir la galerie, 2 images',
      );

      await localization.setLanguage('en');
      expect(localization.reviewCountLabel(0), '0 reviews');
      expect(localization.reviewCountLabel(1), '1 review');
      expect(localization.clientReviewsLabel(2), 'Client reviews (2)');
      expect(localization.galleryPreviewLabel(1), 'Open gallery, 1 image');
    },
  );

  test(
    'fournit une proposition d’accueil claire et prudente en FR/EN',
    () async {
      SharedPreferences.setMockInitialValues({});
      final localization = LocalizationService();
      addTearDown(() => localization.setLanguage('fr'));

      await localization.setLanguage('fr');
      expect(localization.tr('home_eyebrow'), 'Le repère canadien');
      expect(localization.tr('explore_services'), 'Trouver un service');
      expect(localization.tr('register_here'), 'Créer mon profil');

      await localization.setLanguage('en');
      expect(localization.tr('home_eyebrow'), 'Your Canadian starting point');
      expect(localization.tr('explore_services'), 'Find a service');
      expect(localization.tr('register_here'), 'Create my profile');
    },
  );
}
