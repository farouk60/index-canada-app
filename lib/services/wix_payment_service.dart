import 'package:url_launcher/url_launcher.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class WixPaymentService {
  // Liens de paiement Stripe pour chaque plan (NOUVELLES URLs STRIPE)
  static const Map<String, String> paymentLinks = {
    'basic': 'https://buy.stripe.com/aFa00kaOk03MboL40k9Zm00',
    'premium': 'https://buy.stripe.com/5kQ3cw3lS7weboL0O89Zm01',
    'professional':
        'https://buy.stripe.com/9B65kE2hOcQy8czdAU9Zm02', // Plan "En Vedette"
  };

  // Prix des différents plans (Prix de test)
  static const Map<String, double> planPrices = {
  'basic': 49.99,
  'premium': 69.99,
  'professional': 119.99, // Plan "En Vedette"
  };

  // Ouvrir le lien de paiement Stripe avec l'ID du professionnel
  static Future<bool> openPaymentLink(
    String planId, {
    String? professionalId,
  }) async {
    final baseLink = paymentLinks[planId];
    if (baseLink == null) {
      print('Erreur: Plan non trouvé: $planId');
      return false;
    }

    // Utiliser directement le lien Stripe (les métadonnées webhook sont configurées côté Stripe)
    String link = baseLink;

    try {
      final uri = Uri.parse(link);
      print('🔗 Ouverture du lien de paiement Stripe: $link');

      if (await canLaunchUrl(uri)) {
        await launchUrl(
          uri,
          mode: LaunchMode.externalApplication, // Ouvre dans le navigateur
        );
        return true;
      } else {
        print('Erreur: Impossible d\'ouvrir le lien de paiement Stripe');
        return false;
      }
    } catch (e) {
      print('Erreur ouverture lien de paiement Stripe: $e');
      return false;
    }
  }

  // Version rétrocompatible sans professionalId
  static Future<bool> openPaymentLinkLegacy(String planId) async {
    return openPaymentLink(planId);
  }

  // Obtenir le nom du plan en français
  static String getPlanNameFr(String planId) {
    switch (planId) {
      case 'basic':
        return 'Plan Basique';
      case 'premium':
        return 'Plan Premium';
      case 'professional':
        return 'Plan En Vedette';
      default:
        return 'Plan Inconnu';
    }
  }

  // Obtenir le nom du plan en anglais
  static String getPlanNameEn(String planId) {
    switch (planId) {
      case 'basic':
        return 'Basic Plan';
      case 'premium':
        return 'Premium Plan';
      case 'professional':
        return 'Featured Plan';
      default:
        return 'Unknown Plan';
    }
  }

  // Créer les données pour Wix après paiement réussi
  static Map<String, dynamic> createWixPaymentData({
    required String professionalId,
    required String planType,
    required String paymentId,
    required double amountPaid,
  }) {
    final now = DateTime.now();
    final expiryDate = DateTime(
      now.year + 1,
      now.month,
      now.day,
    ); // 1 an plus tard

    return {
      'plan': planType,
      'isActive': false, // Sera activé après confirmation du paiement
      'paymentId': paymentId,
      'expiryDate': expiryDate.toIso8601String(),
      'createdAt': now.toIso8601String(),
      'amountPaid': amountPaid,
    };
  }

  // Mettre à jour le plan professionnel après paiement réussi
  static Future<bool> updateProfessionalPlan({
    required String professionalId,
    required String planType,
    required String paymentId,
    required double amountPaid,
  }) async {
    try {
      final url = Uri.parse(
        'https://www.immigrantindex.com/_functions/updateProfessionalPlan',
      );

      final requestData = {
        'professionalId': professionalId,
        'plan': planType,
        'paymentId': paymentId,
        'amountPaid': amountPaid,
      };

      print('Envoi de la mise à jour du plan: $requestData');

      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: json.encode(requestData),
      );

      print('Réponse du serveur: ${response.statusCode}');
      print('Corps de la réponse: ${response.body}');

      if (response.statusCode == 200) {
        final responseData = json.decode(response.body);
        if (responseData['success'] == true) {
          print('✅ Plan professionnel mis à jour avec succès');
          return true;
        } else {
          print('❌ Erreur dans la réponse: ${responseData['error']}');
          return false;
        }
      } else {
        print('❌ Erreur HTTP: ${response.statusCode}');
        return false;
      }
    } catch (e) {
      print('❌ Erreur lors de la mise à jour du plan: $e');
      return false;
    }
  }
}

// Modèles pour les plans de paiement (mise à jour)
class PaymentPlan {
  final String id;
  final String name;
  final String nameEn;
  final double price;
  final String currency;
  final List<String> features;
  final List<String> featuresEn;
  final bool isPopular;

  PaymentPlan({
    required this.id,
    required this.name,
    required this.nameEn,
    required this.price,
    required this.currency,
    required this.features,
    required this.featuresEn,
    this.isPopular = false,
  });

  // Obtenir le lien de paiement Wix
  String? get paymentLink => WixPaymentService.paymentLinks[id];

  static List<PaymentPlan> getAvailablePlans() {
    return [
      PaymentPlan(
        id: 'basic',
        name: 'Plan Basique',
        nameEn: 'Basic Plan',
  price: 49.99,
        currency: 'CAD',
        features: [
          'Profil professionnel',
          'Informations de contact',
          'Avis clients',
          'Visibilité standard',
        ],
        featuresEn: [
          'Professional profile',
          'Contact information',
          'Customer reviews',
          'Standard visibility',
        ],
      ),
      PaymentPlan(
        id: 'premium',
        name: 'Plan Premium',
        nameEn: 'Premium Plan',
  price: 69.99, // Prix final
        currency: 'CAD',
        isPopular: true,
        features: [
          'Tout du plan Basique',
          'Galerie de 5 photos',
          'Résumé d\'activité mis en avant',
          'Support prioritaire',
          'Réseaux sociaux améliorés',
          'Coupons de réduction exclusifs',
        ],
        featuresEn: [
          'Everything from Basic',
          'Gallery of 5 photos',
          'Featured business summary',
          'Priority support',
          'Enhanced social networks',
          'Exclusive discount coupons',
        ],
      ),
      PaymentPlan(
        id: 'professional',
        name: 'Plan En Vedette',
        nameEn: 'Featured Plan',
  price: 119.99, // Prix final
        currency: 'CAD',
        features: [
          'Tout du plan Premium',
          'Support prioritaire',
          'Personnalisation avancée',
        ],
        featuresEn: [
          'Everything from Premium',
          'Priority support',
          'Advanced customization',
        ],
      ),
    ];
  }
}
