import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class PaymentStatusService {
  static const String _pendingPaymentKey = 'pending_payment';

  // Sauvegarder qu'un paiement est en attente
  static Future<void> savePendingPayment({
    required String professionalId,
    required String planType,
    required double amount,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final paymentData = {
      'professionalId': professionalId,
      'planType': planType,
      'amount': amount,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    };
    await prefs.setString(_pendingPaymentKey, jsonEncode(paymentData));
  }

  // Vérifier s'il y a un paiement en attente
  static Future<Map<String, dynamic>?> getPendingPayment() async {
    final prefs = await SharedPreferences.getInstance();
    final paymentJson = prefs.getString(_pendingPaymentKey);
    if (paymentJson != null) {
      return jsonDecode(paymentJson);
    }
    return null;
  }

  // Supprimer le paiement en attente
  static Future<void> clearPendingPayment() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_pendingPaymentKey);
  }

  // Vérifier le statut du plan du professionnel
  static Future<bool> checkPlanStatus(String professionalId) async {
    try {
      final response = await http.get(
        Uri.parse('https://www.immigrantindex.com/_functions/data'),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final professionnels = data['professionnels'] as List;

        for (var prof in professionnels) {
          if (prof['_id'] == professionalId) {
            return prof['isActive'] == true;
          }
        }
      }
    } catch (e) {
      print('Erreur vérification statut: $e');
    }
    return false;
  }

  // Vérifier et afficher notification si paiement réussi
  static Future<bool> checkAndShowPaymentSuccess() async {
    final pendingPayment = await getPendingPayment();
    if (pendingPayment == null) return false;

    final professionalId = pendingPayment['professionalId'];
    final isActive = await checkPlanStatus(professionalId);

    if (isActive) {
      await clearPendingPayment();
      return true; // Paiement réussi
    }

    // Vérifier si le paiement est trop ancien (plus de 10 minutes)
    final timestamp = pendingPayment['timestamp'] as int;
    final paymentTime = DateTime.fromMillisecondsSinceEpoch(timestamp);
    final now = DateTime.now();

    if (now.difference(paymentTime).inMinutes > 10) {
      await clearPendingPayment(); // Nettoyer les anciens paiements
    }

    return false;
  }
}
