import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/billing_client_wrappers.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as image;

import '../core/config/app_config.dart';
import '../utils/image_base64_utils.dart';

final RegExp _paymentPlanIdPattern = RegExp(r'^[A-Za-z0-9_-]{1,64}$');
final RegExp _currencyCodePattern = RegExp(r'^[A-Za-z]{3}$');
final RegExp _uuidPattern = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
  caseSensitive: false,
);

/// Catalogue signé par le backend. Les montants servent à décrire le forfait;
/// le prix affiché et facturé pour un achat mobile vient toujours du store.
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
    required this.storeProducts,
    required this.billingPeriod,
    required this.autoRenewing,
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
    final rawStoreProducts = json['store_products'];
    final billingPeriod = json['billing_period'];
    final autoRenewing = json['auto_renewing'];
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
    final normalizedId = id.trim();
    final expectedStoreProductId = StoreProductIds.productIdForPlan(
      normalizedId,
    );
    if (requiresPayment &&
        (durationDays != 365 ||
            expectedStoreProductId == null ||
            rawStoreProducts is! Map<String, dynamic> ||
            rawStoreProducts['app_store'] != expectedStoreProductId ||
            rawStoreProducts['google_play'] != expectedStoreProductId ||
            rawStoreProducts.length != 2 ||
            billingPeriod != 'P1Y' ||
            autoRenewing != true)) {
      throw const FormatException('Invalid annual store plan contract');
    }
    final storeProducts = requiresPayment
        ? Map<String, String>.unmodifiable(
            (rawStoreProducts! as Map<String, dynamic>).cast<String, String>(),
          )
        : const <String, String>{};
    return PaymentPlanQuote._(
      id: normalizedId,
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
      storeProducts: storeProducts,
      billingPeriod: requiresPayment ? billingPeriod as String : null,
      autoRenewing: requiresPayment,
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
  final Map<String, String> storeProducts;
  final String? billingPeriod;
  final bool autoRenewing;

  double get amount => amountCents / 100;

  String? productIdForStore(StorePlatform store) {
    return storeProducts[store.wireName];
  }
}

/// Store utilisé pour vérifier un achat auprès du backend.
enum StorePlatform {
  appStore('app_store'),
  googlePlay('google_play');

  const StorePlatform(this.wireName);

  final String wireName;

  static StorePlatform? get current {
    if (kIsWeb) return null;
    return switch (defaultTargetPlatform) {
      TargetPlatform.iOS => StorePlatform.appStore,
      TargetPlatform.android => StorePlatform.googlePlay,
      _ => null,
    };
  }
}

/// Correspondance contrôlée entre les forfaits métier et les produits stores.
abstract final class StoreProductIds {
  static const premiumAnnual = 'ca.indexcanada.app.premium.annual';
  static const professionalAnnual = 'ca.indexcanada.app.professional.annual';

  static const Map<String, String> _byPlan = <String, String>{
    'premium': premiumAnnual,
    'professional': professionalAnnual,
  };

  static Set<String> get all => Set<String>.unmodifiable(_byPlan.values);

  static String? productIdForPlan(String planId) => _byPlan[planId.trim()];

  static String? planIdForProduct(String productId) {
    final normalized = productId.trim();
    for (final entry in _byPlan.entries) {
      if (entry.value == normalized) return entry.key;
    }
    return null;
  }
}

/// Présentation localisée d'un produit retournée par App Store/Google Play.
@immutable
final class StoreProductOffer {
  const StoreProductOffer({
    required this.planId,
    required this.productId,
    required this.title,
    required this.description,
    required this.localizedPrice,
    required this.rawPrice,
    required this.currencyCode,
    this.nativeProduct,
  });

  final String planId;
  final String productId;
  final String title;
  final String description;
  final String localizedPrice;
  final double rawPrice;
  final String currencyCode;

  /// Objet opaque requis uniquement par l'adaptateur du plugiciel.
  final Object? nativeProduct;
}

enum StorePurchaseEventStatus { pending, error, canceled, purchased, restored }

/// Événement agnostique au store, facilement simulable dans les tests.
@immutable
final class StorePurchaseEvent {
  const StorePurchaseEvent({
    required this.status,
    required this.productId,
    this.purchaseId,
    this.verificationData = '',
    this.pendingCompletePurchase = false,
    this.errorCode,
    this.errorMessage,
    this.nativePurchase,
  });

  const StorePurchaseEvent.pending({required String productId})
    : this(status: StorePurchaseEventStatus.pending, productId: productId);

  const StorePurchaseEvent.canceled({required String productId})
    : this(status: StorePurchaseEventStatus.canceled, productId: productId);

  const StorePurchaseEvent.failed({
    required String productId,
    required String code,
    required String message,
  }) : this(
         status: StorePurchaseEventStatus.error,
         productId: productId,
         errorCode: code,
         errorMessage: message,
       );

  final StorePurchaseEventStatus status;
  final String productId;
  final String? purchaseId;
  final String verificationData;
  final bool pendingCompletePurchase;
  final String? errorCode;
  final String? errorMessage;
  final Object? nativePurchase;
}

/// Politique explicite appliquée par Google Play lors d'un changement de
/// forfait. Une transition ne doit jamais retomber sur un achat générique.
enum StoreSubscriptionReplacementMode { withTimeProration, deferred }

@immutable
final class StoreSubscriptionChange {
  const StoreSubscriptionChange({
    required this.oldPurchase,
    required this.replacementMode,
  });

  final StorePurchaseEvent oldPurchase;
  final StoreSubscriptionReplacementMode replacementMode;
}

abstract interface class StorePurchaseGateway {
  Stream<List<StorePurchaseEvent>> get purchaseStream;

  Future<bool> isAvailable();

  Future<List<StoreProductOffer>> queryProducts(Set<String> productIds);

  Future<bool> buyNonConsumable(
    StoreProductOffer product, {
    required String applicationUserName,
  });

  Future<void> restorePurchases();

  Future<void> completePurchase(StorePurchaseEvent purchase);
}

/// Capacités Android optionnelles, séparées du contrat commun afin que les
/// adaptateurs App Store ne puissent pas lancer une transition Google Play.
abstract interface class GooglePlaySubscriptionGateway {
  Future<List<StorePurchaseEvent>> queryOwnedPurchases();

  Future<bool> changeSubscription(
    StoreProductOffer product, {
    required String applicationUserName,
    required StoreSubscriptionChange subscriptionChange,
  });
}

