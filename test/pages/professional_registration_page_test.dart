import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:index_canada/models.dart';
import 'package:index_canada/pages/professional_registration_page.dart';
import 'package:index_canada/services/localization_service.dart';
import 'package:index_canada/services/stripe_native_payment_service.dart';
import 'package:index_canada/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await LocalizationService().setLanguage('fr');
  });

  tearDown(() async {
    await LocalizationService().setLanguage('fr');
  });

  testWidgets(
    'présente les trois prix annuels et la validation avant le formulaire',
    (tester) async {
      await _pumpRegistration(tester);

      expect(find.text('Choisissez votre forfait annuel'), findsOneWidget);
      expect(find.text('Plan Basique'), findsOneWidget);
      expect(find.text('Plan Premium'), findsOneWidget);
      expect(find.text('Plan En Vedette'), findsOneWidget);
      expect(find.text('Validation avant publication'), findsOneWidget);
      expect(
        find.textContaining(
          'Le paiement n’entraîne pas une publication immédiate.',
        ),
        findsOneWidget,
      );

      for (final planId in <String>['basic', 'premium', 'professional']) {
        final price = tester.widget<Text>(
          find.byKey(ValueKey<String>('plan-price-$planId')),
        );
        expect(price.data, endsWith('/ an'));
      }

      expect(
        find.text('Nom du professionnel/entreprise *').hitTestable(),
        findsNothing,
      );
      final continueButton = find.text('Continuer').hitTestable();
      expect(continueButton, findsOneWidget);

      await tester.ensureVisible(continueButton);
      await tester.tap(continueButton);
      await tester.pumpAndSettle();

      final identityLabel = find.text('Nom du professionnel/entreprise *');
      expect(identityLabel, findsOneWidget);
      expect(find.byType(EditableText).hitTestable(), findsWidgets);
    },
  );

  testWidgets('localise les prix annuels et la validation en anglais', (
    tester,
  ) async {
    await LocalizationService().setLanguage('en');
    await _pumpRegistration(tester);

    expect(find.text('Choose your annual plan'), findsOneWidget);
    expect(find.text('Reviewed before publication'), findsOneWidget);
    expect(
      find.textContaining('Payment does not result in immediate publication.'),
      findsOneWidget,
    );

    for (final planId in <String>['basic', 'premium', 'professional']) {
      final price = tester.widget<Text>(
        find.byKey(ValueKey<String>('plan-price-$planId')),
      );
      expect(price.data, endsWith('/ year'));
    }
  });

  testWidgets('affiche les avantages de chaque forfait avant la sélection', (
    tester,
  ) async {
    await _pumpRegistration(tester);

    expect(find.text('Visibilité standard'), findsOneWidget);
    expect(find.text('Galerie de 5 photos'), findsOneWidget);
    expect(find.text('Mise en avant sur la page d’accueil'), findsOneWidget);

    await tester.tap(find.text('Plan Premium'));
    await tester.pump();

    expect(find.text('Sélectionné'), findsOneWidget);
  });
}

Future<void> _pumpRegistration(WidgetTester tester) async {
  tester.view.physicalSize = const Size(520, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      home: ProfessionalRegistrationPage(
        paymentPlansLoader: () async => _catalog(),
        categoriesLoader: () async => <SousCategorie>[
          SousCategorie(
            id: 'bakery',
            title: 'Boulangerie',
            titleEn: 'Bakery',
            image: '',
          ),
        ],
      ),
    ),
  );
  await tester.pumpAndSettle();
}

PaymentPlanCatalog _catalog() {
  return PaymentPlanCatalog.fromJson({
    'success': true,
    'version': 2,
    'plans': [
      _plan(
        id: 'basic',
        amount: 0,
        requiresPayment: false,
        labelFr: 'Plan Basique',
        labelEn: 'Basic Plan',
        featuresFr: ['Profil professionnel', 'Visibilité standard'],
        featuresEn: ['Professional profile', 'Standard visibility'],
        galleryMax: 0,
        coupon: false,
        featured: false,
      ),
      _plan(
        id: 'premium',
        amount: 4999,
        requiresPayment: true,
        labelFr: 'Plan Premium',
        labelEn: 'Premium Plan',
        featuresFr: ['Galerie de 5 photos', 'Coupons de réduction'],
        featuresEn: ['Gallery of 5 photos', 'Discount coupons'],
        galleryMax: 5,
        coupon: true,
        featured: false,
      ),
      _plan(
        id: 'professional',
        amount: 11999,
        requiresPayment: true,
        labelFr: 'Plan En Vedette',
        labelEn: 'Featured Plan',
        featuresFr: ['Mise en avant sur la page d’accueil'],
        featuresEn: ['Featured on the home page'],
        galleryMax: 5,
        coupon: true,
        featured: true,
      ),
    ],
  });
}

Map<String, Object> _plan({
  required String id,
  required int amount,
  required bool requiresPayment,
  required String labelFr,
  required String labelEn,
  required List<String> featuresFr,
  required List<String> featuresEn,
  required int galleryMax,
  required bool coupon,
  required bool featured,
}) {
  return <String, Object>{
    'id': id,
    'amount': amount,
    'currency': 'cad',
    'requires_payment': requiresPayment,
    'duration_days': 365,
    'label': <String, String>{'fr': labelFr, 'en': labelEn},
    'capabilities': <String, Object>{
      'profile_image': true,
      'gallery_max': galleryMax,
      'coupon': coupon,
      'featured': featured,
    },
    'features': <String, List<String>>{'fr': featuresFr, 'en': featuresEn},
  };
}
