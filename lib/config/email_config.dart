// lib/config/email_config.dart
// Configuration pour l'intégration EmailJS avec Gmail

class EmailConfig {
  // ============================================
  // CONFIGURATION EMAILJS POUR GMAIL
  // ============================================

  // Pour obtenir ces informations, allez sur https://emailjs.com/
  // 1. Créez un compte EmailJS
  // 2. Connectez votre compte Gmail (immigrant.index@gmail.com)
  // 3. Créez un service email
  // 4. Créez un template
  // 5. Copiez les IDs ci-dessous

  static const String emailJsServiceId = 'service_abc123'; // ✅ CONFIGURÉ
  static const String emailJsTemplateId =
      'YOUR_TEMPLATE_ID_HERE'; // À configurer
  static const String emailJsUserId =
      'YOUR_USER_ID_HERE'; // À configurer  // ============================================
  // CONFIGURATION GMAIL
  // ============================================

  static const String senderEmail = 'immigrant.index@gmail.com';
  static const String senderName = 'Mon Index 2026 - Support';
  static const String supportEmail = 'immigrant.index@gmail.com';

  // ============================================
  // URLS DES SERVICES
  // ============================================

  static const String wixApiUrl =
      'https://monindex2026.wixsite.com/monindex2026/_functions';
  static const String emailServiceUrl = '$wixApiUrl/gmail-email';
  static const String testEmailUrl = '$wixApiUrl/test-email';

  // ============================================
  // VÉRIFICATION DE LA CONFIGURATION
  // ============================================

  static bool isEmailJsConfigured() {
    return emailJsServiceId != 'YOUR_SERVICE_ID_HERE' &&
        emailJsTemplateId != 'YOUR_TEMPLATE_ID_HERE' &&
        emailJsUserId != 'YOUR_USER_ID_HERE';
  }

  static String getConfigurationStatus() {
    if (isEmailJsConfigured()) {
      return '✅ EmailJS configuré avec Gmail';
    } else {
      return '⚠️ EmailJS non configuré - utilise Wix par défaut';
    }
  }

  // ============================================
  // INSTRUCTIONS DE CONFIGURATION
  // ============================================

  static const String configurationInstructions = '''
ÉTAPES POUR CONFIGURER EMAILJS AVEC GMAIL:

1. Allez sur https://emailjs.com/
2. Créez un compte EmailJS gratuit
3. Connectez votre service Gmail:
   - Cliquez sur "Add New Service"
   - Sélectionnez "Gmail"
   - Connectez votre compte immigrant.index@gmail.com
   - Notez le SERVICE_ID généré

4. Créez un template email:
   - Cliquez sur "Email Templates"
   - Créez un nouveau template
   - Configurez avec les variables: {{business_name}}, {{email}}, {{plan}}, etc.
   - Notez le TEMPLATE_ID généré

5. Récupérez votre USER_ID:
   - Allez dans "Account" > "General"
   - Copiez votre Public Key (USER_ID)

6. Mettez à jour ce fichier avec vos IDs

ALTERNATIVE: Utilisation de l'API Gmail directe
- Plus complexe mais plus fiable
- Nécessite OAuth2 et tokens d'accès
- Documentation: https://developers.google.com/gmail/api
''';
}
