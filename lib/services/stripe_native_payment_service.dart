import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_stripe/flutter_stripe.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as image;

import '../core/config/app_config.dart';
import '../utils/image_base64_utils.dart';
import 'localization_service.dart';

final RegExp _paymentPlanIdPattern = RegExp(r'^[A-Za-z0-9_-]{1,64}$');
final RegExp _currencyCodePattern = RegExp(r'^[A-Za-z]{3}$');

/// Décision pure et testable indiquant si le flux de paiement est disponible.
enum PaymentPlatformSupportDecision {
  supported,
  paidPaymentSheetUnavailableOnWeb;

  bool get isSupported => this == PaymentPlatformSupportDecision.supported;

  String? get errorCode => switch (this) {
    PaymentPlatformSupportDecision.supported => null,
    PaymentPlatformSupportDecision.paidPaymentSheetUnavailableOnWeb =>
      'PAYMENT_PLATFORM_UNSUPPORTED',
  };
}

/// Politique centralisée : le forfait gratuit ne dépend pas de PaymentSheet.
abstract final class PaymentPlatformSupportPolicy {
  static PaymentPlatformSupportDecision evaluate({
    required bool requiresPayment,
    required bool isWeb,
  }) {
    if (requiresPayment && isWeb) {
      return PaymentPlatformSupportDecision.paidPaymentSheetUnavailableOnWeb;
    }
    return PaymentPlatformSupportDecision.supported;
  }
}

/// Les prix, les devises et l’état d’activation viennent du catalogue serveur.
/// Le backend vérifie aussi Stripe avant d’activer un profil payant.
abstract final class StripeNativePaymentService {
  static final StripePaymentApi _api = StripePaymentApi(
    baseUrl: AppConfig.current.apiBaseUrl,
  );
  static final Map<String, PaymentConfirmation> _finalizedConfirmations = {};

  static PaymentPlatformSupportDecision paymentSupportFor({
    required bool requiresPayment,
  }) {
    return PaymentPlatformSupportPolicy.evaluate(
      requiresPayment: requiresPayment,
      isWeb: kIsWeb,
    );
  }

  static Future<PaymentResult> processNativePayment({
    required String planId,
    required String professionalId,
    required String email,
    required String businessName,
    required PaymentPlanQuote serverQuote,
    String? categoryId,
    String? ville,
    String? phone,
    Map<String, dynamic>? registrationData,
  }) async {
    if (!_paymentPlanIdPattern.hasMatch(planId.trim())) {
      return PaymentResult.failure(
        _message(
          fr: 'Le forfait sélectionné n’est pas valide.',
          en: 'The selected plan is not valid.',
        ),
        errorCode: 'INVALID_PLAN',
      );
    }
    if (serverQuote.id != planId.trim()) {
      return PaymentResult.failure(
        _message(
          fr: 'Le forfait sélectionné ne correspond plus aux options actuelles.',
          en: 'The selected plan no longer matches the current options.',
        ),
        errorCode: 'CHECKOUT_QUOTE_MISMATCH',
      );
    }
    final platformSupport = paymentSupportFor(
      requiresPayment: serverQuote.requiresPayment,
    );
    if (!platformSupport.isSupported) {
      return PaymentResult.failure(
        _messageForPlatformSupport(platformSupport),
        errorCode: platformSupport.errorCode,
      );
    }
    if (serverQuote.requiresPayment &&
        !AppConfig.current.hasValidStripeConfiguration) {
      return PaymentResult.failure(
        _message(
          fr: 'Le paiement est temporairement indisponible.',
          en: 'Payment is temporarily unavailable.',
        ),
        errorCode: 'PAYMENT_CONFIGURATION_UNAVAILABLE',
      );
    }

    try {
      final checkout = await _api.createCheckout(
        planId: planId.trim(),
        professionalId: professionalId,
        email: email,
        businessName: businessName,
        categoryId: categoryId,
        ville: ville,
        phone: phone,
        registrationData: registrationData ?? const <String, dynamic>{},
        maxGalleryImages: serverQuote.capabilities.galleryMax,
      );

      if (!_quoteMatchesExpectation(checkout, serverQuote)) {
        return PaymentResult.failure(
          _message(
            fr: 'Le prix du forfait a changé. Aucun paiement n’a été lancé; vérifiez le prix actuel avant de continuer.',
            en: 'The plan price changed. No payment was started; review the current price before continuing.',
          ),
          errorCode: 'CHECKOUT_QUOTE_MISMATCH',
        );
      }

      if (checkout.alreadyFinalized) {
        final confirmation = PaymentConfirmation.finalized(
          professionalId: checkout.professionalId!,
          planId: planId,
          isActive: checkout.requiresPayment,
          status: checkout.requiresPayment ? 'active' : 'pending_review',
          checkoutId: checkout.checkoutId!,
        );
        _rememberFinalizedConfirmation(
          checkout.confirmationReference,
          confirmation,
        );
        return PaymentResult.success(
          checkout.confirmationReference,
          checkoutId: checkout.checkoutId,
          amountCents: checkout.amountCents,
          currency: checkout.currency,
          preparedRegistrationData: checkout.preparedRegistrationData,
          confirmation: confirmation,
        );
      }

      if (!checkout.requiresPayment) {
        return PaymentResult.success(
          checkout.confirmationReference,
          checkoutId: checkout.checkoutId,
          amountCents: checkout.amountCents,
          currency: checkout.currency,
          preparedRegistrationData: checkout.preparedRegistrationData,
        );
      }

      await Stripe.instance.initPaymentSheet(
        paymentSheetParameters: SetupPaymentSheetParameters(
          paymentIntentClientSecret: checkout.clientSecret!,
          merchantDisplayName: AppConfig.current.appName,
          customerEphemeralKeySecret: checkout.ephemeralKey,
          customerId: checkout.customerId,
          returnURL: '${AppConfig.current.stripeUrlScheme.trim()}://redirect',
          style: ThemeMode.system,
          billingDetails: BillingDetails(
            email: email.trim(),
            name: businessName.trim(),
          ),
        ),
      );
      await Stripe.instance.presentPaymentSheet();

      return PaymentResult.success(
        checkout.confirmationReference,
        checkoutId: checkout.checkoutId,
        amountCents: checkout.amountCents,
        currency: checkout.currency,
        preparedRegistrationData: checkout.preparedRegistrationData,
      );
    } on StripeException catch (error) {
      if (error.error.code == FailureCode.Canceled) {
        return const PaymentResult.canceled();
      }
      return PaymentResult.failure(
        _message(
          fr: 'Le paiement n’a pas pu être finalisé. Veuillez réessayer.',
          en: 'The payment could not be completed. Please try again.',
        ),
      );
    } on TimeoutException {
      return PaymentResult.failure(
        _message(
          fr: 'Le service met trop de temps à répondre. Veuillez réessayer.',
          en: 'The service is taking too long to respond. Please try again.',
        ),
      );
    } on PaymentApiException catch (error) {
      return PaymentResult.failure(
        _messageForApiError(error.code),
        errorCode: error.code,
      );
    } on http.ClientException {
      return PaymentResult.failure(_networkErrorMessage());
    } on FormatException {
      return PaymentResult.failure(_networkErrorMessage());
    } on RegistrationImageException catch (error) {
      return PaymentResult.failure(
        _messageForImageError(error.code),
        errorCode: error.code,
      );
    }
  }

