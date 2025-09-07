import 'package:flutter/material.dart';
import '../services/localization_service.dart';
import '../services/confirmation_email_service.dart';
import '../data_service.dart';
import '../models.dart';
import 'professionnel_detail_page.dart';
import 'services_page.dart';

class PaymentSuccessPage extends StatefulWidget {
  final String professionalId;
  final String planType;
  final String businessName;
  final double amountPaid;
  final String paymentId;
  final String? professionalEmail;
  final String? categoryId;
  final String? categoryName;
  final String? categoryNameEn;

  const PaymentSuccessPage({
    Key? key,
    required this.professionalId,
    required this.planType,
    required this.businessName,
    required this.amountPaid,
    required this.paymentId,
    this.professionalEmail,
    this.categoryId,
    this.categoryName,
    this.categoryNameEn,
  }) : super(key: key);

  @override
  State<PaymentSuccessPage> createState() => _PaymentSuccessPageState();
}

class _PaymentSuccessPageState extends State<PaymentSuccessPage>
    with TickerProviderStateMixin {
  final LocalizationService _localizationService = LocalizationService();

  late AnimationController _spinnerController;
  late AnimationController _successController;
  late Animation<double> _scaleAnimation;

  bool _isProcessing = true;
  bool _isPaymentConfirmed = false;
  bool _hasError = false;
  String _errorMessage = '';
  Professionnel? _professional;

  @override
  void initState() {
    super.initState();

    // Animation pour le spinner
    _spinnerController = AnimationController(
      duration: const Duration(seconds: 1),
      vsync: this,
    )..repeat();

    // Animation pour le succès
    _successController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );

    _scaleAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _successController, curve: Curves.elasticOut),
    );

    // Démarrer le processus de confirmation automatiquement
    _confirmPaymentAutomatically();
  }

  @override
  void dispose() {
    _spinnerController.dispose();
    _successController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isEnglish = _localizationService.currentLanguage == 'en';

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(
          isEnglish ? 'Payment Processing' : 'Traitement du paiement',
          style: const TextStyle(color: Colors.white),
        ),
        backgroundColor: Colors.blue[700],
        iconTheme: const IconThemeData(color: Colors.white),
        automaticallyImplyLeading:
            false, // Désactiver le bouton retour pendant le traitement
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: _buildCurrentView(),
        ),
      ),
    );
  }

  Widget _buildCurrentView() {
    if (_isProcessing) {
      return _buildLoadingView();
    } else if (_hasError) {
      return _buildErrorView();
    } else if (_isPaymentConfirmed) {
      return _buildSuccessView();
    } else {
      return _buildLoadingView();
    }
  }

  Widget _buildLoadingView() {
    final isEnglish = _localizationService.currentLanguage == 'en';

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // Spinner animé
        RotationTransition(
          turns: _spinnerController,
          child: Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: Colors.blue[700]!, width: 6),
            ),
            child: const CircularProgressIndicator(
              strokeWidth: 6,
              valueColor: AlwaysStoppedAnimation<Color>(Colors.blue),
            ),
          ),
        ),

        const SizedBox(height: 32),

        Text(
          isEnglish ? 'Processing Payment...' : 'Traitement du paiement...',
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
              ? 'Please wait while we confirm your payment and activate your professional profile.'
              : 'Veuillez patienter pendant que nous confirmons votre paiement et activons votre profil professionnel.',
          style: const TextStyle(
            fontSize: 16,
            color: Color(0xFF757575), // Couleur grise fixe
          ),
          textAlign: TextAlign.center,
        ),

        const SizedBox(height: 24),

        // Informations du paiement
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.grey[50],
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey[200]!),
          ),
          child: Column(
            children: [
              _buildPaymentInfo(
                isEnglish ? 'Business' : 'Entreprise',
                widget.businessName,
              ),
              const SizedBox(height: 8),
              _buildPaymentInfo(
                isEnglish ? 'Plan' : 'Plan',
                _getPlanName(widget.planType, isEnglish),
              ),
              const SizedBox(height: 8),
              _buildPaymentInfo(
                isEnglish ? 'Amount' : 'Montant',
                '\$${widget.amountPaid.toStringAsFixed(2)} CAD',
              ),
              const SizedBox(height: 8),
              _buildPaymentInfo(
                isEnglish ? 'Payment ID' : 'ID de paiement',
                widget.paymentId,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSuccessView() {
    final isEnglish = _localizationService.currentLanguage == 'en';

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // Animation de succès
        ScaleTransition(
          scale: _scaleAnimation,
          child: Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.green[700],
              boxShadow: [
                BoxShadow(
                  color: Colors.green.withOpacity(0.3),
                  blurRadius: 20,
                  spreadRadius: 5,
                ),
              ],
            ),
            child: const Icon(Icons.check, color: Colors.white, size: 60),
          ),
        ),

        const SizedBox(height: 32),

        Text(
          isEnglish ? 'Payment Successful!' : 'Paiement réussi !',
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.bold,
            color: Colors.green[700],
          ),
          textAlign: TextAlign.center,
        ),

        const SizedBox(height: 16),

        Text(
          isEnglish
              ? 'Your professional profile has been activated successfully!'
              : 'Votre profil professionnel a été activé avec succès !',
          style: const TextStyle(fontSize: 18, color: Colors.black87),
          textAlign: TextAlign.center,
        ),

        const SizedBox(height: 8),

        // 📧 AMÉLIORÉ: Message plus détaillé sur l'email de confirmation
        Container(
          padding: const EdgeInsets.all(16),
          margin: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: Colors.blue[50],
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.blue[200]!),
          ),
          child: Row(
            children: [
              Icon(Icons.email, color: Colors.blue[700], size: 24),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isEnglish
                          ? 'Confirmation Email'
                          : 'Email de confirmation',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.blue[700],
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      widget.professionalEmail != null
                          ? (isEnglish
                                ? 'A confirmation email has been sent to ${widget.professionalEmail}'
                                : 'Un email de confirmation a été envoyé à ${widget.professionalEmail}')
                          : (isEnglish
                                ? 'You will receive a confirmation email shortly.'
                                : 'Vous recevrez un email de confirmation sous peu.'),
                      style: TextStyle(fontSize: 14, color: Colors.blue[600]),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 40),

        // Boutons d'action
        Column(
          children: [
            // Bouton "Voir mon profil"
            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton.icon(
                onPressed: _goToProfessionalProfile,
                icon: const Icon(Icons.person, size: 24),
                label: Text(
                  isEnglish ? 'View My Profile' : 'Voir mon profil',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue[700],
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 4,
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Bouton "Parfait" (retour à l'accueil)
            SizedBox(
              width: double.infinity,
              height: 56,
              child: OutlinedButton.icon(
                onPressed: _returnToHome,
                icon: const Icon(Icons.home, size: 24),
                label: Text(
                  isEnglish ? 'View Services' : 'Voir les Services',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.blue[700],
                  side: BorderSide(color: Colors.blue[700]!, width: 2),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildErrorView() {
    final isEnglish = _localizationService.currentLanguage == 'en';

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.error_outline, color: Colors.red[700], size: 80),

        const SizedBox(height: 24),

        Text(
          isEnglish ? 'Payment Error' : 'Erreur de paiement',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: Colors.red[700],
          ),
          textAlign: TextAlign.center,
        ),

        const SizedBox(height: 16),

        Text(
          _errorMessage.isNotEmpty
              ? _errorMessage
              : (isEnglish
                    ? 'Unable to confirm your payment. Please contact support.'
                    : 'Impossible de confirmer votre paiement. Veuillez contacter le support.'),
          style: const TextStyle(fontSize: 16),
          textAlign: TextAlign.center,
        ),

        const SizedBox(height: 32),

        Row(
          children: [
            Expanded(
              child: ElevatedButton(
                onPressed: _retryPaymentConfirmation,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue[700],
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: Text(
                  isEnglish ? 'Retry' : 'Réessayer',
                  style: const TextStyle(fontSize: 16),
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: OutlinedButton(
                onPressed: _returnToHome,
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF757575), // Gris fixe
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: Text(
                  isEnglish ? 'View Services' : 'Voir les Services',
                  style: const TextStyle(fontSize: 16),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildPaymentInfo(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 14,
            color: Color(0xFF757575), // Gris fixe
            fontWeight: FontWeight.w500,
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            textAlign: TextAlign.right,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Future<void> _confirmPaymentAutomatically() async {
    try {
      // Attendre un peu pour l'effet visuel du spinner
      await Future.delayed(const Duration(seconds: 2));

      // NOTE: Le paiement est déjà confirmé via le système Stripe natif
      // Plus besoin d'appeler updateProfessionalPlan car ConfirmPayment s'en charge
      /* 
      final success = await WixPaymentService.updateProfessionalPlan(
        professionalId: widget.professionalId,
        planType: widget.planType,
        paymentId: widget.paymentId,
        amountPaid: widget.amountPaid,
      );
      */

      final success = true; // Le paiement est déjà confirmé

      if (success) {
        // Charger les informations du professionnel
        await _loadProfessionalData();

        // 📧 NOUVEAU: Vérifier et envoyer l'email de confirmation
        if (_professional != null && widget.professionalEmail != null) {
          print('📧 Vérification email de confirmation...');

          try {
            await ConfirmationEmailService.checkAndResendIfNeeded(
              professionalId: widget.professionalId,
              email: widget.professionalEmail!,
              businessName: widget.businessName,
            );

            // Informer l'utilisateur qu'un email de confirmation sera envoyé
            await ConfirmationEmailService.showPostRegistrationEmailInfo(
              businessName: widget.businessName,
              email: widget.professionalEmail!,
              planName: _getPlanName(
                widget.planType,
                _localizationService.currentLanguage == 'en',
              ),
            );

            print('✅ Processus email de confirmation terminé');
          } catch (emailError) {
            print('⚠️ Erreur email de confirmation: $emailError');
            // Ne pas faire échouer la confirmation de paiement pour un problème d'email
          }
        }

        setState(() {
          _isProcessing = false;
          _isPaymentConfirmed = true;
        });

        // Démarrer l'animation de succès
        _successController.forward();
      }
    } catch (e) {
      print('Erreur lors de la confirmation automatique: $e');
      setState(() {
        _isProcessing = false;
        _hasError = true;
        _errorMessage = _localizationService.currentLanguage == 'en'
            ? 'Network error. Please check your connection and try again.'
            : 'Erreur réseau. Veuillez vérifier votre connexion et réessayer.';
      });
    }
  }

  Future<void> _loadProfessionalData() async {
    try {
      final dataService = DataService();
      final professionals = await dataService.fetchProfessionnels(
        forceRefresh: true,
      );

      if (professionals.isNotEmpty) {
        // D'abord essayer de trouver par l'ID exact (qui pourrait être l'ID réel maintenant)
        _professional = professionals.firstWhere(
          (prof) => prof.id == widget.professionalId,
          orElse: () {
            // Si pas trouvé, chercher par nom d'entreprise (businessName)
            return professionals.firstWhere(
              (prof) => prof.title == widget.businessName,
              orElse: () {
                // En dernier recours, chercher par email
                return professionals.firstWhere(
                  (prof) => prof.email == widget.professionalEmail,
                  orElse: () {
                    print(
                      '⚠️ Professionnel non trouvé, utilisation du premier disponible',
                    );
                    return professionals.first;
                  },
                );
              },
            );
          },
        );

        print(
          '✅ Professionnel chargé: ${_professional?.title} (ID: ${_professional?.id})',
        );
      }
    } catch (e) {
      print('Erreur lors du chargement des données du professionnel: $e');
    }
  }

  void _retryPaymentConfirmation() {
    setState(() {
      _isProcessing = true;
      _hasError = false;
      _errorMessage = '';
    });
    _confirmPaymentAutomatically();
  }

  void _goToProfessionalProfile() async {
    if (_professional != null) {
      // Navigation directe vers le profil avec stack personnalisé
      if (widget.categoryId != null && widget.categoryName != null) {
        // Nettoyer la pile et aller directement au profil
        // Quand l'utilisateur appuiera sur retour, il ira vers la catégorie
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(
            builder: (context) =>
                ProfessionnelDetailPage(professionnel: _professional!),
          ),
          (route) => route.isFirst, // Garder seulement la HomePage comme base
        );
      } else {
        // Pas de catégorie spécifique, navigation directe vers le profil
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(
            builder: (context) =>
                ProfessionnelDetailPage(professionnel: _professional!),
          ),
          (route) => route.isFirst, // Garder seulement la HomePage comme base
        );
      }
    } else {
      // Fallback - retourner à l'accueil si pas de professionnel trouvé
      _returnToHome();
    }
  }

  void _returnToHome() {
    // Toujours naviguer vers ServicesPage (page des catégories)
    // Cela permet à l'utilisateur de facilement accéder à sa catégorie
    Navigator.of(context).popUntil((route) => route.isFirst);
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ServicesPage()),
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
