import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/localization_service.dart';
import '../services/store_purchase_service.dart';
import 'payment_success_page.dart';

typedef ExternalLinkLauncher = Future<bool> Function(Uri uri);

class StorePurchasePage extends StatefulWidget {
  const StorePurchasePage({
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
    this.purchaseService,
    this.initialProduct,
    this.store,
    this.linkLauncher,
  });

  final String professionalId;
  final String businessName;
  final String email;
  final String selectedPlan;
  final PaymentPlanQuote serverQuote;
  final String? categoryId;
  final String? categoryName;
  final String? categoryNameEn;
  final Map<String, dynamic>? registrationData;
  final StorePurchaseService? purchaseService;
  final StoreProductOffer? initialProduct;
  final StorePlatform? store;
  final ExternalLinkLauncher? linkLauncher;

  @override
  State<StorePurchasePage> createState() => _StorePurchasePageState();
}

class _StorePurchasePageState extends State<StorePurchasePage> {
  final LocalizationService _localization = LocalizationService();

  StorePurchaseService? _purchaseService;
  StreamSubscription<StorePurchaseUpdate>? _purchaseSubscription;
  StoreProductOffer? _storeProduct;
  StorePurchaseStatus? _status;
  String? _errorMessage;
  bool _isLoadingProduct = false;
  bool _didNavigate = false;
  bool _isShowingErrorDialog = false;

  bool get _paymentSupported {
    if (kIsWeb) return false;
    return widget.purchaseService != null ||
        StorePurchaseService.isSupportedPlatform;
  }

  StorePlatform? get _storePlatform => widget.store ?? StorePlatform.current;

  bool get _isProcessing => switch (_status) {
    StorePurchaseStatus.preparing ||
    StorePurchaseStatus.restoring ||
    StorePurchaseStatus.pending ||
    StorePurchaseStatus.verifying => true,
    _ => false,
  };

  @override
  void initState() {
    super.initState();
    final expectedProductId = StoreProductIds.productIdForPlan(
      widget.selectedPlan,
    );
    final initialProduct = widget.initialProduct;
    if (widget.serverQuote.id == widget.selectedPlan &&
        widget.serverQuote.requiresPayment &&
        initialProduct?.productId == expectedProductId) {
      _storeProduct = initialProduct;
    }
    if (_paymentSupported) {
      _purchaseService = widget.purchaseService ?? StorePurchaseService.shared;
      _purchaseSubscription = _purchaseService!.updates.listen(
        _handlePurchaseUpdate,
      );
      unawaited(_loadStoreProduct());
    }
  }

