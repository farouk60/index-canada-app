import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:index_canada/data_service.dart';
import 'package:index_canada/models.dart';
import 'package:index_canada/pages/professionnel_detail_page.dart';
import 'package:index_canada/services/firebase_analytics_service.dart';

class _ReviewsDataService extends DataService {
  _ReviewsDataService()
    : super.withClient(MockClient((_) async => http.Response('{}', 200)));

  @override
  Future<List<Review>> fetchReviews(
    String professionnelId, {
    bool forceRefresh = false,
  }) async => const <Review>[];
}

Professionnel _professionnel() => Professionnel(
  id: 'pro_123',
  title: 'Nom prive a ne pas tracer',
  subtitle: '',
  ville: 'Montreal',
  address: '123 rue Privee',
  numroDeTlphone: '+1 514 555 0101',
  image: '',
  gallery: const [],
  sousCategorie: 'Construction / Renovation',
  plan: 'premium',
  website: 'https://secret.example.test',
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

  Finder actionButton(IconData icon) =>
      find.widgetWithIcon(ElevatedButton, icon);

  testWidgets('mesure la vue une seule fois apres le premier rendu', (
    tester,
  ) async {
    final (analytics, payloads) = await analyticsHarness();

    await tester.pumpWidget(
      MaterialApp(
        home: ProfessionnelDetailPage(
          professionnel: _professionnel(),
          analyticsService: analytics,
          dataService: _ReviewsDataService(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 10));
    await tester.pump();

    expect(
      payloads.where((payload) => payload['type'] == 'professional_view'),
      hasLength(1),
    );
    final serialized = jsonEncode(payloads);
    expect(serialized, isNot(contains('Nom prive')));
    expect(serialized, isNot(contains('Construction / Renovation')));
    expect(serialized, isNot(contains('Montreal')));
  });

  testWidgets('mesure les contacts seulement apres une ouverture reussie', (
    tester,
  ) async {
    final (analytics, payloads) = await analyticsHarness();

    await tester.pumpWidget(
      MaterialApp(
        home: ProfessionnelDetailPage(
          professionnel: _professionnel(),
          sourcePlacement: 'directory',
          analyticsService: analytics,
          dataService: _ReviewsDataService(),
          phoneLauncher: (_) async => true,
          mapsLauncher: (_) async => true,
          websiteLauncher: (_) async => true,
        ),
      ),
    );
    await tester.pump();

    for (final icon in [Icons.phone, Icons.directions, Icons.language]) {
      final finder = actionButton(icon);
      await tester.ensureVisible(finder);
      await tester.tap(finder);
      await tester.pump();
    }
    await tester.pump();

    final contacts = payloads
        .where((payload) => payload['type'] == 'contact')
        .toList(growable: false);
    expect(contacts, hasLength(3));
    expect(contacts.map((payload) => payload['channel']).toSet(), {
      'phone',
      'map',
      'website',
    });
    expect(contacts.map((payload) => payload['placement']).toSet(), {
      'directory',
    });

    final serialized = jsonEncode(contacts);
    for (final forbidden in [
      'Nom prive',
      '+1 514 555 0101',
      '123 rue Privee',
      'secret.example.test',
    ]) {
      expect(serialized, isNot(contains(forbidden)));
    }
  });

  testWidgets('ne mesure aucun contact lorsque les ouvertures echouent', (
    tester,
  ) async {
    final (analytics, payloads) = await analyticsHarness();

    await tester.pumpWidget(
      MaterialApp(
        home: ProfessionnelDetailPage(
          professionnel: _professionnel(),
          analyticsService: analytics,
          dataService: _ReviewsDataService(),
          phoneLauncher: (_) async => false,
          mapsLauncher: (_) async => false,
          websiteLauncher: (_) async => false,
        ),
      ),
    );
    await tester.pump();

    for (final icon in [Icons.phone, Icons.directions, Icons.language]) {
      final finder = actionButton(icon);
      await tester.ensureVisible(finder);
      await tester.tap(finder);
      await tester.pump();
    }
    await tester.pump();

    expect(payloads.where((payload) => payload['type'] == 'contact'), isEmpty);
  });
}
