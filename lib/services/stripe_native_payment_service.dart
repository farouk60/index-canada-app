import 'package:flutter/material.dart';
import 'package:flutter_stripe/flutter_stripe.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';
import '../utils/image_base64_utils.dart';

class StripeNativePaymentService {
  // Clé publique Stripe (côté client)
  static const String stripePublishableKey =
      'pk_test_51QWOLrHo8XXGFdDl69xQBpnYpWhHMeX4Irc6hDJx5OB3q3BeLcaB5x8U0UqZ2bQG6u3nCKjqRdVxSkVP0vhPDdyI00qJP1mQvO';

  // Configuration des prix Stripe (Price IDs de vos prix)
  static const Map<String, String> stripePriceIds = {
    'basic': 'price_1234567890_basic', // Remplacez par vos vrais Price IDs
    'premium': 'price_1234567890_premium', // Remplacez par vos vrais Price IDs
    'professional': 'price_1234567890_pro', // Remplacez par vos vrais Price IDs
  };

  // Prix pour affichage (doivent correspondre à ceux configurés dans Stripe)
  static const Map<String, double> planPrices = {
  'basic': 49.99,
  'premium': 69.99,
  'professional': 119.99,
  };

  /// Créer un Payment Intent via votre backend
  static Future<Map<String, dynamic>?> createPaymentIntent({
    required String planId,
    required String professionalId,
    required String email,
    String? businessName,
    String? categoryId,
    String? ville,
    String? phone,
    Map<String, dynamic>? registrationData,
    String currency = 'cad',
  }) async {
    try {
      final amount = planPrices[planId];
      if (amount == null) {
        throw Exception('Plan non trouvé: $planId');
      }

      // Convertir en centimes pour Stripe
      final amountInCents = (amount * 100).round();

      final requestBody = {
        'amount': amountInCents,
        'currency': currency,
        'metadata': {
          'professionalId': professionalId,
          'planId': planId,
          'email': email,
          'businessName': businessName ?? 'Nouveau Professionnel',
          'categoryId': categoryId ?? '',
          'ville': ville ?? '',
          'phone': phone ?? '',
        },
        // Inclure toutes les données de registration pour le backend
        'registrationData': registrationData ?? {},
      };

      print(
        '📤 Envoi createPaymentIntent avec businessName: ${businessName ?? 'Nouveau Professionnel'}',
      );
      print(
        '📤 Métadonnées complètes: ${json.encode(requestBody['metadata'])}',
      );

      // Ajouter l'action dans le body pour le routing
      requestBody['action'] = 'createPaymentIntent';

    final response = await http
      .post(
        Uri.parse(
          'https://www.immigrantindex.com/_functions/createPaymentIntent',
        ),
        headers: {'Content-Type': 'application/json'},
        body: json.encode(requestBody),
    )
      .timeout(const Duration(seconds: 20));

      print('📧 CreatePaymentIntent Response: ${response.statusCode}');
      print('📧 Response body: ${response.body}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return data;
      } else {
        throw Exception('Erreur serveur: ${response.statusCode}');
      }
    } catch (e) {
      print('❌ Erreur createPaymentIntent: $e');
      return null;
    }
  }

  /// Traiter le paiement avec carte de crédit native
  static Future<PaymentResult> processNativePayment({
    required BuildContext context,
    required String planId,
    required String professionalId,
    required String email,
    required String businessName,
    String? categoryId,
    String? ville,
    String? phone,
    Map<String, dynamic>? registrationData,
  }) async {
    try {
      // 1. Créer le Payment Intent
      final paymentIntentData = await createPaymentIntent(
        planId: planId,
        professionalId: professionalId,
        email: email,
        businessName: businessName,
        categoryId: categoryId,
        ville: ville,
        phone: phone,
        registrationData: registrationData,
      );

      if (paymentIntentData == null) {
        return PaymentResult(
          success: false,
          error: 'Impossible de créer le paiement',
        );
      }

      final clientSecret = paymentIntentData['client_secret'];
      if (clientSecret == null) {
        return PaymentResult(success: false, error: 'Client secret manquant');
      }

      // 2. Initialiser la feuille de paiement
      await Stripe.instance.initPaymentSheet(
        paymentSheetParameters: SetupPaymentSheetParameters(
          paymentIntentClientSecret: clientSecret,
          merchantDisplayName: 'Immigrant Index',
          customerEphemeralKeySecret: paymentIntentData['ephemeral_key'],
          customerId: paymentIntentData['customer_id'],
          style: ThemeMode.system,
          billingDetails: BillingDetails(email: email, name: businessName),
        ),
      );

      // 3. Présenter la feuille de paiement
      await Stripe.instance.presentPaymentSheet();

      // 4. Si on arrive ici, le paiement a réussi
      return PaymentResult(
        success: true,
        paymentIntentId: paymentIntentData['id'],
      );
    } on StripeException catch (e) {
      print('❌ Erreur Stripe: ${e.error.localizedMessage}');

      // Gérer les cas d'annulation
      if (e.error.code == FailureCode.Canceled) {
        return PaymentResult(
          success: false,
          error: 'Paiement annulé',
          wasCanceled: true,
        );
      }

      return PaymentResult(
        success: false,
        error: e.error.localizedMessage ?? 'Erreur de paiement',
      );
    } catch (e) {
      print('❌ Erreur générale: $e');
      return PaymentResult(success: false, error: 'Erreur inattendue: $e');
    }
  }

