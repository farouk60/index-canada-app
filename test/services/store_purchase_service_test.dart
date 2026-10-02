import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:index_canada/services/store_purchase_service.dart';

void main() {
  group('StoreProductIds', () {
    test('lie les forfaits payants aux produits annuels des stores', () {
      expect(
        StoreProductIds.productIdForPlan('premium'),
        'ca.indexcanada.app.premium.annual',
      );
      expect(
        StoreProductIds.productIdForPlan('professional'),
        'ca.indexcanada.app.professional.annual',
      );
      expect(StoreProductIds.planIdForProduct('unknown'), isNull);
    });
  });

  group('catalogue et inscription gratuite', () {
    test('charge le catalogue depuis le backend', () async {
      final client = MockClient((request) async {
        expect(request.method, 'GET');
        expect(request.url.path, '/paymentPlans');
        return http.Response(jsonEncode(_catalogJson()), 200);
      });
      final api = StoreCheckoutApi(
        baseUrl: 'https://payments.example.invalid///',
        client: client,
      );

      final catalog = await api.fetchPaymentPlans();

      expect(catalog.findPlan('basic')?.requiresPayment, isFalse);
      expect(catalog.findPlan('premium')?.requiresPayment, isTrue);
    });

    test('refuse un contrat store non annuel ou incohérent', () {
      final invalidCatalogs = <Map<String, dynamic>>[
        _catalogJsonWithPaidPlan(<String, dynamic>{
          'store_products': <String, String>{
            'app_store': 'ca.indexcanada.app.incorrect',
            'google_play': StoreProductIds.premiumAnnual,
          },
        }),
        _catalogJsonWithPaidPlan(<String, dynamic>{'billing_period': 'P1M'}),
        _catalogJsonWithPaidPlan(<String, dynamic>{'auto_renewing': false}),
      ];

      for (final catalog in invalidCatalogs) {
        expect(
          () => PaymentPlanCatalog.fromJson(catalog),
          throwsA(isA<FormatException>()),
        );
      }
    });

    test(
      'crée puis confirme le checkout gratuit sans données de prix',
      () async {
        final calls = <String>[];
        late Map<String, dynamic> createPayload;
        late Map<String, dynamic> confirmPayload;
        final client = MockClient((request) async {
          calls.add(request.url.path);
          final payload = jsonDecode(request.body) as Map<String, dynamic>;
          if (request.url.path == '/createPaymentIntent') {
            createPayload = payload;
            return http.Response(
              jsonEncode({
                'success': true,
                'requires_payment': false,
                'confirmation_token': 'signed.free.fixture',
                'checkout_id': 'checkout-free-fixture',
                'amount': 0,
                'currency': 'cad',
              }),
              200,
            );
          }
          expect(request.url.path, '/confirmPayment');
          confirmPayload = payload;
          return http.Response(
            jsonEncode({
              'success': true,
              'idempotent': false,
              'status': 'pending_review',
              'checkout_id': 'checkout-free-fixture',
              'data': {
                'professionalId': 'professional-free-fixture',
                'planId': 'basic',
                'isActive': false,
              },
            }),
            200,
          );
        });
        final api = StoreCheckoutApi(
          baseUrl: 'https://payments.example.invalid',
          client: client,
        );

        final result = await api.submitFreeRegistration(
          _freeRequest(),
          serverQuote: _freeQuote(),
        );

        expect(calls, <String>['/createPaymentIntent', '/confirmPayment']);
        expect(createPayload['planId'], 'basic');
        expect(createPayload['registrationData'], <String, dynamic>{
          'address': '10 rue Test',
          'description': 'Description de test',
        });
        for (final forbiddenKey in <String>[
          'amount',
          'price',
          'currency',
          'store',
        ]) {
          expect(createPayload.containsKey(forbiddenKey), isFalse);
        }
        expect(confirmPayload, <String, dynamic>{
          'confirmationToken': 'signed.free.fixture',
        });
        expect(result.checkout.checkoutId, 'checkout-free-fixture');
        expect(result.confirmation.professionalId, 'professional-free-fixture');
      },
    );

    test('ne reconfirme pas un checkout gratuit déjà finalisé', () async {
      var requestCount = 0;
      final api = StoreCheckoutApi(
        baseUrl: 'https://payments.example.invalid',
        client: MockClient((request) async {
          requestCount += 1;
          expect(request.url.path, '/createPaymentIntent');
          return http.Response(
            jsonEncode({
              'success': true,
              'requires_payment': false,
              'already_finalized': true,
              'professional_id': 'professional-existing-fixture',
              'checkout_id': 'checkout-free-existing',
              'amount': 0,
              'currency': 'cad',
            }),
            200,
          );
        }),
      );

      final result = await api.submitFreeRegistration(
        _freeRequest(),
        serverQuote: _freeQuote(),
      );

      expect(requestCount, 1);
      expect(result.confirmation.idempotent, isTrue);
      expect(
        result.confirmation.professionalId,
        'professional-existing-fixture',
      );
    });

    test('rejoue une seule fois une confirmation gratuite après une erreur serveur transitoire', () async {
      var confirmAttempts = 0;
      final calls = <String>[];
      final api = StoreCheckoutApi(
        baseUrl: 'https://payments.example.invalid',
        client: MockClient((request) async {
          calls.add(request.url.path);
          if (request.url.path == '/createPaymentIntent') {
            return http.Response(
              jsonEncode({
                'success': true,
                'requires_payment': false,
                'confirmation_token': 'signed.free.retry',
                'checkout_id': 'checkout-free-retry',
                'amount': 0,
                'currency': 'cad',
              }),
              200,
            );
          }

          expect(request.url.path, '/confirmPayment');
          confirmAttempts += 1;
          if (confirmAttempts == 1) {
            return http.Response(
              jsonEncode({
                'success': false,
                'code': 'RUNTIME_UNAVAILABLE',
                'error': 'Temporary failure.',
              }),
              503,
            );
          }
          return http.Response(
            jsonEncode({
              'success': true,
              'idempotent': true,
              'status': 'pending_review',
              'checkout_id': 'checkout-free-retry',
              'data': {
                'professionalId': 'professional-free-retry',
                'planId': 'basic',
                'isActive': false,
              },
            }),
            200,
          );
        }),
      );

      final result = await api.submitFreeRegistration(
        _freeRequest(),
        serverQuote: _freeQuote(),
      );

      expect(calls, <String>[
        '/createPaymentIntent',
        '/confirmPayment',
        '/confirmPayment',
      ]);
      expect(result.confirmation.idempotent, isTrue);
      expect(result.confirmation.professionalId, 'professional-free-retry');
    });
  });

  group('StorePurchaseService', () {
    late _FakeStorePurchaseGateway gateway;
    final services = <StorePurchaseService>[];

    setUp(() {
      gateway = _FakeStorePurchaseGateway(products: _storeProducts());
    });

    tearDown(() async {
      for (final service in services) {
        await service.dispose();
      }
      await gateway.close();
      services.clear();
    });

    StorePurchaseService buildService(
      http.Client client, {
      List<String>? callOrder,
      StorePlatform store = StorePlatform.appStore,
    }) {
      gateway.callOrder = callOrder;
      final service = StorePurchaseService(
        gateway: gateway,
        api: StoreCheckoutApi(
          baseUrl: 'https://payments.example.invalid',
          client: client,
        ),
        store: store,
      );
      services.add(service);
      return service;
    }

    test('charge les prix localisés pour les deux produits attendus', () async {
      final service = buildService(_unexpectedHttpClient());

      final products = await service.loadProducts();

      expect(gateway.queriedProductIds, StoreProductIds.all);
      expect(products['premium']?.localizedPrice, '49,99 \$ CA');
      expect(products['professional']?.localizedPrice, '119,99 \$ CA');
      expect(products['premium']?.productId, StoreProductIds.premiumAnnual);
    });

    test(
      'refuse un catalogue store auquel il manque un produit payant',
      () async {
        await gateway.close();
        gateway = _FakeStorePurchaseGateway(
          products: <StoreProductOffer>[_storeProducts().first],
        );
        final service = buildService(_unexpectedHttpClient());

        expect(
          service.loadProducts(),
          throwsA(
            isA<StorePurchaseException>().having(
              (error) => error.code,
              'code',
              'STORE_PRODUCTS_INCOMPLETE',
            ),
          ),
        );
      },
    );

    test('refuse plusieurs offres pour un même produit annuel v1', () async {
      await gateway.close();
      gateway = _FakeStorePurchaseGateway(
        products: <StoreProductOffer>[
          ..._storeProducts(),
          _storeProducts().first,
        ],
      );
      final service = buildService(_unexpectedHttpClient());

      await expectLater(
        service.loadProducts(),
        throwsA(
          isA<StorePurchaseException>().having(
            (error) => error.code,
            'code',
            'AMBIGUOUS_STORE_PRODUCT_OFFER',
          ),
        ),
      );
    });

    test('crée le checkout sans prix client et transmet le jeton de compte au store', () async {
      late Map<String, dynamic> createPayload;
      final client = MockClient((request) async {
        expect(request.url.path, '/createStoreCheckout');
        createPayload = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(
          jsonEncode({
            'success': true,
            'checkout_id': 'chk_store_123',
            'product_id': StoreProductIds.premiumAnnual,
            'account_token': '6ba7b810-9dad-11d1-80b4-00c04fd430c8',
          }),
          200,
        );
      });
      final service = buildService(client);
      await service.loadProducts();

      await service.startPurchase(_request());

      expect(createPayload['store'], 'app_store');
      expect(createPayload['planId'], 'premium');
      expect(createPayload['professionalId'], 'temp_registration_12345');
      expect(createPayload.containsKey('amount'), isFalse);
      expect(createPayload.containsKey('currency'), isFalse);
      expect(gateway.boughtProduct?.productId, StoreProductIds.premiumAnnual);
      expect(
        gateway.applicationUserName,
        '6ba7b810-9dad-11d1-80b4-00c04fd430c8',
      );
      expect(gateway.ownedPurchaseQueryCount, 0);
      expect(gateway.subscriptionChange, isNull);
    });

    test(
      'Google Play remplace Premium par Professional avec prorata immédiat',
      () async {
        gateway.ownedPurchases = <StorePurchaseEvent>[
          _ownedPurchase(StoreProductIds.premiumAnnual),
        ];
        final calls = <String>[];
        final service = buildService(
          MockClient((request) async {
            calls.add(request.url.path);
            if (request.url.path == '/createStoreCheckout') {
              return _checkoutResponse(
                productId: StoreProductIds.professionalAnnual,
              );
            }
            expect(request.url.path, '/confirmStorePurchase');
            return http.Response(
              jsonEncode({
                'success': true,
                'checkout_id': 'chk_store_123',
                'idempotent': false,
                'complete_purchase': true,
                'status': 'pending_review',
                'data': {
                  'professionalId': 'professional-fixture',
                  'planId': 'professional',
                  'isActive': false,
                },
              }),
              200,
            );
          }),
          store: StorePlatform.googlePlay,
        );
        await service.loadProducts();

        await service.startPurchase(_request(planId: 'professional'));

        expect(gateway.ownedPurchaseQueryCount, 1);
        expect(
          gateway.boughtProduct?.productId,
          StoreProductIds.professionalAnnual,
        );
        expect(
          gateway.subscriptionChange?.oldPurchase.productId,
          StoreProductIds.premiumAnnual,
        );
        expect(
          gateway.subscriptionChange?.replacementMode,
          StoreSubscriptionReplacementMode.withTimeProration,
        );

        final purchased = service.updates.firstWhere(
          (update) => update.status == StorePurchaseStatus.purchased,
        );
        final immediateEvent = StorePurchaseEvent(
          status: StorePurchaseEventStatus.purchased,
          productId: StoreProductIds.professionalAnnual,
          purchaseId: 'immediate-upgrade-order-fixture',
          verificationData: 'immediate-upgrade-token-fixture',
          pendingCompletePurchase: true,
          nativePurchase: const _NativePurchase(),
        );
        gateway.emit(immediateEvent);
        final result = await purchased;

        expect(calls, <String>[
          '/createStoreCheckout',
          '/confirmStorePurchase',
        ]);
        expect(result.confirmation?.data?.planId, 'professional');
        expect(result.confirmation?.data?.pendingPlanId, isNull);
        expect(gateway.completedPurchases, <StorePurchaseEvent>[
          immediateEvent,
        ]);
      },
    );

    test('Google Play rattache le nouveau jeton différé de l’ancien produit au checkout Premium', () async {
      gateway.ownedPurchases = <StorePurchaseEvent>[
        _ownedPurchase(StoreProductIds.professionalAnnual),
      ];
      final calls = <String>[];
      late Map<String, dynamic> confirmPayload;
      final service = buildService(
        MockClient((request) async {
          calls.add(request.url.path);
          if (request.url.path == '/createStoreCheckout') {
            return _checkoutResponse();
          }
          expect(request.url.path, '/confirmStorePurchase');
          confirmPayload = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response(
            jsonEncode({
              'success': true,
              'checkout_id': 'chk_store_123',
              'idempotent': false,
              'complete_purchase': true,
              'status': 'pending_review',
              'data': {
                'professionalId': 'professional-fixture',
                'planId': 'professional',
                'pendingPlanId': 'premium',
                'isActive': false,
              },
            }),
            200,
          );
        }),
        store: StorePlatform.googlePlay,
      );
      await service.loadProducts();

      await service.startPurchase(_request());

      expect(gateway.ownedPurchaseQueryCount, 1);
      expect(gateway.boughtProduct?.productId, StoreProductIds.premiumAnnual);
      expect(
        gateway.subscriptionChange?.oldPurchase.productId,
        StoreProductIds.professionalAnnual,
      );
      expect(
        gateway.subscriptionChange?.replacementMode,
        StoreSubscriptionReplacementMode.deferred,
      );

      final purchased = service.updates.firstWhere(
        (update) => update.status == StorePurchaseStatus.purchased,
      );
      final deferredEvent = StorePurchaseEvent(
        status: StorePurchaseEventStatus.purchased,
        productId: StoreProductIds.professionalAnnual,
        purchaseId: 'deferred-order-fixture',
        verificationData: 'new-deferred-purchase-token-fixture',
        pendingCompletePurchase: true,
        nativePurchase: const _NativePurchase(),
      );
      gateway.emit(deferredEvent);
      final result = await purchased;

      expect(calls, <String>['/createStoreCheckout', '/confirmStorePurchase']);
      expect(confirmPayload['checkoutId'], 'chk_store_123');
      expect(confirmPayload['productId'], StoreProductIds.premiumAnnual);
      expect(
        confirmPayload['verificationData'],
        'new-deferred-purchase-token-fixture',
      );
      expect(result.planId, 'premium');
      expect(result.productId, StoreProductIds.premiumAnnual);
      expect(result.confirmation?.data?.planId, 'professional');
      expect(result.confirmation?.data?.pendingPlanId, 'premium');
      expect(gateway.completedPurchases, <StorePurchaseEvent>[deferredEvent]);
    });

    test('Google Play conserve le succès différé face aux terminaux tardifs du même lot', () async {
      gateway.ownedPurchases = <StorePurchaseEvent>[
        _ownedPurchase(StoreProductIds.professionalAnnual),
      ];
      final service = buildService(
        MockClient((request) async {
          if (request.url.path == '/createStoreCheckout') {
            return _checkoutResponse();
          }
          expect(request.url.path, '/confirmStorePurchase');
          return http.Response(
            jsonEncode({
              'success': true,
              'checkout_id': 'chk_store_123',
              'idempotent': false,
              'complete_purchase': true,
              'status': 'pending_review',
              'data': {
                'professionalId': 'professional-fixture',
                'planId': 'professional',
                'pendingPlanId': 'premium',
                'isActive': false,
              },
            }),
            200,
          );
        }),
        store: StorePlatform.googlePlay,
      );
      await service.loadProducts();
      await service.startPurchase(_request());

      final purchased = service.updates.firstWhere(
        (update) => update.status == StorePurchaseStatus.purchased,
      );
      const purchasedEvent = StorePurchaseEvent(
        status: StorePurchaseEventStatus.purchased,
        productId: StoreProductIds.professionalAnnual,
        purchaseId: 'deferred-order-fixture',
        verificationData: 'new-deferred-purchase-token-fixture',
        pendingCompletePurchase: true,
        nativePurchase: _NativePurchase(),
      );
      gateway.emitAll(<StorePurchaseEvent>[
        purchasedEvent,
        StorePurchaseEvent.canceled(
          productId: StoreProductIds.professionalAnnual,
        ),
        StorePurchaseEvent.failed(
          productId: StoreProductIds.professionalAnnual,
          code: 'late_deferred_store_error',
          message: 'Late deferred terminal event',
        ),
      ]);

      await purchased;
      final replay = await service.updates.first;

      expect(gateway.completedPurchases, <StorePurchaseEvent>[purchasedEvent]);
      expect(replay.status, StorePurchaseStatus.purchased);
      expect(replay.errorCode, isNull);
    });

    test('Google Play traite cancel/error de l’ancien produit différé puis autorise le retry', () async {
      gateway.ownedPurchases = <StorePurchaseEvent>[
        _ownedPurchase(StoreProductIds.professionalAnnual),
      ];
      var createCount = 0;
      final observed = <StorePurchaseUpdate>[];
      final service = buildService(
        MockClient((request) async {
          expect(request.url.path, '/createStoreCheckout');
          createCount += 1;
          return _checkoutResponse();
        }),
        store: StorePlatform.googlePlay,
      );
      final subscription = service.updates.listen(observed.add);
      await service.loadProducts();
      await service.startPurchase(_request());

      final canceled = service.updates.firstWhere(
        (update) => update.status == StorePurchaseStatus.canceled,
      );
      final failed = service.updates.firstWhere(
        (update) => update.errorCode == 'deferred_store_error',
      );
      gateway.emitAll(<StorePurchaseEvent>[
        StorePurchaseEvent.canceled(
          productId: StoreProductIds.professionalAnnual,
        ),
        StorePurchaseEvent.failed(
          productId: StoreProductIds.professionalAnnual,
          code: 'deferred_store_error',
          message: 'Deferred change failed',
        ),
      ]);

      expect((await canceled).planId, 'premium');
      expect((await failed).planId, 'premium');
      expect(
        observed.where(
          (update) => update.errorCode == 'STORE_PURCHASE_CHECKOUT_MISMATCH',
        ),
        isEmpty,
      );

      await service.startPurchase(_request());
      expect(createCount, 2);
      expect(gateway.buyCallCount, 2);
      await subscription.cancel();
    });

    test(
      'Google Play garde le verrou sur pending de l’ancien produit différé',
      () async {
        gateway.ownedPurchases = <StorePurchaseEvent>[
          _ownedPurchase(StoreProductIds.professionalAnnual),
        ];
        final observed = <StorePurchaseUpdate>[];
        final service = buildService(
          MockClient((request) async {
            expect(request.url.path, '/createStoreCheckout');
            return _checkoutResponse();
          }),
          store: StorePlatform.googlePlay,
        );
        final subscription = service.updates.listen(observed.add);
        await service.loadProducts();
        await service.startPurchase(_request());

        final pending = service.updates.firstWhere(
          (update) => update.status == StorePurchaseStatus.pending,
        );
        gateway.emit(
          StorePurchaseEvent.pending(
            productId: StoreProductIds.professionalAnnual,
          ),
        );
        expect((await pending).planId, 'premium');
        await expectLater(
          service.startPurchase(_request()),
          throwsA(
            isA<StorePurchaseException>().having(
              (error) => error.code,
              'code',
              'STORE_PURCHASE_IN_PROGRESS',
            ),
          ),
        );
        expect(
          observed.where(
            (update) => update.errorCode == 'STORE_PURCHASE_CHECKOUT_MISMATCH',
          ),
          isEmpty,
        );
        expect(gateway.buyCallCount, 1);
        await subscription.cancel();
      },
    );

    test('Google Play refuse deux événements compatibles avec le même changement différé', () async {
      gateway.ownedPurchases = <StorePurchaseEvent>[
        _ownedPurchase(StoreProductIds.professionalAnnual),
      ];
      var requestCount = 0;
      final service = buildService(
        MockClient((request) async {
          requestCount += 1;
          expect(request.url.path, '/createStoreCheckout');
          return _checkoutResponse();
        }),
        store: StorePlatform.googlePlay,
      );
      await service.loadProducts();
      await service.startPurchase(_request());

      final failed = service.updates.firstWhere(
        (update) =>
            update.status == StorePurchaseStatus.error &&
            update.errorCode == 'STORE_SUBSCRIPTION_CHANGE_AMBIGUOUS',
      );
      gateway.emitAll(<StorePurchaseEvent>[
        const StorePurchaseEvent(
          status: StorePurchaseEventStatus.purchased,
          productId: StoreProductIds.professionalAnnual,
          purchaseId: 'deferred-old-product-event',
          verificationData: 'new-deferred-token-fixture',
          pendingCompletePurchase: true,
          nativePurchase: _NativePurchase(),
        ),
        const StorePurchaseEvent(
          status: StorePurchaseEventStatus.purchased,
          productId: StoreProductIds.premiumAnnual,
          purchaseId: 'deferred-target-product-event',
          verificationData: 'target-product-token-fixture',
          pendingCompletePurchase: true,
          nativePurchase: _NativePurchase(),
        ),
      ]);

      expect((await failed).planId, 'premium');
      expect(requestCount, 1);
      expect(gateway.completedPurchases, isEmpty);
    });

    test('Google Play ne rattache pas une relecture de l’ancien jeton au checkout différé', () async {
      gateway.ownedPurchases = <StorePurchaseEvent>[
        _ownedPurchase(StoreProductIds.professionalAnnual),
      ];
      var requestCount = 0;
      final service = buildService(
        MockClient((request) async {
          requestCount += 1;
          expect(request.url.path, '/createStoreCheckout');
          return _checkoutResponse();
        }),
        store: StorePlatform.googlePlay,
      );
      await service.loadProducts();
      await service.startPurchase(_request());

      final failed = service.updates.firstWhere(
        (update) =>
            update.status == StorePurchaseStatus.error &&
            update.errorCode == 'STORE_PURCHASE_CHECKOUT_MISMATCH',
      );
      gateway.emit(
        const StorePurchaseEvent(
          status: StorePurchaseEventStatus.purchased,
          productId: StoreProductIds.professionalAnnual,
          purchaseId: 'stale-old-product-event',
          verificationData: 'owned-verification-data',
          pendingCompletePurchase: true,
          nativePurchase: _NativePurchase(),
        ),
      );

      expect((await failed).planId, 'premium');
      expect(requestCount, 1);
      expect(gateway.completedPurchases, isEmpty);
    });

    test('Google Play n’acquitte pas un différé sans ancien plan actif et cible planifiée', () async {
      gateway.ownedPurchases = <StorePurchaseEvent>[
        _ownedPurchase(StoreProductIds.professionalAnnual),
      ];
      final service = buildService(
        MockClient((request) async {
          if (request.url.path == '/createStoreCheckout') {
            return _checkoutResponse();
          }
          expect(request.url.path, '/confirmStorePurchase');
          return http.Response(
            jsonEncode({
              'success': true,
              'checkout_id': 'chk_store_123',
              'idempotent': false,
              'complete_purchase': true,
              'status': 'pending_review',
              'data': {
                'professionalId': 'professional-fixture',
                'planId': 'premium',
                'isActive': false,
              },
            }),
            200,
          );
        }),
        store: StorePlatform.googlePlay,
      );
      await service.loadProducts();
      await service.startPurchase(_request());

      final failed = service.updates.firstWhere(
        (update) =>
            update.status == StorePurchaseStatus.error &&
            update.errorCode == 'INVALID_STORE_CONFIRMATION',
      );
      gateway.emit(
        const StorePurchaseEvent(
          status: StorePurchaseEventStatus.purchased,
          productId: StoreProductIds.professionalAnnual,
          purchaseId: 'deferred-invalid-contract-event',
          verificationData: 'new-invalid-contract-token-fixture',
          pendingCompletePurchase: true,
          nativePurchase: _NativePurchase(),
        ),
      );

      expect((await failed).planId, 'premium');
      expect(gateway.completedPurchases, isEmpty);
    });

    test(
      'Google Play refuse de racheter génériquement un forfait déjà possédé',
      () async {
        gateway.ownedPurchases = <StorePurchaseEvent>[
          _ownedPurchase(StoreProductIds.premiumAnnual),
        ];
        final service = buildService(
          _unexpectedHttpClient(),
          store: StorePlatform.googlePlay,
        );
        await service.loadProducts();

        await expectLater(
          service.startPurchase(_request()),
          throwsA(
            isA<StorePurchaseException>().having(
              (error) => error.code,
              'code',
              'STORE_SUBSCRIPTION_ALREADY_OWNED',
            ),
          ),
        );

        expect(gateway.boughtProduct, isNull);
        expect(gateway.subscriptionChange, isNull);
      },
    );

    test(
      'Google Play échoue fermé si un changement est déjà en attente',
      () async {
        gateway.ownedPurchases = <StorePurchaseEvent>[
          _ownedPurchase(
            StoreProductIds.professionalAnnual,
            status: StorePurchaseEventStatus.pending,
          ),
        ];
        final service = buildService(
          _unexpectedHttpClient(),
          store: StorePlatform.googlePlay,
        );
        await service.loadProducts();

        await expectLater(
          service.startPurchase(_request()),
          throwsA(
            isA<StorePurchaseException>().having(
              (error) => error.code,
              'code',
              'STORE_SUBSCRIPTION_CHANGE_PENDING',
            ),
          ),
        );

        expect(gateway.boughtProduct, isNull);
      },
    );

    test(
      'Google Play échoue fermé si les achats possédés sont indisponibles',
      () async {
        gateway.ownedPurchasesError = const StorePurchaseException(
          'STORE_OWNED_PURCHASES_UNAVAILABLE',
          'unavailable',
        );
        final service = buildService(
          _unexpectedHttpClient(),
          store: StorePlatform.googlePlay,
        );
        await service.loadProducts();

        await expectLater(
          service.startPurchase(_request()),
          throwsA(
            isA<StorePurchaseException>().having(
              (error) => error.code,
              'code',
              'STORE_OWNED_PURCHASES_UNAVAILABLE',
            ),
          ),
        );

        expect(gateway.boughtProduct, isNull);
        expect(gateway.subscriptionChange, isNull);
      },
    );

    test('restaure le droit sans relancer le store si le checkout est déjà finalisé', () async {
      gateway.restoreStarted = Completer<void>();
      gateway.restoreBlocker = Completer<void>();
      final service = buildService(
        MockClient((request) async {
          expect(request.url.path, '/createStoreCheckout');
          return http.Response(
            jsonEncode({
              'success': true,
              'checkout_id': 'chk_store_existing',
              'product_id': StoreProductIds.premiumAnnual,
              'account_token': '6ba7b810-9dad-11d1-80b4-00c04fd430c8',
              'already_finalized': true,
              'complete_purchase': true,
              'professional_id': 'professional-existing-fixture',
            }),
            200,
          );
        }),
      );
      await service.loadProducts();

      final finalizedPurchase = service.startPurchase(_request());
      await gateway.restoreStarted!.future;

      await expectLater(
        service.restorePurchase(planId: 'premium'),
        throwsA(
          isA<StorePurchaseException>().having(
            (error) => error.code,
            'code',
            'STORE_OPERATION_IN_PROGRESS',
          ),
        ),
      );
      await expectLater(
        service.startPurchase(_request()),
        throwsA(
          isA<StorePurchaseException>().having(
            (error) => error.code,
            'code',
            'STORE_PURCHASE_IN_PROGRESS',
          ),
        ),
      );
      gateway.restoreBlocker!.complete();
      await finalizedPurchase;

      expect(gateway.boughtProduct, isNull);
      expect(gateway.restoreWasCalled, isTrue);
    });

    test(
      'propage pending puis purchased et acquitte après confirmation',
      () async {
        final callOrder = <String>[];
        late Map<String, dynamic> confirmPayload;
        final client = _successfulCheckoutClient(
          onConfirm: (payload) {
            confirmPayload = payload;
            callOrder.add('confirm');
          },
        );
        final service = buildService(client, callOrder: callOrder);
        await service.loadProducts();
        await service.startPurchase(_request());

        final pending = service.updates.firstWhere(
          (update) => update.status == StorePurchaseStatus.pending,
        );
        gateway.emit(
          StorePurchaseEvent.pending(productId: StoreProductIds.premiumAnnual),
        );
        expect((await pending).status, StorePurchaseStatus.pending);
        expect(gateway.completedPurchases, isEmpty);
        await expectLater(
          service.startPurchase(_request()),
          throwsA(
            isA<StorePurchaseException>().having(
              (error) => error.code,
              'code',
              'STORE_PURCHASE_IN_PROGRESS',
            ),
          ),
        );

        final purchased = service.updates.firstWhere(
          (update) => update.status == StorePurchaseStatus.purchased,
        );
        final event = _purchaseEvent(StorePurchaseEventStatus.purchased);
        gateway.emit(event);
        final result = await purchased;

        expect(result.confirmation?.status, 'pending_review');
        expect(confirmPayload, {
          'checkoutId': 'chk_store_123',
          'store': 'app_store',
          'productId': StoreProductIds.premiumAnnual,
          'verificationData': 'server-verification-data',
          'purchaseId': 'purchase-123',
        });
        expect(gateway.completedPurchases, <StorePurchaseEvent>[event]);
        expect(callOrder, <String>['confirm', 'complete']);
      },
    );

    test('n’acquitte jamais un achat rejeté par le serveur', () async {
      final client = MockClient((request) async {
        if (request.url.path == '/createStoreCheckout') {
          return _checkoutResponse();
        }
        return http.Response(
          jsonEncode({
            'success': false,
            'code': 'INVALID_STORE_PURCHASE',
            'error': 'invalid',
          }),
          400,
        );
      });
      final service = buildService(client);
      await service.loadProducts();
      await service.startPurchase(_request());

      final failed = service.updates.firstWhere(
        (update) => update.status == StorePurchaseStatus.error,
      );
      gateway.emit(_purchaseEvent(StorePurchaseEventStatus.purchased));
      final result = await failed;

      expect(result.errorCode, 'INVALID_STORE_PURCHASE');
      expect(gateway.completedPurchases, isEmpty);
    });

    test(
      'n’acquitte pas si la confirmation refuse complete_purchase',
      () async {
        final client = MockClient((request) async {
          if (request.url.path == '/createStoreCheckout') {
            return _checkoutResponse();
          }
          expect(request.url.path, '/confirmStorePurchase');
          return http.Response(
            jsonEncode({
              'success': true,
              'checkout_id': 'chk_store_123',
              'idempotent': false,
              'complete_purchase': false,
              'status': 'pending_review',
              'data': {
                'professionalId': 'professional-fixture',
                'planId': 'premium',
                'isActive': false,
              },
            }),
            200,
          );
        });
        final service = buildService(client);
        await service.loadProducts();
        await service.startPurchase(_request());

        final failed = service.updates.firstWhere(
          (update) => update.status == StorePurchaseStatus.error,
        );
        gateway.emit(_purchaseEvent(StorePurchaseEventStatus.purchased));
        final result = await failed;

        expect(result.errorCode, 'INVALID_STORE_CONFIRMATION');
        expect(gateway.completedPurchases, isEmpty);
      },
    );

    test('Google Play confirme avec le jeton même sans purchaseId', () async {
      late Map<String, dynamic> confirmPayload;
      final service = buildService(
        _successfulCheckoutClient(
          onConfirm: (payload) => confirmPayload = payload,
        ),
        store: StorePlatform.googlePlay,
      );
      await service.loadProducts();
      await service.startPurchase(_request());
      final purchased = service.updates.firstWhere(
        (update) => update.status == StorePurchaseStatus.purchased,
      );
      final event = StorePurchaseEvent(
        status: StorePurchaseEventStatus.purchased,
        productId: StoreProductIds.premiumAnnual,
        verificationData: 'google-purchase-token-fixture',
        pendingCompletePurchase: true,
        nativePurchase: const _NativePurchase(),
      );

      gateway.emit(event);
      await purchased;

      expect(confirmPayload['store'], 'google_play');
      expect(
        confirmPayload['verificationData'],
        'google-purchase-token-fixture',
      );
      expect(confirmPayload.containsKey('purchaseId'), isFalse);
      expect(gateway.completedPurchases, <StorePurchaseEvent>[event]);
    });

    test('refuse un account_token qui n’est pas un UUID', () async {
      final service = buildService(
        MockClient((request) async {
          expect(request.url.path, '/createStoreCheckout');
          return http.Response(
            jsonEncode({
              'success': true,
              'checkout_id': 'chk_store_123',
              'product_id': StoreProductIds.premiumAnnual,
              'account_token': 'not-a-uuid',
            }),
            200,
          );
        }),
      );
      await service.loadProducts();

      await expectLater(
        service.startPurchase(_request()),
        throwsA(
          isA<StorePurchaseException>().having(
            (error) => error.code,
            'code',
            'INVALID_STORE_RESPONSE',
          ),
        ),
      );
      expect(gateway.boughtProduct, isNull);
    });

    test('rejoue uniquement le dernier état normalisé non sensible', () async {
      final service = buildService(
        _successfulCheckoutClient(onConfirm: (_) {}),
      );
      await service.loadProducts();
      await service.startPurchase(_request());
      final purchased = service.updates.firstWhere(
        (update) =>
            update.status == StorePurchaseStatus.purchased && !update.isReplay,
      );
      gateway.emit(_purchaseEvent(StorePurchaseEventStatus.purchased));
      await purchased;

      final replay = await service.updates.first;

      expect(replay.isReplay, isTrue);
      expect(replay.status, StorePurchaseStatus.purchased);
      expect(replay.planId, 'premium');
      expect(replay.productId, StoreProductIds.premiumAnnual);
      expect(replay.checkoutId, isNull);
      expect(replay.confirmation, isNull);
      expect(replay.errorMessage, isNull);
    });

    test(
      'traite tout le lot annulé/erreur puis autorise une nouvelle tentative',
      () async {
        var requestCount = 0;
        final client = MockClient((request) async {
          requestCount += 1;
          return _checkoutResponse();
        });
        final service = buildService(client);
        await service.loadProducts();
        await service.startPurchase(_request());
        expect(requestCount, 1);

        final canceled = service.updates.firstWhere(
          (update) => update.status == StorePurchaseStatus.canceled,
        );
        final failed = service.updates.firstWhere(
          (update) => update.errorCode == 'store_error',
        );
        gateway.emitAll(<StorePurchaseEvent>[
          StorePurchaseEvent.canceled(productId: StoreProductIds.premiumAnnual),
          StorePurchaseEvent.failed(
            productId: StoreProductIds.premiumAnnual,
            code: 'store_error',
            message: 'Store unavailable',
          ),
        ]);

        expect((await canceled).status, StorePurchaseStatus.canceled);
        expect((await failed).errorCode, 'store_error');
        expect(requestCount, 1);
        expect(gateway.completedPurchases, isEmpty);

        await service.startPurchase(_request());
        expect(requestCount, 2);
        expect(gateway.buyCallCount, 2);
      },
    );

    test(
      'un achat confirmé domine cancel/error tardifs du même lot store',
      () async {
        final service = buildService(
          _successfulCheckoutClient(onConfirm: (_) {}),
        );
        await service.loadProducts();
        await service.startPurchase(_request());

        final purchased = service.updates.firstWhere(
          (update) => update.status == StorePurchaseStatus.purchased,
        );
        final purchasedEvent = _purchaseEvent(
          StorePurchaseEventStatus.purchased,
        );
        gateway.emitAll(<StorePurchaseEvent>[
          purchasedEvent,
          StorePurchaseEvent.canceled(productId: StoreProductIds.premiumAnnual),
          StorePurchaseEvent.failed(
            productId: StoreProductIds.premiumAnnual,
            code: 'late_store_error',
            message: 'Late terminal event from the same store batch',
          ),
        ]);

        await purchased;
        final replay = await service.updates.first;

        expect(gateway.completedPurchases, <StorePurchaseEvent>[
          purchasedEvent,
        ]);
        expect(replay.status, StorePurchaseStatus.purchased);
        expect(replay.errorCode, isNull);
      },
    );

    test('une erreur store terminale libère seule le checkout', () async {
      final service = buildService(
        _successfulCheckoutClient(onConfirm: (_) {}),
      );
      await service.loadProducts();
      await service.startPurchase(_request());

      final failed = service.updates.firstWhere(
        (update) => update.errorCode == 'store_error',
      );
      gateway.emit(
        StorePurchaseEvent.failed(
          productId: StoreProductIds.premiumAnnual,
          code: 'store_error',
          message: 'Store unavailable',
        ),
      );
      await failed;

      await service.startPurchase(_request());
      expect(gateway.buyCallCount, 2);
    });

    test('expose une erreur si le store ne peut pas lancer l’achat', () async {
      final service = buildService(
        _successfulCheckoutClient(onConfirm: (_) {}),
      );
      await service.loadProducts();
      gateway.buyError = Exception('store launch failed');

      final failed = service.updates.firstWhere(
        (update) => update.status == StorePurchaseStatus.error,
      );
      await expectLater(
        service.startPurchase(_request()),
        throwsA(
          isA<StorePurchaseException>().having(
            (error) => error.code,
            'code',
            'STORE_PURCHASE_LAUNCH_FAILED',
          ),
        ),
      );

      expect((await failed).errorCode, 'STORE_PURCHASE_LAUNCH_FAILED');
      expect(gateway.completedPurchases, isEmpty);
    });

    test('refuse un second lancement sans écraser le checkout actif', () async {
      gateway.buyStarted = Completer<void>();
      gateway.buyBlocker = Completer<void>();
      final service = buildService(
        _successfulCheckoutClient(onConfirm: (_) {}),
      );
      await service.loadProducts();

      final firstLaunch = service.startPurchase(_request());
      await gateway.buyStarted!.future;

      await expectLater(
        service.startPurchase(_request(planId: 'professional')),
        throwsA(
          isA<StorePurchaseException>().having(
            (error) => error.code,
            'code',
            'STORE_PURCHASE_IN_PROGRESS',
          ),
        ),
      );
      await expectLater(
        service.restorePurchase(planId: 'premium'),
        throwsA(
          isA<StorePurchaseException>().having(
            (error) => error.code,
            'code',
            'STORE_OPERATION_IN_PROGRESS',
          ),
        ),
      );
      expect(gateway.buyCallCount, 1);

      gateway.buyBlocker!.complete();
      await firstLaunch;
      final purchased = service.updates.firstWhere(
        (update) => update.status == StorePurchaseStatus.purchased,
      );
      gateway.emit(_purchaseEvent(StorePurchaseEventStatus.purchased));
      final result = await purchased;

      expect(result.planId, 'premium');
      expect(result.productId, StoreProductIds.premiumAnnual);
      expect(gateway.completedPurchases, hasLength(1));
    });

    test(
      'libère le checkout si le store confirme ne pas avoir lancé l’achat',
      () async {
        final service = buildService(
          _successfulCheckoutClient(onConfirm: (_) {}),
        );
        await service.loadProducts();
        gateway.buyResult = false;

        await expectLater(
          service.startPurchase(_request()),
          throwsA(
            isA<StorePurchaseException>().having(
              (error) => error.code,
              'code',
              'STORE_PURCHASE_NOT_LAUNCHED',
            ),
          ),
        );

        gateway.buyResult = true;
        await service.startPurchase(_request());
        expect(gateway.buyCallCount, 2);
      },
    );

    test(
      'conserve un lancement incertain et rattache un achat store tardif',
      () async {
        final callOrder = <String>[];
        final service = buildService(
          _successfulCheckoutClient(onConfirm: (_) => callOrder.add('confirm')),
          callOrder: callOrder,
        );
        await service.loadProducts();
        gateway.buyError = Exception('native launch result unavailable');

        await expectLater(
          service.startPurchase(_request()),
          throwsA(
            isA<StorePurchaseException>().having(
              (error) => error.code,
              'code',
              'STORE_PURCHASE_LAUNCH_FAILED',
            ),
          ),
        );
        await expectLater(
          service.startPurchase(_request(planId: 'professional')),
          throwsA(
            isA<StorePurchaseException>().having(
              (error) => error.code,
              'code',
              'STORE_PURCHASE_IN_PROGRESS',
            ),
          ),
        );

        final purchased = service.updates.firstWhere(
          (update) => update.status == StorePurchaseStatus.purchased,
        );
        final latePurchase = _purchaseEvent(StorePurchaseEventStatus.purchased);
        gateway.emit(latePurchase);
        final result = await purchased;

        expect(result.planId, 'premium');
        expect(callOrder, <String>['confirm', 'complete']);
        expect(gateway.completedPurchases, <StorePurchaseEvent>[latePurchase]);
      },
    );

    test(
      'sérialise restauration/restauration et achat jusqu’à l’événement store',
      () async {
        gateway.restoreStarted = Completer<void>();
        gateway.restoreBlocker = Completer<void>();
        final service = buildService(
          MockClient((request) async {
            if (request.url.path == '/createStoreCheckout') {
              return _checkoutResponse();
            }
            expect(request.url.path, '/restoreStorePurchase');
            return _restoreResponse();
          }),
        );
        await service.loadProducts();

        final firstRestore = service.restorePurchase(planId: 'premium');
        await gateway.restoreStarted!.future;

        Future<void> expectOperationsBlocked() async {
          await expectLater(
            service.restorePurchase(planId: 'premium'),
            throwsA(
              isA<StorePurchaseException>().having(
                (error) => error.code,
                'code',
                'STORE_OPERATION_IN_PROGRESS',
              ),
            ),
          );
          await expectLater(
            service.startPurchase(_request()),
            throwsA(
              isA<StorePurchaseException>().having(
                (error) => error.code,
                'code',
                'STORE_PURCHASE_IN_PROGRESS',
              ),
            ),
          );
        }

        await expectOperationsBlocked();
        gateway.restoreBlocker!.complete();
        await firstRestore;
        await expectOperationsBlocked();
        expect(gateway.restoreCallCount, 1);
        expect(gateway.buyCallCount, 0);

        final restored = service.updates.firstWhere(
          (update) => update.status == StorePurchaseStatus.restored,
        );
        gateway.emit(_purchaseEvent(StorePurchaseEventStatus.restored));
        await restored;

        await service.startPurchase(_request());
        expect(gateway.buyCallCount, 1);
      },
    );

    test('reprend un purchased au redémarrage sans checkout actif', () async {
      final callOrder = <String>[];
      final service = buildService(
        MockClient((request) async {
          expect(request.url.path, '/restoreStorePurchase');
          callOrder.add('restore');
          return _restoreResponse();
        }),
        callOrder: callOrder,
      );
      await service.loadProducts();

      final recovered = service.updates.firstWhere(
        (update) => update.status == StorePurchaseStatus.restored,
      );
      final event = _purchaseEvent(StorePurchaseEventStatus.purchased);
      gateway.emit(event);
      final result = await recovered;

      expect(result.planId, 'premium');
      expect(result.confirmation?.professionalId, 'professional-fixture');
      expect(gateway.completedPurchases, <StorePurchaseEvent>[event]);
      expect(callOrder, <String>['restore', 'complete']);
    });

    test('Google Play restaure Premium différé depuis l’ancien produit Professional', () async {
      final observed = <StorePurchaseUpdate>[];
      final service = buildService(
        MockClient((request) async {
          expect(request.url.path, '/restoreStorePurchase');
          return _restoreResponse(
            planId: 'professional',
            pendingPlanId: 'premium',
          );
        }),
        store: StorePlatform.googlePlay,
      );
      final subscription = service.updates.listen(observed.add);
      await service.loadProducts();
      await service.restorePurchase(planId: 'premium');

      final restored = service.updates.firstWhere(
        (update) => update.status == StorePurchaseStatus.restored,
      );
      const deferredPurchase = StorePurchaseEvent(
        status: StorePurchaseEventStatus.restored,
        productId: StoreProductIds.professionalAnnual,
        purchaseId: 'deferred-restore-order',
        verificationData: 'deferred-restore-token',
        pendingCompletePurchase: true,
        nativePurchase: _NativePurchase(),
      );
      gateway.emit(deferredPurchase);
      final result = await restored;
      await Future<void>.delayed(Duration.zero);

      expect(result.planId, 'premium');
      expect(result.productId, StoreProductIds.professionalAnnual);
      expect(result.confirmation?.data?.planId, 'professional');
      expect(result.confirmation?.data?.pendingPlanId, 'premium');
      expect(gateway.completedPurchases, <StorePurchaseEvent>[
        deferredPurchase,
      ]);
      expect(
        observed.where(
          (update) => update.errorCode == 'NO_STORE_PURCHASE_FOUND',
        ),
        isEmpty,
      );
      await subscription.cancel();
    });

    test('Google Play restaure Professional actif tout en conservant Premium pending', () async {
      final service = buildService(
        MockClient((request) async {
          expect(request.url.path, '/restoreStorePurchase');
          return _restoreResponse(
            planId: 'professional',
            pendingPlanId: 'premium',
          );
        }),
        store: StorePlatform.googlePlay,
      );
      await service.loadProducts();
      await service.restorePurchase(planId: 'professional');

      final restored = service.updates.firstWhere(
        (update) => update.status == StorePurchaseStatus.restored,
      );
      const activeProfessional = StorePurchaseEvent(
        status: StorePurchaseEventStatus.restored,
        productId: StoreProductIds.professionalAnnual,
        purchaseId: 'active-professional-restore-order',
        verificationData: 'active-professional-restore-token',
        pendingCompletePurchase: true,
        nativePurchase: _NativePurchase(),
      );
      gateway.emit(activeProfessional);
      final result = await restored;

      expect(result.planId, 'professional');
      expect(result.productId, StoreProductIds.professionalAnnual);
      expect(result.confirmation?.data?.planId, 'professional');
      expect(result.confirmation?.data?.pendingPlanId, 'premium');
      expect(gateway.completedPurchases, <StorePurchaseEvent>[
        activeProfessional,
      ]);
    });

    test('Google Play refuse le vieux produit sans cible Premium différée confirmée', () async {
      final observed = <StorePurchaseUpdate>[];
      final service = buildService(
        MockClient((request) async {
          expect(request.url.path, '/restoreStorePurchase');
          return _restoreResponse(planId: 'professional');
        }),
        store: StorePlatform.googlePlay,
      );
      final subscription = service.updates.listen(observed.add);
      await service.loadProducts();
      await service.restorePurchase(planId: 'premium');

      final failed = service.updates.firstWhere(
        (update) => update.errorCode == 'INVALID_STORE_RESTORATION',
      );
      gateway.emit(
        const StorePurchaseEvent(
          status: StorePurchaseEventStatus.restored,
          productId: StoreProductIds.professionalAnnual,
          purchaseId: 'invalid-deferred-restore-order',
          verificationData: 'invalid-deferred-restore-token',
          pendingCompletePurchase: true,
          nativePurchase: _NativePurchase(),
        ),
      );
      await failed;
      await Future<void>.delayed(Duration.zero);

      expect(gateway.completedPurchases, isEmpty);
      expect(
        observed.where(
          (update) => update.errorCode == 'NO_STORE_PURCHASE_FOUND',
        ),
        isEmpty,
      );
      await subscription.cancel();
    });

    test(
      'checkout déjà finalisé restaure aussi le downgrade Google différé',
      () async {
        gateway.ownedPurchases = <StorePurchaseEvent>[
          _ownedPurchase(StoreProductIds.professionalAnnual),
        ];
        final observed = <StorePurchaseUpdate>[];
        final service = buildService(
          MockClient((request) async {
            if (request.url.path == '/createStoreCheckout') {
              return http.Response(
                jsonEncode({
                  'success': true,
                  'checkout_id': 'chk_store_existing_deferred',
                  'product_id': StoreProductIds.premiumAnnual,
                  'account_token': '6ba7b810-9dad-11d1-80b4-00c04fd430c8',
                  'already_finalized': true,
                  'complete_purchase': true,
                  'professional_id': 'professional-existing-fixture',
                }),
                200,
              );
            }
            expect(request.url.path, '/restoreStorePurchase');
            return _restoreResponse(
              planId: 'professional',
              pendingPlanId: 'premium',
              checkoutId: 'chk_store_existing_deferred',
            );
          }),
          store: StorePlatform.googlePlay,
        );
        final subscription = service.updates.listen(observed.add);
        await service.loadProducts();

        await service.startPurchase(_request());
        expect(gateway.restoreWasCalled, isTrue);
        expect(gateway.buyCallCount, 0);

        final restored = service.updates.firstWhere(
          (update) => update.status == StorePurchaseStatus.restored,
        );
        const deferredPurchase = StorePurchaseEvent(
          status: StorePurchaseEventStatus.restored,
          productId: StoreProductIds.professionalAnnual,
          purchaseId: 'finalized-deferred-restore-order',
          verificationData: 'finalized-deferred-restore-token',
          pendingCompletePurchase: true,
          nativePurchase: _NativePurchase(),
        );
        gateway.emit(deferredPurchase);
        final result = await restored;
        await Future<void>.delayed(Duration.zero);

        expect(result.planId, 'premium');
        expect(result.confirmation?.data?.planId, 'professional');
        expect(result.confirmation?.data?.pendingPlanId, 'premium');
        expect(gateway.completedPurchases, <StorePurchaseEvent>[
          deferredPurchase,
        ]);
        expect(
          observed.where(
            (update) => update.errorCode == 'NO_STORE_PURCHASE_FOUND',
          ),
          isEmpty,
        );
        await subscription.cancel();
      },
    );

    test(
      'restaure inter-appareils sans créer de checkout puis acquitte',
      () async {
        final callOrder = <String>[];
        late Map<String, dynamic> restorePayload;
        var requestCount = 0;
        final service = buildService(
          MockClient((request) async {
            requestCount += 1;
            expect(request.url.path, '/restoreStorePurchase');
            restorePayload = jsonDecode(request.body) as Map<String, dynamic>;
            callOrder.add('restore');
            return _restoreResponse();
          }),
          callOrder: callOrder,
        );
        await service.loadProducts();

        await service.restorePurchase(planId: 'premium');
        expect(gateway.restoreWasCalled, isTrue);

        final restored = service.updates.firstWhere(
          (update) => update.status == StorePurchaseStatus.restored,
        );
        final event = _purchaseEvent(StorePurchaseEventStatus.restored);
        gateway.emit(event);
        final result = await restored;

        expect(requestCount, 1);
        expect(restorePayload, <String, dynamic>{
          'store': 'app_store',
          'productId': StoreProductIds.premiumAnnual,
          'verificationData': 'server-verification-data',
          'purchaseId': 'purchase-123',
        });
        expect(result.wasRestored, isTrue);
        expect(result.checkoutId, 'chk_store_123');
        expect(result.confirmation?.professionalId, 'professional-fixture');
        expect(gateway.completedPurchases, <StorePurchaseEvent>[event]);
        expect(callOrder, <String>['restore', 'complete']);
      },
    );

    test('omet purchaseId absent lors d’une restauration', () async {
      late Map<String, dynamic> restorePayload;
      final service = buildService(
        MockClient((request) async {
          expect(request.url.path, '/restoreStorePurchase');
          restorePayload = jsonDecode(request.body) as Map<String, dynamic>;
          return _restoreResponse();
        }),
      );
      await service.loadProducts();
      await service.restorePurchase(planId: 'premium');

      final restored = service.updates.firstWhere(
        (update) => update.status == StorePurchaseStatus.restored,
      );
      final event = StorePurchaseEvent(
        status: StorePurchaseEventStatus.restored,
        productId: StoreProductIds.premiumAnnual,
        verificationData: 'server-verification-data',
        pendingCompletePurchase: true,
        nativePurchase: const _NativePurchase(),
      );
      gateway.emit(event);
      await restored;

      expect(restorePayload.containsKey('purchaseId'), isFalse);
      expect(gateway.completedPurchases, <StorePurchaseEvent>[event]);
    });

    test('n’acquitte pas si le serveur refuse complete_purchase', () async {
      final service = buildService(
        MockClient((request) async {
          expect(request.url.path, '/restoreStorePurchase');
          return _restoreResponse(completePurchase: false);
        }),
      );
      await service.loadProducts();
      await service.restorePurchase(planId: 'premium');

      final failed = service.updates.firstWhere(
        (update) => update.status == StorePurchaseStatus.error,
      );
      gateway.emit(_purchaseEvent(StorePurchaseEventStatus.restored));

      expect((await failed).errorCode, 'INVALID_STORE_RESTORATION');
      expect(gateway.completedPurchases, isEmpty);
    });

    test(
      'n’acquitte pas une restauration rattachée à un autre forfait',
      () async {
        final callOrder = <String>[];
        final service = buildService(
          MockClient((request) async {
            expect(request.url.path, '/restoreStorePurchase');
            return _restoreResponse(planId: 'professional');
          }),
          callOrder: callOrder,
        );
        await service.loadProducts();
        await service.restorePurchase(planId: 'premium');

        final failed = service.updates.firstWhere(
          (update) => update.status == StorePurchaseStatus.error,
        );
        gateway.emit(_purchaseEvent(StorePurchaseEventStatus.restored));

        expect((await failed).errorCode, 'INVALID_STORE_RESTORATION');
        expect(gateway.completedPurchases, isEmpty);
        expect(callOrder, isEmpty);
      },
    );
  });
}