  static bool _quoteMatchesExpectation(
    CheckoutSession checkout,
    PaymentPlanQuote serverQuote,
  ) {
    if (checkout.requiresPayment != serverQuote.requiresPayment ||
        checkout.amountCents != serverQuote.amountCents) {
      return false;
    }
    if (checkout.currency?.toLowerCase() != serverQuote.currency) {
      return false;
    }
    return true;
  }

  static Future<PaymentPlanCatalog> fetchPaymentPlans() {
    return _api.fetchPaymentPlans();
  }

  static Future<PaymentConfirmation> confirmPaymentOnServerTyped({
    required String paymentIntentId,
    String? checkoutId,
  }) async {
    final finalized = _takeFinalizedConfirmation(paymentIntentId, checkoutId);
    if (finalized != null) return finalized;
    try {
      final confirmation = await _api.confirmCheckout(
        confirmationToken: paymentIntentId,
      );
      return confirmation.withFallbackCheckoutId(checkoutId);
    } on TimeoutException {
      return PaymentConfirmation.failure(
        code: 'REQUEST_TIMEOUT',
        message: _message(
          fr: 'La confirmation prend trop de temps. Réessayez sans repayer.',
          en: 'Confirmation is taking too long. Try again without paying again.',
        ),
        checkoutId: checkoutId,
      );
    } on PaymentApiException catch (error) {
      return PaymentConfirmation.failure(
        code: error.code,
        message: _messageForApiError(error.code),
        httpStatusCode: error.statusCode,
        checkoutId: checkoutId,
      );
    } on http.ClientException {
      return PaymentConfirmation.failure(
        code: 'NETWORK_ERROR',
        message: _message(
          fr: 'Connexion impossible pendant la confirmation. Réessayez sans repayer.',
          en: 'Unable to connect during confirmation. Try again without paying again.',
        ),
        checkoutId: checkoutId,
      );
    } on FormatException {
      return PaymentConfirmation.failure(
        code: 'INVALID_CONFIRMATION_RESPONSE',
        message: _message(
          fr: 'Nous n’avons pas pu vérifier la confirmation. Réessayez sans repayer.',
          en: 'We could not verify the confirmation. Try again without paying again.',
        ),
        checkoutId: checkoutId,
      );
    } on RegistrationImageException catch (error) {
      return PaymentConfirmation.failure(
        code: error.code,
        message: _messageForImageError(error.code),
        checkoutId: checkoutId,
      );
    }
  }

  static void _rememberFinalizedConfirmation(
    String reference,
    PaymentConfirmation confirmation,
  ) {
    _finalizedConfirmations[reference] = confirmation;
    final checkoutId = confirmation.checkoutId;
    if (checkoutId != null) _finalizedConfirmations[checkoutId] = confirmation;
    while (_finalizedConfirmations.length > 12) {
      _finalizedConfirmations.remove(_finalizedConfirmations.keys.first);
    }
  }

  static PaymentConfirmation? _takeFinalizedConfirmation(
    String reference,
    String? checkoutId,
  ) {
    final confirmation =
        _finalizedConfirmations.remove(reference) ??
        (checkoutId == null
            ? null
            : _finalizedConfirmations.remove(checkoutId));
    if (confirmation != null) {
      _finalizedConfirmations.removeWhere(
        (_, candidate) => identical(candidate, confirmation),
      );
    }
    return confirmation;
  }

