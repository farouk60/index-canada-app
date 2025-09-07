// lib/services/confirmation_email_service.dart
// Service pour gérer les emails de confirmation

import 'package:http/http.dart' as http;
import 'dart:convert';

class ConfirmationEmailService {
  static const String baseUrl = 'https://www.immigrantindex.com/_functions';

  /// Envoyer manuellement un email de confirmation à un professionnel
  static Future<bool> sendManualConfirmation({
    String? professionalId,
    String? email,
  }) async {
    if (professionalId == null && email == null) {
      print('❌ professionalId ou email requis');
      return false;
    }

    try {
      final response = await http.post(
        Uri.parse('$baseUrl/sendManualConfirmation'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          if (professionalId != null) 'professionalId': professionalId,
          if (email != null) 'email': email,
        }),
      );

      print('📧 Réponse envoi email manuel: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          print('✅ Email de confirmation envoyé manuellement');
          return true;
        } else {
          print('❌ Erreur: ${data['error']}');
        }
      } else {
        print('❌ Erreur HTTP: ${response.statusCode}');
      }
    } catch (e) {
      print('❌ Erreur envoi email manuel: $e');
    }
    return false;
  }

  /// Vérifier si un professionnel a reçu son email de confirmation
  static Future<bool> hasReceivedConfirmationEmail(
    String professionalId,
  ) async {
    try {
      final response = await http.get(
        Uri.parse('https://www.immigrantindex.com/_functions/data'),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final professionnels = data['professionnels'] as List;

        for (var prof in professionnels) {
          if (prof['_id'] == professionalId) {
            return prof['emailConfirmationSent'] == true;
          }
        }
      }
    } catch (e) {
      print('❌ Erreur vérification email: $e');
    }
    return false;
  }

  /// Obtenir la liste des professionnels sans email de confirmation
  static Future<List<Map<String, dynamic>>>
  getProfessionalsWithoutEmail() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/professionalsWithoutEmail'),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          return List<Map<String, dynamic>>.from(data['professionals']);
        }
      }
    } catch (e) {
      print('❌ Erreur récupération professionnels: $e');
    }
    return [];
  }

  /// Envoyer des emails de confirmation en lot
  static Future<Map<String, dynamic>?> sendBatchConfirmationEmails(
    List<String> professionalIds,
  ) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/sendBatchConfirmationEmails'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'professionalIds': professionalIds}),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          return data['results'];
        }
      }
    } catch (e) {
      print('❌ Erreur envoi en lot: $e');
    }
    return null;
  }

  /// Afficher une notification à l'utilisateur après inscription
  static Future<void> showPostRegistrationEmailInfo({
    required String businessName,
    required String email,
    required String planName,
  }) async {
    // Cette méthode peut être appelée après une inscription réussie
    // pour informer l'utilisateur qu'un email de confirmation sera envoyé
    print('📧 Email de confirmation sera envoyé à: $email');
    print('📧 Entreprise: $businessName');
    print('📧 Plan: $planName');
  }

  /// Vérifier et renvoyer l'email si nécessaire
  static Future<bool> checkAndResendIfNeeded({
    required String professionalId,
    required String email,
    required String businessName,
  }) async {
    print('🔍 Vérification email de confirmation pour: $businessName');

    // Vérifier si l'email a été envoyé
    final hasReceived = await hasReceivedConfirmationEmail(professionalId);

    if (!hasReceived) {
      print('📧 Email non reçu, tentative de renvoi...');

      // Attendre un peu (parfois l'email est en cours d'envoi)
      await Future.delayed(const Duration(seconds: 5));

      // Renvoyer l'email
      final sent = await sendManualConfirmation(
        professionalId: professionalId,
        email: email,
      );

      if (sent) {
        print('✅ Email de confirmation renvoyé avec succès');
        return true;
      } else {
        print('❌ Échec du renvoi de l\'email');
        return false;
      }
    } else {
      print('✅ Email de confirmation déjà envoyé');
      return true;
    }
  }
}