StorePurchaseRequest _request({String planId = 'premium'}) =>
    StorePurchaseRequest(
      planId: planId,
      professionalId: 'temp_registration_12345',
      email: 'qa@example.ca',
      businessName: 'Entreprise QA',
      categoryId: 'services',
      ville: 'Montréal',
      phone: '5145550101',
      registrationData: <String, dynamic>{
        'address': '10 rue Test',
        'description': 'Description de test',
      },
    );

StorePurchaseRequest _freeRequest() => const StorePurchaseRequest(
  planId: 'basic',
  professionalId: 'temp_registration_free',
  email: 'qa@example.ca',
  businessName: 'Entreprise QA',
  categoryId: 'services',
  ville: 'Montréal',
  phone: '5145550101',
  registrationData: <String, dynamic>{
    'address': '10 rue Test',
    'description': 'Description de test',
  },
  maxGalleryImages: 0,
);

PaymentPlanQuote _freeQuote() {
  return PaymentPlanQuote.fromJson(
    _catalogJson()['plans']!.cast<Map<String, dynamic>>().first,
  );
}

Map<String, dynamic> _catalogJson() => <String, dynamic>{
  'success': true,
  'version': 2,
  'plans': <Map<String, dynamic>>[
    <String, dynamic>{
      'id': 'basic',
      'amount': 0,
      'currency': 'cad',
      'requires_payment': false,
      'duration_days': 365,
      'label': <String, String>{'fr': 'Basique', 'en': 'Basic'},
      'features': <String, List<String>>{
        'fr': <String>['Profil'],
        'en': <String>['Profile'],
      },
      'capabilities': <String, dynamic>{
        'profile_image': true,
        'gallery_max': 0,
        'coupon': false,
        'featured': false,
      },
    },
    <String, dynamic>{
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
      'label': <String, String>{'fr': 'Premium', 'en': 'Premium'},
      'features': <String, List<String>>{
        'fr': <String>['Galerie'],
        'en': <String>['Gallery'],
      },
      'capabilities': <String, dynamic>{
        'profile_image': true,
        'gallery_max': 5,
        'coupon': true,
        'featured': false,
      },
    },
  ],
};