  static String _messageForApiError(String code) {
    return switch (code) {
      'PAYMENT_ALREADY_USED' => _message(
        fr: 'Ce paiement a déjà été utilisé.',
        en: 'This payment has already been used.',
      ),
      'STRIPE_UNAVAILABLE' => _message(
        fr: 'Le service de paiement est temporairement indisponible.',
        en: 'Payment is temporarily unavailable.',
      ),
      'REQUEST_FAILED' || 'UNEXPECTED_ERROR' => _message(
        fr: 'Le service est temporairement indisponible. Réessayez dans quelques instants.',
        en: 'The service is temporarily unavailable. Try again in a few moments.',
      ),
      'CHECKOUT_INTEGRITY_ERROR' => _message(
        fr: 'Cette session ne peut pas être vérifiée. Ne repayez pas et communiquez avec le soutien.',
        en: 'This session cannot be verified. Do not pay again; contact support.',
      ),
      'PAYMENT_NOT_SUCCEEDED' => _message(
        fr: 'Le paiement n’est pas encore confirmé par Stripe. Réessayez sans repayer.',
        en: 'Stripe has not confirmed the payment yet. Try again without paying again.',
      ),
      'PAYMENT_NOT_FOUND' ||
      'INVALID_PAYMENT_REFERENCE' ||
      'UNTRUSTED_PAYMENT_INTENT' => _message(
        fr: 'La référence de paiement est invalide. Communiquez avec le soutien.',
        en: 'The payment reference is invalid. Contact support.',
      ),
      'CHECKOUT_NOT_FOUND' => _message(
        fr: 'Cette session d’inscription est introuvable ou expirée. Recommencez l’inscription.',
        en: 'This registration session was not found or has expired. Please restart registration.',
      ),
      'RATE_LIMITED' => _message(
        fr: 'Trop de tentatives ont été effectuées. Patientez avant de réessayer.',
        en: 'Too many attempts were made. Wait before trying again.',
      ),
      'REGISTRATION_MISMATCH' ||
      'PAYMENT_AMOUNT_MISMATCH' ||
      'CHECKOUT_CONFLICT' => _message(
        fr: 'Les données de l’inscription ne correspondent pas au paiement. Aucun nouveau paiement ne doit être effectué.',
        en: 'The registration details do not match the payment. Do not make another payment.',
      ),
      'PLAN_CAPABILITY_VIOLATION' => _message(
        fr: 'Certaines options choisies ne sont pas incluses dans ce forfait. Modifiez l’inscription ou choisissez un autre forfait.',
        en: 'Some selected options are not included in this plan. Update the registration or choose another plan.',
      ),
      'INVALID_PLAN' => _message(
        fr: 'Ce forfait n’est plus offert. Actualisez les forfaits avant de continuer.',
        en: 'This plan is no longer available. Refresh the plans before continuing.',
      ),
      'EXISTING_PROFILE_NOT_ALLOWED' => _message(
        fr: 'Cette inscription vise un profil déjà existant. Utilisez plutôt la gestion du profil.',
        en: 'This registration targets an existing profile. Use profile management instead.',
      ),
      'INVALID_REGISTRATION' ||
      'INVALID_REGISTRATION_ID' ||
      'INVALID_IMAGE' ||
      'PAYLOAD_TOO_LARGE' => _message(
        fr: 'Les informations ou les images de l’inscription sont invalides. Vérifiez-les avant de réessayer.',
        en: 'The registration information or images are invalid. Review them before trying again.',
      ),
      'LEGACY_FREE_TOKEN_DISABLED' || 'INVALID_CONFIRMATION_TOKEN' => _message(
        fr: 'Cette confirmation a expiré. Recommencez l’inscription.',
        en: 'This confirmation has expired. Please restart registration.',
      ),
      _ => _message(
        fr: 'La demande n’a pas pu être traitée. Vérifiez vos informations.',
        en: 'The request could not be processed. Check your information.',
      ),
    };
  }

  static String _messageForImageError(String code) {
    return switch (code) {
      'GALLERY_LIMIT_EXCEEDED' => _message(
        fr: 'Le nombre d’images dépasse la limite du forfait sélectionné.',
        en: 'The number of images exceeds the selected plan limit.',
      ),
      'IMAGE_TOO_LARGE' || 'IMAGE_BUDGET_EXCEEDED' => _message(
        fr: 'Une image reste trop volumineuse après optimisation. Choisissez une image plus petite.',
        en: 'An image is still too large after optimization. Choose a smaller image.',
      ),
      'INVALID_REGISTRATION_PAYLOAD' => _message(
        fr: 'Les informations de l’inscription ne peuvent pas être envoyées. Vérifiez les champs et réessayez.',
        en: 'The registration details cannot be sent. Review the fields and try again.',
      ),
      _ => _message(
        fr: 'Une image sélectionnée est invalide ou non prise en charge.',
        en: 'A selected image is invalid or unsupported.',
      ),
    };
  }

