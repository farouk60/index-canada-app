import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'services/localization_service.dart';

/// Ouvre le composeur téléphonique sans demander une permission d'appel direct.
class SimplePhoneCall {
  static Future<bool> call(String phoneNumber) async {
    final normalized = phoneNumber.trim().replaceAll(RegExp(r'[^0-9+]'), '');
    if (normalized.isEmpty) return false;

    return launchUrl(
      Uri(scheme: 'tel', path: normalized),
      mode: LaunchMode.externalApplication,
    );
  }

  /// Formate le numéro pour l'affichage (optionnel)
  static String format(String phoneNumber) {
    if (phoneNumber.length == 10 && phoneNumber.startsWith('0')) {
      return '${phoneNumber.substring(0, 2)} ${phoneNumber.substring(2, 4)} ${phoneNumber.substring(4, 6)} ${phoneNumber.substring(6, 8)} ${phoneNumber.substring(8, 10)}';
    }
    return phoneNumber;
  }
}

Future<void> _callWithFeedback(
  BuildContext context,
  String phoneNumber, {
  VoidCallback? onCallInitiated,
}) async {
  onCallInitiated?.call();

  var launched = false;
  try {
    launched = await SimplePhoneCall.call(phoneNumber);
  } on Exception {
    launched = false;
  }

  if (!launched && context.mounted) {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(content: Text(LocalizationService().tr('phone_call_error'))),
    );
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

    return TextButton(
      onPressed: () => _callWithFeedback(
        context,
        phoneNumber,
        onCallInitiated: onCallInitiated,
      ),
      style: TextButton.styleFrom(
        minimumSize: const Size(48, 48),
        padding: const EdgeInsets.symmetric(horizontal: 8),
      ),
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
      onPressed: () => _callWithFeedback(context, phoneNumber),
      icon: const Icon(Icons.phone),
      label: Text(label ?? LocalizationService().tr('call')),
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.green.shade600,
        foregroundColor: Colors.white,
      ),
    );
  }
}
