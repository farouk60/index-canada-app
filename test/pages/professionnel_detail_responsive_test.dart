import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:index_canada/data_service.dart';
import 'package:index_canada/models.dart';
import 'package:index_canada/pages/professionnel_detail_page.dart';
import 'package:index_canada/services/firebase_analytics_service.dart';
import 'package:index_canada/services/localization_service.dart';
import 'package:index_canada/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _ResponsiveReviewsDataService extends DataService {
  _ResponsiveReviewsDataService()
    : super.withClient(MockClient((_) async => http.Response('{}', 200)));

  @override
  Future<List<Review>> fetchReviews(
    String professionnelId, {
    bool forceRefresh = false,
  }) async => <Review>[
    Review(
      id: 'review_1',
      professionalId: professionnelId,
      auteurNom: 'Cliente de Saint-Jean-sur-Richelieu',
      rating: 5,
      message: 'Service attentionné et produits excellents.',
      title: 'Très bonne expérience',
    ),
  ];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  tearDown(() async {
    await LocalizationService().setLanguage('fr');
  });

  for (final locale in <String>['fr', 'en']) {
    testWidgets('reste sans débordement à 320 px en $locale', (tester) async {
      await LocalizationService().setLanguage(locale);
      tester.view.physicalSize = const Size(320, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: ProfessionnelDetailPage(
            professionnel: _professionnel(),
            analyticsService: _analyticsService(),
            dataService: _ResponsiveReviewsDataService(),
            phoneLauncher: (_) async => true,
            mapsLauncher: (_) async => true,
            websiteLauncher: (_) async => true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(
        find.byKey(const ValueKey('persistent_contact_bar')),
        findsOneWidget,
      );
      for (final key in <String>[
        'professional_call_action',
        'professional_directions_action',
        'professional_website_action',
      ]) {
        final rect = tester.getRect(find.byKey(ValueKey(key)));
        expect(rect.left, greaterThanOrEqualTo(0));
        expect(rect.right, lessThanOrEqualTo(320));
        expect(rect.height, greaterThanOrEqualTo(48));
      }

      final reviewsHeader = find.byKey(
        const ValueKey('professional_reviews_header'),
      );
      await tester.ensureVisible(reviewsHeader);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(reviewsHeader, findsOneWidget);
      expect(
        find.byKey(const ValueKey('professional_add_review_action')),
        findsOneWidget,
      );
      expect(
        find.text(locale == 'fr' ? 'Itinéraire' : 'Directions'),
        findsOneWidget,
      );
      expect(
        find.text(locale == 'fr' ? 'Ajouter un avis' : 'Add Review'),
        findsOneWidget,
      );
    });
  }
}

FirebaseAnalyticsService _analyticsService() {
  return FirebaseAnalyticsService.withClient(
    MockClient((_) async => http.Response('{"received":true}', 201)),
    baseUrl: 'https://api.example.test/_functions',
  );
}

Professionnel _professionnel() => Professionnel(
  id: 'st_boulangerie',
  title: 'ST Boulangerie et pâtisserie artisanale',
  subtitle: 'Pains, viennoiseries et pâtisseries préparés avec soin pour la communauté.',
  ville: 'Saint-Jean-sur-Richelieu, QC',
  address: '1234, boulevard très long, Saint-Jean-sur-Richelieu, Québec',
  numroDeTlphone: '+1 514 555 0101',
  image: '',
  gallery: const <dynamic>[],
  sousCategorie: '428c5a36-ec70-4d59-b975-628f92ca7972',
  plan: 'professional',
  averageRating: 4.8,
  reviewCount: 128,
  email: 'bonjour@st-boulangerie.example',
  website: 'https://st-boulangerie.example',
);