  static String _messageForPlatformSupport(
    PaymentPlatformSupportDecision decision,
  ) {
    return switch (decision) {
      PaymentPlatformSupportDecision.supported => '',
      PaymentPlatformSupportDecision.paidPaymentSheetUnavailableOnWeb =>
        LocalizationService().tr('paid_payment_web_unavailable'),
    };
  }

  static String _networkErrorMessage() => _message(
    fr: 'Connexion impossible. Vérifiez votre réseau et réessayez.',
    en: 'Unable to connect. Check your network and try again.',
  );

  static String _message({required String fr, required String en}) {
    return LocalizationService().currentLanguage == 'en' ? en : fr;
  }
}

/// Frontière HTTP injectable de l’API de paiement.
final class StripePaymentApi {
  StripePaymentApi({
    required String baseUrl,
    http.Client? client,
    this.timeout = const Duration(seconds: 25),
  }) : _baseUrl = baseUrl.replaceFirst(RegExp(r'/+$'), ''),
       _client = client ?? http.Client();

  final String _baseUrl;
  final http.Client _client;
  final Duration timeout;

  Future<PaymentPlanCatalog> fetchPaymentPlans() async {
    final response = await _get('paymentPlans');
    return PaymentPlanCatalog.fromJson(response);
  }

  Future<CheckoutSession> createCheckout({
    required String planId,
    required String professionalId,
    required String email,
    required String businessName,
    String? categoryId,
    String? ville,
    String? phone,
    required Map<String, dynamic> registrationData,
    int? maxGalleryImages,
  }) async {
    final preparedRegistration = await RegistrationPayloadPreparer.prepare(
      registrationData,
      maxGalleryImages: maxGalleryImages,
    );
    final payload = <String, dynamic>{
      'planId': planId,
      'professionalId': professionalId,
      'email': email.trim(),
      'businessName': businessName.trim(),
      if (categoryId != null) 'categoryId': categoryId.trim(),
      if (ville != null) 'ville': ville.trim(),
      if (phone != null) 'phone': phone.trim(),
      'registrationData': preparedRegistration,
    };
    RegistrationPayloadPreparer.validateCheckoutRequest(payload);
    final response = await _post('createPaymentIntent', payload);
    return CheckoutSession.fromJson(
      response,
      preparedRegistrationData: preparedRegistration,
    );
  }

  Future<PaymentConfirmation> confirmCheckout({
    required String confirmationToken,
  }) async {
    final response = await _post('confirmPayment', {
      'confirmationToken': confirmationToken,
    });
    return PaymentConfirmation.fromJson(response);
  }

  Future<Map<String, dynamic>> _post(
    String endpoint,
    Map<String, dynamic> payload,
  ) async {
    final response = await _client
        .post(
          Uri.parse('$_baseUrl/$endpoint'),
          headers: const {
            'Accept': 'application/json',
            'Content-Type': 'application/json',
          },
          body: jsonEncode(payload),
        )
        .timeout(timeout);

    return _decodeResponse(response);
  }

  Future<Map<String, dynamic>> _get(String endpoint) async {
    final response = await _client
        .get(
          Uri.parse('$_baseUrl/$endpoint'),
          headers: const {'Accept': 'application/json'},
        )
        .timeout(timeout);

    return _decodeResponse(response);
  }

  Map<String, dynamic> _decodeResponse(http.Response response) {
    Map<String, dynamic>? decoded;
    try {
      final candidate = jsonDecode(response.body);
      if (candidate is Map<String, dynamic>) {
        decoded = candidate;
      }
    } on FormatException {
      // Le statut HTTP doit rester disponible lors d’une panne de passerelle.
    }

    final isSuccessStatus =
        response.statusCode >= 200 && response.statusCode < 300;
    if (!isSuccessStatus) {
      throw PaymentApiException(
        code: decoded?['code']?.toString() ?? 'REQUEST_FAILED',
        statusCode: response.statusCode,
        serverMessage: decoded?['error']?.toString(),
        requestId: decoded?['requestId']?.toString(),
      );
    }
    if (decoded == null) {
      throw const FormatException('Invalid checkout response');
    }
    if (decoded['success'] != true) {
      throw PaymentApiException(
        code: decoded['code']?.toString() ?? 'REQUEST_FAILED',
        statusCode: response.statusCode,
        serverMessage: decoded['error']?.toString(),
        requestId: decoded['requestId']?.toString(),
      );
    }
    return Map<String, dynamic>.unmodifiable(decoded);
  }
}

@immutable
final class PaymentPlanCatalog {
  const PaymentPlanCatalog._({required this.version, required this.plans});

  factory PaymentPlanCatalog.fromJson(Map<String, dynamic> json) {
    final version = json['version'];
    final rawPlans = json['plans'];
    if (version != 2 || rawPlans is! List<dynamic>) {
      throw const FormatException('Invalid payment plans contract');
    }

    final plans = <PaymentPlanQuote>[];
    final identifiers = <String>{};
    for (final rawPlan in rawPlans) {
      if (rawPlan is! Map<String, dynamic>) {
        throw const FormatException('Invalid payment plan entry');
      }
      final plan = PaymentPlanQuote.fromJson(rawPlan);
      if (!identifiers.add(plan.id)) {
        throw const FormatException('Duplicate payment plan identifier');
      }
      plans.add(plan);
    }
    if (plans.isEmpty) {
      throw const FormatException('Payment plan catalog is empty');
    }

    return PaymentPlanCatalog._(
      version: version,
      plans: List<PaymentPlanQuote>.unmodifiable(plans),
    );
  }

