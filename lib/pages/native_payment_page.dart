import 'package:flutter/material.dart';
import '../services/stripe_native_payment_service.dart';
import '../services/localization_service.dart';
import '../services/wix_payment_service.dart';
// Browser-based payment removed; keep native payments only
import 'payment_success_page.dart';

class NativePaymentPage extends StatefulWidget {
  final String professionalId;
  final String businessName;
  final String email;
  final String selectedPlan;
  final String? categoryId;
  final String? categoryName;
  final String? categoryNameEn;
  final Map<String, dynamic>? registrationData;

  const NativePaymentPage({
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
  State<NativePaymentPage> createState() => _NativePaymentPageState();
}

class _NativePaymentPageState extends State<NativePaymentPage> {
  bool isProcessing = false;
  final LocalizationService _localization = LocalizationService();
  late PaymentPlan selectedPlan;

  @override
  void initState() {
    super.initState();
    selectedPlan = PaymentPlan.getAvailablePlans().firstWhere(
      (plan) => plan.id == widget.selectedPlan,
    );
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
          isEnglish ? 'Secure Payment' : 'Paiement sécurisé',
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
            // Information sécurité
            Container(
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
            ),

            const SizedBox(height: 24),

            // Plan sélectionné
            _buildPlanSummary(planName, features, isEnglish),

            const SizedBox(height: 24),

            // Résumé de commande
            _buildOrderSummary(planName, isEnglish),

            const SizedBox(height: 32),

            // Bouton de paiement natif
            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton.icon(
                onPressed: isProcessing ? null : _processNativePayment,
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
                    : const Icon(Icons.payment),
                label: Text(
                  isProcessing
                      ? (isEnglish ? 'Processing...' : 'Traitement...')
                      : (isEnglish ? 'Pay Now' : 'Payer maintenant'),
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Navigateur désactivé

            const SizedBox(height: 24),

            // Information Stripe
            Center(
              child: Column(
                children: [
                  Text(
                    isEnglish ? 'Powered by' : 'Propulsé par',
                    style: TextStyle(color: Colors.grey[600], fontSize: 12),
                  ),
                  const SizedBox(height: 4),
                  Image.asset(
                    'assets/images/stripe_logo.png', // Ajoutez le logo Stripe
                    height: 20,
                    errorBuilder: (context, error, stackTrace) => Text(
                      'Stripe',
                      style: TextStyle(
                        color: Colors.grey[700],
                        fontWeight: FontWeight.bold,
                      ),
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

  Widget _buildOrderSummary(String planName, bool isEnglish) {
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
                  '\$${selectedPlan.price.toStringAsFixed(2)} ${selectedPlan.currency}',
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
                  '\$${selectedPlan.price.toStringAsFixed(2)} ${selectedPlan.currency}',
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

  Future<void> _processNativePayment() async {
    setState(() {
      isProcessing = true;
    });

    try {
      // Extraire les données supplémentaires depuis registrationData
      final ville = widget.registrationData?['city'] as String?;
      final phone = widget.registrationData?['phone'] as String?;

      print('🔍 DONNÉES EXTRAITES POUR LE PAIEMENT:');
      print('  📧 Email: ${widget.email}');
      print('  🏢 Business Name: ${widget.businessName}');
      print('  🏷️ Category ID: ${widget.categoryId}');
      print('  🏙️ Ville: $ville');
      print('  📞 Phone: $phone');
      print('  📋 Registration Data complètes: ${widget.registrationData}');

      // Traiter le paiement avec Stripe natif
      final result = await StripeNativePaymentService.processNativePayment(
        context: context,
        planId: selectedPlan.id,
        professionalId: widget.professionalId,
        email: widget.email,
        businessName: widget.businessName,
        categoryId: widget.categoryId,
        ville: ville,
        phone: phone,
        registrationData: widget.registrationData,
      );

      if (result.success && result.paymentIntentId != null) {
        // Confirmer côté serveur
        final confirmationData =
            await StripeNativePaymentService.confirmPaymentOnServer(
              paymentIntentId: result.paymentIntentId!,
              professionalId: widget.professionalId,
              planId: selectedPlan.id,
              businessName: widget.businessName,
              registrationData: widget.registrationData,
            );

        if (confirmationData != null && confirmationData['success'] == true) {
          // Le backend a déjà créé le professionnel et renvoyé l'ID
          final data = confirmationData['data'] as Map<String, dynamic>;
          final realProfessionalId = data['professionalId'] ?? widget.professionalId;
          final hasImage = data['hasImage'];
          print('✅ Professionnel confirmé avec ID: $realProfessionalId | hasImage: $hasImage');

          // Si aucune image sauvegardée côté backend mais on a du base64, tenter un upload rapide
          if (hasImage != true && (widget.registrationData?['profileImageBase64']?.toString().isNotEmpty == true ||
              (widget.registrationData?['galleryImagesBase64'] is List && (widget.registrationData?['galleryImagesBase64'] as List).isNotEmpty))) {
            final success = await StripeNativePaymentService.uploadProfessionalImages(
              professionalId: realProfessionalId,
              email: widget.email,
              profileImageBase64: widget.registrationData?['profileImageBase64'],
              galleryImagesBase64: (widget.registrationData?['galleryImagesBase64'] as List?)?.whereType<String>().toList(),
            );
            print('🖼️ Upload images après confirmation: ${success ? 'OK' : 'ECHEC'}');
          }

          // Naviguer vers la page de succès
          if (mounted) {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (context) => PaymentSuccessPage(
                  professionalId: realProfessionalId,
                  businessName: widget.businessName,
                  planType: selectedPlan.id,
                  amountPaid: selectedPlan.price,
                  paymentId: result.paymentIntentId!,
                  professionalEmail: widget.email,
                  categoryId: widget.categoryId,
                  categoryName: widget.categoryName,
                  categoryNameEn: widget.categoryNameEn,
                ),
              ),
            );
          }
        } else {
          _showErrorDialog('Erreur de confirmation du paiement');
        }
      } else if (result.wasCanceled) {
        // Paiement annulé - ne rien faire
        print('💭 Paiement annulé par l\'utilisateur');
      } else {
        _showErrorDialog(result.error ?? 'Erreur de paiement inconnue');
      }
    } catch (e) {
      _showErrorDialog('Erreur inattendue: $e');
    } finally {
      if (mounted) {
        setState(() {
          isProcessing = false;
        });
      }
    }
  }

  // Navigateur désactivé

  void _showErrorDialog(String message) {
    final isEnglish = _localization.currentLanguage == 'en';
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(isEnglish ? 'Payment Error' : 'Erreur de paiement'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(isEnglish ? 'OK' : 'D\'accord'),
          ),
        ],
      ),
    );
  }
}