/// Adaptateur minimal du plugiciel officiel Flutter.
final class InAppPurchaseGateway
    implements StorePurchaseGateway, GooglePlaySubscriptionGateway {
  InAppPurchaseGateway({InAppPurchase? inAppPurchase})
    : _inAppPurchase = inAppPurchase ?? InAppPurchase.instance;

  final InAppPurchase _inAppPurchase;

  @override
  Stream<List<StorePurchaseEvent>> get purchaseStream {
    return _inAppPurchase.purchaseStream.map(
      (purchases) => purchases.map(_toStoreEvent).toList(growable: false),
    );
  }

  @override
  Future<bool> isAvailable() => _inAppPurchase.isAvailable();

  @override
  Future<List<StoreProductOffer>> queryProducts(Set<String> productIds) async {
    final response = await _inAppPurchase.queryProductDetails(productIds);
    if (response.error != null) {
      throw StorePurchaseException(
        response.error!.code,
        response.error!.message,
      );
    }
    return response.productDetails
        .map((product) {
          final planId = StoreProductIds.planIdForProduct(product.id);
          if (planId == null) {
            throw StorePurchaseException(
              'UNEXPECTED_STORE_PRODUCT',
              'Unexpected product returned by the store.',
            );
          }
          return StoreProductOffer(
            planId: planId,
            productId: product.id,
            title: product.title,
            description: product.description,
            localizedPrice: product.price,
            rawPrice: product.rawPrice,
            currencyCode: product.currencyCode,
            nativeProduct: product,
          );
        })
        .toList(growable: false);
  }

  @override
  Future<List<StorePurchaseEvent>> queryOwnedPurchases() async {
    final addition = _inAppPurchase
        .getPlatformAddition<InAppPurchaseAndroidPlatformAddition>();
    final response = await addition.queryPastPurchases();
    final error = response.error;
    if (error != null) {
      throw StorePurchaseException(
        'STORE_OWNED_PURCHASES_UNAVAILABLE',
        error.message,
      );
    }
    return response.pastPurchases.map(_toStoreEvent).toList(growable: false);
  }

  @override
  Future<bool> buyNonConsumable(
    StoreProductOffer product, {
    required String applicationUserName,
  }) => _buyNonConsumable(product, applicationUserName: applicationUserName);

  @override
  Future<bool> changeSubscription(
    StoreProductOffer product, {
    required String applicationUserName,
    required StoreSubscriptionChange subscriptionChange,
  }) => _buyNonConsumable(
    product,
    applicationUserName: applicationUserName,
    subscriptionChange: subscriptionChange,
  );

  Future<bool> _buyNonConsumable(
    StoreProductOffer product, {
    required String applicationUserName,
    StoreSubscriptionChange? subscriptionChange,
  }) {
    final nativeProduct = product.nativeProduct;
    if (nativeProduct is! ProductDetails) {
      throw StorePurchaseException(
        'INVALID_STORE_PRODUCT',
        'The store product cannot be purchased.',
      );
    }
    PurchaseParam purchaseParam;
    if (subscriptionChange != null) {
      final oldNativePurchase = subscriptionChange.oldPurchase.nativePurchase;
      if (nativeProduct is! GooglePlayProductDetails ||
          oldNativePurchase is! GooglePlayPurchaseDetails) {
        throw const StorePurchaseException(
          'INVALID_STORE_SUBSCRIPTION_CHANGE',
          'Google Play could not safely replace the existing subscription.',
        );
      }
      final replacementMode = switch (subscriptionChange.replacementMode) {
        StoreSubscriptionReplacementMode.withTimeProration =>
          ReplacementMode.withTimeProration,
        StoreSubscriptionReplacementMode.deferred => ReplacementMode.deferred,
      };
      purchaseParam = GooglePlayPurchaseParam(
        productDetails: nativeProduct,
        applicationUserName: applicationUserName,
        offerToken: nativeProduct.offerToken,
        changeSubscriptionParam: ChangeSubscriptionParam(
          oldPurchaseDetails: oldNativePurchase,
          replacementMode: replacementMode,
        ),
      );
    } else if (nativeProduct is GooglePlayProductDetails) {
      purchaseParam = GooglePlayPurchaseParam(
        productDetails: nativeProduct,
        applicationUserName: applicationUserName,
        offerToken: nativeProduct.offerToken,
      );
    } else {
      purchaseParam = PurchaseParam(
        productDetails: nativeProduct,
        applicationUserName: applicationUserName,
      );
    }
    return _inAppPurchase.buyNonConsumable(purchaseParam: purchaseParam);
  }

  @override
  Future<void> restorePurchases() => _inAppPurchase.restorePurchases();

  @override
  Future<void> completePurchase(StorePurchaseEvent purchase) {
    final nativePurchase = purchase.nativePurchase;
    if (nativePurchase is! PurchaseDetails) {
      throw StorePurchaseException(
        'INVALID_STORE_PURCHASE',
        'The native purchase cannot be completed.',
      );
    }
    return _inAppPurchase.completePurchase(nativePurchase);
  }

  static StorePurchaseEvent _toStoreEvent(PurchaseDetails purchase) {
    final status = switch (purchase.status) {
      PurchaseStatus.pending => StorePurchaseEventStatus.pending,
      PurchaseStatus.purchased => StorePurchaseEventStatus.purchased,
      PurchaseStatus.restored => StorePurchaseEventStatus.restored,
      PurchaseStatus.canceled => StorePurchaseEventStatus.canceled,
      PurchaseStatus.error => StorePurchaseEventStatus.error,
    };
    return StorePurchaseEvent(
      status: status,
      productId: purchase.productID,
      purchaseId: purchase.purchaseID,
      verificationData: purchase.verificationData.serverVerificationData,
      pendingCompletePurchase: purchase.pendingCompletePurchase,
      errorCode: purchase.error?.code,
      errorMessage: purchase.error?.message,
      nativePurchase: purchase,
    );
  }
}

@immutable
final class StorePurchaseRequest {
  const StorePurchaseRequest({
    required this.planId,
    required this.professionalId,
    required this.email,
    required this.businessName,
    required this.categoryId,
    required this.ville,
    required this.phone,
    required this.registrationData,
    this.maxGalleryImages,
  });

  final String planId;
  final String professionalId;
  final String email;
  final String businessName;
  final String categoryId;
  final String ville;
  final String phone;
  final Map<String, dynamic> registrationData;
  final int? maxGalleryImages;
}