  final int version;
  final List<PaymentPlanQuote> plans;

  PaymentPlanQuote? findPlan(String planId) {
    final normalizedId = planId.trim();
    for (final plan in plans) {
      if (plan.id == normalizedId) return plan;
    }
    return null;
  }

  PaymentPlanQuote requirePlan(String planId) {
    final plan = findPlan(planId);
    if (plan == null) {
      throw const FormatException('Requested payment plan is missing');
    }
    return plan;
  }
}

@immutable
final class PaymentPlanCapabilities {
  const PaymentPlanCapabilities._({
    required this.profileImage,
    required this.galleryMax,
    required this.coupon,
    required this.featured,
  });

  factory PaymentPlanCapabilities.fromJson(Map<String, dynamic> json) {
    final profileImage = json['profile_image'];
    final galleryMax = json['gallery_max'];
    final coupon = json['coupon'];
    final featured = json['featured'];
    if (profileImage is! bool ||
        galleryMax is! int ||
        galleryMax < 0 ||
        coupon is! bool ||
        featured is! bool) {
      throw const FormatException('Invalid payment plan capabilities');
    }
    return PaymentPlanCapabilities._(
      profileImage: profileImage,
      galleryMax: galleryMax,
      coupon: coupon,
      featured: featured,
    );
  }

  final bool profileImage;
  final int galleryMax;
  final bool coupon;
  final bool featured;
}

@immutable
final class PaymentPlanQuote {
  const PaymentPlanQuote._({
    required this.id,
    required this.amountCents,
    required this.currency,
    required this.requiresPayment,
    required this.durationDays,
    required this.labelFr,
    required this.labelEn,
    required this.featuresFr,
    required this.featuresEn,
    required this.capabilities,
  });

  factory PaymentPlanQuote.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final amount = json['amount'];
    final currency = json['currency'];
    final requiresPayment = json['requires_payment'];
    final durationDays = json['duration_days'];
    final label = json['label'];
    final features = json['features'];
    final rawCapabilities = json['capabilities'];
    if (id is! String ||
        !_paymentPlanIdPattern.hasMatch(id.trim()) ||
        amount is! int ||
        amount < 0 ||
        currency is! String ||
        !_currencyCodePattern.hasMatch(currency.trim()) ||
        requiresPayment is! bool ||
        (requiresPayment && amount <= 0) ||
        (!requiresPayment && amount != 0) ||
        durationDays is! int ||
        durationDays <= 0 ||
        label is! Map<String, dynamic> ||
        features is! Map<String, dynamic> ||
        rawCapabilities is! Map<String, dynamic>) {
      throw const FormatException('Invalid payment plan');
    }
    final labelFr = label['fr'];
    final labelEn = label['en'];
    final featuresFr = features['fr'];
    final featuresEn = features['en'];
    if (labelFr is! String ||
        labelFr.trim().isEmpty ||
        labelEn is! String ||
        labelEn.trim().isEmpty ||
        featuresFr is! List<dynamic> ||
        featuresEn is! List<dynamic> ||
        featuresFr.any(
          (feature) => feature is! String || feature.trim().isEmpty,
        ) ||
        featuresEn.any(
          (feature) => feature is! String || feature.trim().isEmpty,
        )) {
      throw const FormatException('Invalid payment plan presentation');
    }
    return PaymentPlanQuote._(
      id: id.trim(),
      amountCents: amount,
      currency: currency.trim().toLowerCase(),
      requiresPayment: requiresPayment,
      durationDays: durationDays,
      labelFr: labelFr.trim(),
      labelEn: labelEn.trim(),
      featuresFr: List<String>.unmodifiable(
        featuresFr.cast<String>().map((feature) => feature.trim()),
      ),
      featuresEn: List<String>.unmodifiable(
        featuresEn.cast<String>().map((feature) => feature.trim()),
      ),
      capabilities: PaymentPlanCapabilities.fromJson(rawCapabilities),
    );
  }

  final String id;
  final int amountCents;
  final String currency;
  final bool requiresPayment;
  final int durationDays;
  final String labelFr;
  final String labelEn;
  final List<String> featuresFr;
  final List<String> featuresEn;
  final PaymentPlanCapabilities capabilities;

  double get amount => amountCents / 100;
}

/// Prépare les images avant la création du checkout afin qu’une charge Stripe
/// ne puisse pas précéder la détection d’une image invalide.
abstract final class RegistrationPayloadPreparer {
  static const int _targetImageBytes = 50 * 1024;
  static const int _maxTotalImageChars = 410000;
  static const int _maxPreparedRegistrationChars = 475000;
  static const int _maxCheckoutRequestChars = 490000;

  static final RegExp _base64Pattern = RegExp(r'^[A-Za-z0-9+/]*={0,2}$');
  static final RegExp _dataUrlPattern = RegExp(
    r'^data:image/(png|jpe?g|webp);base64,(.*)$',
    caseSensitive: false,
    dotAll: true,
  );

