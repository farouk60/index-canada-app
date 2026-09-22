import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/localization_service.dart';
import '../services/stripe_native_payment_service.dart';
import 'payment_success_page.dart';

class NativePaymentPage extends StatefulWidget {
  final String professionalId;
  final String businessName;
  final String email;
  final String selectedPlan;
  final PaymentPlanQuote serverQuote;
  final String? categoryId;
  final String? categoryName;
  final String? categoryNameEn;
  final Map<String, dynamic>? registrationData;

  const NativePaymentPage({
    super.key,
    required this.professionalId,
    required this.businessName,
    required this.email,
    required this.selectedPlan,
    required this.serverQuote,
    this.categoryId,
    this.categoryName,
    this.categoryNameEn,
    this.registrationData,
  });

  @override
  State<NativePaymentPage> createState() => _NativePaymentPageState();
}

class _NativePaymentPageState extends State<NativePaymentPage> {
  bool isProcessing = false;
  final LocalizationService _localization = LocalizationService();
  PaymentPlanQuote? _serverQuote;
  bool _isLoadingQuote = false;
  bool _quoteUnavailable = false;

  PaymentPlatformSupportDecision get _paymentSupport {
    return StripeNativePaymentService.paymentSupportFor(requiresPayment: true);
  }

  @override
  void initState() {
    super.initState();
    final quote = widget.serverQuote;
    if (quote.id == widget.selectedPlan && quote.requiresPayment) {
      _serverQuote = quote;
    } else {
      _quoteUnavailable = true;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEnglish = _localization.currentLanguage == 'en';
    final quote = _serverQuote;
    final planName = quote == null
        ? (isEnglish ? 'Plan unavailable' : 'Forfait indisponible')
        : (isEnglish ? quote.labelEn : quote.labelFr);
    final features = quote == null
        ? const <String>[]
        : (isEnglish ? quote.featuresEn : quote.featuresFr);
    final paymentSupported = _paymentSupport.isSupported;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          paymentSupported
              ? (isEnglish ? 'Secure Payment' : 'Paiement sécurisé')
              : _localization.tr('payment_unavailable_on_web'),
          style: const TextStyle(color: Colors.white),
        ),
        backgroundColor: Colors.blue[700],
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildPaymentAvailabilityNotice(isEnglish, paymentSupported),

            const SizedBox(height: 24),

            // Plan sélectionné
            _buildPlanSummary(planName, features, isEnglish),

            const SizedBox(height: 24),

            // Résumé de commande
            _buildOrderSummary(planName, isEnglish, quote),

            const SizedBox(height: 16),

            _buildQuoteStatus(isEnglish),

            const SizedBox(height: 32),

            // Bouton de paiement natif
            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton.icon(
                onPressed:
                    isProcessing ||
                        _isLoadingQuote ||
                        quote == null ||
                        !paymentSupported
                    ? null
                    : _processNativePayment,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue[700],
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                icon: isProcessing
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            Colors.white,
                          ),
                        ),
                      )
                    : Icon(paymentSupported ? Icons.payment : Icons.block),
                label: Text(
                  !paymentSupported
                      ? _localization.tr('payment_unavailable_on_web')
                      : isProcessing
                      ? (isEnglish ? 'Processing...' : 'Traitement...')
                      : _isLoadingQuote
                      ? (isEnglish
                            ? 'Verifying price...'
                            : 'Vérification du prix...')
                      : (isEnglish ? 'Pay Now' : 'Payer maintenant'),
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),

            const SizedBox(height: 16),

            const SizedBox(height: 8),

            if (paymentSupported)
              Center(
                child: Column(
                  children: [
                    Text(
                      isEnglish ? 'Powered by' : 'Propulsé par',
                      style: TextStyle(color: Colors.grey[600], fontSize: 12),
                    ),
                    const SizedBox(height: 4),
                    Semantics(
                      label: isEnglish
                          ? 'Payment provider: Stripe'
                          : 'Fournisseur de paiement : Stripe',
                      child: Text(
                        'Stripe',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlanSummary(
    String planName,
    List<String> features,
    bool isEnglish,
  ) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              planName,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              isEnglish ? 'Features included:' : 'Fonctionnalités incluses :',
              style: const TextStyle(fontSize: 14, color: Colors.grey),
            ),
            const SizedBox(height: 8),
            ...features.map(
              (feature) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    Icon(Icons.check, color: Colors.green[600], size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        feature,
                        style: const TextStyle(fontSize: 14),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOrderSummary(
    String planName,
    bool isEnglish,
    PaymentPlanQuote? quote,
  ) {
    final amount = quote == null
        ? '—'
        : NumberFormat.simpleCurrency(
            locale: isEnglish ? 'en_CA' : 'fr_CA',
            name: quote.currency.toUpperCase(),
            decimalDigits: 2,
          ).format(quote.amount);
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              isEnglish ? 'Order Summary' : 'Résumé de commande',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(planName),
                Text(
                  amount,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const Divider(),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  isEnglish ? 'Total' : 'Total',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  amount,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPaymentAvailabilityNotice(
    bool isEnglish,
    bool paymentSupported,
  ) {
    final theme = Theme.of(context);
    if (!paymentSupported) {
      return Semantics(
        container: true,
        liveRegion: true,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: theme.colorScheme.errorContainer,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.block, color: theme.colorScheme.onErrorContainer),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  _localization.tr('paid_payment_web_unavailable'),
                  style: TextStyle(color: theme.colorScheme.onErrorContainer),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.green[50],
        border: Border.all(color: Colors.green[200]!),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(Icons.security, color: Colors.green[700]),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              isEnglish
                  ? 'Secure payment processed by Stripe. Your payment information is encrypted and protected.'
                  : 'Paiement sécurisé traité par Stripe. Vos informations de paiement sont cryptées et protégées.',
              style: TextStyle(color: Colors.green[700]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuoteStatus(bool isEnglish) {
    final theme = Theme.of(context);
    if (!_paymentSupport.isSupported) {
      return Semantics(
        container: true,
        child: Row(
          children: [
            Icon(
              Icons.phone_iphone_outlined,
              size: 18,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _localization.tr('paid_plan_mobile_only'),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      );
    }
    if (_isLoadingQuote) {
      return Row(
        children: [
          const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              isEnglish
                  ? 'Verifying the current price…'
                  : 'Vérification du prix actuel…',
              style: theme.textTheme.bodyMedium,
            ),
          ),
        ],
      );
    }
    if (_quoteUnavailable) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: theme.colorScheme.errorContainer,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(
              Icons.error_outline,
              color: theme.colorScheme.onErrorContainer,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                isEnglish
                    ? 'The current price could not be verified. Payment remains disabled.'
                    : 'Le prix actuel n’a pas pu être vérifié. Le paiement reste désactivé.',
                style: TextStyle(color: theme.colorScheme.onErrorContainer),
              ),
            ),
            TextButton(
              onPressed: () => _loadPlanQuote(),
              child: Text(isEnglish ? 'Retry' : 'Réessayer'),
            ),
          ],
        ),
      );
    }
    return Row(
      children: [
        Icon(
          Icons.verified_outlined,
          size: 18,
          color: theme.colorScheme.primary,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            isEnglish
                ? 'Price verified with Index Canada.'
                : 'Prix vérifié auprès d’Index Canada.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.primary,
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _loadPlanQuote() async {
    if (!_paymentSupport.isSupported) return;
    if (mounted) {
      setState(() {
        _isLoadingQuote = true;
        _quoteUnavailable = false;
      });
    }
    try {
      final catalog = await StripeNativePaymentService.fetchPaymentPlans();
      final quote = catalog.requirePlan(widget.selectedPlan);
      if (!quote.requiresPayment) {
        throw const FormatException('Selected plan does not require payment');
      }
      if (!mounted) return;
      setState(() {
        _serverQuote = quote;
        _isLoadingQuote = false;
        _quoteUnavailable = false;
      });
    } on Exception {
      if (!mounted) return;
      setState(() {
        _serverQuote = null;
        _isLoadingQuote = false;
        _quoteUnavailable = true;
      });
    }
  }

  Future<void> _processNativePayment() async {
    if (isProcessing) return;
    final isEnglish = _localization.currentLanguage == 'en';
    if (!_paymentSupport.isSupported) {
      await _showErrorDialog(_localization.tr('paid_payment_web_unavailable'));
      return;
    }
    final quote = _serverQuote;
    if (quote == null) {
      await _showErrorDialog(
        isEnglish
            ? 'The current price must be verified before payment.'
            : 'Le prix actuel doit être vérifié avant le paiement.',
      );
      return;
    }
    setState(() {
      isProcessing = true;
    });

    try {
      // Extraire les données supplémentaires depuis registrationData
      final rawCity = widget.registrationData?['city'];
      final rawPhone = widget.registrationData?['phone'];
      final ville = rawCity is String ? rawCity : null;
      final phone = rawPhone is String ? rawPhone : null;

      // Traiter le paiement avec Stripe natif
      final result = await StripeNativePaymentService.processNativePayment(
        planId: widget.selectedPlan,
        professionalId: widget.professionalId,
        email: widget.email,
        businessName: widget.businessName,
        categoryId: widget.categoryId,
        ville: ville,
        phone: phone,
        registrationData: widget.registrationData,
        serverQuote: quote,
      );
      if (!mounted) return;

      if (result.success && result.paymentIntentId != null) {
        final confirmation =
            result.confirmation ??
            await StripeNativePaymentService.confirmPaymentOnServerTyped(
              paymentIntentId: result.paymentIntentId!,
              checkoutId: result.checkoutId,
            );
        if (!mounted) return;

        if (confirmation.success && confirmation.data != null) {
          final realProfessionalId =
              confirmation.professionalId ?? widget.professionalId;
          // Le reçu reprend toujours le devis serveur validé avant le paiement.
          final amountPaid = quote.amountCents / 100;
          final currency = quote.currency.toUpperCase();

          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (context) => PaymentSuccessPage(
                professionalId: realProfessionalId,
                businessName: widget.businessName,
                planType: widget.selectedPlan,
                amountPaid: amountPaid,
                currency: currency,
                paymentId: result.paymentIntentId!,
                professionalEmail: widget.email,
                categoryId: widget.categoryId,
                categoryName: widget.categoryName,
                categoryNameEn: widget.categoryNameEn,
                confirmation: confirmation,
              ),
            ),
          );
        } else {
          await _showErrorDialog(
            confirmation.message ??
                (isEnglish
                    ? 'The payment was received, but the registration could not be confirmed. Try again without paying again.'
                    : 'Le paiement a été reçu, mais l’inscription n’a pas pu être confirmée. Réessayez sans repayer.'),
          );
        }
      } else if (result.wasCanceled) {
        // L’annulation est attendue; les données du formulaire sont conservées.
      } else {
        if (result.errorCode == 'CHECKOUT_QUOTE_MISMATCH') {
          await _loadPlanQuote();
          if (!mounted) return;
        }
        await _showErrorDialog(
          result.error ??
              (isEnglish
                  ? 'Unknown payment error.'
                  : 'Erreur de paiement inconnue.'),
        );
      }
    } on Exception {
      if (mounted) {
        await _showErrorDialog(
          _localization.currentLanguage == 'en'
              ? 'We could not complete the payment. Please try again.'
              : 'Le paiement n’a pas pu être finalisé. Veuillez réessayer.',
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          isProcessing = false;
        });
      }
    }
  }

  Future<void> _showErrorDialog(String message) async {
    if (!mounted) return;
    final isEnglish = _localization.currentLanguage == 'en';
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(isEnglish ? 'Payment Error' : 'Erreur de paiement'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(isEnglish ? 'OK' : 'D\'accord'),
          ),
        ],
      ),
    );
  }
}