/// Prépare les médias avant tout checkout afin qu'une image invalide ne soit
/// jamais découverte après le lancement d'un achat.
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
      for (final rawImage in rawGallery) {
        if (rawImage is! String) {
          throw const RegistrationImageException('INVALID_IMAGE');
        }
        if (rawImage.trim().isNotEmpty) galleryInput.add(rawImage);
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
        final normalizedImage = _validateAndNormalizeImage(compressed);
        gallery.add(normalizedImage);
        totalImageChars += normalizedImage.length;
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
final class PaymentConfirmationData {
  const PaymentConfirmationData({
    required this.professionalId,
    required this.planId,
    required this.isActive,
    this.pendingPlanId,
  });

  factory PaymentConfirmationData.fromJson(Map<String, dynamic> json) {
    final professionalId = json['professionalId'];
    final planId = json['planId'];
    final pendingPlanId = json['pendingPlanId'];
    final isActive = json['isActive'];
    if (professionalId is! String ||
        professionalId.trim().isEmpty ||
        planId is! String ||
        !_paymentPlanIdPattern.hasMatch(planId.trim()) ||
        (pendingPlanId != null &&
            (pendingPlanId is! String ||
                !_paymentPlanIdPattern.hasMatch(pendingPlanId.trim()))) ||
        isActive is! bool) {
      throw const FormatException('Invalid confirmation data');
    }
    return PaymentConfirmationData(
      professionalId: professionalId.trim(),
      planId: planId.trim(),
      isActive: isActive,
      pendingPlanId: pendingPlanId is String ? pendingPlanId.trim() : null,
    );
  }

  final String professionalId;
  final String planId;
  final bool isActive;
  final String? pendingPlanId;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'professionalId': professionalId,
    'planId': planId,
    'isActive': isActive,
    if (pendingPlanId != null) 'pendingPlanId': pendingPlanId,
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
}

@immutable
final class StoreRestorationResult {
  const StoreRestorationResult({
    required this.confirmation,
    required this.completePurchase,
  });

  factory StoreRestorationResult.fromJson(Map<String, dynamic> json) {
    if (json['restored'] != true || json['complete_purchase'] != true) {
      throw const FormatException('Invalid store restoration response');
    }
    return StoreRestorationResult(
      confirmation: PaymentConfirmation.fromJson(json),
      completePurchase: true,
    );
  }

  final PaymentConfirmation confirmation;
  final bool completePurchase;
}

@immutable
final class FreeCheckoutSession {
  const FreeCheckoutSession({
    required this.confirmationToken,
    required this.checkoutId,
    required this.amountCents,
    required this.currency,
    this.alreadyFinalized = false,
    this.professionalId,
  });

  factory FreeCheckoutSession.fromJson(Map<String, dynamic> json) {
    final requiresPayment = json['requires_payment'];
    final alreadyFinalized = json['already_finalized'] == true;
    final rawCheckoutId = json['checkout_id'] ?? json['checkoutId'];
    final rawProfessionalId = json['professional_id'] ?? json['professionalId'];
    final rawToken = json['confirmation_token'] ?? json['id'];
    final rawAmount = json['amount'];
    final rawCurrency = json['currency'];
    if (requiresPayment != false ||
        rawCheckoutId is! String ||
        rawCheckoutId.trim().isEmpty ||
        rawAmount is! int ||
        rawAmount != 0 ||
        rawCurrency is! String ||
        rawCurrency.trim().isEmpty ||
        (!alreadyFinalized &&
            (rawToken is! String || rawToken.trim().isEmpty)) ||
        (alreadyFinalized &&
            (rawProfessionalId is! String ||
                rawProfessionalId.trim().isEmpty))) {
      throw const FormatException('Invalid free checkout response');
    }
    return FreeCheckoutSession(
      confirmationToken: rawToken is String ? rawToken.trim() : '',
      checkoutId: rawCheckoutId.trim(),
      amountCents: rawAmount,
      currency: rawCurrency.trim().toLowerCase(),
      alreadyFinalized: alreadyFinalized,
      professionalId: rawProfessionalId is String
          ? rawProfessionalId.trim()
          : null,
    );
  }

  final String confirmationToken;
  final String checkoutId;
  final int amountCents;
  final String currency;
  final bool alreadyFinalized;
  final String? professionalId;
}

@immutable
final class FreeRegistrationResult {
  const FreeRegistrationResult({
    required this.checkout,
    required this.confirmation,
  });

  final FreeCheckoutSession checkout;
  final PaymentConfirmation confirmation;
}

@immutable
final class StoreCheckoutSession {
  const StoreCheckoutSession({
    required this.checkoutId,
    required this.productId,
    required this.accountToken,
    this.alreadyFinalized = false,
    this.professionalId,
  });

  factory StoreCheckoutSession.fromJson(
    Map<String, dynamic> json, {
    required String expectedProductId,
  }) {
    final checkoutId = json['checkout_id'];
    final productId = json['product_id'];
    final accountToken = json['account_token'] ?? json['app_account_token'];
    final alreadyFinalized = json['already_finalized'] ?? false;
    final completePurchase = json['complete_purchase'];
    final professionalId = json['professional_id'];
    if (checkoutId is! String ||
        checkoutId.trim().isEmpty ||
        productId is! String ||
        productId.trim() != expectedProductId ||
        accountToken is! String ||
        accountToken.trim().isEmpty ||
        !_uuidPattern.hasMatch(accountToken.trim()) ||
        alreadyFinalized is! bool ||
        (alreadyFinalized &&
            (completePurchase != true ||
                professionalId is! String ||
                professionalId.trim().isEmpty))) {
      throw const FormatException('Invalid store checkout response');
    }
    return StoreCheckoutSession(
      checkoutId: checkoutId.trim(),
      productId: productId.trim(),
      accountToken: accountToken.trim(),
      alreadyFinalized: alreadyFinalized,
      professionalId: professionalId is String ? professionalId.trim() : null,
    );
  }

  final String checkoutId;
  final String productId;
  final String accountToken;
  final bool alreadyFinalized;
  final String? professionalId;
}

enum StorePurchaseStatus {
  loadingProducts,
  ready,
  preparing,
  restoring,
  pending,
  verifying,
  purchased,
  restored,
  canceled,
  error,
}

@immutable
final class StorePurchaseUpdate {
  const StorePurchaseUpdate({
    required this.status,
    this.planId,
    this.productId,
    this.checkoutId,
    this.confirmation,
    this.errorCode,
    this.errorMessage,
    this.isReplay = false,
  });

  final StorePurchaseStatus status;
  final String? planId;
  final String? productId;
  final String? checkoutId;
  final PaymentConfirmation? confirmation;
  final String? errorCode;
  final String? errorMessage;
  final bool isReplay;

  bool get wasRestored => status == StorePurchaseStatus.restored;

  StorePurchaseUpdate toReplayableState() {
    return StorePurchaseUpdate(
      status: status,
      planId: planId,
      productId: productId,
      errorCode: errorCode,
      isReplay: true,
    );
  }
}

final class StorePurchaseException implements Exception {
  const StorePurchaseException(this.code, this.message, {this.statusCode});

  final String code;
  final String message;
  final int? statusCode;

  @override
  String toString() => 'StorePurchaseException($code)';
}

/// Client du contrat serveur IAP. Les prix ne sont jamais envoyés par le client.
final class StoreCheckoutApi {
  StoreCheckoutApi({
    required String baseUrl,
    http.Client? client,
    this.timeout = const Duration(seconds: 25),
  }) : _baseUrl = baseUrl.replaceFirst(RegExp(r'/+$'), ''),
       _client = client ?? http.Client();

  final String _baseUrl;
  final http.Client _client;
  final Duration timeout;

  Future<PaymentPlanCatalog> fetchPaymentPlans() async {
    return PaymentPlanCatalog.fromJson(await _get('paymentPlans'));
  }

  Future<FreeRegistrationResult> submitFreeRegistration(
    StorePurchaseRequest request, {
    required PaymentPlanQuote serverQuote,
  }) async {
    if (serverQuote.id != request.planId ||
        serverQuote.requiresPayment ||
        serverQuote.amountCents != 0) {
      throw const StorePurchaseException(
        'FREE_CHECKOUT_QUOTE_MISMATCH',
        'The free plan does not match the current server catalog.',
      );
    }
    final checkout = await createFreeCheckout(request);
    if (checkout.currency != serverQuote.currency) {
      throw const StorePurchaseException(
        'FREE_CHECKOUT_QUOTE_MISMATCH',
        'The free checkout currency does not match the current catalog.',
      );
    }
    final confirmation = checkout.alreadyFinalized
        ? PaymentConfirmation.finalized(
            professionalId: checkout.professionalId!,
            planId: request.planId,
            isActive: false,
            status: 'pending_review',
            checkoutId: checkout.checkoutId,
          )
        : await _confirmFreeCheckoutWithSingleRetry(
            confirmationToken: checkout.confirmationToken,
            checkoutId: checkout.checkoutId,
          );
    if (confirmation.data?.planId != request.planId ||
        confirmation.checkoutId != checkout.checkoutId) {
      throw const StorePurchaseException(
        'INVALID_FREE_CONFIRMATION',
        'The free registration confirmation does not match its checkout.',
      );
    }
    return FreeRegistrationResult(
      checkout: checkout,
      confirmation: confirmation,
    );
  }

  Future<FreeCheckoutSession> createFreeCheckout(
    StorePurchaseRequest request,
  ) async {
    if (StoreProductIds.productIdForPlan(request.planId) != null) {
      throw const StorePurchaseException(
        'INVALID_FREE_PLAN',
        'A paid store plan cannot use the free checkout.',
      );
    }
    final preparedRegistration = await RegistrationPayloadPreparer.prepare(
      request.registrationData,
      maxGalleryImages: request.maxGalleryImages,
    );
    final payload = _registrationPayload(request, preparedRegistration);
    RegistrationPayloadPreparer.validateCheckoutRequest(payload);
    return FreeCheckoutSession.fromJson(
      await _post('createPaymentIntent', payload),
    );
  }

  Future<PaymentConfirmation> confirmFreeCheckout({
    required String confirmationToken,
    String? checkoutId,
  }) async {
    final token = confirmationToken.trim();
    if (token.isEmpty) {
      throw const StorePurchaseException(
        'INVALID_CONFIRMATION_TOKEN',
        'The free checkout confirmation token is missing.',
      );
    }
    final response = await _post('confirmPayment', <String, dynamic>{
      'confirmationToken': token,
    });
    return PaymentConfirmation.fromJson(response)
        .withFallbackCheckoutId(checkoutId);
  }

  Future<PaymentConfirmation> _confirmFreeCheckoutWithSingleRetry({
    required String confirmationToken,
    String? checkoutId,
  }) async {
    try {
      return await confirmFreeCheckout(
        confirmationToken: confirmationToken,
        checkoutId: checkoutId,
      );
    } on Object catch (error) {
      if (!_isRetryableFreeConfirmationError(error)) rethrow;
    }

    return confirmFreeCheckout(
      confirmationToken: confirmationToken,
      checkoutId: checkoutId,
    );
  }

  bool _isRetryableFreeConfirmationError(Object error) {
    if (error is TimeoutException || error is http.ClientException) {
      return true;
    }
    if (error is! StorePurchaseException) return false;
    final statusCode = error.statusCode;
    return statusCode == 408 ||
        statusCode == 429 ||
        (statusCode != null && statusCode >= 500);
  }

  Future<StoreCheckoutSession> createStoreCheckout(
    StorePurchaseRequest request, {
    required StorePlatform store,
  }) async {
    final productId = StoreProductIds.productIdForPlan(request.planId);
    if (productId == null) {
      throw const StorePurchaseException(
        'INVALID_STORE_PLAN',
        'The selected plan has no store product.',
      );
    }
    final preparedRegistration = await RegistrationPayloadPreparer.prepare(
      request.registrationData,
      maxGalleryImages: request.maxGalleryImages,
    );
    final payload = <String, dynamic>{
      ..._registrationPayload(request, preparedRegistration),
      'store': store.wireName,
    };
    RegistrationPayloadPreparer.validateCheckoutRequest(payload);
    final response = await _post('createStoreCheckout', payload);
    return StoreCheckoutSession.fromJson(
      response,
      expectedProductId: productId,
    );
  }

  Future<PaymentConfirmation> confirmStorePurchase({
    required StoreCheckoutSession checkout,
    required StorePlatform store,
    required StorePurchaseEvent purchase,
  }) async {
    final purchaseId = purchase.purchaseId?.trim() ?? '';
    final verificationData = purchase.verificationData.trim();
    if (verificationData.isEmpty ||
        (store == StorePlatform.appStore && purchaseId.isEmpty)) {
      throw const StorePurchaseException(
        'INVALID_STORE_PURCHASE',
        'The store purchase proof is incomplete.',
      );
    }
    final response = await _post('confirmStorePurchase', <String, dynamic>{
      'checkoutId': checkout.checkoutId,
      'store': store.wireName,
      'productId': checkout.productId,
      'verificationData': verificationData,
      if (purchaseId.isNotEmpty) 'purchaseId': purchaseId,
    });
    if (response['complete_purchase'] != true) {
      throw const FormatException(
        'The store confirmation cannot be completed.',
      );
    }
    return PaymentConfirmation.fromJson(response);
  }

  Future<StoreRestorationResult> restoreStorePurchase({
    required StorePlatform store,
    required StorePurchaseEvent purchase,
  }) async {
    final productId = purchase.productId.trim();
    final verificationData = purchase.verificationData.trim();
    if (productId.isEmpty || verificationData.isEmpty) {
      throw const StorePurchaseException(
        'INVALID_STORE_PURCHASE',
        'The restored store purchase proof is incomplete.',
      );
    }
    final purchaseId = purchase.purchaseId?.trim();
    final response = await _post('restoreStorePurchase', <String, dynamic>{
      'store': store.wireName,
      'productId': productId,
      'verificationData': verificationData,
      if (purchaseId != null && purchaseId.isNotEmpty) 'purchaseId': purchaseId,
    });
    return StoreRestorationResult.fromJson(response);
  }

  Map<String, dynamic> _registrationPayload(
    StorePurchaseRequest request,
    Map<String, dynamic> preparedRegistration,
  ) {
    return <String, dynamic>{
      'planId': request.planId.trim(),
      'professionalId': request.professionalId.trim(),
      'email': request.email.trim(),
      'businessName': request.businessName.trim(),
      'categoryId': request.categoryId.trim(),
      'ville': request.ville.trim(),
      'phone': request.phone.trim(),
      'registrationData': preparedRegistration,
    };
  }

  Future<Map<String, dynamic>> _get(String endpoint) async {
    final response = await _client
        .get(
          Uri.parse('$_baseUrl/$endpoint'),
          headers: const <String, String>{'Accept': 'application/json'},
        )
        .timeout(timeout);
    return _decodeResponse(response);
  }

  Future<Map<String, dynamic>> _post(
    String endpoint,
    Map<String, dynamic> payload,
  ) async {
    final response = await _client
        .post(
          Uri.parse('$_baseUrl/$endpoint'),
          headers: const <String, String>{
            'Accept': 'application/json',
            'Content-Type': 'application/json',
          },
          body: jsonEncode(payload),
        )
        .timeout(timeout);
    return _decodeResponse(response);
  }

  Map<String, dynamic> _decodeResponse(http.Response response) {
    Map<String, dynamic>? decoded;
    try {
      final candidate = jsonDecode(response.body);
      if (candidate is Map<String, dynamic>) decoded = candidate;
    } on FormatException {
      // Le statut HTTP demeure utile même si la passerelle renvoie du HTML.
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StorePurchaseException(
        decoded?['code']?.toString() ?? 'STORE_REQUEST_FAILED',
        decoded?['error']?.toString() ?? 'Store request failed.',
        statusCode: response.statusCode,
      );
    }
    if (decoded == null || decoded['success'] != true) {
      throw StorePurchaseException(
        decoded?['code']?.toString() ?? 'INVALID_STORE_RESPONSE',
        decoded?['error']?.toString() ?? 'Invalid store response.',
        statusCode: response.statusCode,
      );
    }
    return Map<String, dynamic>.unmodifiable(decoded);
  }
}

/// Orchestre achat/restauration et n'acquitte le store qu'après validation serveur.
final class StorePurchaseService {
  factory StorePurchaseService({
    required StorePurchaseGateway gateway,
    required StoreCheckoutApi api,
    required StorePlatform store,
  }) => StorePurchaseService._(gateway, api, store);

  StorePurchaseService._(this._gateway, this._api, this._store) {
    _purchaseSubscription = _gateway.purchaseStream.listen(
      _enqueuePurchases,
      onError: (Object error, StackTrace stackTrace) {
        _emitError('STORE_STREAM_ERROR', error.toString());
      },
    );
  }

  static StorePurchaseService? _sharedInstance;
  static StoreCheckoutApi? _sharedRegistrationApi;

  static bool get isSupportedPlatform => StorePlatform.current != null;

  /// Installe le listener global le plus tôt possible sur les plateformes
  /// mobiles prises en charge. Aucun SDK store n'est chargé sur le Web.
  static void initializeShared() {
    if (isSupportedPlatform) shared;
  }

  static StoreCheckoutApi get _registrationApi {
    return _sharedRegistrationApi ??= StoreCheckoutApi(
      baseUrl: AppConfig.current.apiBaseUrl,
    );
  }

  static Future<PaymentPlanCatalog> fetchPaymentPlans() {
    return _registrationApi.fetchPaymentPlans();
  }

  /// Crée et confirme un profil gratuit sans initialiser le SDK des stores.
  static Future<FreeRegistrationResult> submitFreeRegistration(
    StorePurchaseRequest request, {
    required PaymentPlanQuote serverQuote,
  }) {
    return _registrationApi.submitFreeRegistration(
      request,
      serverQuote: serverQuote,
    );
  }

  static StorePurchaseService get shared {
    final store = StorePlatform.current;
    if (store == null) {
      throw const StorePurchaseException(
        'STORE_PLATFORM_UNSUPPORTED',
        'In-app purchases are unavailable on this platform.',
      );
    }
    return _sharedInstance ??= StorePurchaseService(
      gateway: InAppPurchaseGateway(),
      api: StoreCheckoutApi(baseUrl: AppConfig.current.apiBaseUrl),
      store: store,
    );
  }

  final StorePurchaseGateway _gateway;
  final StoreCheckoutApi _api;
  final StorePlatform _store;
  final StreamController<StorePurchaseUpdate> _updates =
      StreamController<StorePurchaseUpdate>.broadcast();

  late final StreamSubscription<List<StorePurchaseEvent>> _purchaseSubscription;
  Future<void> _eventQueue = Future<void>.value();
  Map<String, StoreProductOffer> _productsByPlan =
      const <String, StoreProductOffer>{};
  StoreCheckoutSession? _activeCheckout;
  StorePurchaseRequest? _activeRequest;
  StoreSubscriptionChange? _activeSubscriptionChange;
  bool _purchaseStartInProgress = false;
  bool _restoreRequested = false;
  String? _requestedRestorePlanId;
  StorePurchaseUpdate? _lastReplayableUpdate;
  bool _disposed = false;

  Stream<StorePurchaseUpdate> get updates {
    return Stream<StorePurchaseUpdate>.multi((controller) {
      final subscription = _updates.stream.listen(
        controller.add,
        onError: controller.addError,
        onDone: controller.close,
      );
      final replay = _lastReplayableUpdate;
      if (replay != null) controller.add(replay);
      controller.onCancel = subscription.cancel;
    }, isBroadcast: true);
  }

  Map<String, StoreProductOffer> get productsByPlan => _productsByPlan;

  Future<Map<String, StoreProductOffer>> loadProducts({
    bool forceRefresh = false,
  }) async {
    if (_productsByPlan.isNotEmpty && !forceRefresh) return _productsByPlan;
    _emit(
      const StorePurchaseUpdate(status: StorePurchaseStatus.loadingProducts),
    );
    try {
      if (!await _gateway.isAvailable()) {
        throw const StorePurchaseException(
          'STORE_UNAVAILABLE',
          'The store is unavailable.',
        );
      }
      final offers = await _gateway.queryProducts(StoreProductIds.all);
      final products = <String, StoreProductOffer>{};
      for (final offer in offers) {
        final expectedProductId = StoreProductIds.productIdForPlan(
          offer.planId,
        );
        if (expectedProductId == null || expectedProductId != offer.productId) {
          throw const StorePurchaseException(
            'UNEXPECTED_STORE_PRODUCT',
            'The store returned an unexpected product.',
          );
        }
        if (offer.localizedPrice.trim().isEmpty ||
            offer.rawPrice <= 0 ||
            !_currencyCodePattern.hasMatch(offer.currencyCode)) {
          throw const StorePurchaseException(
            'INVALID_STORE_PRODUCT_OFFER',
            'The annual store offer has invalid recurring price details.',
          );
        }
        // Contrat v1 : un seul base plan/offre annuel doit être publié par
        // produit. Le client refuse toute ambiguïté au lieu de choisir un
        // offerToken arbitraire.
        if (products.containsKey(offer.planId)) {
          throw const StorePurchaseException(
            'AMBIGUOUS_STORE_PRODUCT_OFFER',
            'Exactly one annual offer is required for each store product.',
          );
        }
        products[offer.planId] = offer;
      }
      if (products.length != StoreProductIds.all.length) {
        throw const StorePurchaseException(
          'STORE_PRODUCTS_INCOMPLETE',
          'One or more store products are unavailable.',
        );
      }
      _productsByPlan = Map<String, StoreProductOffer>.unmodifiable(products);
      _emit(const StorePurchaseUpdate(status: StorePurchaseStatus.ready));
      return _productsByPlan;
    } on StorePurchaseException catch (error) {
      _emitError(error.code, error.message);
      rethrow;
    } on Exception catch (error) {
      _emitError('STORE_PRODUCTS_UNAVAILABLE', error.toString());
      throw StorePurchaseException(
        'STORE_PRODUCTS_UNAVAILABLE',
        error.toString(),
      );
    }
  }

  Future<void> startPurchase(StorePurchaseRequest request) async {
    if (_purchaseStartInProgress ||
        _activeCheckout != null ||
        _activeRequest != null ||
        _restoreRequested) {
      const error = StorePurchaseException(
        'STORE_PURCHASE_IN_PROGRESS',
        'Another store purchase is already in progress.',
      );
      _emitError(
        error.code,
        error.message,
        request: request,
        productId: StoreProductIds.productIdForPlan(request.planId),
      );
      throw error;
    }

    _purchaseStartInProgress = true;
    try {
      final offer = await _offerForRequest(request);
      late final StoreSubscriptionChange? subscriptionChange;
      try {
        subscriptionChange = await _googlePlaySubscriptionChange(
          request,
          offer,
        );
      } on StorePurchaseException catch (error) {
        _emitError(
          error.code,
          error.message,
          request: request,
          productId: offer.productId,
        );
        rethrow;
      } on Exception catch (error) {
        final message = error.toString();
        _emitError(
          'STORE_SUBSCRIPTION_STATE_UNAVAILABLE',
          message,
          request: request,
          productId: offer.productId,
        );
        throw StorePurchaseException(
          'STORE_SUBSCRIPTION_STATE_UNAVAILABLE',
          message,
        );
      }
      final checkout = await _prepareCheckout(request, offer);
      _activeSubscriptionChange = subscriptionChange;
      if (checkout.alreadyFinalized) {
        _clearActivePurchase(checkout);
        await _restorePurchase(
          planId: request.planId,
          fromFinalizedCheckout: true,
        );
        return;
      }

      late final bool launched;
      var storeInvocationStarted = false;
      try {
        if (subscriptionChange == null) {
          storeInvocationStarted = true;
          launched = await _gateway.buyNonConsumable(
            offer,
            applicationUserName: checkout.accountToken,
          );
        } else {
          if (_gateway is! GooglePlaySubscriptionGateway) {
            _clearActivePurchase(checkout);
            throw const StorePurchaseException(
              'STORE_SUBSCRIPTION_CHANGE_UNAVAILABLE',
              'Google Play subscription changes are unavailable.',
            );
          }
          final googlePlayGateway = _gateway as GooglePlaySubscriptionGateway;
          storeInvocationStarted = true;
          launched = await googlePlayGateway.changeSubscription(
            offer,
            applicationUserName: checkout.accountToken,
            subscriptionChange: subscriptionChange,
          );
        }
      } on StorePurchaseException catch (error) {
        if (!storeInvocationStarted) _clearActivePurchase(checkout);
        _emitError(
          error.code,
          error.message,
          request: request,
          checkout: checkout,
        );
        rethrow;
      } on Exception catch (error) {
        // Une exception après l'appel natif ne prouve pas que la feuille store
        // n'a pas été lancée. Le checkout reste donc actif afin qu'un événement
        // tardif puisse encore être vérifié et acquitté.
        if (!storeInvocationStarted) _clearActivePurchase(checkout);
        final message = error.toString();
        _emitError(
          'STORE_PURCHASE_LAUNCH_FAILED',
          message,
          request: request,
          checkout: checkout,
        );
        throw StorePurchaseException('STORE_PURCHASE_LAUNCH_FAILED', message);
      }
      if (!launched) {
        // `false` est le seul signal certain que le plugiciel n'a pas lancé
        // l'achat. Libérer ce checkout autorise alors une nouvelle tentative.
        _clearActivePurchase(checkout);
        const error = StorePurchaseException(
          'STORE_PURCHASE_NOT_LAUNCHED',
          'The store did not launch the purchase.',
        );
        _emitError(
          error.code,
          error.message,
          request: request,
          checkout: checkout,
        );
        throw error;
      }
    } finally {
      _purchaseStartInProgress = false;
    }
  }

  Future<StoreSubscriptionChange?> _googlePlaySubscriptionChange(
    StorePurchaseRequest request,
    StoreProductOffer targetOffer,
  ) async {
    if (_store != StorePlatform.googlePlay) return null;

    if (_gateway is! GooglePlaySubscriptionGateway) {
      throw const StorePurchaseException(
        'STORE_SUBSCRIPTION_STATE_UNAVAILABLE',
        'Google Play subscriptions cannot be inspected safely.',
      );
    }
    final googlePlayGateway = _gateway as GooglePlaySubscriptionGateway;
    final purchases = await googlePlayGateway.queryOwnedPurchases();
    final activeByProduct = <String, StorePurchaseEvent>{};
    for (final purchase in purchases) {
      if (!StoreProductIds.all.contains(purchase.productId)) continue;
      switch (purchase.status) {
        case StorePurchaseEventStatus.pending:
          throw const StorePurchaseException(
            'STORE_SUBSCRIPTION_CHANGE_PENDING',
            'A Google Play subscription change is already pending.',
          );
        case StorePurchaseEventStatus.purchased:
        case StorePurchaseEventStatus.restored:
          activeByProduct.putIfAbsent(purchase.productId, () => purchase);
          break;
        case StorePurchaseEventStatus.error:
        case StorePurchaseEventStatus.canceled:
          break;
      }
    }

    if (activeByProduct.isEmpty) return null;
    if (activeByProduct.length != 1) {
      throw const StorePurchaseException(
        'STORE_SUBSCRIPTION_STATE_AMBIGUOUS',
        'Multiple Google Play subscriptions are active.',
      );
    }

    final oldPurchase = activeByProduct.values.single;
    if (oldPurchase.productId == targetOffer.productId) {
      throw const StorePurchaseException(
        'STORE_SUBSCRIPTION_ALREADY_OWNED',
        'This Google Play subscription is already active. Restore it instead.',
      );
    }

    final oldPlanId = StoreProductIds.planIdForProduct(oldPurchase.productId);
    final replacementMode = switch ((oldPlanId, request.planId.trim())) {
      ('premium', 'professional') =>
        StoreSubscriptionReplacementMode.withTimeProration,
      ('professional', 'premium') => StoreSubscriptionReplacementMode.deferred,
      _ => throw const StorePurchaseException(
        'STORE_SUBSCRIPTION_CHANGE_UNSUPPORTED',
        'This Google Play subscription change is unsupported.',
      ),
    };
    return StoreSubscriptionChange(
      oldPurchase: oldPurchase,
      replacementMode: replacementMode,
    );
  }

  Future<void> restorePurchase({required String planId}) {
    return _restorePurchase(planId: planId);
  }

  Future<void> _restorePurchase({
    required String planId,
    bool fromFinalizedCheckout = false,
  }) async {
    final normalizedPlanId = planId.trim();
    if (_restoreRequested ||
        _activeCheckout != null ||
        _activeRequest != null ||
        (_purchaseStartInProgress && !fromFinalizedCheckout)) {
      const error = StorePurchaseException(
        'STORE_OPERATION_IN_PROGRESS',
        'Another store purchase or restoration is already in progress.',
      );
      _emitError(
        error.code,
        error.message,
        planId: normalizedPlanId,
        productId: StoreProductIds.productIdForPlan(normalizedPlanId),
      );
      throw error;
    }

    // Réserver la restauration avant tout `await` ferme la fenêtre entre un
    // checkout déjà finalisé et l'appel natif de restauration.
    _restoreRequested = true;
    _requestedRestorePlanId = normalizedPlanId;
    var restoreInvocationStarted = false;
    try {
      final products = await loadProducts();
      final offer = products[normalizedPlanId];
      if (offer == null) {
        const error = StorePurchaseException(
          'INVALID_STORE_PLAN',
          'The selected plan is unavailable in the store.',
        );
        _emitError(
          error.code,
          error.message,
          planId: normalizedPlanId,
          productId: StoreProductIds.productIdForPlan(normalizedPlanId),
        );
        throw error;
      }
      _emit(
        StorePurchaseUpdate(
          status: StorePurchaseStatus.restoring,
          planId: normalizedPlanId,
          productId: offer.productId,
        ),
      );
      restoreInvocationStarted = true;
      await _gateway.restorePurchases();
    } on Exception catch (error) {
      _clearRestoreRequest();
      if (!restoreInvocationStarted) rethrow;
      _emitError(
        'STORE_RESTORE_FAILED',
        error.toString(),
        planId: normalizedPlanId,
        productId: StoreProductIds.productIdForPlan(normalizedPlanId),
      );
      rethrow;
    }
  }

  void _clearRestoreRequest() {
    _restoreRequested = false;
    _requestedRestorePlanId = null;
  }

  Future<StoreProductOffer> _offerForRequest(
    StorePurchaseRequest request,
  ) async {
    final products = await loadProducts();
    final offer = products[request.planId];
    if (offer == null) {
      throw const StorePurchaseException(
        'INVALID_STORE_PLAN',
        'The selected plan is unavailable in the store.',
      );
    }
    return offer;
  }

  Future<StoreCheckoutSession> _prepareCheckout(
    StorePurchaseRequest request,
    StoreProductOffer offer,
  ) async {
    _emit(
      StorePurchaseUpdate(
        status: StorePurchaseStatus.preparing,
        planId: request.planId,
        productId: offer.productId,
      ),
    );
    try {
      final checkout = await _api.createStoreCheckout(request, store: _store);
      _activeRequest = request;
      _activeCheckout = checkout;
      return checkout;
    } on StorePurchaseException catch (error) {
      _emitError(error.code, error.message, request: request);
      rethrow;
    } on FormatException catch (error) {
      final message = error.message.toString();
      _emitError('INVALID_STORE_RESPONSE', message, request: request);
      throw StorePurchaseException('INVALID_STORE_RESPONSE', message);
    } on RegistrationImageException catch (error) {
      _emitError(error.code, error.toString(), request: request);
      throw StorePurchaseException(error.code, error.toString());
    } on TimeoutException catch (error) {
      final message = error.toString();
      _emitError('STORE_REQUEST_TIMEOUT', message, request: request);
      throw StorePurchaseException('STORE_REQUEST_TIMEOUT', message);
    } on http.ClientException catch (error) {
      final message = error.toString();
      _emitError('STORE_NETWORK_ERROR', message, request: request);
      throw StorePurchaseException('STORE_NETWORK_ERROR', message);
    } on Exception catch (error) {
      final message = error.toString();
      _emitError('STORE_CHECKOUT_FAILED', message, request: request);
      throw StorePurchaseException('STORE_CHECKOUT_FAILED', message);
    }
  }

  void _enqueuePurchases(List<StorePurchaseEvent> purchases) {
    _eventQueue = _eventQueue.then<void>((_) => _handlePurchases(purchases));
  }

  Future<void> _handlePurchases(List<StorePurchaseEvent> purchases) async {
    if (purchases.isEmpty) {
      if (_restoreRequested) {
        final requestedPlanId = _requestedRestorePlanId;
        _clearRestoreRequest();
        final unresolvedCheckout = _activeCheckout;
        if (unresolvedCheckout != null) {
          _clearActivePurchase(unresolvedCheckout);
        }
        _emitError(
          'NO_STORE_PURCHASE_FOUND',
          'No matching purchase was found.',
          planId: requestedPlanId,
          productId: requestedPlanId == null
              ? null
              : StoreProductIds.productIdForPlan(requestedPlanId),
        );
      }
      return;
    }

    final activeCheckout = _activeCheckout;
    final activeRequest = _activeRequest;
    final deferredOldProductId = activeCheckout != null && activeRequest != null
        ? _activeDeferredChangeFor(
            activeCheckout,
            activeRequest,
          )?.oldPurchase.productId
        : null;
    if (activeCheckout != null && activeRequest != null) {
      final matchingPurchasedEvents = purchases.where(
        (purchase) =>
            purchase.status == StorePurchaseEventStatus.purchased &&
            _matchesActiveCheckout(purchase, activeCheckout, activeRequest),
      );
      if (matchingPurchasedEvents.length > 1) {
        _emitError(
          'STORE_SUBSCRIPTION_CHANGE_AMBIGUOUS',
          'Multiple store purchases match the active subscription change.',
          request: activeRequest,
          checkout: activeCheckout,
        );
        return;
      }
    }

    var handledRequestedRestore = false;
    StoreCheckoutSession? terminalCheckout;
    var confirmedPurchaseInBatch = false;
    for (final purchase in purchases) {
      // Garder le même contexte pour tout le lot. Après confirmation et
      // acquittement, ignorer seulement les terminaux tardifs de cette même
      // opération afin qu'ils ne remplacent pas le succès déjà acquis.
      final checkout = activeCheckout;
      final request = activeRequest;
      final hasActiveCheckout = checkout != null && request != null;
      final eventPlanId = StoreProductIds.planIdForProduct(purchase.productId);
      final mustRecoverWithoutCheckout =
          purchase.status == StorePurchaseEventStatus.purchased &&
          !hasActiveCheckout;
      if (purchase.status == StorePurchaseEventStatus.restored ||
          mustRecoverWithoutCheckout) {
        if (eventPlanId == null) {
          _emitError(
            'UNEXPECTED_STORE_PRODUCT',
            'The store returned an unexpected product.',
            productId: purchase.productId,
          );
          continue;
        }
        final requestedRestorePlanId = _restoreRequested
            ? _requestedRestorePlanId
            : null;
        final matchesRequestedRestore =
            requestedRestorePlanId != null &&
            (eventPlanId == requestedRestorePlanId ||
                _isDeferredRestorationTransition(
                  activePlanId: eventPlanId,
                  targetPlanId: requestedRestorePlanId,
                ));
        if (matchesRequestedRestore) {
          handledRequestedRestore = true;
        }
        await _restoreAndComplete(
          purchase,
          eventPlanId,
          requestedPlanId: matchesRequestedRestore
              ? requestedRestorePlanId
              : null,
        );
        continue;
      }

      if (checkout == null || request == null) continue;
      final isLateTerminalForConfirmedPurchase =
          confirmedPurchaseInBatch &&
          (purchase.status == StorePurchaseEventStatus.canceled ||
              purchase.status == StorePurchaseEventStatus.error) &&
          (purchase.productId == checkout.productId ||
              purchase.productId == deferredOldProductId);
      if (isLateTerminalForConfirmedPurchase) continue;
      if (!_matchesActiveCheckout(purchase, checkout, request)) {
        _emitError(
          'STORE_PURCHASE_CHECKOUT_MISMATCH',
          'The store purchase does not match the active checkout.',
          request: request,
          checkout: checkout,
        );
        continue;
      }
      switch (purchase.status) {
        case StorePurchaseEventStatus.pending:
          _emit(
            StorePurchaseUpdate(
              status: StorePurchaseStatus.pending,
              planId: request.planId,
              productId: checkout.productId,
              checkoutId: checkout.checkoutId,
            ),
          );
          break;
        case StorePurchaseEventStatus.canceled:
          _emit(
            StorePurchaseUpdate(
              status: StorePurchaseStatus.canceled,
              planId: request.planId,
              productId: checkout.productId,
              checkoutId: checkout.checkoutId,
            ),
          );
          terminalCheckout ??= checkout;
          break;
        case StorePurchaseEventStatus.error:
          _emitError(
            purchase.errorCode ?? 'STORE_PURCHASE_FAILED',
            purchase.errorMessage ?? 'The store purchase failed.',
            request: request,
            checkout: checkout,
          );
          terminalCheckout ??= checkout;
          break;
        case StorePurchaseEventStatus.purchased:
          confirmedPurchaseInBatch =
              await _verifyPurchaseAndComplete(purchase, request, checkout) ||
              confirmedPurchaseInBatch;
          break;
        case StorePurchaseEventStatus.restored:
          break;
      }
    }
    if (_restoreRequested && !handledRequestedRestore) {
      final requestedPlanId = _requestedRestorePlanId;
      _clearRestoreRequest();
      final unresolvedCheckout = _activeCheckout;
      if (unresolvedCheckout != null) {
        _clearActivePurchase(unresolvedCheckout);
      }
      _emitError(
        'NO_STORE_PURCHASE_FOUND',
        'No matching purchase was found.',
        planId: requestedPlanId,
        productId: requestedPlanId == null
            ? null
            : StoreProductIds.productIdForPlan(requestedPlanId),
      );
    } else if (handledRequestedRestore) {
      _clearRestoreRequest();
    }
    if (terminalCheckout != null) {
      _clearActivePurchase(terminalCheckout);
    }
  }

  bool _matchesActiveCheckout(
    StorePurchaseEvent purchase,
    StoreCheckoutSession checkout,
    StorePurchaseRequest request,
  ) {
    if (purchase.productId == checkout.productId) return true;

    final subscriptionChange = _activeDeferredChangeFor(checkout, request);
    if (subscriptionChange == null ||
        purchase.productId != subscriptionChange.oldPurchase.productId) {
      return false;
    }

    if (purchase.status != StorePurchaseEventStatus.purchased) {
      return purchase.status == StorePurchaseEventStatus.pending ||
          purchase.status == StorePurchaseEventStatus.canceled ||
          purchase.status == StorePurchaseEventStatus.error;
    }

    // Google Play conserve l'ancien productId jusqu'au renouvellement pour un
    // remplacement différé, tout en émettant immédiatement un nouveau jeton.
    // Exiger un jeton distinct évite de rattacher une simple relecture de
    // l'ancien abonnement au checkout cible.
    final newVerificationData = purchase.verificationData.trim();
    final oldVerificationData = subscriptionChange.oldPurchase.verificationData
        .trim();
    return newVerificationData.isNotEmpty &&
        oldVerificationData.isNotEmpty &&
        newVerificationData != oldVerificationData;
  }

  StoreSubscriptionChange? _activeDeferredChangeFor(
    StoreCheckoutSession checkout,
    StorePurchaseRequest request,
  ) {
    final subscriptionChange = _activeSubscriptionChange;
    final targetProductId = StoreProductIds.productIdForPlan(request.planId);
    if (_store != StorePlatform.googlePlay ||
        subscriptionChange == null ||
        subscriptionChange.replacementMode !=
            StoreSubscriptionReplacementMode.deferred ||
        targetProductId == null ||
        checkout.productId != targetProductId ||
        subscriptionChange.oldPurchase.productId == targetProductId ||
        StoreProductIds.planIdForProduct(
              subscriptionChange.oldPurchase.productId,
            ) ==
            null) {
      return null;
    }
    return subscriptionChange;
  }

  bool _isDeferredRestorationTransition({
    required String activePlanId,
    required String targetPlanId,
  }) {
    return _store == StorePlatform.googlePlay &&
        activePlanId == 'professional' &&
        targetPlanId == 'premium';
  }

  Future<bool> _verifyPurchaseAndComplete(
    StorePurchaseEvent purchase,
    StorePurchaseRequest request,
    StoreCheckoutSession checkout,
  ) async {
    _emit(
      StorePurchaseUpdate(
        status: StorePurchaseStatus.verifying,
        planId: request.planId,
        productId: checkout.productId,
        checkoutId: checkout.checkoutId,
      ),
    );
    try {
      final confirmation = await _api.confirmStorePurchase(
        checkout: checkout,
        store: _store,
        purchase: purchase,
      );
      final confirmationData = confirmation.data;
      final deferredChange = _activeDeferredChangeFor(checkout, request);
      final expectedActivePlanId = deferredChange == null
          ? request.planId
          : StoreProductIds.planIdForProduct(
              deferredChange.oldPurchase.productId,
            );
      final expectedPendingPlanId = deferredChange == null
          ? null
          : request.planId;
      if (confirmationData?.planId != expectedActivePlanId ||
          confirmationData?.pendingPlanId != expectedPendingPlanId ||
          confirmation.checkoutId != checkout.checkoutId) {
        throw const StorePurchaseException(
          'INVALID_STORE_CONFIRMATION',
          'The store confirmation does not match its checkout.',
        );
      }
      if (purchase.pendingCompletePurchase) {
        await _gateway.completePurchase(purchase);
      }
      _clearActivePurchase(checkout);
      _emit(
        StorePurchaseUpdate(
          status: StorePurchaseStatus.purchased,
          planId: request.planId,
          productId: checkout.productId,
          checkoutId: checkout.checkoutId,
          confirmation: confirmation,
        ),
      );
      return true;
    } on StorePurchaseException catch (error) {
      _emitError(
        error.code,
        error.message,
        request: request,
        checkout: checkout,
      );
      return false;
    } on FormatException catch (error) {
      _emitError(
        'INVALID_STORE_CONFIRMATION',
        error.message.toString(),
        request: request,
        checkout: checkout,
      );
      return false;
    } on Exception catch (error) {
      _emitError(
        'STORE_COMPLETION_FAILED',
        error.toString(),
        request: request,
        checkout: checkout,
      );
      return false;
    }
  }

  void _clearActivePurchase(StoreCheckoutSession checkout) {
    if (_activeCheckout?.checkoutId != checkout.checkoutId) return;
    _activeCheckout = null;
    _activeRequest = null;
    _activeSubscriptionChange = null;
  }

  Future<void> _restoreAndComplete(
    StorePurchaseEvent purchase,
    String activePlanId, {
    String? requestedPlanId,
  }) async {
    _emit(
      StorePurchaseUpdate(
        status: StorePurchaseStatus.verifying,
        planId: requestedPlanId ?? activePlanId,
        productId: purchase.productId,
      ),
    );
    try {
      final restoration = await _api.restoreStorePurchase(
        store: _store,
        purchase: purchase,
      );
      final confirmation = restoration.confirmation;
      final confirmationData = confirmation.data;
      final pendingPlanId = confirmationData?.pendingPlanId;
      final requestedActivePlan = requestedPlanId == activePlanId;
      final expectedPendingPlanId =
          requestedPlanId == null || requestedActivePlan
          ? pendingPlanId
          : requestedPlanId;
      final isDeferredRestoration =
          expectedPendingPlanId != null &&
          _isDeferredRestorationTransition(
            activePlanId: activePlanId,
            targetPlanId: expectedPendingPlanId,
          );
      final restoredPlanId = requestedActivePlan
          ? activePlanId
          : isDeferredRestoration
          ? expectedPendingPlanId
          : activePlanId;
      if (!restoration.completePurchase ||
          confirmationData?.planId != activePlanId ||
          pendingPlanId != expectedPendingPlanId ||
          (expectedPendingPlanId != null && !isDeferredRestoration) ||
          (requestedPlanId != null && restoredPlanId != requestedPlanId) ||
          confirmation.checkoutId == null) {
        throw const StorePurchaseException(
          'INVALID_STORE_RESTORATION',
          'The store restoration does not match its product.',
        );
      }
      if (purchase.pendingCompletePurchase) {
        await _gateway.completePurchase(purchase);
      }
      final activeCheckout = _activeCheckout;
      if (activeCheckout != null &&
          activeCheckout.checkoutId == confirmation.checkoutId) {
        _clearActivePurchase(activeCheckout);
      }
      _emit(
        StorePurchaseUpdate(
          status: StorePurchaseStatus.restored,
          planId: restoredPlanId,
          productId: purchase.productId,
          checkoutId: confirmation.checkoutId,
          confirmation: confirmation,
        ),
      );
    } on StorePurchaseException catch (error) {
      _emitError(
        error.code,
        error.message,
        planId: requestedPlanId ?? activePlanId,
        productId: purchase.productId,
      );
    } on FormatException catch (error) {
      _emitError(
        'INVALID_STORE_RESTORATION',
        error.message.toString(),
        planId: requestedPlanId ?? activePlanId,
        productId: purchase.productId,
      );
    } on Exception catch (error) {
      _emitError(
        'STORE_RESTORATION_FAILED',
        error.toString(),
        planId: requestedPlanId ?? activePlanId,
        productId: purchase.productId,
      );
    }
  }

  void _emitError(
    String code,
    String message, {
    StorePurchaseRequest? request,
    StoreCheckoutSession? checkout,
    String? planId,
    String? productId,
    String? checkoutId,
  }) {
    _emit(
      StorePurchaseUpdate(
        status: StorePurchaseStatus.error,
        planId: planId ?? request?.planId,
        productId: productId ?? checkout?.productId,
        checkoutId: checkoutId ?? checkout?.checkoutId,
        errorCode: code,
        errorMessage: message,
      ),
    );
  }

  void _emit(StorePurchaseUpdate update) {
    if (_disposed) return;
    _lastReplayableUpdate = update.toReplayableState();
    _updates.add(update);
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _purchaseSubscription.cancel();
    await _eventQueue;
    await _updates.close();
  }
}