  static Future<Map<String, dynamic>> prepare(
    Map<String, dynamic> registrationData, {
    int? maxGalleryImages,
  }) async {
    final prepared = withoutImages(registrationData);
    var totalImageChars = 0;

    final rawProfile = registrationData['profileImageBase64'];
    if (rawProfile != null) {
      if (rawProfile is! String) {
        throw const RegistrationImageException('INVALID_IMAGE');
      }
      if (rawProfile.trim().isNotEmpty) {
        final compressed = await compressBase64(
          rawProfile,
          maxKB: 50,
          maxWidth: 800,
          maxHeight: 800,
        );
        final profile = _validateAndNormalizeImage(compressed);
        prepared['profileImageBase64'] = profile;
        totalImageChars += profile.length;
      }
    }

    final rawGallery = registrationData['galleryImagesBase64'];
    if (rawGallery != null) {
      if (rawGallery is! List<dynamic>) {
        throw const RegistrationImageException('INVALID_IMAGE');
      }
      final galleryInput = <String>[];
      for (final image in rawGallery) {
        if (image is! String) {
          throw const RegistrationImageException('INVALID_IMAGE');
        }
        if (image.trim().isNotEmpty) galleryInput.add(image);
      }
      if (maxGalleryImages != null && galleryInput.length > maxGalleryImages) {
        throw const RegistrationImageException('GALLERY_LIMIT_EXCEEDED');
      }

      final compressedGallery = await compressGallery(
        galleryInput,
        limit: maxGalleryImages ?? galleryInput.length,
        maxKB: 50,
        maxWidth: 1024,
        maxHeight: 1024,
      );
      final gallery = <String>[];
      for (final compressed in compressedGallery) {
        final image = _validateAndNormalizeImage(compressed);
        gallery.add(image);
        totalImageChars += image.length;
      }
      if (gallery.isNotEmpty) {
        prepared['galleryImagesBase64'] = List<String>.unmodifiable(gallery);
      }
    }

    if (totalImageChars > _maxTotalImageChars) {
      throw const RegistrationImageException('IMAGE_BUDGET_EXCEEDED');
    }

    try {
      if (jsonEncode(prepared).length > _maxPreparedRegistrationChars) {
        throw const RegistrationImageException('IMAGE_BUDGET_EXCEEDED');
      }
    } on JsonUnsupportedObjectError {
      throw const RegistrationImageException('INVALID_REGISTRATION_PAYLOAD');
    }
    return Map<String, dynamic>.unmodifiable(prepared);
  }

  static void validateCheckoutRequest(Map<String, dynamic> payload) {
    try {
      if (jsonEncode(payload).length > _maxCheckoutRequestChars) {
        throw const RegistrationImageException('IMAGE_BUDGET_EXCEEDED');
      }
    } on JsonUnsupportedObjectError {
      throw const RegistrationImageException('INVALID_REGISTRATION_PAYLOAD');
    }
  }

  static Map<String, dynamic> withoutImages(
    Map<String, dynamic> registrationData,
  ) {
    final sanitized = Map<String, dynamic>.from(registrationData);
    sanitized.remove('profileImageBase64');
    sanitized.remove('galleryImagesBase64');
    return sanitized;
  }

  static String _validateAndNormalizeImage(String rawImage) {
    final trimmed = rawImage.trim();
    final dataUrlMatch = _dataUrlPattern.firstMatch(trimmed);
    if (trimmed.startsWith('data:') && dataUrlMatch == null) {
      throw const RegistrationImageException('INVALID_IMAGE');
    }
    final encoded = (dataUrlMatch?.group(2) ?? trimmed).replaceAll(
      RegExp(r'\s'),
      '',
    );
    if (encoded.length < 16 ||
        encoded.length % 4 == 1 ||
        !_base64Pattern.hasMatch(encoded)) {
      throw const RegistrationImageException('INVALID_IMAGE');
    }

    final paddingLength = (4 - encoded.length % 4) % 4;
    final padded = '$encoded${List.filled(paddingLength, '=').join()}';
    late Uint8List bytes;
    try {
      bytes = base64Decode(padded);
    } on FormatException {
      throw const RegistrationImageException('INVALID_IMAGE');
    }
    if (bytes.length > _targetImageBytes) {
      throw const RegistrationImageException('IMAGE_TOO_LARGE');
    }
    if (bytes.length < 32 ||
        !_hasSupportedImageSignature(bytes) ||
        !_isDecodableImage(bytes)) {
      throw const RegistrationImageException('INVALID_IMAGE');
    }
    return base64Encode(bytes);
  }

  static bool _isDecodableImage(Uint8List bytes) {
    try {
      return image.decodeImage(bytes) != null;
    } catch (_) {
      return false;
    }
  }

  static bool _hasSupportedImageSignature(List<int> bytes) {
    final isPng =
        bytes.length >= 8 &&
        bytes[0] == 137 &&
        bytes[1] == 80 &&
        bytes[2] == 78 &&
        bytes[3] == 71 &&
        bytes[4] == 13 &&
        bytes[5] == 10 &&
        bytes[6] == 26 &&
        bytes[7] == 10;
    final isJpeg =
        bytes.length >= 3 &&
        bytes[0] == 255 &&
        bytes[1] == 216 &&
        bytes[2] == 255;
    final isWebp =
        bytes.length >= 12 &&
        String.fromCharCodes(bytes.take(4)) == 'RIFF' &&
        String.fromCharCodes(bytes.skip(8).take(4)) == 'WEBP';
    return isPng || isJpeg || isWebp;
  }
}

