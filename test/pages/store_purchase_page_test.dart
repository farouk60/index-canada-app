import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:index_canada/pages/store_purchase_page.dart';
import 'package:index_canada/services/localization_service.dart';
import 'package:index_canada/services/store_purchase_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeStoreGateway gateway;
  late StorePurchaseService service;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await LocalizationService().setLanguage('fr');
    gateway = _FakeStoreGateway();
    service = StorePurchaseService(
      gateway: gateway,
      api: StoreCheckoutApi(
        baseUrl: 'https://payments.example.invalid',
        client: MockClient((request) async {
          fail('Aucun appel HTTP attendu: ${request.url}');
        }),
      ),
      store: StorePlatform.appStore,
    );
  });

  tearDown(() async {
    await service.dispose();
    await gateway.close();
    await LocalizationService().setLanguage('fr');
  });

  testWidgets('affiche et ouvre les liens obligatoires sur iOS', (
    tester,
  ) async {
    final opened = <Uri>[];
    await _pumpPage(
      tester,
      service: service,
      store: StorePlatform.appStore,
      launcher: (uri) async {
        opened.add(uri);
        return true;
      },
    );

    expect(
      find.textContaining('se renouvelle automatiquement'),
      findsOneWidget,
    );
    expect(
      find.textContaining('débité de votre compte App Store'),
      findsOneWidget,
    );
    expect(find.textContaining('Gérez-le ou annulez-le'), findsOneWidget);
    expect(find.byKey(const Key('store_purchase_privacy')), findsOneWidget);
    expect(find.byKey(const Key('store_purchase_eula')), findsOneWidget);
    expect(find.byKey(const Key('store_purchase_manage')), findsOneWidget);

    final manage = find.byKey(const Key('store_purchase_manage'));
    await tester.ensureVisible(manage);
    await tester.tap(manage);
    await tester.pump();
    final privacy = find.byKey(const Key('store_purchase_privacy'));
    await tester.ensureVisible(privacy);
    await tester.tap(privacy);
    await tester.pump();
    final eula = find.byKey(const Key('store_purchase_eula'));
    await tester.ensureVisible(eula);
    await tester.tap(eula);
    await tester.pump();

    expect(opened, <Uri>[
      Uri.parse('https://apps.apple.com/account/subscriptions'),
      Uri.parse('https://www.immigrantindex.com/privacy'),
      Uri.parse(
        'https://www.apple.com/legal/internet-services/itunes/dev/stdeula/',
      ),
    ]);
  });

  testWidgets('affiche Google Play sans présenter l’EULA Apple', (
    tester,
  ) async {
    await LocalizationService().setLanguage('en');
    final opened = <Uri>[];
    await _pumpPage(
      tester,
      service: service,
      store: StorePlatform.googlePlay,
      launcher: (uri) async {
        opened.add(uri);
        return true;
      },
    );

    expect(find.textContaining('renews automatically'), findsOneWidget);
    expect(
      find.textContaining('charged to your Google Play account'),
      findsOneWidget,
    );
    expect(find.textContaining('Manage or cancel it'), findsOneWidget);
    expect(find.byKey(const Key('store_purchase_privacy')), findsOneWidget);
    expect(find.byKey(const Key('store_purchase_eula')), findsNothing);
    expect(find.byKey(const Key('store_purchase_manage')), findsOneWidget);
    expect(find.text('Manage subscription'), findsOneWidget);
    expect(find.textContaining('Apple EULA'), findsNothing);

    final manage = find.byKey(const Key('store_purchase_manage'));
    await tester.ensureVisible(manage);
    await tester.tap(manage);
    await tester.pump();
    final privacy = find.byKey(const Key('store_purchase_privacy'));
    await tester.ensureVisible(privacy);
    await tester.tap(privacy);
    await tester.pump();

    expect(opened, <Uri>[
      Uri.parse('https://play.google.com/store/account/subscriptions'),
      Uri.parse('https://www.immigrantindex.com/privacy'),
    ]);
  });
}

Future<void> _pumpPage(
  WidgetTester tester, {
  required StorePurchaseService service,
  required StorePlatform store,
  required ExternalLinkLauncher launcher,
}) async {
  tester.view.physicalSize = const Size(520, 1500);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    MaterialApp(
      home: StorePurchasePage(
        professionalId: 'temporary-professional',
        businessName: 'Entreprise QA',
        email: 'qa@example.ca',
        selectedPlan: 'premium',
        serverQuote: _premiumQuote(),
        categoryId: 'services',
        registrationData: const <String, dynamic>{
          'city': 'Montréal',
          'phone': '5145550101',
        },
        purchaseService: service,
        initialProduct: _products().first,
        store: store,
        linkLauncher: launcher,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

PaymentPlanQuote _premiumQuote() => PaymentPlanQuote.fromJson(<String, dynamic>{
  'id': 'premium',
  'amount': 4999,
  'currency': 'cad',
  'requires_payment': true,
  'duration_days': 365,
  'store_products': <String, String>{
    'app_store': StoreProductIds.premiumAnnual,
    'google_play': StoreProductIds.premiumAnnual,
  },
  'billing_period': 'P1Y',
  'auto_renewing': true,
  'label': <String, String>{'fr': 'Plan Premium', 'en': 'Premium Plan'},
  'features': <String, List<String>>{
    'fr': <String>['Galerie de 5 photos'],
    'en': <String>['Gallery of 5 photos'],
  },
  'capabilities': <String, dynamic>{
    'profile_image': true,
    'gallery_max': 5,
    'coupon': true,
    'featured': false,
  },
});

List<StoreProductOffer> _products() => const <StoreProductOffer>[
  StoreProductOffer(
    planId: 'premium',
    productId: StoreProductIds.premiumAnnual,
    title: 'Premium annuel',
    description: 'Premium',
    localizedPrice: '49,99 \$ CA',
    rawPrice: 49.99,
    currencyCode: 'CAD',
  ),
  StoreProductOffer(
    planId: 'professional',
    productId: StoreProductIds.professionalAnnual,
    title: 'En vedette annuel',
    description: 'En vedette',
    localizedPrice: '119,99 \$ CA',
    rawPrice: 119.99,
    currencyCode: 'CAD',
  ),
];

final class _FakeStoreGateway implements StorePurchaseGateway {
  final StreamController<List<StorePurchaseEvent>> _controller =
      StreamController<List<StorePurchaseEvent>>.broadcast();

  @override
  Stream<List<StorePurchaseEvent>> get purchaseStream => _controller.stream;

  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<List<StoreProductOffer>> queryProducts(Set<String> productIds) async {
    return _products();
  }

  @override
  Future<bool> buyNonConsumable(
    StoreProductOffer product, {
    required String applicationUserName,
  }) async {
    return true;
  }

  @override
  Future<void> restorePurchases() async {}

  @override
  Future<void> completePurchase(StorePurchaseEvent purchase) async {}

  Future<void> close() => _controller.close();
}
