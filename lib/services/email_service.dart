import 'package:http/http.dart' as http;
import 'dart:convert';

class EmailService {
  // Envoyer email de bienvenue après paiement réussi
  static Future<bool> sendWelcomeEmail({
    required String professionalId,
    required String businessName,
    required String email,
    required String plan,
    required double amountPaid,
    required String language,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('https://www.immigrantindex.com/_functions/sendWelcomeEmail'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'professionalId': professionalId,
          'businessName': businessName,
          'email': email,
          'plan': plan,
          'amountPaid': amountPaid,
          'language': language,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['success'] == true;
      }
    } catch (e) {
      print('Erreur envoi email: $e');
    }
    return false;
  }

  // Envoyer notification de paiement échoué
  static Future<bool> sendPaymentFailedEmail({
    required String email,
    required String businessName,
    required String language,
  }) async {
    try {
      final response = await http.post(
        Uri.parse(
          'https://www.immigrantindex.com/_functions/sendPaymentFailedEmail',
        ),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'email': email,
          'businessName': businessName,
          'language': language,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['success'] == true;
      }
    } catch (e) {
      print('Erreur envoi email échec: $e');
    }
    return false;
  }
}