  @override
  void dispose() {
    _purchaseSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isEnglish = _localization.currentLanguage == 'en';
    final quote = widget.serverQuote;
    final planName = isEnglish ? quote.labelEn : quote.labelFr;
    final features = isEnglish ? quote.featuresEn : quote.featuresFr;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _paymentSupported
              ? (isEnglish ? 'Secure purchase' : 'Achat sécurisé')
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
            _buildAvailabilityNotice(isEnglish),
            const SizedBox(height: 24),
            _buildPlanSummary(planName, features, isEnglish),
            const SizedBox(height: 24),
            _buildOrderSummary(planName, isEnglish),
            const SizedBox(height: 16),
            _buildSubscriptionTerms(isEnglish),
            const SizedBox(height: 16),
            _buildPurchaseStatus(isEnglish),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              height: 56,
              child: FilledButton.icon(
                key: const Key('store_purchase_buy'),
                onPressed:
                    !_paymentSupported ||
                        _isLoadingProduct ||
                        _isProcessing ||
                        _storeProduct == null
                    ? null
                    : _startPurchase,
                icon: _isProcessing
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.shopping_bag_outlined),
                label: Text(_primaryButtonLabel(isEnglish)),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                key: const Key('store_purchase_restore'),
                onPressed:
                    !_paymentSupported ||
                        _isLoadingProduct ||
                        _isProcessing ||
                        _storeProduct == null
                    ? null
                    : _restorePurchase,
                icon: const Icon(Icons.restore),
                label: Text(
                  isEnglish ? 'Restore my purchases' : 'Restaurer mes achats',
                ),
              ),
            ),
            const SizedBox(height: 20),
            if (_paymentSupported)
              Center(
                child: Text(
                  isEnglish
                      ? 'Purchase handled securely by ${_storeName(isEnglish)}'
                      : 'Achat traité de façon sécurisée par ${_storeName(isEnglish)}',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildAvailabilityNotice(bool isEnglish) {
    final theme = Theme.of(context);
    if (!_paymentSupported) {
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.verified_user_outlined, color: Colors.green[700]),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              isEnglish
                  ? 'The store processes this purchase. Index Canada activates the plan only after server verification.'
                  : 'Le store traite cet achat. Index Canada active le forfait uniquement après vérification serveur.',
              style: TextStyle(color: Colors.green[700]),
            ),
          ),
        ],
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
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.check, color: Colors.green[600], size: 16),
                    const SizedBox(width: 8),
                    Expanded(child: Text(feature)),
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
    final price = _storeProduct?.localizedPrice ?? '—';
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              isEnglish ? 'Order summary' : 'Résumé de commande',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(child: Text(planName)),
                const SizedBox(width: 12),
                Text(
                  price,
                  key: const Key('store_purchase_localized_price'),
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const Divider(),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  isEnglish ? 'Billed annually' : 'Facturé annuellement',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                Text(
                  price,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSubscriptionTerms(bool isEnglish) {
    final theme = Theme.of(context);
    final store = _storePlatform;
    final manageUri = switch (store) {
      StorePlatform.appStore => Uri.parse(
        'https://apps.apple.com/account/subscriptions',
      ),
      StorePlatform.googlePlay => Uri.parse(
        'https://play.google.com/store/account/subscriptions',
      ),
      null => null,
    };
    final renewalText = switch (store) {
      StorePlatform.appStore =>
        isEnglish
            ? 'This annual subscription renews automatically. Payment is charged to your App Store account. Manage or cancel it from your App Store account settings.'
            : 'Cet abonnement annuel se renouvelle automatiquement. Le paiement est débité de votre compte App Store. Gérez-le ou annulez-le dans les réglages de votre compte App Store.',
      StorePlatform.googlePlay =>
        isEnglish
            ? 'This annual subscription renews automatically. Payment is charged to your Google Play account. Manage or cancel it from your Google Play subscriptions.'
            : 'Cet abonnement annuel se renouvelle automatiquement. Le paiement est débité de votre compte Google Play. Gérez-le ou annulez-le dans vos abonnements Google Play.',
      null =>
        isEnglish
            ? 'This annual subscription renews automatically and is managed in your mobile store account.'
            : 'Cet abonnement annuel se renouvelle automatiquement et se gère dans votre compte de boutique mobile.',
    };

    return Semantics(
      container: true,
      child: Container(
        key: const Key('store_purchase_subscription_terms'),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              isEnglish
                  ? 'Subscription information'
                  : 'Informations d’abonnement',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(renewalText),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                if (manageUri != null)
                  TextButton(
                    key: const Key('store_purchase_manage'),
                    onPressed: () {
                      unawaited(_openLegalLink(manageUri));
                    },
                    child: Text(
                      isEnglish ? 'Manage subscription' : 'Gérer l’abonnement',
                    ),
                  ),
                TextButton(
                  key: const Key('store_purchase_privacy'),
                  onPressed: () {
                    unawaited(
                      _openLegalLink(
                        Uri.parse('https://www.immigrantindex.com/privacy'),
                      ),
                    );
                  },
                  child: Text(
                    isEnglish
                        ? 'Privacy Policy'
                        : 'Politique de confidentialité',
                  ),
                ),
                if (store == StorePlatform.appStore)
                  TextButton(
                    key: const Key('store_purchase_eula'),
                    onPressed: () {
                      unawaited(
                        _openLegalLink(
                          Uri.parse(
                            'https://www.apple.com/legal/internet-services/itunes/dev/stdeula/',
                          ),
                        ),
                      );
                    },
                    child: Text(
                      isEnglish
                          ? 'Terms of Use (Apple EULA)'
                          : 'Conditions d’utilisation (EULA Apple)',
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPurchaseStatus(bool isEnglish) {
    final theme = Theme.of(context);
    if (_isLoadingProduct) {
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
                  ? 'Loading the current store price…'
                  : 'Chargement du prix actuel du store…',
            ),
          ),
        ],
      );
    }
    if (_errorMessage != null) {
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
                _errorMessage!,
                style: TextStyle(color: theme.colorScheme.onErrorContainer),
              ),
            ),
            TextButton(
              onPressed: _loadStoreProduct,
              child: Text(isEnglish ? 'Retry' : 'Réessayer'),
            ),
          ],
        ),
      );
    }
    final message = switch (_status) {
      StorePurchaseStatus.preparing =>
        isEnglish
            ? 'Preparing the secure purchase…'
            : 'Préparation de l’achat sécurisé…',
      StorePurchaseStatus.restoring =>
        isEnglish
            ? 'Looking for previous purchases…'
            : 'Recherche des achats précédents…',
      StorePurchaseStatus.pending =>
        isEnglish
            ? 'The purchase is pending in the store.'
            : 'L’achat est en attente dans le store.',
      StorePurchaseStatus.verifying =>
        isEnglish
            ? 'Verifying the purchase with Index Canada…'
            : 'Vérification de l’achat auprès d’Index Canada…',
      StorePurchaseStatus.canceled =>
        isEnglish
            ? 'Purchase canceled. You can try again.'
            : 'Achat annulé. Vous pouvez réessayer.',
      _ =>
        isEnglish
            ? 'Price supplied by ${_storeName(isEnglish)}.'
            : 'Prix fourni par ${_storeName(isEnglish)}.',
    };
    return Row(
      children: [
        Icon(
          _status == StorePurchaseStatus.canceled
              ? Icons.info_outline
              : Icons.verified_outlined,
          size: 18,
          color: theme.colorScheme.primary,
        ),
        const SizedBox(width: 8),
        Expanded(child: Text(message)),
      ],
    );
  }

  String _primaryButtonLabel(bool isEnglish) {
    return switch (_status) {
      StorePurchaseStatus.preparing =>
        isEnglish ? 'Preparing…' : 'Préparation…',
      StorePurchaseStatus.pending =>
        isEnglish ? 'Purchase pending…' : 'Achat en attente…',
      StorePurchaseStatus.verifying =>
        isEnglish ? 'Verifying…' : 'Vérification…',
      StorePurchaseStatus.restoring =>
        isEnglish ? 'Restoring…' : 'Restauration…',
      _ => isEnglish ? 'Continue in store' : 'Continuer dans le store',
    };
  }

  String _storeName(bool isEnglish) {
    return switch (_storePlatform) {
      StorePlatform.appStore => 'App Store',
      StorePlatform.googlePlay => 'Google Play',
      null => isEnglish ? 'mobile store' : 'store mobile',
    };
  }

  Future<void> _openLegalLink(Uri uri) async {
    var launched = false;
    try {
      final launcher = widget.linkLauncher;
      launched = launcher != null
          ? await launcher(uri)
          : await launchUrl(uri, mode: LaunchMode.externalApplication);
    } on Exception {
      launched = false;
    }
    if (!launched && mounted) {
      final isEnglish = _localization.currentLanguage == 'en';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isEnglish
                ? 'The link could not be opened.'
                : 'Le lien n’a pas pu être ouvert.',
          ),
        ),
      );
    }
  }

  Future<void> _loadStoreProduct() async {
    final service = _purchaseService;
    if (service == null) return;
    setState(() {
      _isLoadingProduct = true;
      _errorMessage = null;
    });
    try {
      final products = await service.loadProducts(forceRefresh: true);
      final product = products[widget.selectedPlan];
      if (product == null) {
        throw const StorePurchaseException(
          'STORE_PRODUCT_UNAVAILABLE',
          'The selected store product is unavailable.',
        );
      }
      if (!mounted) return;
      setState(() {
        _storeProduct = product;
        _isLoadingProduct = false;
      });
    } on Exception {
      if (!mounted) return;
      setState(() {
        _isLoadingProduct = false;
        _errorMessage = _localization.currentLanguage == 'en'
            ? 'The current store price is unavailable.'
            : 'Le prix actuel du store est indisponible.';
      });
    }
  }

  Future<void> _startPurchase() async {
    if (_isProcessing) return;
    setState(() {
      _status = StorePurchaseStatus.preparing;
      _errorMessage = null;
    });
    try {
      await _purchaseService!.startPurchase(_purchaseRequest());
    } on Exception {
      if (mounted && _errorMessage == null) {
        setState(() => _status = StorePurchaseStatus.error);
      }
    }
  }

  Future<void> _restorePurchase() async {
    if (_isProcessing) return;
    setState(() {
      _status = StorePurchaseStatus.restoring;
      _errorMessage = null;
    });
    try {
      await _purchaseService!.restorePurchase(planId: widget.selectedPlan);
    } on Exception {
      if (mounted && _errorMessage == null) {
        setState(() => _status = StorePurchaseStatus.error);
      }
    }
  }

  StorePurchaseRequest _purchaseRequest() {
    final registration = widget.registrationData ?? const <String, dynamic>{};
    return StorePurchaseRequest(
      planId: widget.selectedPlan,
      professionalId: widget.professionalId,
      email: widget.email,
      businessName: widget.businessName,
      categoryId:
          widget.categoryId ?? registration['category']?.toString() ?? '',
      ville: registration['city']?.toString() ?? '',
      phone: registration['phone']?.toString() ?? '',
      registrationData: registration,
      maxGalleryImages: widget.serverQuote.capabilities.galleryMax,
    );
  }

  void _handlePurchaseUpdate(StorePurchaseUpdate update) {
    if (!mounted ||
        (update.planId != null && update.planId != widget.selectedPlan)) {
      return;
    }
    switch (update.status) {
      case StorePurchaseStatus.loadingProducts:
      case StorePurchaseStatus.ready:
        return;
      case StorePurchaseStatus.preparing:
      case StorePurchaseStatus.restoring:
      case StorePurchaseStatus.pending:
      case StorePurchaseStatus.verifying:
        setState(() {
          _status = update.status;
          _errorMessage = null;
        });
        break;
      case StorePurchaseStatus.canceled:
        setState(() {
          _status = StorePurchaseStatus.canceled;
          _errorMessage = null;
        });
        break;
      case StorePurchaseStatus.error:
        final message = _messageForError(update.errorCode);
        setState(() {
          _status = StorePurchaseStatus.error;
          _errorMessage = message;
        });
        if (!update.isReplay) unawaited(_showErrorDialog(message));
        break;
      case StorePurchaseStatus.purchased:
      case StorePurchaseStatus.restored:
        if (update.isReplay) {
          setState(() {
            _status = update.status;
            _errorMessage = null;
          });
        } else {
          unawaited(_openSuccessPage(update));
        }
        break;
    }
  }

  Future<void> _openSuccessPage(StorePurchaseUpdate update) async {
    if (_didNavigate || !mounted) return;
    final confirmation = update.confirmation;
    final product = _storeProduct;
    if (confirmation == null || product == null || update.checkoutId == null) {
      final message = _messageForError('INVALID_STORE_CONFIRMATION');
      setState(() {
        _status = StorePurchaseStatus.error;
        _errorMessage = message;
      });
      await _showErrorDialog(message);
      return;
    }
    _didNavigate = true;
    final professionalId = confirmation.professionalId ?? widget.professionalId;
    await Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (context) => PaymentSuccessPage(
          professionalId: professionalId,
          businessName: widget.businessName,
          planType: widget.selectedPlan,
          amountPaid: product.rawPrice,
          currency: product.currencyCode,
          paymentId: update.checkoutId!,
          professionalEmail: widget.email,
          categoryId: widget.categoryId,
          categoryName: widget.categoryName,
          categoryNameEn: widget.categoryNameEn,
          confirmation: confirmation,
        ),
      ),
    );
  }

  String _messageForError(String? code) {
    final isEnglish = _localization.currentLanguage == 'en';
    return switch (code) {
      'NO_STORE_PURCHASE_FOUND' =>
        isEnglish
            ? 'No matching purchase was found for this plan.'
            : 'Aucun achat correspondant n’a été trouvé pour ce forfait.',
      'INVALID_STORE_PURCHASE' || 'INVALID_STORE_CONFIRMATION' =>
        isEnglish
            ? 'The purchase could not be verified. Do not purchase again; retry the verification.'
            : 'L’achat n’a pas pu être vérifié. Ne rachetez pas; réessayez la vérification.',
      'STORE_UNAVAILABLE' || 'STORE_PRODUCTS_INCOMPLETE' =>
        isEnglish
            ? 'The store is temporarily unavailable.'
            : 'Le store est temporairement indisponible.',
      _ =>
        isEnglish
            ? 'The purchase could not be completed. Please try again.'
            : 'L’achat n’a pas pu être finalisé. Veuillez réessayer.',
    };
  }

  Future<void> _showErrorDialog(String message) async {
    if (!mounted || _isShowingErrorDialog) return;
    _isShowingErrorDialog = true;
    final isEnglish = _localization.currentLanguage == 'en';
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(isEnglish ? 'Purchase error' : 'Erreur d’achat'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(isEnglish ? 'OK' : 'D’accord'),
          ),
        ],
      ),
    );
    _isShowingErrorDialog = false;
  }
}
