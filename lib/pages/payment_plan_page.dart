import 'package:flutter/material.dart';
import '../services/wix_payment_service.dart';
import '../services/localization_service.dart';
// import removed: payment via browser disabled
import 'native_payment_page.dart';

class PaymentPlanPage extends StatefulWidget {
  final String professionalId;
  final String businessName;
  final String email;
  final String selectedPlan; // Plan déjà choisi lors de l'inscription
  final String? categoryId;
  final String? categoryName;
  final String? categoryNameEn;
  final Map<String, dynamic>?
  registrationData; // Données pour création après paiement

  const PaymentPlanPage({
    Key? key,
    required this.professionalId,
    required this.businessName,
    required this.email,
    required this.selectedPlan,
    this.categoryId,
    this.categoryName,
    this.categoryNameEn,
    this.registrationData,
  }) : super(key: key);

  @override
  State<PaymentPlanPage> createState() => _PaymentPlanPageState();
}

class _PaymentPlanPageState extends State<PaymentPlanPage> {
  bool isProcessing = false;
  final LocalizationService _localization = LocalizationService();
  late PaymentPlan selectedPlan;

  @override
  void initState() {
    super.initState();
    // Trouver le plan sélectionné
    selectedPlan = PaymentPlan.getAvailablePlans().firstWhere(
      (plan) => plan.id == widget.selectedPlan,
    );
    // Plus besoin d'initialiser Stripe, nous utilisons Wix
  }

  @override
  Widget build(BuildContext context) {
    final isEnglish = _localization.currentLanguage == 'en';
    final planName = isEnglish ? selectedPlan.nameEn : selectedPlan.name;
    final features = isEnglish
        ? selectedPlan.featuresEn
        : selectedPlan.features;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          isEnglish ? 'Confirm Your Plan' : 'Confirmez votre plan',
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
            // En-tête
            Text(
              isEnglish
                  ? 'You have selected the following plan:'
                  : 'Vous avez sélectionné le plan suivant :',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 24),

            // Plan sélectionné
            _buildSelectedPlanCard(planName, features, isEnglish),

            const SizedBox(height: 24),

            // Résumé de commande
            _buildOrderSummary(planName, isEnglish),

            const SizedBox(height: 24),

            // Bouton de paiement natif (nouveau)
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton.icon(
                onPressed: isProcessing ? null : _processNativePayment,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green[600],
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                icon: const Icon(Icons.payment),
                label: Text(
                  isEnglish
                      ? 'Pay Securely \$${selectedPlan.price.toStringAsFixed(2)} CAD'
                      : 'Payer en sécurité ${selectedPlan.price.toStringAsFixed(2)}\$ CAD',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),

            const SizedBox(height: 12),

            // Navigateur désactivé: paiement uniquement natif
            const SizedBox(height: 16),

            // Informations sur la sécurité
            _buildSecurityInfo(isEnglish),
          ],
        ),
      ),
    );
  }

  Widget _buildSelectedPlanCard(
    String planName,
    List<String> features,
    bool isEnglish,
  ) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: Colors.blue[700]!, width: 2),
        borderRadius: BorderRadius.circular(12),
        color: Colors.blue[50],
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            planName,
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          if (selectedPlan.isPopular) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.orange,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                isEnglish ? 'POPULAR' : 'POPULAIRE',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${selectedPlan.price.toStringAsFixed(2)}\$ CAD/${isEnglish ? "year" : "année"}',
                        style: TextStyle(
                          fontSize: 16,
                          color: Colors.grey[700],
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.green.shade50,
                          border: Border.all(color: Colors.green.shade300),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          isEnglish
                              ? 'Total: ${selectedPlan.price.toStringAsFixed(2)}\$ CAD'
                              : 'Total : ${selectedPlan.price.toStringAsFixed(2)}\$ CAD',
                          style: TextStyle(
                            fontSize: 18,
                            color: Colors.green[800],
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.check_circle, color: Colors.green[600], size: 30),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              isEnglish ? 'Included features:' : 'Fonctionnalités incluses :',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            ...features.map(
              (feature) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    Icon(Icons.check, size: 18, color: Colors.green[600]),
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

  Widget _buildOrderSummary(String planName, bool isEnglish) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey[300]!),
      ),
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
                '${selectedPlan.price.toStringAsFixed(2)}\$ CAD',
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
                '${selectedPlan.price.toStringAsFixed(2)}\$ CAD',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.blue,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSecurityInfo(bool isEnglish) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(Icons.security, color: Colors.green[600], size: 20),
              const SizedBox(width: 8),
              Text(
                isEnglish ? 'Secure Payment' : 'Paiement sécurisé',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            isEnglish
                ? 'Your payment is processed securely by Stripe. We do not store your credit card information.'
                : 'Votre paiement est traité de manière sécurisée par Stripe. Nous ne conservons pas vos informations de carte de crédit.',
            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
          ),
        ],
      ),
    );
  }

  Future<void> _processNativePayment() async {
    setState(() {
      isProcessing = true;
    });

    try {
      // Naviguer vers la page de paiement natif
      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => NativePaymentPage(
              professionalId: widget.professionalId,
              businessName: widget.businessName,
              email: widget.email,
              selectedPlan: selectedPlan.id,
              categoryId: widget.categoryId,
              categoryName: widget.categoryName,
              categoryNameEn: widget.categoryNameEn,
              registrationData: widget.registrationData,
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        final isEnglish = _localization.currentLanguage == 'en';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              isEnglish
                  ? 'Error opening payment: ${e.toString()}'
                  : 'Erreur lors de l\'ouverture du paiement: ${e.toString()}',
            ),
            backgroundColor: Colors.red,
          ),
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

  // Paiement navigateur supprimé
}