final class RegistrationImageException implements Exception {
  const RegistrationImageException(this.code);

  final String code;

  @override
  String toString() => 'RegistrationImageException($code)';
}

@immutable
final class CheckoutSession {
  const CheckoutSession({
    required this.requiresPayment,
    required this.confirmationReference,
    this.alreadyFinalized = false,
    this.professionalId,
    this.clientSecret,
    this.customerId,
    this.ephemeralKey,
    this.checkoutId,
    this.amountCents,
    this.currency,
    this.preparedRegistrationData = const <String, dynamic>{},
  });

  factory CheckoutSession.fromJson(
    Map<String, dynamic> json, {
    Map<String, dynamic>? preparedRegistrationData,
  }) {
    final requiresPayment = json['requires_payment'];
    final rawAlreadyFinalized = json['already_finalized'];
    final alreadyFinalized = rawAlreadyFinalized == true;
    final clientSecret = json['client_secret'];
    final rawAmount = json['amount'];
    final amountCents = rawAmount is int
        ? rawAmount
        : rawAmount is num &&
              rawAmount.isFinite &&
              rawAmount == rawAmount.round()
        ? rawAmount.toInt()
        : null;
    final rawCurrency = json['currency'];
    final rawCheckoutId = json['checkout_id'] ?? json['checkoutId'];
    final rawProfessionalId = json['professional_id'] ?? json['professionalId'];
    final reference = requiresPayment == true
        ? json['payment_intent_id'] ??
              json['id'] ??
              (alreadyFinalized ? rawCheckoutId : null)
        : json['confirmation_token'] ??
              json['payment_intent_id'] ??
              json['id'] ??
              (alreadyFinalized ? rawCheckoutId : null);

    if (requiresPayment is! bool ||
        (rawAlreadyFinalized != null && rawAlreadyFinalized is! bool) ||
        reference is! String ||
        reference.trim().isEmpty ||
        (json.containsKey('amount') &&
            (amountCents == null || amountCents < 0)) ||
        (json.containsKey('currency') &&
            (rawCurrency is! String || rawCurrency.trim().isEmpty)) ||
        (rawCheckoutId != null &&
            (rawCheckoutId is! String || rawCheckoutId.trim().isEmpty)) ||
        (rawProfessionalId != null &&
            (rawProfessionalId is! String ||
                rawProfessionalId.trim().isEmpty)) ||
        (alreadyFinalized &&
            (rawCheckoutId is! String ||
                rawCheckoutId.trim().isEmpty ||
                rawProfessionalId is! String ||
                rawProfessionalId.trim().isEmpty)) ||
        (requiresPayment &&
            !alreadyFinalized &&
            (clientSecret is! String || clientSecret.trim().isEmpty))) {
      throw const FormatException('Invalid checkout contract');
    }

    return CheckoutSession(
      requiresPayment: requiresPayment,
      confirmationReference: reference.trim(),
      alreadyFinalized: alreadyFinalized,
      professionalId: rawProfessionalId is String
          ? rawProfessionalId.trim()
          : null,
      clientSecret: clientSecret is String ? clientSecret.trim() : null,
      customerId: json['customer_id'] is String
          ? (json['customer_id'] as String).trim()
          : null,
      ephemeralKey: json['ephemeral_key'] is String
          ? (json['ephemeral_key'] as String).trim()
          : null,
      checkoutId: rawCheckoutId is String ? rawCheckoutId.trim() : null,
      amountCents: amountCents,
      currency: rawCurrency is String ? rawCurrency.trim().toLowerCase() : null,
      preparedRegistrationData: Map<String, dynamic>.unmodifiable(
        preparedRegistrationData ?? const <String, dynamic>{},
      ),
    );
  }

  final bool requiresPayment;
  final String confirmationReference;
  final bool alreadyFinalized;
  final String? professionalId;
  final String? clientSecret;
  final String? customerId;
  final String? ephemeralKey;
  final String? checkoutId;
  final int? amountCents;
  final String? currency;
  final Map<String, dynamic> preparedRegistrationData;

  Map<String, dynamic> toJson() => {
    'success': true,
    'requires_payment': requiresPayment,
    'id': confirmationReference,
    'payment_intent_id': confirmationReference,
    if (!requiresPayment) 'confirmation_token': confirmationReference,
    if (clientSecret != null) 'client_secret': clientSecret,
    if (customerId != null) 'customer_id': customerId,
    if (ephemeralKey != null) 'ephemeral_key': ephemeralKey,
    if (checkoutId != null) 'checkout_id': checkoutId,
    if (amountCents != null) 'amount': amountCents,
    if (currency != null) 'currency': currency,
    if (alreadyFinalized) 'already_finalized': true,
    if (professionalId != null) 'professional_id': professionalId,
  };
}

@immutable
final class PaymentConfirmationData {
  const PaymentConfirmationData({
    required this.professionalId,
    required this.planId,
    required this.isActive,
  });

  factory PaymentConfirmationData.fromJson(Map<String, dynamic> json) {
    final professionalId = json['professionalId'];
    final planId = json['planId'];
    final isActive = json['isActive'];
    if (professionalId is! String ||
        professionalId.trim().isEmpty ||
        planId is! String ||
        planId.trim().isEmpty ||
        isActive is! bool) {
      throw const FormatException('Invalid confirmation data');
    }
    return PaymentConfirmationData(
      professionalId: professionalId.trim(),
      planId: planId.trim(),
      isActive: isActive,
    );
  }

