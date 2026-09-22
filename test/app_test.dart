import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:index_canada/core/config/app_config.dart';
import 'package:index_canada/main.dart';
import 'package:index_canada/pages/payment_success_page.dart';
import 'package:index_canada/services/localization_service.dart';
import 'package:index_canada/widgets/main_navigation.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'MyApp configure la navigation, les thèmes et respecte le TextScaler',
    (tester) async {
      const config = AppConfig(
        environment: AppEnvironment.development,
        appName: 'Index Canada Test',
        apiBaseUrl: 'https://example.invalid',
        stripePublishableKey: '',
        stripeUrlScheme: AppConfig.requiredStripeUrlScheme,
        imageCacheMaximumSize: 10,
        imageCacheMaximumSizeBytes: 1024,
        loggingEnabled: false,
      );
      late MaterialApp materialApp;

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Builder(
            builder: (context) {
              final app = const MyApp(config: config).build(context);
              final listenableApp = app as ListenableBuilder;
              materialApp = listenableApp.builder(context, null) as MaterialApp;
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      expect(materialApp.title, 'Index Canada Test');
      expect(materialApp.home, isA<MainNavigationPage>());
      expect(materialApp.themeMode, ThemeMode.light);
      expect(materialApp.theme?.brightness, Brightness.light);
      expect(materialApp.darkTheme?.brightness, Brightness.dark);
      expect(materialApp.locale, const Locale('fr', 'CA'));
      expect(materialApp.supportedLocales, const [
        Locale('fr', 'CA'),
        Locale('en', 'CA'),
      ]);

      // Aucun builder MediaQuery ne remplace le TextScaler de l'utilisateur.
      expect(materialApp.builder, isNull);
      expect(materialApp.debugShowCheckedModeBanner, isFalse);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'un onglet déjà monté se reconstruit après un changement de langue',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      await LocalizationService().setLanguage('fr');
      addTearDown(() => LocalizationService().setLanguage('fr'));

      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(const MaterialApp(home: MainNavigationPage()));
      await tester.pump();

      await tester.tap(find.text('Services').last);
      await tester.pump();
      expect(find.text('Rechercher'), findsOneWidget);

      await LocalizationService().setLanguage('en');
      await tester.pump();

      expect(find.text('Search'), findsOneWidget);
      expect(find.text('Rechercher'), findsNothing);
    },
  );

  testWidgets(
    'Voir les services revient à la racine et sélectionne le bon onglet',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      await LocalizationService().setLanguage('fr');

      await tester.pumpWidget(const MaterialApp(home: MainNavigationPage()));
      await tester.pump();

      final navigator = tester.state<NavigatorState>(find.byType(Navigator));
      navigator.push(
        MaterialPageRoute<void>(
          builder: (_) => const PaymentSuccessPage(
            professionalId: 'pro-1',
            planType: 'basic',
            businessName: 'Cabinet Exemple',
            amountPaid: 0,
            paymentId: 'checkout-1',
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      final action = find.byKey(const Key('payment_success_view_services'));
      await tester.ensureVisible(action);
      await tester.pumpAndSettle();
      await tester.tap(action);
      await tester.pumpAndSettle();

      expect(find.byType(PaymentSuccessPage), findsNothing);
      expect(
        tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
        1,
      );
      expect(find.text('Rechercher'), findsOneWidget);
    },
  );
}
