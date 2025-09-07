import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/localization_service.dart';
import '../pages/payment_success_page.dart';
import '../data_service.dart';

class PaymentReturnDetector extends StatefulWidget {
  final String professionalId;
  final String businessName;
  final String email;
  final String planType;
  final double amount;
  final String? categoryId;
  final String? categoryName;
  final String? categoryNameEn;
  final Map<String, dynamic>?
  registrationData; // Données pour création après paiement

  const PaymentReturnDetector({
    Key? key,
    required this.professionalId,
    required this.businessName,
    required this.email,
    required this.planType,
    required this.amount,
    this.categoryId,
    this.categoryName,
    this.categoryNameEn,
    this.registrationData,
  }) : super(key: key);

  @override
  State<PaymentReturnDetector> createState() => _PaymentReturnDetectorState();
}

class _PaymentReturnDetectorState extends State<PaymentReturnDetector>
    with WidgetsBindingObserver {
  final LocalizationService _localization = LocalizationService();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // Démarrer la vérification périodique du retour
    _startPaymentReturnDetection();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    // Détecter quand l'utilisateur revient dans l'app
    if (state == AppLifecycleState.resumed) {
      print('🔄 App resumed - checking payment status...');
      _checkPaymentStatusAndRedirect();
    }
  }

  void _startPaymentReturnDetection() {
    // Démarrer la détection après 3 secondes (temps pour l'utilisateur d'aller sur Stripe)
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) {
        _periodicPaymentCheck();
      }
    });
  }

  void _periodicPaymentCheck() {
    // Vérifier toutes les 5 secondes si l'utilisateur est revenu
    Future.delayed(const Duration(seconds: 5), () {
      if (mounted) {
        _checkPaymentStatusAndRedirect();
        _periodicPaymentCheck(); // Continuer la vérification
      }
    });
  }

  Future<void> _checkPaymentStatusAndRedirect() async {
    try {
      // Ici on pourrait vérifier le statut du paiement via une API
      // Pour l'instant, on navigue vers la page de succès après un délai

      print(
        '🔍 Checking payment status for professional: ${widget.professionalId}',
      );

      // Simuler la vérification d'un paiement réussi
      // En réalité, vous pourriez faire un appel API pour vérifier le statut

      // Si l'app est en focus (resumed), assumer que l'utilisateur revient de Stripe
      if (WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
        _navigateToSuccessPage();
      }
    } catch (e) {
      print('❌ Error checking payment status: $e');
    }
  }

  void _navigateToSuccessPage() async {
    if (mounted) {
      // Générer un ID de paiement simulé basé sur le timestamp
      final paymentId = 'stripe_${DateTime.now().millisecondsSinceEpoch}';

      // CRÉER LE PROFESSIONNEL DANS WIX SEULEMENT APRÈS PAIEMENT RÉUSSI
      String? realProfessionalId;

      if (widget.registrationData != null) {
        try {
          print('💳 Paiement réussi! Création du professionnel dans Wix...');

          final dataService = DataService();
          final data = widget.registrationData!;

          realProfessionalId = await dataService.postProfessionalRegistration(
            businessName: data['businessName'],
            category: data['category'],
            email: data['email'],
            phone: data['phone'],
            address: data['address'],
            city: data['city'],
            description: data['description'],
            selectedPlan: data['selectedPlan'],
            planPrice: data['planPrice'],
            website: data['website'],
            businessSummary: data['businessSummary'],
            facebook: data['facebook'],
            instagram: data['instagram'],
            tiktok: data['tiktok'],
            youtube: data['youtube'],
            whatsapp: data['whatsapp'],
            couponTitle: data['couponTitle'],
            couponCode: data['couponCode'],
            couponDescription: data['couponDescription'],
            couponExpirationDate: data['couponExpirationDate'],
            hasProfileImage: data['hasProfileImage'],
            galleryImagesCount: data['galleryImagesCount'],
            profileImageBase64: data['profileImageBase64'],
            galleryImagesBase64: data['galleryImagesBase64'],
          );

          if (realProfessionalId.isNotEmpty) {
            print('✅ Professionnel créé dans Wix avec ID: $realProfessionalId');
          } else {
            print(
              '⚠️ Erreur lors de la création dans Wix, utilisation de l\'ID temporaire',
            );
            realProfessionalId = widget.professionalId;
          }
        } catch (e) {
          print('❌ Erreur création professionnel après paiement: $e');
          realProfessionalId =
              widget.professionalId; // Fallback sur ID temporaire
        }
      } else {
        print(
          '⚠️ Pas de données d\'inscription, utilisation de l\'ID existant',
        );
        realProfessionalId = widget.professionalId;
      }

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => PaymentSuccessPage(
            professionalId: realProfessionalId ?? widget.professionalId,
            planType: widget.planType,
            businessName: widget.businessName,
            amountPaid: widget.amount,
            paymentId: paymentId,
            professionalEmail: widget.email,
            categoryId: widget.categoryId,
            categoryName: widget.categoryName,
            categoryNameEn: widget.categoryNameEn,
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEnglish = _localization.currentLanguage == 'en';

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(
          isEnglish ? 'Payment in Progress' : 'Paiement en cours',
          style: const TextStyle(color: Colors.white),
        ),
        backgroundColor: Colors.blue[700],
        iconTheme: const IconThemeData(color: Colors.white),
        automaticallyImplyLeading: false,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Indicateur de chargement
              Container(
                width: 80,
                height: 80,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.blue[50],
                  border: Border.all(color: Colors.blue[200]!, width: 2),
                ),
                child: CircularProgressIndicator(
                  strokeWidth: 4,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.blue[700]!),
                ),
              ),

              const SizedBox(height: 32),

              Text(
                isEnglish
                    ? 'Complete Your Payment'
                    : 'Complétez votre paiement',
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
                textAlign: TextAlign.center,
              ),

              const SizedBox(height: 16),

              Text(
                isEnglish
                    ? 'You have been redirected to Stripe to complete your payment. Return to this app after completing the payment.'
                    : 'Vous avez été redirigé vers Stripe pour compléter votre paiement. Revenez à cette app après avoir complété le paiement.',
                style: const TextStyle(
                  fontSize: 16,
                  color: Color(0xFF757575),
                  height: 1.5,
                ),
                textAlign: TextAlign.center,
              ),

              const SizedBox(height: 40),

              // Informations du paiement
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.grey[50],
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey[200]!),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isEnglish ? 'Payment Details' : 'Détails du paiement',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 16),
                    _buildDetailRow(
                      isEnglish ? 'Business' : 'Entreprise',
                      widget.businessName,
                    ),
                    const SizedBox(height: 12),
                    _buildDetailRow(
                      isEnglish ? 'Plan' : 'Plan',
                      _getPlanName(widget.planType, isEnglish),
                    ),
                    const SizedBox(height: 12),
                    _buildDetailRow(
                      isEnglish ? 'Amount' : 'Montant',
                      '\$${widget.amount.toStringAsFixed(2)} CAD',
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 40),

              // Instructions
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.blue[50],
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.blue[200]!),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, color: Colors.blue[700], size: 24),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        isEnglish
                            ? 'This page will automatically detect when you return from Stripe and show your payment confirmation.'
                            : 'Cette page détectera automatiquement votre retour de Stripe et affichera votre confirmation de paiement.',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.blue[800],
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // Bouton de retour d'urgence
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop();
                },
                child: Text(
                  isEnglish ? 'Cancel Payment' : 'Annuler le paiement',
                  style: TextStyle(color: Colors.grey[600], fontSize: 16),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 16,
            color: Color(0xFF757575),
            fontWeight: FontWeight.w500,
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Colors.black87,
            ),
            textAlign: TextAlign.right,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  String _getPlanName(String planType, bool isEnglish) {
    switch (planType.toLowerCase()) {
      case 'basic':
        return isEnglish ? 'Basic Plan' : 'Plan Basique';
      case 'premium':
        return isEnglish ? 'Premium Plan' : 'Plan Premium';
      case 'professional':
        return isEnglish ? 'Professional Plan' : 'Plan Professionnel';
      default:
        return planType;
    }
  }
}