Map<String, dynamic> _catalogJsonWithPaidPlan(Map<String, dynamic> overrides) {
  final catalog = _catalogJson();
  final plans = (catalog['plans']! as List<Map<String, dynamic>>)
      .map(Map<String, dynamic>.from)
      .toList();
  plans[1] = <String, dynamic>{...plans[1], ...overrides};
  return <String, dynamic>{...catalog, 'plans': plans};
}

List<StoreProductOffer> _storeProducts() => const <StoreProductOffer>[
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

StorePurchaseEvent _purchaseEvent(StorePurchaseEventStatus status) {
  return StorePurchaseEvent(
    status: status,
    productId: StoreProductIds.premiumAnnual,
    purchaseId: 'purchase-123',
    verificationData: 'server-verification-data',
    pendingCompletePurchase: true,
    nativePurchase: const _NativePurchase(),
  );
}

StorePurchaseEvent _ownedPurchase(
  String productId, {
  StorePurchaseEventStatus status = StorePurchaseEventStatus.purchased,
}) {
  return StorePurchaseEvent(
    status: status,
    productId: productId,
    purchaseId: 'owned-purchase-${productId.hashCode}',
    verificationData: 'owned-verification-data',
    nativePurchase: const _NativePurchase(),
  );
}

http.Client _successfulCheckoutClient({
  required void Function(Map<String, dynamic>) onConfirm,
}) {
  return MockClient((request) async {
    if (request.url.path == '/createStoreCheckout') return _checkoutResponse();
    expect(request.url.path, '/confirmStorePurchase');
    final payload = jsonDecode(request.body) as Map<String, dynamic>;
    onConfirm(payload);
    return http.Response(
      jsonEncode({
        'success': true,
        'checkout_id': 'chk_store_123',
        'idempotent': false,
        'complete_purchase': true,
        'status': 'pending_review',
        'data': {
          'professionalId': 'professional-fixture',
          'planId': 'premium',
          'isActive': false,
        },
      }),
      200,
    );
  });
}

http.Response _checkoutResponse({
  String productId = StoreProductIds.premiumAnnual,
}) => http.Response(
  jsonEncode({
    'success': true,
    'checkout_id': 'chk_store_123',
    'product_id': productId,
    'account_token': '6ba7b810-9dad-11d1-80b4-00c04fd430c8',
  }),
  200,
);

http.Response _restoreResponse({
  bool completePurchase = true,
  String planId = 'premium',
  String? pendingPlanId,
  String checkoutId = 'chk_store_123',
}) => http.Response(
  jsonEncode({
    'success': true,
    'restored': true,
    'checkout_id': checkoutId,
    'idempotent': false,
    'complete_purchase': completePurchase,
    'status': 'pending_review',
    'data': {
      'professionalId': 'professional-fixture',
      'planId': planId,
      'pendingPlanId': ?pendingPlanId,
      'isActive': false,
    },
  }),
  200,
);

http.Client _unexpectedHttpClient() => MockClient((request) async {
  fail('Aucun appel HTTP attendu: ${request.url}');
});

final class _NativePurchase {
  const _NativePurchase();
}

final class _FakeStorePurchaseGateway
    implements StorePurchaseGateway, GooglePlaySubscriptionGateway {
  _FakeStorePurchaseGateway({required this.products});

  final List<StoreProductOffer> products;
  final StreamController<List<StorePurchaseEvent>> _controller =
      StreamController<List<StorePurchaseEvent>>.broadcast();

  Set<String> queriedProductIds = <String>{};
  StoreProductOffer? boughtProduct;
  String? applicationUserName;
  StoreSubscriptionChange? subscriptionChange;
  List<StorePurchaseEvent> ownedPurchases = <StorePurchaseEvent>[];
  Object? ownedPurchasesError;
  int ownedPurchaseQueryCount = 0;
  bool restoreWasCalled = false;
  int restoreCallCount = 0;
  Completer<void>? restoreStarted;
  Completer<void>? restoreBlocker;
  final List<StorePurchaseEvent> completedPurchases = <StorePurchaseEvent>[];
  List<String>? callOrder;
  Object? buyError;
  bool buyResult = true;
  int buyCallCount = 0;
  Completer<void>? buyStarted;
  Completer<void>? buyBlocker;

  @override
  Stream<List<StorePurchaseEvent>> get purchaseStream => _controller.stream;

  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<List<StoreProductOffer>> queryProducts(Set<String> productIds) async {
    queriedProductIds = productIds;
    return products;
  }

  @override
  Future<List<StorePurchaseEvent>> queryOwnedPurchases() async {
    ownedPurchaseQueryCount += 1;
    final error = ownedPurchasesError;
    if (error != null) throw error;
    return ownedPurchases;
  }

  @override
  Future<bool> buyNonConsumable(
    StoreProductOffer product, {
    required String applicationUserName,
  }) => _buy(product, applicationUserName: applicationUserName);

  @override
  Future<bool> changeSubscription(
    StoreProductOffer product, {
    required String applicationUserName,
    required StoreSubscriptionChange subscriptionChange,
  }) => _buy(
    product,
    applicationUserName: applicationUserName,
    subscriptionChange: subscriptionChange,
  );

  Future<bool> _buy(
    StoreProductOffer product, {
    required String applicationUserName,
    StoreSubscriptionChange? subscriptionChange,
  }) async {
    buyCallCount += 1;
    final started = buyStarted;
    if (started != null && !started.isCompleted) started.complete();
    final blocker = buyBlocker;
    if (blocker != null) await blocker.future;
    final error = buyError;
    if (error != null) throw error;
    boughtProduct = product;
    this.applicationUserName = applicationUserName;
    this.subscriptionChange = subscriptionChange;
    return buyResult;
  }

  @override
  Future<void> restorePurchases() async {
    restoreWasCalled = true;
    restoreCallCount += 1;
    final started = restoreStarted;
    if (started != null && !started.isCompleted) started.complete();
    final blocker = restoreBlocker;
    if (blocker != null) await blocker.future;
  }

  @override
  Future<void> completePurchase(StorePurchaseEvent purchase) async {
    callOrder?.add('complete');
    completedPurchases.add(purchase);
  }

  void emit(StorePurchaseEvent purchase) {
    _controller.add(<StorePurchaseEvent>[purchase]);
  }

  void emitAll(List<StorePurchaseEvent> purchases) {
    _controller.add(List<StorePurchaseEvent>.unmodifiable(purchases));
  }

  Future<void> close() => _controller.close();
}