  final String professionalId;
  final String planId;
  final bool isActive;

  Map<String, dynamic> toJson() => {
    'professionalId': professionalId,
    'planId': planId,
    'isActive': isActive,
  };
}

@immutable
final class PaymentConfirmation {
  const PaymentConfirmation._({
    required this.success,
    this.status,
    this.data,
    this.idempotent,
    this.code,
    this.message,
    this.httpStatusCode,
    this.checkoutId,
  });

  factory PaymentConfirmation.fromJson(Map<String, dynamic> json) {
    final status = json['status'];
    final rawData = json['data'];
    final idempotent = json['idempotent'];
    final rawCheckoutId = json['checkout_id'] ?? json['checkoutId'];
    if (json['success'] != true ||
        status is! String ||
        status.trim().isEmpty ||
        rawData is! Map<String, dynamic> ||
        idempotent is! bool ||
        (rawCheckoutId != null &&
            (rawCheckoutId is! String || rawCheckoutId.trim().isEmpty))) {
      throw const FormatException('Invalid confirmation contract');
    }
    return PaymentConfirmation._(
      success: true,
      status: status.trim(),
      data: PaymentConfirmationData.fromJson(rawData),
      idempotent: idempotent,
      checkoutId: rawCheckoutId is String ? rawCheckoutId.trim() : null,
    );
  }

  factory PaymentConfirmation.finalized({
    required String professionalId,
    required String planId,
    required bool isActive,
    required String status,
    required String checkoutId,
  }) {
    return PaymentConfirmation._(
      success: true,
      status: status,
      data: PaymentConfirmationData(
        professionalId: professionalId,
        planId: planId,
        isActive: isActive,
      ),
      idempotent: true,
      checkoutId: checkoutId,
    );
  }

  const PaymentConfirmation.failure({
    required String code,
    required String message,
    int? httpStatusCode,
    String? checkoutId,
  }) : this._(
         success: false,
         status: 'failed',
         code: code,
         message: message,
         httpStatusCode: httpStatusCode,
         checkoutId: checkoutId,
       );

  final bool success;
  final String? status;
  final PaymentConfirmationData? data;
  final bool? idempotent;
  final String? code;
  final String? message;
  final int? httpStatusCode;
  final String? checkoutId;

  bool get isActive => data?.isActive ?? false;
  String? get professionalId => data?.professionalId;

  PaymentConfirmation withFallbackCheckoutId(String? fallbackCheckoutId) {
    final normalizedFallback = fallbackCheckoutId?.trim();
    if (checkoutId != null ||
        normalizedFallback == null ||
        normalizedFallback.isEmpty) {
      return this;
    }
    return PaymentConfirmation._(
      success: success,
      status: status,
      data: data,
      idempotent: idempotent,
      code: code,
      message: message,
      httpStatusCode: httpStatusCode,
      checkoutId: normalizedFallback,
    );
  }

  Map<String, dynamic> toJson() => {
    'success': success,
    if (status != null) 'status': status,
    if (idempotent != null) 'idempotent': idempotent,
    if (data != null) 'data': data!.toJson(),
    if (code != null) 'code': code,
    if (message != null) 'error': message,
    if (httpStatusCode != null) 'statusCode': httpStatusCode,
    if (checkoutId != null) 'checkout_id': checkoutId,
  };
}

final class PaymentApiException implements Exception {
  const PaymentApiException({
    required this.code,
    required this.statusCode,
    this.serverMessage,
    this.requestId,
  });

  final String code;
  final int statusCode;
  final String? serverMessage;
  final String? requestId;

  @override
  String toString() => 'PaymentApiException($code, $statusCode)';
}

@immutable
final class PaymentResult {
  const PaymentResult({
    required this.success,
    this.error,
    this.errorCode,
    this.paymentIntentId,
    this.checkoutId,
    this.amountCents,
    this.currency,
    this.preparedRegistrationData,
    this.confirmation,
    this.wasCanceled = false,
  });

  const PaymentResult.success(
    String confirmationReference, {
    this.checkoutId,
    this.amountCents,
    this.currency,
    this.preparedRegistrationData,
    this.confirmation,
  }) : success = true,
       error = null,
       errorCode = null,
       paymentIntentId = confirmationReference,
       wasCanceled = false;

  const PaymentResult.failure(String message, {this.errorCode})
    : success = false,
      error = message,
      paymentIntentId = null,
      checkoutId = null,
      amountCents = null,
      currency = null,
      preparedRegistrationData = null,
      confirmation = null,
      wasCanceled = false;

  const PaymentResult.canceled()
    : success = false,
      error = null,
      errorCode = null,
      paymentIntentId = null,
      checkoutId = null,
      amountCents = null,
      currency = null,
      preparedRegistrationData = null,
      confirmation = null,
      wasCanceled = true;

  final bool success;
  final String? error;
  final String? errorCode;
  final String? paymentIntentId;
  final String? checkoutId;
  final int? amountCents;
  final String? currency;
  final Map<String, dynamic>? preparedRegistrationData;
  final PaymentConfirmation? confirmation;
  final bool wasCanceled;
}
