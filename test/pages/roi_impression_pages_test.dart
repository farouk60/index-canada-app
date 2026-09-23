import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:index_canada/data_service.dart';
import 'package:index_canada/models.dart';
import 'package:index_canada/models/wix_offer_models.dart';
import 'package:index_canada/models/wix_partner_models.dart';
import 'package:index_canada/pages/home_page.dart';
import 'package:index_canada/pages/professionnels_page.dart';
import 'package:index_canada/services/firebase_analytics_service.dart';

class _DirectoryDataService extends DataService {
  _DirectoryDataService(this.professionnels)
    : super.withClient(MockClient((_) async => http.Response('{}', 200)));

  final List<Professionnel> professionnels;

  @override
  Future<void> forceSyncWithWix() async {}

  @override
  Future<List<SousCategorie>> fetchSousCategories({
    bool forceRefresh = false,
  }) async => <SousCategorie>[
    SousCategorie(
      id: 'cat_123',
      title: 'Services',
      titleEn: 'Services',
      image: '',
    ),
  ];

  @override
  Future<List<Professionnel>> fetchSponsoredProfessionnels({
    bool forceRefresh = false,
  }) async => professionnels;

  @override
  Future<List<Professionnel>> fetchProfessionnels({
    String? sousCategorie,
    String? search,
    String? ville,
    bool forceRefresh = false,
  }) async => professionnels;

  @override
  Future<List<WixPartner>> fetchPartners({bool forceRefresh = false}) async =>
      <WixPartner>[];

  @override
  Future<List<WixOffer>> fetchExclusiveOffers({
    bool forceRefresh = false,
  }) async => <WixOffer>[];
}

Professionnel _professionnel() => Professionnel(
  id: 'pro_123',
  title: 'Entreprise visible',
  subtitle: 'Service test',
  ville: 'Montreal',
  address: '123 rue Privee',
  numroDeTlphone: '',
  image: '',
  gallery: const [],
  sousCategorie: 'Services',
  plan: 'professional',
);

void main() {
  Future<(FirebaseAnalyticsService, List<Map<String, Object?>>)>
  analyticsHarness() async {
    final payloads = <Map<String, Object?>>[];
    final service = FirebaseAnalyticsService.withClient(
      MockClient((request) async {
        payloads.add(
          Map<String, Object?>.from(
            jsonDecode(request.body) as Map<String, dynamic>,
          ),
        );
        return http.Response('{"received":true}', 201);
      }),
      baseUrl: 'https://api.example.test/_functions',
      localeProvider: () => 'fr_CA',
    );
    await service.initialize();
    return (service, payloads);
  }

  Iterable<Map<String, Object?>> impressions(
    List<Map<String, Object?>> payloads,
  ) =>
      payloads.where((payload) => payload['type'] == 'professional_impression');

  testWidgets('compte une seule impression de la vedette visible sur accueil', (
    tester,
  ) async {
    final (analytics, payloads) = await analyticsHarness();
    final professionnel = _professionnel();

    await tester.pumpWidget(
      MaterialApp(
        home: HomePage(
          analyticsService: analytics,
          dataService: _DirectoryDataService([professionnel]),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    final title = find.text(professionnel.title);
    expect(title, findsOneWidget);
    await Scrollable.ensureVisible(tester.element(title));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1100));
    await tester.pump();

    expect(impressions(payloads), hasLength(1));
    expect(impressions(payloads).single['placement'], 'home_featured');

    await tester.pump(const Duration(seconds: 2));
    expect(impressions(payloads), hasLength(1));
  });

  testWidgets('compte une seule impression visible dans annuaire', (
    tester,
  ) async {
    final (analytics, payloads) = await analyticsHarness();
    final professionnel = _professionnel();
    var mapsOpened = false;
    final categorie = SousCategorie(
      id: 'cat_123',
      title: 'Services',
      titleEn: 'Services',
      image: '',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: ProfessionnelsPage(
          sousCategorie: categorie,
          analyticsService: analytics,
          dataService: _DirectoryDataService([professionnel]),
          mapsLauncher: (_) async {
            mapsOpened = true;
            return true;
          },
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    final title = find.text(professionnel.title);
    expect(title, findsOneWidget);
    await Scrollable.ensureVisible(tester.element(title));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1100));
    await tester.pump();

    expect(impressions(payloads), hasLength(1));
    expect(impressions(payloads).single['placement'], 'directory');

    await tester.pump(const Duration(seconds: 2));
    expect(impressions(payloads), hasLength(1));

    await tester.tap(find.text(professionnel.address));
    await tester.pump();
    expect(mapsOpened, isTrue);
    final contacts = payloads.where((payload) => payload['type'] == 'contact');
    expect(contacts, hasLength(1));
    expect(contacts.single['channel'], 'map');
    expect(contacts.single['placement'], 'directory');
    expect(
      jsonEncode(contacts.toList(growable: false)),
      isNot(contains(professionnel.address)),
    );
  });
}
