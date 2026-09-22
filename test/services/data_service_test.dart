import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:index_canada/data_service.dart';

http.Response directoryResponse(
  String key,
  List<Object?> items, {
  bool hasMore = false,
  String? nextCursor,
}) {
  return http.Response(
    jsonEncode({
      'success': true,
      'version': 2,
      key: items,
      'pagination': {
        'limit': 100,
        'has_more': hasMore,
        'next_cursor': nextCursor,
      },
    }),
    200,
  );
}

void main() {
  group('DataService', () {
    test('partage une seule route v2 entre appels concurrents', () async {
      final gate = Completer<void>();
      final requestStarted = Completer<void>();
      var requestCount = 0;
      final service = DataService.withClient(
        MockClient((_) async {
          requestCount++;
          if (!requestStarted.isCompleted) requestStarted.complete();
          await gate.future;
          return directoryResponse('categories', const []);
        }),
      );

      final first = service.fetchSousCategories();
      final second = service.fetchSousCategories();

      await requestStarted.future;
      expect(requestCount, 1);
      gate.complete();
      final responses = await Future.wait([first, second]);

      expect(requestCount, 1);
      expect(responses[0], isEmpty);
      expect(responses[1], isEmpty);
    });

    test('rejette un élément v2 qui n’est pas un objet', () async {
      final service = DataService.withClient(
        MockClient(
          (_) async => directoryResponse('professionals', [
            'entrée invalide',
            {'_id': 'pro-1', 'title': 'Clinique du quartier'},
          ]),
        ),
      );

      await expectLater(
        service.fetchProfessionnels(),
        throwsA(isA<FormatException>()),
      );
    });

    test(
      'conserve une URL cacheable sauf lors d’un rafraîchissement forcé',
      () async {
        final requestedUris = <Uri>[];
        final service = DataService.withClient(
          MockClient((request) async {
            requestedUris.add(request.url);
            return directoryResponse('categories', const []);
          }),
        );

        await service.fetchSousCategories();
        await service.forceSyncWithWix();
        await service.fetchSousCategories();

        expect(requestedUris, hasLength(2));
        expect(requestedUris.first.path, endsWith('/categories'));
        expect(requestedUris.first.queryParameters['refresh'], isNull);
        expect(requestedUris.last.queryParameters['refresh'], isNot(isEmpty));
      },
    );

    test('ne conserve que les avis du professionnel demandé', () async {
      final service = DataService.withClient(
        MockClient(
          (_) async => directoryResponse('reviews', [
            {
              '_id': 'approved',
              'professionalId': 'pro-1',
              'auteurNom': 'Client',
              'rating': 5,
              'message': 'Excellent',
              'title': 'Très bon service',
            },
            {'_id': 'other', 'professionalId': 'pro-2'},
          ]),
        ),
      );

      final reviews = await service.fetchReviews('pro-1');

      expect(reviews, hasLength(1));
      expect(reviews.single.id, 'approved');
    });

    test('rejette une racine v2 qui n’est pas un objet', () async {
      final service = DataService.withClient(
        MockClient((_) async => http.Response(jsonEncode(['invalide']), 200)),
      );

      await expectLater(
        service.fetchSousCategories(),
        throwsA(isA<FormatException>()),
      );
    });

    test(
      'propage une panne réseau au lieu de simuler une liste vide',
      () async {
        final service = DataService.withClient(
          MockClient((request) async {
            throw http.ClientException('réseau indisponible', request.url);
          }),
        );

        await expectLater(
          service.fetchSousCategories(),
          throwsA(isA<http.ClientException>()),
        );
        await expectLater(
          service.fetchSponsoredProfessionnels(),
          throwsA(isA<http.ClientException>()),
        );
      },
    );

    test(
      'suit le curseur opaque et transmet les filtres professionnels',
      () async {
        final requestedUris = <Uri>[];
        final service = DataService.withClient(
          MockClient((request) async {
            requestedUris.add(request.url);
            if (request.url.queryParameters['cursor'] == null) {
              return directoryResponse(
                'professionals',
                const [
                  {'_id': 'pro-1', 'title': 'Fiscalité Montréal'},
                ],
                hasMore: true,
                nextCursor: 'opaque.cursor+1',
              );
            }
            return directoryResponse('professionals', const [
              {'_id': 'pro-2', 'title': 'Conseil fiscal'},
            ]);
          }),
        );

        final professionals = await service.fetchProfessionnels(
          sousCategorie: 'cat-fiscalite',
          search: 'fiscal',
          ville: 'Montréal',
        );

        expect(professionals.map((item) => item.id), ['pro-1', 'pro-2']);
        expect(requestedUris, hasLength(2));
        expect(requestedUris.first.path, endsWith('/professionals'));
        expect(
          requestedUris.first.queryParameters,
          containsPair('limit', '100'),
        );
        expect(
          requestedUris.first.queryParameters,
          containsPair('category', 'cat-fiscalite'),
        );
        expect(
          requestedUris.first.queryParameters,
          containsPair('search', 'fiscal'),
        );
        expect(
          requestedUris.first.queryParameters,
          containsPair('city', 'Montréal'),
        );
        expect(requestedUris.last.queryParameters['cursor'], 'opaque.cursor+1');
      },
    );

    test('refuse un curseur de pagination répété', () async {
      final service = DataService.withClient(
        MockClient(
          (_) async => directoryResponse(
            'categories',
            const [],
            hasMore: true,
            nextCursor: 'same-cursor',
          ),
        ),
      );

      await expectLater(
        service.fetchSousCategories(),
        throwsA(isA<FormatException>()),
      );
    });

    test('refuse un même identifiant reçu sur plusieurs pages', () async {
      var requestCount = 0;
      final service = DataService.withClient(
        MockClient((_) async {
          requestCount++;
          return directoryResponse(
            'categories',
            const [
              {'_id': 'cat-1', 'title': 'Catégorie'},
            ],
            hasMore: requestCount == 1,
            nextCursor: requestCount == 1 ? 'next-page' : null,
          );
        }),
      );

      await expectLater(
        service.fetchSousCategories(),
        throwsA(isA<FormatException>()),
      );
      expect(requestCount, 2);
    });

    test('charge les favoris par lots de 50 et restaure leur ordre', () async {
      final ids = List.generate(51, (index) => 'pro_$index');
      final batchSizes = <int>[];
      final service = DataService.withClient(
        MockClient((request) async {
          final batch = request.url.queryParameters['ids']!.split(',');
          batchSizes.add(batch.length);
          return directoryResponse(
            'professionals',
            batch.reversed
                .map((id) => <String, Object>{'_id': id, 'title': id})
                .toList(),
          );
        }),
      );

      final professionals = await service.fetchProfessionnelsByIds(ids);

      expect(batchSizes, [50, 1]);
      expect(professionals.map((item) => item.id), ids);
    });

    test(
      'utilise uniquement les routes ciblées pour le répertoire public',
      () async {
        final requestedPaths = <String>[];
        final service = DataService.withClient(
          MockClient((request) async {
            requestedPaths.add(request.url.path);
            return switch (request.url.pathSegments.last) {
              'categories' => directoryResponse('categories', const []),
              'professionals' => directoryResponse('professionals', const []),
              'reviews' => directoryResponse('reviews', const []),
              'partners' => directoryResponse('partners', const []),
              'offers' => directoryResponse('offers', const []),
              _ => http.Response('introuvable', 404),
            };
          }),
        );

        await service.fetchSousCategories();
        await service.fetchSponsoredProfessionnels();
        await service.fetchProfessionnels();
        await service.fetchReviews('pro-1');
        await service.fetchPartners();
        await service.fetchOffers();

        expect(requestedPaths, hasLength(6));
        expect(requestedPaths.any((path) => path.endsWith('/data')), isFalse);
        expect(requestedPaths.map((path) => path.split('/').last).toSet(), {
          'categories',
          'professionals',
          'reviews',
          'partners',
          'offers',
        });
      },
    );
  });
}
