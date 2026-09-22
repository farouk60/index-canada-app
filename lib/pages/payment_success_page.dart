import 'package:flutter/material.dart';

import '../services/localization_service.dart';
import '../services/main_navigation_controller.dart';
import '../services/stripe_native_payment_service.dart';

/// Écran de résultat en lecture seule. Le paiement et la confirmation de
/// l’inscription sont déjà terminés lors de son ouverture.
class PaymentSuccessPage extends StatelessWidget {
  const PaymentSuccessPage({
    super.key,
    required this.professionalId,
    required this.planType,
    required this.businessName,
    required this.amountPaid,
    required this.paymentId,
    this.currency = 'CAD',
    this.professionalEmail,
    this.categoryId,
    this.categoryName,
    this.categoryNameEn,
    this.confirmation,
    this.onViewProfile,
  });

  final String professionalId;
  final String planType;
  final String businessName;
  final double amountPaid;
  final String paymentId;
  final String currency;
  final String? professionalEmail;
  final String? categoryId;
  final String? categoryName;
  final String? categoryNameEn;
  final PaymentConfirmation? confirmation;
  final VoidCallback? onViewProfile;

  bool get _isActive =>
      confirmation?.isActive ?? planType.toLowerCase() != 'basic';

  bool get _isPendingReview =>
      confirmation?.status == 'pending_review' || !_isActive;

  @override
  Widget build(BuildContext context) {
    final isEnglish = LocalizationService().currentLanguage == 'en';
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final statusColor = _isPendingReview ? colors.tertiary : colors.primary;

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: Text(
          _isPendingReview
              ? (isEnglish ? 'Registration received' : 'Inscription reçue')
              : (isEnglish
                    ? 'Registration confirmed'
                    : 'Inscription confirmée'),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 24),
                  Align(
                    child: Container(
                      width: 104,
                      height: 104,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: statusColor.withValues(alpha: 0.12),
                      ),
                      child: Icon(
                        _isPendingReview
                            ? Icons.fact_check_outlined
                            : Icons.check_circle_outline,
                        color: statusColor,
                        size: 58,
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    _isPendingReview
                        ? (isEnglish
                              ? 'Your request is under review'
                              : 'Votre demande est en révision')
                        : (isEnglish
                              ? 'Your profile is active'
                              : 'Votre profil est actif'),
                    style: theme.textTheme.headlineSmall?.copyWith(
                      color: statusColor,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _isPendingReview
                        ? (isEnglish
                              ? 'Your registration was received successfully. The profile will remain hidden until the review is complete.'
                              : 'Votre inscription a bien été reçue. Le profil restera masqué jusqu’à la fin de la révision.')
                        : (isEnglish
                              ? 'Your registration was confirmed and your professional profile is now active.'
                              : 'Votre inscription est confirmée et votre profil professionnel est maintenant actif.'),
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 28),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            isEnglish ? 'Receipt' : 'Reçu',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 16),
                          _ReceiptRow(
                            label: isEnglish ? 'Business' : 'Entreprise',
                            value: businessName,
                          ),
                          const SizedBox(height: 10),
                          _ReceiptRow(
                            label: isEnglish ? 'Plan' : 'Forfait',
                            value: _planName(planType, isEnglish),
                          ),
                          const SizedBox(height: 10),
                          _ReceiptRow(
                            label: isEnglish ? 'Amount' : 'Montant',
                            value:
                                '\$${amountPaid.toStringAsFixed(2)} ${currency.toUpperCase()}',
                          ),
                          const SizedBox(height: 10),
                          _ReceiptRow(
                            label: isEnglish ? 'Status' : 'Statut',
                            value: _isPendingReview
                                ? (isEnglish ? 'Under review' : 'En révision')
                                : (isEnglish ? 'Active' : 'Actif'),
                          ),
                          const SizedBox(height: 10),
                          _ReceiptRow(
                            label: isEnglish ? 'Reference' : 'Référence',
                            value: _shortReference(
                              confirmation?.checkoutId ?? paymentId,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (_isPendingReview) ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: colors.tertiaryContainer,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.visibility_off_outlined,
                            color: colors.onTertiaryContainer,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              isEnglish
                                  ? 'The “View my profile” action will become available after approval.'
                                  : 'L’action « Voir mon profil » sera disponible après l’approbation.',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: colors.onTertiaryContainer,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 28),
                  if (_isActive && onViewProfile != null) ...[
                    FilledButton.icon(
                      onPressed: onViewProfile,
                      icon: const Icon(Icons.person_outline),
                      label: Text(
                        isEnglish ? 'View my profile' : 'Voir mon profil',
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  OutlinedButton.icon(
                    key: const Key('payment_success_view_services'),
                    onPressed: () => _openServices(context),
                    icon: const Icon(Icons.home_outlined),
                    label: Text(
                      isEnglish ? 'View services' : 'Voir les services',
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  static String _shortReference(String value) {
    final normalized = value.trim();
    if (normalized.length <= 16) return normalized;
    return '${normalized.substring(0, 8)}…${normalized.substring(normalized.length - 4)}';
  }

  static String _planName(String planType, bool isEnglish) {
    return switch (planType.toLowerCase()) {
      'basic' => isEnglish ? 'Basic Plan' : 'Plan Basique',
      'premium' => isEnglish ? 'Premium Plan' : 'Plan Premium',
      'professional' => isEnglish ? 'Professional Plan' : 'Plan Professionnel',
      _ => planType,
    };
  }

  static void _openServices(BuildContext context) {
    MainNavigationController.instance.requestDestination(
      MainNavigationController.servicesDestination,
    );
    Navigator.of(context).popUntil((route) => route.isFirst);
  }
}

class _ReceiptRow extends StatelessWidget {
  const _ReceiptRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(
            label,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Text(
            value,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
            textAlign: TextAlign.end,
          ),
        ),
      ],
    );
  }
}