  /// Confirmer le paiement côté serveur après succès
  static Future<Map<String, dynamic>?> confirmPaymentOnServer({
    required String paymentIntentId,
    required String professionalId,
    required String planId,
    required String businessName,
    Map<String, dynamic>? registrationData, // pour transmettre les images Base64
  }) async {
    try {
      // Assainir, compresser et préparer les images si disponibles (meilleures perfs mobile)
      String profileBase64 = '';
      List<String> galleryBase64 = [];
      if (registrationData != null) {
        if (registrationData['profileImageBase64'] is String) {
          final raw = (registrationData['profileImageBase64'] as String);
          profileBase64 = await compressBase64(
            raw,
            maxKB: 50,
            maxWidth: 800,
            maxHeight: 800,
          );
        }
        final rawGallery = registrationData['galleryImagesBase64'];
        if (rawGallery is List) {
          final cleaned = rawGallery
              .whereType<String>()
              .where((s) => s.trim().isNotEmpty)
              .toList();
          galleryBase64 = await compressGallery(
            cleaned,
            limit: 5,
            maxKB: 60,
            maxWidth: 1024,
            maxHeight: 1024,
          );
        }
      }

  final Map<String, dynamic> requestBody = {
        'paymentIntentId': paymentIntentId,
        'professionalId': professionalId,
        'planId': planId,
        'businessName': businessName,
      };

      // Ajouter l'action dans le body pour le routing
      requestBody['action'] = 'confirmPayment';

      // Inclure les images uniquement si présentes
      if (profileBase64.isNotEmpty) {
        requestBody['profileImageBase64'] = profileBase64;
      }
      if (galleryBase64.isNotEmpty) {
        requestBody['galleryImagesBase64'] = galleryBase64;
      }

      print('📤 Envoi confirmPayment avec businessName: $businessName');
      final hasImg = profileBase64.isNotEmpty;
      final galCount = galleryBase64.length;
      print('📎 Images incluses dans confirmPayment -> profil: $hasImg, galerie: $galCount');
      print('📤 Données complètes: ${json.encode(requestBody)}');

    final response = await http
      .post(
        Uri.parse('https://www.immigrantindex.com/_functions/confirmPayment'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode(requestBody),
    )
      .timeout(const Duration(seconds: 25));

      print('✅ ConfirmPayment Response: ${response.statusCode}');
      print('Response body: ${response.body}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true) {
          return data; // Retourner toutes les données incluant l'ID réel
        }
      }

      return null;
    } catch (e) {
      print('❌ Erreur confirmPayment: $e');
      return null;
    }
  }

  /// Upload images for an already created professional (post-confirm fallback)
  static Future<bool> uploadProfessionalImages({
    required String professionalId,
  String? email,
    String? profileImageBase64,
    List<String>? galleryImagesBase64,
  }) async {
    try {
      // Sanitize
      final String profile = (profileImageBase64 is String)
          ? profileImageBase64
          : '';
      List<String> gallery = [];
      if (galleryImagesBase64 is List<String>) {
        gallery = galleryImagesBase64
            .where((s) => s.trim().isNotEmpty)
            .toList();
        if (gallery.length > 5) gallery = gallery.sublist(0, 5);
      }

  final payload = <String, dynamic>{
        'professionalId': professionalId,
      };
  if (email != null && email.isNotEmpty) payload['email'] = email;
      if (profile.isNotEmpty) payload['profileImageBase64'] = profile;
      if (gallery.isNotEmpty) payload['galleryImagesBase64'] = gallery;

  print('📤 Upload images -> proId: $professionalId, profil: ${profile.isNotEmpty}, galerie: ${gallery.length}');

    final resp = await http
      .post(
        Uri.parse('https://www.immigrantindex.com/_functions/updateProfessionalImages'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode(payload),
    )
      .timeout(const Duration(seconds: 25));

      print('🖼️ Upload images response: ${resp.statusCode}');
      if (resp.body.isNotEmpty) print('🖼️ Body: ${resp.body}');

  if (resp.statusCode == 200 || resp.statusCode == 201) {
        try {
          final data = json.decode(resp.body);
          // Accept success:true or presence of updated fields
          return data is Map && (data['success'] == true || data['imageUrl'] != null);
        } catch (_) {
          return true; // assume success if server returned 200
        }
      }
      return false;
    } catch (e) {
      print('❌ Erreur uploadProfessionalImages: $e');
      return false;
    }
  }
}

/// Classe pour le résultat du paiement
class PaymentResult {
  final bool success;
  final String? error;
  final String? paymentIntentId;
  final bool wasCanceled;

  PaymentResult({
    required this.success,
    this.error,
    this.paymentIntentId,
    this.wasCanceled = false,
  });
}
