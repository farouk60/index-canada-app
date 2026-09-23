import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:index_canada/core/logging/app_logger.dart';
import 'package:index_canada/services/firebase_analytics_service.dart';

void main() {
  const baseUrl = 'https://api.example.test/_functions/';

  FirebaseAnalyticsService serviceWith(
    MockClient client, {
    Duration timeout = const Duration(milliseconds: 100),
    AppLogger? logger,
  }) {
    return FirebaseAnalyticsService.withClient(
      client,
      baseUrl: baseUrl,
      requestTimeout: timeout,
      localeProvider: () => 'fr_CA',
      logger: logger,
    );
  }

  Future<Map<String, Object?>> decodeRequest(http.Request request) async {
    return Map<String, Object?>.from(
      jsonDecode(request.body) as Map<String, dynamic>,
    );
  }

  group('FirebaseAnalyticsService ROI v1', () {
    test('envoie une vue professionnelle sans donnée personnelle', () async {
      final requestReceived = Completer<http.Request>();
      final service = serviceWith(
        MockClient((request) async {
          requestReceived.complete(request);
          return http.Response('{"received":true}', 201);
        }),
      );

      expect(service.isAvailable, isFalse);
      await service.initialize();
      expect(service.isAvailable, isTrue);

      await service.trackProfessionalView(
        professionalId: 'pro_123',
        professionalName: 'Nom confidentiel',
        categoryId: 'cat_9',
        category: 'Santé',
        city: 'Montréal',
        isSponsor: true,
        parameters: const {
          'email': 'client@example.test',
          'phoneNumber': '+1 514 555 0101',
          'address': '123 rue Privée',
          'website': 'https://secret.example.test',
          'unexpected': 'ne doit jamais sortir',
        },
      );

      final request = await requestReceived.future.timeout(
        const Duration(seconds: 1),
      );
      final body = await decodeRequest(request);

      expect(request.method, 'POST');
      expect(request.url.toString(), '${baseUrl}engagementEvent');
      expect(request.headers['content-type'], contains('application/json'));
      expect(body.keys.toSet(), {
        'version',
        'eventId',
        'type',
        'professionalId',
        'placement',
        'locale',
      });
      expect(body['version'], 1);
      expect(body['type'], 'professional_view');
      expect(body['professionalId'], 'pro_123');
      expect(body, isNot(contains('categoryId')));
      expect(body['placement'], 'detail');
      expect(body['locale'], 'fr');
      expect(
        body['eventId'],
        matches(
          RegExp(
            r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
          ),
        ),
      );

      final serialized = jsonEncode(body);
      for (final forbidden in [
        'query',
        'searchQuery',
        'Nom confidentiel',
        'client@example.test',
        '+1 514 555 0101',
        '123 rue Privée',
        'secret.example.test',
        'Montréal',
        'unexpected',
        'timestamp',
        'userId',
        'sessionId',
        'deviceId',
      ]) {
        expect(serialized, isNot(contains(forbidden)));
      }
    });

    test('génère un UUID v4 distinct pour chaque événement', () async {
      final requests = <http.Request>[];
      final allReceived = Completer<void>();
      final service = serviceWith(
        MockClient((request) async {
          requests.add(request);
          if (requests.length == 2 && !allReceived.isCompleted) {
            allReceived.complete();
          }
          return http.Response('{"received":true}', 201);
        }),
      );
      await service.initialize();

      await service.trackProfessionalView(professionalId: 'pro_1');
      await service.trackProfessionalView(professionalId: 'pro_1');
      await allReceived.future.timeout(const Duration(seconds: 1));

      final first = await decodeRequest(requests[0]);
      final second = await decodeRequest(requests[1]);
      expect(first['eventId'], isNot(second['eventId']));
    });

    test('regroupe le nombre de résultats sans envoyer la recherche', () async {
      final requests = <http.Request>[];
      final allReceived = Completer<void>();
      final service = serviceWith(
        MockClient((request) async {
          requests.add(request);
          if (requests.length == 8 && !allReceived.isCompleted) {
            allReceived.complete();
          }
          return http.Response('{"received":true}', 201);
        }),
      );
      await service.initialize();

      for (final entry in const [
        (count: 0, kind: 'professional'),
        (count: 1, kind: 'professional'),
        (count: 5, kind: 'professional'),
        (count: 6, kind: 'city'),
        (count: 20, kind: 'city'),
        (count: 21, kind: 'category'),
        (count: 250, kind: 'category'),
        (count: 3, kind: 'inconnu'),
      ]) {
        await service.trackSearch(
          query: 'requête confidentielle',
          searchQuery: 'autre recherche privée',
          searchType: entry.kind,
          resultsCount: entry.count,
          parameters: const {'ville': 'Québec'},
        );
      }

      await allReceived.future.timeout(const Duration(seconds: 1));
      final bodies = await Future.wait(requests.map(decodeRequest));
      expect(bodies.map((body) => body['resultsBucket']), [
        '0',
        '1-5',
        '1-5',
        '6-20',
        '6-20',
        '21+',
        '21+',
        '1-5',
      ]);
      expect(bodies.map((body) => body['searchKind']), [
        'text',
        'text',
        'text',
        'city',
        'city',
        'category',
        'category',
        'text',
      ]);
      for (final body in bodies) {
        expect(body.keys.toSet(), {
          'version',
          'eventId',
          'type',
          'placement',
          'searchKind',
          'resultsBucket',
          'locale',
        });
        expect(body['type'], 'search');
        expect(body['placement'], 'directory');
        expect(jsonEncode(body), isNot(contains('requête confidentielle')));
        expect(jsonEncode(body), isNot(contains('autre recherche privée')));
        expect(jsonEncode(body), isNot(contains('Québec')));
      }
    });

    test('convertit les trois contacts en canaux stricts', () async {
      final requests = <http.Request>[];
      final allReceived = Completer<void>();
      final service = serviceWith(
        MockClient((request) async {
          requests.add(request);
          if (requests.length == 3 && !allReceived.isCompleted) {
            allReceived.complete();
          }
          return http.Response('{"received":true}', 201);
        }),
      );
      await service.initialize();

      await service.trackPhoneCall(
        professionalId: 'pro_1',
        professionalName: 'Entreprise privée',
        phoneNumber: '+1 514 555 0101',
      );
      await service.trackWebsiteClick(
        professionalId: 'pro_1',
        professionalName: 'Entreprise privée',
        website: 'https://private.example.test',
      );
      await service.trackMapNavigation(
        professionalId: 'pro_1',
        professionalName: 'Entreprise privée',
        address: '123 rue Privée',
        placement: 'directory',
      );

      await allReceived.future.timeout(const Duration(seconds: 1));
      final bodies = await Future.wait(requests.map(decodeRequest));
      expect(bodies.map((body) => body['channel']), [
        'phone',
        'website',
        'map',
      ]);
      expect(bodies.map((body) => body['placement']), [
        'detail',
        'detail',
        'directory',
      ]);
      for (final body in bodies) {
        expect(body['type'], 'contact');
        expect(body['professionalId'], 'pro_1');
        expect(body.keys.toSet(), {
          'version',
          'eventId',
          'type',
          'professionalId',
          'placement',
          'channel',
          'locale',
        });
        final serialized = jsonEncode(body);
        expect(serialized, isNot(contains('Entreprise privée')));
        expect(serialized, isNot(contains('514')));
        expect(serialized, isNot(contains('private.example')));
        expect(serialized, isNot(contains('123 rue')));
      }
    });

    test('envoie uniquement les événements business allowlist', () async {
      final requests = <http.Request>[];
      final allReceived = Completer<void>();
      final service = serviceWith(
        MockClient((request) async {
          requests.add(request);
          if (requests.length == 3 && !allReceived.isCompleted) {
            allReceived.complete();
          }
          return http.Response('{"received":true}', 201);
        }),
      );
      await service.initialize();

      await service.trackSponsorClick(
        sponsorId: 'pro_1',
        sponsorName: 'Nom privé',
        categoryId: 'cat_1',
        clickType: 'carousel',
        sourceScreen: 'home_page',
      );
      await service.trackProfessionalImpression(
        professionalId: 'pro_2',
        categoryId: 'cat_2',
        placement: 'directory',
      );
      await service.trackCouponCopy(
        professionalId: 'pro_3',
        categoryId: 'cat_3',
        placement: 'detail',
      );

      await allReceived.future.timeout(const Duration(seconds: 1));
      final bodies = await Future.wait(requests.map(decodeRequest));
      expect(bodies.map((body) => body['type']), [
        'professional_click',
        'professional_impression',
        'coupon_copy',
      ]);
      expect(bodies.map((body) => body['placement']), [
        'home_featured',
        'directory',
        'detail',
      ]);
      expect(bodies[0]['professionalId'], 'pro_1');
      expect(bodies[0], isNot(contains('categoryId')));
      expect(bodies[1], isNot(contains('categoryId')));
      expect(bodies[2], isNot(contains('categoryId')));
      expect(bodies[1]['professionalId'], 'pro_2');
      expect(bodies[2]['professionalId'], 'pro_3');
      expect(jsonEncode(bodies), isNot(contains('Nom privé')));
    });

    test('laisse les anciennes méthodes non business en no-op', () async {
      var requestCount = 0;
      final service = serviceWith(
        MockClient((_) async {
          requestCount++;
          return http.Response('{"received":true}', 201);
        }),
      );
      await service.initialize();

      await service.logCustomEvent('arbitraire', const {'secret': 'valeur'});
      await service.logButtonTapped(
        'bouton',
        parameters: const {'email': 'client@example.test'},
      );
      await service.trackFavoriteAction(
        action: 'add',
        professionalId: 'pro_1',
        professionalName: 'Nom privé',
        parameters: const {'unexpected': 'valeur'},
      );
      await service.trackCategoryView(
        categoryId: 'cat_1',
        categoryName: 'Nom privé',
        sourceScreen: 'services_page',
      );
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(requestCount, 0);
    });

    test('ignore les événements invalides', () async {
      var requestCount = 0;
      final service = serviceWith(
        MockClient((_) async {
          requestCount++;
          return http.Response('{"received":true}', 201);
        }),
      );
      await service.initialize();

      await service.trackProfessionalView(professionalId: 'id avec espaces');
      await service.trackProfessionalImpression(
        professionalId: '',
        placement: 'directory',
      );
      await service.trackCouponCopy(
        professionalId: 'pro_1',
        placement: 'placement_inconnu',
      );
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(requestCount, 0);
    });

    test('ne bloque pas une action UI pendant la requête', () async {
      final requestStarted = Completer<void>();
      final releaseRequest = Completer<void>();
      final service = serviceWith(
        MockClient((_) async {
          requestStarted.complete();
          await releaseRequest.future;
          return http.Response('{"received":true}', 201);
        }),
      );
      await service.initialize();

      await service
          .trackProfessionalView(professionalId: 'pro_1')
          .timeout(const Duration(milliseconds: 50));
      await requestStarted.future.timeout(const Duration(seconds: 1));
      expect(releaseRequest.isCompleted, isFalse);

      releaseRequest.complete();
    });

    test('reessaie un echec transitoire avec le meme identifiant', () async {
      final bodies = <Map<String, Object?>>[];
      final delivered = Completer<void>();
      final service = serviceWith(
        MockClient((request) async {
          bodies.add(await decodeRequest(request));
          if (bodies.length == 1) return http.Response('indisponible', 503);
          delivered.complete();
          return http.Response('{"received":true}', 201);
        }),
      );
      await service.initialize();

      await service.trackProfessionalView(professionalId: 'pro_1');
      await delivered.future.timeout(const Duration(seconds: 1));

      expect(bodies, hasLength(2));
      expect(bodies[0]['eventId'], bodies[1]['eventId']);
      expect(bodies[0], bodies[1]);
    });

    test('ne reessaie pas une requete rejetee par le contrat', () async {
      var requestCount = 0;
      final logReceived = Completer<void>();
      final service = serviceWith(
        MockClient((_) async {
          requestCount++;
          return http.Response('{"code":"INVALID_ENGAGEMENT_EVENT"}', 400);
        }),
        logger: AppLogger(
          enabled: true,
          sink: (_) {
            if (!logReceived.isCompleted) logReceived.complete();
          },
        ),
      );
      await service.initialize();

      await service.trackProfessionalView(professionalId: 'pro_1');
      await logReceived.future.timeout(const Duration(seconds: 1));
      expect(requestCount, 1);
    });

    test('avale les erreurs sans renseignement sensible', () async {
      final logs = <String>[];
      final logReceived = Completer<void>();
      final logger = AppLogger(
        enabled: true,
        sink: (message) {
          logs.add(message);
          if (!logReceived.isCompleted) logReceived.complete();
        },
      );
      final service = serviceWith(
        MockClient((request) async {
          throw http.ClientException(
            'Échec pour client@example.test au +1 514 555 0101',
            request.url,
          );
        }),
        logger: logger,
      );
      await service.initialize();

      await service.trackPhoneCall(
        professionalId: 'pro_1',
        professionalName: 'Entreprise privée',
        phoneNumber: '+1 514 555 0101',
      );
      await logReceived.future.timeout(const Duration(seconds: 1));

      final serialized = logs.join('\n');
      expect(serialized, contains('télémétrie business'));
      expect(serialized, isNot(contains('client@example.test')));
      expect(serialized, isNot(contains('514')));
      expect(serialized, isNot(contains('Entreprise privée')));
      expect(serialized, isNot(contains('pro_1')));
    });

    test('interrompt une requête bloquée sans propager le timeout', () async {
      final never = Completer<http.Response>();
      final logReceived = Completer<void>();
      final service = serviceWith(
        MockClient((_) => never.future),
        timeout: const Duration(milliseconds: 5),
        logger: AppLogger(
          enabled: true,
          sink: (_) {
            if (!logReceived.isCompleted) logReceived.complete();
          },
        ),
      );
      await service.initialize();

      await service.trackProfessionalView(professionalId: 'pro_1');
      await logReceived.future.timeout(const Duration(seconds: 1));
    });
  });
}
