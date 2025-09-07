import 'package:flutter/material.dart';
import 'package:flutter_phone_direct_caller/flutter_phone_direct_caller.dart';

/// Solution ultra-simple : clic = appel direct
class SimplePhoneCall {
  /// Lance directement un appel téléphonique
  static Future<void> call(String phoneNumber) async {
    debugPrint('📞 Tentative d\'appel vers: $phoneNumber');

    if (phoneNumber.isEmpty) {
      debugPrint('❌ Numéro vide !');
      return;
    }

    try {
      debugPrint('🔄 Lancement de l\'appel...');
      await FlutterPhoneDirectCaller.callNumber(phoneNumber);
      debugPrint('✅ Appel lancé avec succès');
    } catch (e) {
      debugPrint('❌ Appel échoué: $e');
    }
  }

  /// Formate le numéro pour l'affichage (optionnel)
  static String format(String phoneNumber) {
    if (phoneNumber.length == 10 && phoneNumber.startsWith('0')) {
      return '${phoneNumber.substring(0, 2)} ${phoneNumber.substring(2, 4)} ${phoneNumber.substring(4, 6)} ${phoneNumber.substring(6, 8)} ${phoneNumber.substring(8, 10)}';
    }
    return phoneNumber;
  }
}

/// Widget ultra-simple : texte cliquable qui lance l'appel
class ClickToCall extends StatelessWidget {
  final String phoneNumber;
  final TextStyle? style;
  final VoidCallback? onCallInitiated; // Callback pour tracking

  const ClickToCall({
    super.key,
    required this.phoneNumber,
    this.style,
    this.onCallInitiated,
  });

  @override
  Widget build(BuildContext context) {
    if (phoneNumber.isEmpty) return const SizedBox.shrink();

    return GestureDetector(
      onTap: () {
        debugPrint('🖱️ Clic détecté sur le numéro: $phoneNumber');
        onCallInitiated?.call(); // Appeler le callback pour tracking
        SimplePhoneCall.call(phoneNumber);
      },
      child: Text(
        SimplePhoneCall.format(phoneNumber),
        style:
            style ??
            TextStyle(
              color: Colors.blue.shade600,
              decoration: TextDecoration.underline,
              fontWeight: FontWeight.w500,
            ),
      ),
    );
  }
}

/// Bouton simple avec icône téléphone
class CallButton extends StatelessWidget {
  final String phoneNumber;
  final String? label;

  const CallButton({super.key, required this.phoneNumber, this.label});

  @override
  Widget build(BuildContext context) {
    if (phoneNumber.isEmpty) return const SizedBox.shrink();

    return ElevatedButton.icon(
      onPressed: () {
        debugPrint('🔘 Bouton appeler pressé pour: $phoneNumber');
        SimplePhoneCall.call(phoneNumber);
      },
      icon: const Icon(Icons.phone),
      label: Text(label ?? 'Appeler'),
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.green.shade600,
        foregroundColor: Colors.white,
      ),
    );
  }
}
