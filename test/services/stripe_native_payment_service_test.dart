import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:index_canada/services/stripe_native_payment_service.dart';

void main() {
  group('PaymentPlatformSupportPolicy', () {
    test('autorise le forfait gratuit sur le Web sans PaymentSheet', () {
      final decision = PaymentPlatformSupportPolicy.evaluate(
        requiresPayment: false,
        isWeb: true,
      );

      expect(decision, PaymentPlatformSupportDecision.supported);
      expect(decision.isSupported, isTrue);
      expect(decision.errorCode, isNull);
    });

    test('bloque un forfait payant sur le Web avant le checkout', () {
      final decision = PaymentPlatformSupportPolicy.evaluate(
        requiresPayment: true,
        isWeb: true,
      );

      expect(
        decision,
        PaymentPlatformSupportDecision.paidPaymentSheetUnavailableOnWeb,
      );
      expect(decision.isSupported, isFalse);
      expect(decision.errorCode, 'PAYMENT_PLATFORM_UNSUPPORTED');
    });

    test('autorise un forfait payant sur une plateforme native', () {
      final decision = PaymentPlatformSupportPolicy.evaluate(
        requiresPayment: true,
        isWeb: false,
      );

      expect(decision, PaymentPlatformSupportDecision.supported);
      expect(decision.isSupported, isTrue);
    });
  });

  group('StripePaymentApi', () {
    test('charge tout le catalogue v2 en un seul appel typé', () async {
      late http.Request capturedRequest;
      var requestCount = 0;
      final api = StripePaymentApi(
        baseUrl: 'https://payments.example.invalid',
        client: MockClient((request) async {
          requestCount += 1;
          capturedRequest = request;
          return http.Response(
            jsonEncode({
              'success': true,
              'version': 2,
              'plans': [
                {
                  'id': 'premium',
                  'amount': 4999,
                  'currency': 'cad',
                  'requires_payment': true,
                  'duration_days': 365,
                  'label': {'fr': 'Plan Premium', 'en': 'Premium Plan'},
                  'capabilities': {
                    'profile_image': true,
                    'gallery_max': 5,
                    'coupon': true,
                    'featured': false,
                  },
                  'features': {
                    'fr': ['Galerie de 5 photos'],
                    'en': ['Gallery of 5 photos'],
                  },
                },
              ],
            }),
            200,
          );
        }),
      );

      final catalog = await api.fetchPaymentPlans();
      final quote = catalog.requirePlan('premium');

      expect(capturedRequest.method, 'GET');
      expect(
        capturedRequest.url,
        Uri.parse('https://payments.example.invalid/paymentPlans'),
      );
      expect(quote.id, 'premium');
      expect(quote.amountCents, 4999);
      expect(quote.amount, 49.99);
      expect(quote.currency, 'cad');
      expect(quote.durationDays, 365);
      expect(catalog.version, 2);
      expect(requestCount, 1);
      expect(catalog.plans, hasLength(1));
      expect(quote.capabilities.galleryMax, 5);
      expect(quote.capabilities.coupon, isTrue);
      expect(() => catalog.plans.add(quote), throwsA(isA<UnsupportedError>()));
    });

    test('rejette les identifiants de forfait dupliqués', () async {
      final plan = {
        'id': 'premium',
        'amount': 4999,
        'currency': 'cad',
        'requires_payment': true,
        'duration_days': 365,
        'label': {'fr': 'Plan Premium', 'en': 'Premium Plan'},
        'capabilities': {
          'profile_image': true,
          'gallery_max': 5,
          'coupon': true,
          'featured': false,
        },
        'features': {
          'fr': ['Galerie de 5 photos'],
          'en': ['Gallery of 5 photos'],
        },
      };
      final api = StripePaymentApi(
        baseUrl: 'https://payments.example.invalid',
        client: MockClient((_) async {
          return http.Response(
            jsonEncode({
              'success': true,
              'version': 2,
              'plans': [plan, plan],
            }),
            200,
          );
        }),
      );

      await expectLater(
        api.fetchPaymentPlans(),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejette des capacités de forfait non typées', () async {
      final api = StripePaymentApi(
        baseUrl: 'https://payments.example.invalid',
        client: MockClient((_) async {
          return http.Response(
            jsonEncode({
              'success': true,
              'version': 2,
              'plans': [
                {
                  'id': 'premium',
                  'amount': 4999,
                  'currency': 'cad',
                  'requires_payment': true,
                  'duration_days': 365,
                  'label': {'fr': 'Plan Premium', 'en': 'Premium Plan'},
                  'capabilities': {
                    'profile_image': true,
                    'gallery_max': '5',
                    'coupon': true,
                    'featured': false,
                  },
                  'features': {
                    'fr': ['Galerie de 5 photos'],
                    'en': ['Gallery of 5 photos'],
                  },
                },
              ],
            }),
            200,
          );
        }),
      );

      await expectLater(
        api.fetchPaymentPlans(),
        throwsA(isA<FormatException>()),
      );
    });

    test('refuse un catalogue d’une version contractuelle différente', () {
      expect(
        () => PaymentPlanCatalog.fromJson({
          'success': true,
          'version': 3,
          'plans': [
            {
              'id': 'premium',
              'amount': 4999,
              'currency': 'cad',
              'requires_payment': true,
              'duration_days': 365,
              'label': {'fr': 'Plan Premium', 'en': 'Premium Plan'},
              'capabilities': {
                'profile_image': true,
                'gallery_max': 5,
                'coupon': true,
                'featured': false,
              },
              'features': {
                'fr': ['Galerie de 5 photos'],
                'en': ['Gallery of 5 photos'],
              },
            },
          ],
        }),
        throwsA(isA<FormatException>()),
      );
    });

    test(
      'crée le checkout sans transmettre de prix contrôlé par le client',
      () async {
        late http.Request capturedRequest;
        late Map<String, dynamic> capturedPayload;
        final client = MockClient((request) async {
          capturedRequest = request;
          capturedPayload = jsonDecode(request.body) as Map<String, dynamic>;
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
        });
        final api = StripePaymentApi(
          baseUrl: 'https://payments.example.invalid///',
          client: client,
        );

        final session = await api.createCheckout(
          planId: 'basic',
          professionalId: 'professional-fixture',
          email: '  qa@example.invalid  ',
          businessName: '  Entreprise Test  ',
          categoryId: '  services  ',
          ville: '  Montréal  ',
          phone: '  5145550101  ',
          registrationData: const {'source': 'test'},
        );

        expect(
          capturedRequest.url,
          Uri.parse('https://payments.example.invalid/createPaymentIntent'),
        );
        expect(capturedRequest.method, 'POST');
        expect(capturedRequest.headers['Accept'], 'application/json');
        expect(
          capturedRequest.headers['Content-Type'],
          startsWith('application/json'),
        );
        expect(capturedPayload, {
          'planId': 'basic',
          'professionalId': 'professional-fixture',
          'email': 'qa@example.invalid',
          'businessName': 'Entreprise Test',
          'categoryId': 'services',
          'ville': 'Montréal',
          'phone': '5145550101',
          'registrationData': {'source': 'test'},
        });
        for (final forbiddenKey in [
          'amount',
          'price',
          'priceId',
          'unitAmount',
          'currency',
        ]) {
          expect(capturedPayload.containsKey(forbiddenKey), isFalse);
        }
        expect(session.requiresPayment, isFalse);
        expect(session.confirmationReference, 'signed.free.fixture');
        expect(session.checkoutId, 'checkout-free-fixture');
        expect(session.amountCents, 0);
        expect(session.currency, 'cad');
      },
    );

    test('envoie confirmationToken au endpoint de confirmation', () async {
      late http.Request capturedRequest;
      late Map<String, dynamic> capturedPayload;
      final client = MockClient((request) async {
        capturedRequest = request;
        capturedPayload = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(
          jsonEncode({
            'success': true,
            'idempotent': false,
            'status': 'active',
            'checkout_id': 'checkout-paid-fixture',
            'data': {
              'professionalId': 'professional-fixture',
              'planId': 'premium',
              'isActive': true,
            },
          }),
          200,
        );
      });
      final api = StripePaymentApi(
        baseUrl: 'https://payments.example.invalid',
        client: client,
      );

      final response = await api.confirmCheckout(
        confirmationToken: 'confirmation.signed.fixture',
      );

      expect(
        capturedRequest.url,
        Uri.parse('https://payments.example.invalid/confirmPayment'),
      );
      expect(capturedPayload, {
        'confirmationToken': 'confirmation.signed.fixture',
      });
      expect(response.success, isTrue);
      expect(response.status, 'active');
      expect(response.isActive, isTrue);
      expect(response.professionalId, 'professional-fixture');
    });

    test('rejette une réponse qui n’est pas un document JSON valide', () async {
      final api = StripePaymentApi(
        baseUrl: 'https://payments.example.invalid',
        client: MockClient((_) async => http.Response('{json-invalide', 200)),
      );

      await expectLater(
        api.confirmCheckout(confirmationToken: 'confirmation.fixture'),
        throwsA(isA<FormatException>()),
      );
    });

    test('propage le code métier et le statut d’une erreur HTTP', () async {
      final api = StripePaymentApi(
        baseUrl: 'https://payments.example.invalid',
        client: MockClient((_) async {
          return http.Response(
            jsonEncode({'success': false, 'code': 'PAYMENT_ALREADY_USED'}),
            409,
          );
        }),
      );

      await expectLater(
        api.confirmCheckout(confirmationToken: 'confirmation.fixture'),
        throwsA(
          isA<PaymentApiException>()
              .having(
                (exception) => exception.code,
                'code',
                'PAYMENT_ALREADY_USED',
              )
              .having((exception) => exception.statusCode, 'statusCode', 409),
        ),
      );
    });

    test(
      'conserve le statut HTTP quand la réponse 5xx n’est pas JSON',
      () async {
        final api = StripePaymentApi(
          baseUrl: 'https://payments.example.invalid',
          client: MockClient(
            (_) async => http.Response('<html>gateway unavailable</html>', 502),
          ),
        );

        await expectLater(
          api.confirmCheckout(confirmationToken: 'confirmation.fixture'),
          throwsA(
            isA<PaymentApiException>()
                .having((exception) => exception.code, 'code', 'REQUEST_FAILED')
                .having((exception) => exception.statusCode, 'statusCode', 502),
          ),
        );
      },
    );

    test('valide les images avant le premier appel HTTP', () async {
      var requestWasSent = false;
      final api = StripePaymentApi(
        baseUrl: 'https://payments.example.invalid',
        client: MockClient((_) async {
          requestWasSent = true;
          return http.Response('{}', 200);
        }),
      );

      await expectLater(
        api.createCheckout(
          planId: 'premium',
          professionalId: 'professional-fixture',
          email: 'qa@example.invalid',
          businessName: 'Entreprise Test',
          registrationData: const {'profileImageBase64': 'image-invalide'},
        ),
        throwsA(isA<RegistrationImageException>()),
      );
      expect(requestWasSent, isFalse);
    });

    test('applique la limite de galerie issue du devis serveur', () async {
      await expectLater(
        RegistrationPayloadPreparer.prepare(const {
          'galleryImagesBase64': ['image-1'],
        }, maxGalleryImages: 0),
        throwsA(
          isA<RegistrationImageException>().having(
            (exception) => exception.code,
            'code',
            'GALLERY_LIMIT_EXCEEDED',
          ),
        ),
      );
    });

    test('prépare et transmet les images avant de créer le checkout', () async {
      const imageBytes = <int>[
        137,
        80,
        78,
        71,
        13,
        10,
        26,
        10,
        0,
        0,
        0,
        13,
        73,
        72,
        68,
        82,
        0,
        0,
        0,
        1,
        0,
        0,
        0,
        1,
        8,
        4,
        0,
        0,
        0,
        181,
        28,
        12,
        2,
        0,
        0,
        0,
        11,
        73,
        68,
        65,
        84,
        120,
        218,
        99,
        100,
        248,
        15,
        0,
        1,
        5,
        1,
        1,
        39,
        24,
        227,
        102,
        0,
        0,
        0,
        0,
        73,
        69,
        78,
        68,
        174,
        66,
        96,
        130,
      ];
      final imageBase64 = base64Encode(imageBytes);
      late Map<String, dynamic> capturedPayload;
      final api = StripePaymentApi(
        baseUrl: 'https://payments.example.invalid',
        client: MockClient((request) async {
          capturedPayload = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response(
            jsonEncode({
              'success': true,
              'requires_payment': false,
              'confirmation_token': 'signed.free.fixture',
              'checkout_id': 'checkout-image-fixture',
              'amount': 0,
              'currency': 'cad',
            }),
            200,
          );
        }),
      );

      final session = await api.createCheckout(
        planId: 'basic',
        professionalId: 'professional-fixture',
        email: 'qa@example.invalid',
        businessName: 'Entreprise Test',
        registrationData: {
          'source': 'test',
          'profileImageBase64': 'data:image/png;base64,$imageBase64',
        },
      );

      expect(capturedPayload['registrationData'], {
        'source': 'test',
        'profileImageBase64': imageBase64,
      });
      expect(
        session.preparedRegistrationData['profileImageBase64'],
        imageBase64,
      );
    });
  });

  group('CheckoutSession', () {
    test('parse un forfait gratuit avec son jeton signé', () {
      final session = CheckoutSession.fromJson(const {
        'requires_payment': false,
        'confirmation_token': 'signed.free.fixture',
      });

      expect(session.requiresPayment, isFalse);
      expect(session.confirmationReference, 'signed.free.fixture');
      expect(session.clientSecret, isNull);
    });

    test('parse un paiement avec son client_secret Stripe', () {
      final session = CheckoutSession.fromJson(const {
        'requires_payment': true,
        'payment_intent_id': 'pi_fixture_reference_12345',
        'client_secret': 'client-secret-fixture',
        'customer_id': 'customer-fixture',
        'ephemeral_key': 'ephemeral-fixture',
        'checkout_id': 'checkout-paid-fixture',
        'amount': 4999,
        'currency': 'cad',
      });

      expect(session.requiresPayment, isTrue);
      expect(session.confirmationReference, 'pi_fixture_reference_12345');
      expect(session.clientSecret, 'client-secret-fixture');
      expect(session.customerId, 'customer-fixture');
      expect(session.ephemeralKey, 'ephemeral-fixture');
      expect(session.checkoutId, 'checkout-paid-fixture');
      expect(session.amountCents, 4999);
      expect(session.currency, 'cad');
    });

    test('parse un checkout payant déjà finalisé sans client_secret', () {
      final session = CheckoutSession.fromJson(const {
        'requires_payment': true,
        'already_finalized': true,
        'checkout_id': 'checkout-finalized-fixture',
        'professional_id': 'professional-finalized-fixture',
        'amount': 4999,
        'currency': 'cad',
      });

      expect(session.requiresPayment, isTrue);
      expect(session.alreadyFinalized, isTrue);
      expect(session.confirmationReference, 'checkout-finalized-fixture');
      expect(session.professionalId, 'professional-finalized-fixture');
      expect(session.clientSecret, isNull);
    });

    test('rejette les contrats incomplets ou de mauvais type', () {
      const invalidContracts = <Map<String, dynamic>>[
        {'requires_payment': false},
        {
          'requires_payment': 'false',
          'confirmation_token': 'confirmation.fixture',
        },
        {
          'requires_payment': true,
          'confirmation_token': 'confirmation.fixture',
        },
        {
          'requires_payment': true,
          'confirmation_token': 'confirmation.fixture',
          'client_secret': '   ',
        },
        {
          'requires_payment': true,
          'confirmation_token': 'confirmation.fixture',
          'client_secret': 'client-secret-fixture',
        },
        {
          'requires_payment': true,
          'already_finalized': true,
          'checkout_id': 'checkout-finalized-fixture',
        },
        {
          'requires_payment': false,
          'confirmation_token': 'confirmation.fixture',
          'amount': '4999',
        },
      ];

      for (final contract in invalidContracts) {
        expect(
          () => CheckoutSession.fromJson(contract),
          throwsA(isA<FormatException>()),
        );
      }
    });
  });

  group('PaymentConfirmation', () {
    test('construit le DTO d’un checkout déjà finalisé', () {
      final confirmation = PaymentConfirmation.finalized(
        professionalId: 'professional-finalized-fixture',
        planId: 'premium',
        isActive: true,
        status: 'active',
        checkoutId: 'checkout-finalized-fixture',
      );

      expect(confirmation.success, isTrue);
      expect(confirmation.idempotent, isTrue);
      expect(confirmation.status, 'active');
      expect(confirmation.isActive, isTrue);
      expect(confirmation.professionalId, 'professional-finalized-fixture');
      expect(confirmation.checkoutId, 'checkout-finalized-fixture');
    });

    test('parse le statut et les données de confirmation du backend', () {
      final confirmation = PaymentConfirmation.fromJson(const {
        'success': true,
        'idempotent': true,
        'status': 'pending_review',
        'checkout_id': 'checkout-free-fixture',
        'data': {
          'professionalId': 'professional-fixture',
          'planId': 'basic',
          'isActive': false,
        },
      });

      expect(confirmation.success, isTrue);
      expect(confirmation.status, 'pending_review');
      expect(confirmation.isActive, isFalse);
      expect(confirmation.professionalId, 'professional-fixture');
      expect(confirmation.data?.planId, 'basic');
      expect(confirmation.checkoutId, 'checkout-free-fixture');
      expect(confirmation.toJson()['checkout_id'], 'checkout-free-fixture');
    });

    test('rejette une confirmation réussie sans DTO complet', () {
      const invalidConfirmations = <Map<String, dynamic>>[
        {'success': true},
        {
          'success': true,
          'idempotent': false,
          'status': 'active',
          'data': {'professionalId': 'professional-fixture'},
        },
        {
          'success': true,
          'idempotent': false,
          'status': 'active',
          'data': {
            'professionalId': 'professional-fixture',
            'planId': 'premium',
            'isActive': 'true',
          },
        },
      ];

      for (final payload in invalidConfirmations) {
        expect(
          () => PaymentConfirmation.fromJson(payload),
          throwsA(isA<FormatException>()),
        );
      }
    });
  });
}
