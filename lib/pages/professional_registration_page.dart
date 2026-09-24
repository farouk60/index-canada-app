import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../data/canadian_cities.dart';
import '../data_service.dart';
import '../models.dart';
import '../services/localization_service.dart';
import '../services/stripe_native_payment_service.dart';
import '../theme/app_theme.dart';
import '../widgets/language_selector.dart';
import 'native_payment_page.dart';
import 'payment_success_page.dart';

typedef PaymentPlansLoader = Future<PaymentPlanCatalog> Function();
typedef ProfessionalCategoriesLoader = Future<List<SousCategorie>> Function();

class ProfessionalRegistrationPage extends StatefulWidget {
  final String? categoryId;
  final String? categoryName;
  final String? categoryNameEn;
  final PaymentPlansLoader? paymentPlansLoader;
  final ProfessionalCategoriesLoader? categoriesLoader;

  const ProfessionalRegistrationPage({
    super.key,
    this.categoryId,
    this.categoryName,
    this.categoryNameEn,
    this.paymentPlansLoader,
    this.categoriesLoader,
  });

  @override
  State<ProfessionalRegistrationPage> createState() =>
      _ProfessionalRegistrationPageState();
}

class _ProfessionalRegistrationPageState
    extends State<ProfessionalRegistrationPage> {
  static final RegExp _emailPattern = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]{2,}$');
  static final RegExp _phoneCharactersPattern = RegExp(r'^[+()\-.\s0-9]+$');

  final LocalizationService _localizationService = LocalizationService();
  late final String _registrationSessionId =
      'temp_${DateTime.now().microsecondsSinceEpoch}';

  // Clés de formulaire pour chaque section du parcours.
  final _step1Key = GlobalKey<FormState>(); // Identité
  final _step2Key = GlobalKey<FormState>(); // Contact & Localisation
  final _step3Key = GlobalKey<FormState>(); // Médias & Social
  final _step4Key = GlobalKey<FormState>(); // Plan & Coupons

  // Contrôleurs - Étape 1 : Identité
  final _businessNameController = TextEditingController();
  final _descriptionController = TextEditingController();

  // Contrôleurs - Étape 2 : Contact & Localisation
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _addressController = TextEditingController();
  final _cityController = TextEditingController();
  final FocusNode _cityFocusNode = FocusNode();
  final _websiteController = TextEditingController();

  // Contrôleurs - Étape 3 : Médias & Social
  final _facebookController = TextEditingController();
  final _instagramController = TextEditingController();
  final _tiktokController = TextEditingController();
  final _youtubeController = TextEditingController();
  final _whatsappController = TextEditingController();

  // Contrôleurs - Étape 4 : Plan & Coupons
  final _couponTitleController = TextEditingController();
  final _couponCodeController = TextEditingController();
  final _couponDescriptionController = TextEditingController();

  // State du Stepper
  int _currentStep = 0;
  String? _selectedPlanId;
  bool _isSubmitting = false;
  bool _isLoadingPlans = true;
  bool _plansUnavailable = false;
  List<PaymentPlanQuote> _paymentPlans = const <PaymentPlanQuote>[];

  // Images
  Uint8List? _profileImage;
  final List<Uint8List> _galleryImages = [];

  // Date d'expiration du coupon
  DateTime? _couponExpirationDate;

  // Catégories
  List<SousCategorie> _sousCategories = [];
  String _selectedCategoryId = '';
  bool _isLoadingCategories = true;
  bool _categoriesUnavailable = false;

  PaymentPlanQuote? get _selectedPlan {
    final selectedId = _selectedPlanId;
    if (selectedId == null) return null;
    for (final plan in _paymentPlans) {
      if (plan.id == selectedId) return plan;
    }
    return null;
  }

  bool _isPlanSupported(PaymentPlanQuote plan) {
    return StripeNativePaymentService.paymentSupportFor(
      requiresPayment: plan.requiresPayment,
    ).isSupported;
  }

  SousCategorie? get _selectedCategory {
    for (final category in _sousCategories) {
      if (category.id == _selectedCategoryId) return category;
    }
    return null;
  }

  String _formatPlanPrice(PaymentPlanQuote plan, bool isEn) {
    final amount = NumberFormat.simpleCurrency(
      locale: isEn ? 'en_CA' : 'fr_CA',
      name: plan.currency.toUpperCase(),
      decimalDigits: 2,
    ).format(plan.amount);
    final durationDays = plan.durationDays;
    late final String period;
    if (durationDays >= 360 && durationDays <= 366) {
      period = isEn ? 'year' : 'an';
    } else if (durationDays >= 28 && durationDays <= 31) {
      period = isEn ? 'month' : 'mois';
    } else if (durationDays == 7) {
      period = isEn ? 'week' : 'semaine';
    } else {
      period = isEn ? '$durationDays days' : '$durationDays jours';
    }
    return '$amount / $period';
  }

  @override
  void initState() {
    super.initState();
    final initialCategoryId = widget.categoryId;
    if (initialCategoryId != null) {
      _selectedCategoryId = initialCategoryId;
    }
    _loadAllCategories();
    _loadPaymentPlans();
  }

  Future<void> _loadPaymentPlans() async {
    if (mounted) {
      setState(() {
        _isLoadingPlans = true;
        _plansUnavailable = false;
      });
    }
    try {
      final catalog =
          await (widget.paymentPlansLoader?.call() ??
              StripeNativePaymentService.fetchPaymentPlans());
      if (!mounted) return;

      final previousSelection = catalog.findPlan(_selectedPlanId ?? '');
      PaymentPlanQuote? defaultPlan;
      if (previousSelection != null && _isPlanSupported(previousSelection)) {
        defaultPlan = previousSelection;
      }
      if (defaultPlan == null) {
        for (final plan in catalog.plans) {
          if (!plan.requiresPayment && _isPlanSupported(plan)) {
            defaultPlan = plan;
            break;
          }
        }
      }
      if (defaultPlan == null) {
        for (final plan in catalog.plans) {
          if (_isPlanSupported(plan)) {
            defaultPlan = plan;
            break;
          }
        }
      }

      setState(() {
        _paymentPlans = catalog.plans;
        _selectedPlanId = defaultPlan?.id;
        _isLoadingPlans = false;
        _plansUnavailable = false;
      });
    } on Exception {
      if (!mounted) return;
      setState(() {
        _paymentPlans = const <PaymentPlanQuote>[];
        _selectedPlanId = null;
        _isLoadingPlans = false;
        _plansUnavailable = true;
      });
    }
  }

  Future<void> _loadAllCategories() async {
    if (mounted) {
      setState(() {
        _isLoadingCategories = true;
        _categoriesUnavailable = false;
      });
    }
    try {
      final categories =
          await (widget.categoriesLoader?.call() ??
              DataService().fetchSousCategories());
      if (mounted) {
        setState(() {
          _sousCategories = categories;
          _isLoadingCategories = false;
          _categoriesUnavailable = categories.isEmpty;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _sousCategories = const <SousCategorie>[];
          _isLoadingCategories = false;
          _categoriesUnavailable = true;
        });
      }
    }
  }

  @override
  void dispose() {
    _businessNameController.dispose();
    _descriptionController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    _cityController.dispose();
    _cityFocusNode.dispose();
    _websiteController.dispose();
    _facebookController.dispose();
    _instagramController.dispose();
    _tiktokController.dispose();
    _youtubeController.dispose();
    _whatsappController.dispose();
    _couponTitleController.dispose();
    _couponCodeController.dispose();
    _couponDescriptionController.dispose();
    super.dispose();
  }

  // --- Helpers ---

  String? _validateEmail(String? rawValue, bool isEn) {
    final value = rawValue?.trim() ?? '';
    if (value.isEmpty) return isEn ? 'Email is required' : 'L’email est requis';
    if (value.length > 254 || !_emailPattern.hasMatch(value)) {
      return isEn ? 'Enter a valid email' : 'Saisissez un email valide';
    }
    return null;
  }

  String? _validatePhone(String? rawValue, bool isEn) {
    final value = rawValue?.trim() ?? '';
    final digitCount = value.replaceAll(RegExp(r'\D'), '').length;
    if (value.isEmpty) {
      return isEn ? 'Phone number is required' : 'Le téléphone est requis';
    }
    if (!_phoneCharactersPattern.hasMatch(value) ||
        digitCount < 10 ||
        digitCount > 15) {
      return isEn
          ? 'Enter a valid phone number'
          : 'Saisissez un numéro de téléphone valide';
    }
    return null;
  }

  String? _validateWebsite(String? rawValue, bool isEn) {
    final value = rawValue?.trim() ?? '';
    if (value.isEmpty) return null;
    final normalized = value.contains('://') ? value : 'https://$value';
    final uri = Uri.tryParse(normalized);
    if (uri == null ||
        (uri.scheme != 'http' && uri.scheme != 'https') ||
        uri.host.isEmpty ||
        !uri.host.contains('.') ||
        uri.userInfo.isNotEmpty) {
      return isEn
          ? 'Enter a valid website address'
          : 'Saisissez une adresse de site valide';
    }
    return null;
  }

  String _removeDiacritics(String str) {
    var withDia =
        'ÀÁÂÃÄÅàáâãäåÒÓÔÕÕÖØòóôõöøÈÉÊËèéêëðÇçÐÌÍÎÏìíîïÙÚÛÜùúûüÑñŠšŸÿýŽž';
    var withoutDia =
        'AAAAAAaaaaaaOOOOOOOooooooEEEEeeeeeCcDIIIIiiiiUUUUuuuuNnSsYyyZz';
    for (int i = 0; i < withDia.length; i++) {
      str = str.replaceAll(withDia[i], withoutDia[i]);
    }
    return str;
  }

  String _normalizeForSorting(String text) {
    return _removeDiacritics(text).toLowerCase();
  }

  List<SousCategorie> _getSortedCategories() {
    final categories = List<SousCategorie>.from(_sousCategories);
    categories.sort((a, b) {
      final titleA = _localizationService.currentLanguage == 'en'
          ? a.titleEn
          : a.title;
      final titleB = _localizationService.currentLanguage == 'en'
          ? b.titleEn
          : b.title;
      return _normalizeForSorting(titleA)
          .compareTo(_normalizeForSorting(titleB));
    });
    return categories;
  }

  void _showSuccessMessage(String message) {
    if (mounted) {
      final colors = Theme.of(context).colorScheme;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message, style: TextStyle(color: colors.onTertiary)),
          backgroundColor: colors.tertiary,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _showErrorMessage(String message) {
    if (mounted) {
      final colors = Theme.of(context).colorScheme;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message, style: TextStyle(color: colors.onError)),
          backgroundColor: colors.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  // --- Image Logic ---
  void _pickProfileImage() {
    if (_selectedPlan?.capabilities.profileImage != true) return;
    _showImageSourceChoice(false);
  }

  void _pickGalleryImages() {
    final galleryMax = _selectedPlan?.capabilities.galleryMax ?? 0;
    if (galleryMax <= 0) {
      _showErrorMessage(
        _localizationService.currentLanguage == 'en'
            ? 'The selected plan does not include a photo gallery.'
            : 'Le forfait sélectionné n’inclut pas de galerie photo.',
      );
      return;
    }
    if (_galleryImages.length >= galleryMax) {
      _showErrorMessage(
        _localizationService.currentLanguage == 'en'
            ? 'Maximum $galleryMax images'
            : 'Maximum de $galleryMax images',
      );
      return;
    }
    _showImageSourceChoice(true);
  }

  void _showImageSourceChoice(bool isGallery) {
    final isEn = _localizationService.currentLanguage == 'en';
    final colors = Theme.of(context).colorScheme;
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(Icons.camera_alt, color: colors.primary),
              title: Text(isEn ? 'Camera' : 'Appareil photo'),
              onTap: () {
                Navigator.pop(context);
                _processImage(ImageSource.camera, isGallery);
              },
            ),
            ListTile(
              leading: Icon(Icons.photo_library, color: colors.tertiary),
              title: Text(isEn ? 'Gallery' : 'Galerie'),
              onTap: () {
                Navigator.pop(context);
                _processImage(ImageSource.gallery, isGallery);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _processImage(ImageSource source, bool isGallery) async {
    try {
      final picker = ImagePicker();
      final XFile? image = await picker.pickImage(
        source: source,
        maxWidth: 600,
        maxHeight: 600,
        imageQuality: 50,
      );

      if (image != null) {
        final bytes = await image.readAsBytes();
        if (!mounted) return;
        if (bytes.lengthInBytes > 5 * 1024 * 1024) {
          _showErrorMessage(
            _localizationService.currentLanguage == 'en'
                ? 'The selected image exceeds 5 MB.'
                : 'L’image sélectionnée dépasse 5 Mo.',
          );
          return;
        }
        setState(() {
          if (isGallery) {
            final galleryMax = _selectedPlan?.capabilities.galleryMax ?? 0;
            if (_galleryImages.length < galleryMax) {
              _galleryImages.add(bytes);
            }
          } else {
            _profileImage = bytes;
          }
        });
      }
    } catch (_) {
      if (!mounted) return;
      _showErrorMessage(
        _localizationService.currentLanguage == 'en'
            ? 'The image could not be selected.'
            : 'L’image n’a pas pu être sélectionnée.',
      );
    }
  }

  // --- Form Logic ---

  Future<void> _submitForm() async {
    // Validation finale au cas où
    final selectedCategory = _selectedCategory;
    if (_businessNameController.text.trim().isEmpty ||
        selectedCategory == null) {
      setState(() => _currentStep = 1);
      _showErrorMessage(
        _localizationService.currentLanguage == 'en'
            ? 'Select a valid business name and category.'
            : 'Sélectionnez un nom d’entreprise et une catégorie valides.',
      );
      return;
    }

    final selectedPlan = _selectedPlan;
    final isEn = _localizationService.currentLanguage == 'en';
    if (_plansUnavailable || _isLoadingPlans || selectedPlan == null) {
      _showErrorMessage(
        isEn ? 'Plans are temporarily unavailable. Please retry.' : 'Les forfaits sont temporairement indisponibles. Veuillez réessayer.',
      );
      return;
    }
    if (!_isPlanSupported(selectedPlan)) {
      setState(() => _currentStep = 0);
      _showErrorMessage(
        _localizationService.tr('paid_payment_web_unavailable'),
      );
      return;
    }
    if (_galleryImages.length > selectedPlan.capabilities.galleryMax) {
      setState(() => _currentStep = 3);
      _showErrorMessage(
        isEn
            ? 'This plan allows up to ${selectedPlan.capabilities.galleryMax} gallery images.'
            : 'Ce forfait permet au maximum ${selectedPlan.capabilities.galleryMax} images de galerie.',
      );
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      // 1. Prepare Images
      String? profileImageBase64;
      List<String>? galleryImagesBase64;
      if (_profileImage != null && selectedPlan.capabilities.profileImage) {
        profileImageBase64 = base64Encode(_profileImage!);
      }

      if (_galleryImages.isNotEmpty &&
          selectedPlan.capabilities.galleryMax > 0) {
        galleryImagesBase64 = [];
        for (final bytes in _galleryImages) {
          galleryImagesBase64.add(base64Encode(bytes));
        }
      }

      // 2. Prepare Data
      final registrationData = {
        'businessName': _businessNameController.text.trim(),
        'category': _selectedCategoryId,
        'email': _emailController.text.trim(),
        'phone': _phoneController.text.trim(),
        'address': _addressController.text.trim(),
        'city': _cityController.text.trim(),
        'description': _descriptionController.text.trim(),
        'selectedPlan': selectedPlan.id,
        'website': _websiteController.text.trim().isNotEmpty
            ? _websiteController.text.trim()
            : null,
        'businessSummary': _descriptionController.text.trim(),
        'facebook': _facebookController.text.trim().isNotEmpty
            ? _facebookController.text.trim()
            : null,
        'instagram': _instagramController.text.trim().isNotEmpty
            ? _instagramController.text.trim()
            : null,
        'tiktok': _tiktokController.text.trim().isNotEmpty
            ? _tiktokController.text.trim()
            : null,
        'youtube': _youtubeController.text.trim().isNotEmpty
            ? _youtubeController.text.trim()
            : null,
        'whatsapp': _whatsappController.text.trim().isNotEmpty
            ? _whatsappController.text.trim()
            : null,
        if (selectedPlan.capabilities.coupon) ...{
          'couponTitle': _couponTitleController.text.trim().isNotEmpty
              ? _couponTitleController.text.trim()
              : null,
          'couponCode': _couponCodeController.text.trim().isNotEmpty
              ? _couponCodeController.text.trim()
              : null,
          'couponDescription':
              _couponDescriptionController.text.trim().isNotEmpty
              ? _couponDescriptionController.text.trim()
              : null,
          'couponExpirationDate': _couponExpirationDate?.toIso8601String(),
        },
        'hasProfileImage': profileImageBase64 != null,
        'galleryImagesCount': galleryImagesBase64?.length ?? 0,
        'profileImageBase64': profileImageBase64,
        'galleryImagesBase64': galleryImagesBase64,
      };

      // 3. Process Payment/Create
      if (!selectedPlan.requiresPayment) {
        _showSuccessMessage(
          isEn ? 'Creating free profile...' : 'Création du profil gratuit...',
        );

        final result = await StripeNativePaymentService.processNativePayment(
          planId: selectedPlan.id,
          professionalId: _registrationSessionId,
          email: _emailController.text,
          businessName: _businessNameController.text,
          categoryId: selectedCategory.id,
          ville: _cityController.text,
          phone: _phoneController.text,
          registrationData: registrationData,
          serverQuote: selectedPlan,
        );

        if (result.success && result.paymentIntentId != null) {
          final confirm =
              result.confirmation ??
              await StripeNativePaymentService.confirmPaymentOnServerTyped(
                paymentIntentId: result.paymentIntentId!,
                checkoutId: result.checkoutId,
              );

          if (confirm.success) {
            final realId = confirm.professionalId ?? _registrationSessionId;
            if (!mounted) return;
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (_) => PaymentSuccessPage(
                  professionalId: realId,
                  businessName: _businessNameController.text,
                  planType: selectedPlan.id,
                  amountPaid: selectedPlan.amount,
                  currency: selectedPlan.currency.toUpperCase(),
                  paymentId: result.checkoutId ?? result.paymentIntentId!,
                  professionalEmail: _emailController.text,
                  categoryId: selectedCategory.id,
                  categoryName: selectedCategory.title,
                  categoryNameEn: selectedCategory.titleEn,
                  confirmation: confirm,
                ),
              ),
            );
          } else {
            if (!mounted) return;
            _showErrorMessage(
              confirm.message ??
                  (isEn
                      ? 'The registration could not be confirmed. Please retry.'
                      : 'L’inscription n’a pas pu être confirmée. Veuillez réessayer.'),
            );
          }
        } else {
          if (!mounted) return;
          _showErrorMessage(
            result.error ??
                (isEn
                    ? 'The registration could not be submitted. Please retry.'
                    : 'L’inscription n’a pas pu être envoyée. Veuillez réessayer.'),
          );
        }
      } else {
        // Paid Plan
        if (!mounted) return;
        await Navigator.push<void>(
          context,
          MaterialPageRoute(
            builder: (_) => NativePaymentPage(
              businessName: _businessNameController.text,
              email: _emailController.text,
              selectedPlan: selectedPlan.id,
              serverQuote: selectedPlan,
              professionalId: _registrationSessionId,
              categoryId: selectedCategory.id,
              categoryName: selectedCategory.title,
              categoryNameEn: selectedCategory.titleEn,
              registrationData: registrationData,
            ),
          ),
        );
      }
    } on Exception {
      if (mounted) {
        _showErrorMessage(
          isEn
              ? 'We could not submit your registration. Please try again.'
              : 'L’inscription n’a pas pu être envoyée. Veuillez réessayer.',
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  // --- UI Building Blocks ---

  Widget _buildStep1Identity(bool isEn) {
    final selectedCategoryValue = _selectedCategory?.id;
    return Form(
      key: _step1Key,
      child: Column(
        children: [
          TextFormField(
            controller: _businessNameController,
            decoration: InputDecoration(
              labelText: isEn
                  ? 'Professional/Business Name *'
                  : 'Nom du professionnel/entreprise *',
              border: const OutlineInputBorder(),
              prefixIcon: const Icon(Icons.business),
            ),
            validator: (v) => (v == null || v.trim().length < 2)
                ? (isEn ? 'Min 2 chars' : 'Min 2 caractères')
                : null,
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            key: ValueKey(selectedCategoryValue),
            initialValue: selectedCategoryValue,
            isExpanded: true,
            decoration: InputDecoration(
              labelText: isEn ? 'Category *' : 'Catégorie *',
              border: const OutlineInputBorder(),
              prefixIcon: const Icon(Icons.category),
            ),
            items: _getSortedCategories()
                .map(
                  (c) => DropdownMenuItem(
                    value: c.id,
                    child: Text(
                      isEn ? c.titleEn : c.title,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                )
                .toList(),
            onChanged: _isLoadingCategories || _categoriesUnavailable
                ? null
                : (value) => setState(() => _selectedCategoryId = value ?? ''),
            validator: (v) => (v == null || v.trim().isEmpty)
                ? (isEn ? 'Required' : 'Requis')
                : null,
          ),
          if (_isLoadingCategories) ...[
            const SizedBox(height: 8),
            const LinearProgressIndicator(),
          ] else if (_categoriesUnavailable) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text(
                    isEn
                        ? 'Categories are temporarily unavailable.'
                        : 'Les catégories sont temporairement indisponibles.',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: _loadAllCategories,
                  child: Text(isEn ? 'Retry' : 'Réessayer'),
                ),
              ],
            ),
          ],
          const SizedBox(height: 16),
          TextFormField(
            controller: _descriptionController,
            maxLines: 3,
            decoration: InputDecoration(
              labelText: isEn ? 'Short Description' : 'Brève description',
              hintText: isEn ? 'What do you offer?' : 'Que proposez-vous ?',
              border: const OutlineInputBorder(),
              prefixIcon: const Icon(Icons.description),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStep2Location(bool isEn) {
    return Form(
      key: _step2Key,
      child: Column(
        children: [
          TextFormField(
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            decoration: InputDecoration(
              labelText: 'Email *',
              border: const OutlineInputBorder(),
              prefixIcon: const Icon(Icons.email),
            ),
            validator: (value) => _validateEmail(value, isEn),
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _phoneController,
            keyboardType: TextInputType.phone,
            decoration: InputDecoration(
              labelText: isEn ? 'Phone *' : 'Téléphone *',
              border: const OutlineInputBorder(),
              prefixIcon: const Icon(Icons.phone),
            ),
            validator: (value) => _validatePhone(value, isEn),
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _addressController,
            decoration: InputDecoration(
              labelText: isEn ? 'Address *' : 'Adresse *',
              border: const OutlineInputBorder(),
              prefixIcon: const Icon(Icons.location_on),
            ),
            validator: (v) => (v == null || v.trim().isEmpty)
                ? (isEn ? 'Required' : 'Requis')
                : null,
          ),
          const SizedBox(height: 16),
          // Autocomplete Ville
          RawAutocomplete<String>(
            textEditingController: _cityController,
            focusNode: _cityFocusNode,
            optionsBuilder: (TextEditingValue textEditingValue) {
              if (textEditingValue.text.isEmpty) {
                return const Iterable<String>.empty();
              }
              return kCanadianCities.where((String option) {
                final normalizedOption = _removeDiacritics(
                  option.toLowerCase(),
                );
                final normalizedInput = _removeDiacritics(
                  textEditingValue.text.toLowerCase(),
                );
                return normalizedOption.contains(normalizedInput);
              });
            },
            fieldViewBuilder:
                (context, controller, focusNode, onFieldSubmitted) {
                  return TextFormField(
                    controller: controller,
                    focusNode: focusNode,
                    decoration: InputDecoration(
                      labelText: isEn ? 'City *' : 'Ville *',
                      border: const OutlineInputBorder(),
                      prefixIcon: const Icon(Icons.location_city),
                      suffixIcon: const Icon(Icons.arrow_drop_down),
                    ),
                    validator: (v) => (v == null || v.trim().isEmpty)
                        ? (isEn ? 'Required' : 'Requis')
                        : null,
                  );
                },
            optionsViewBuilder: (context, onSelected, options) {
              return Align(
                alignment: Alignment.topLeft,
                child: Material(
                  elevation: 4,
                  child: Container(
                    width:
                        MediaQuery.of(context).size.width -
                        64, // Ajustement largeur
                    constraints: const BoxConstraints(maxHeight: 200),
                    color: Colors.white,
                    child: ListView.builder(
                      padding: EdgeInsets.zero,
                      itemCount: options.length,
                      itemBuilder: (ctx, index) {
                        final option = options.elementAt(index);
                        return ListTile(
                          title: Text(option),
                          onTap: () => onSelected(option),
                        );
                      },
                    ),
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _websiteController,
            decoration: InputDecoration(
              labelText: isEn ? 'Website (optional)' : 'Site Web (optionnel)',
              border: const OutlineInputBorder(),
              prefixIcon: const Icon(Icons.language),
            ),
            keyboardType: TextInputType.url,
            validator: (value) => _validateWebsite(value, isEn),
          ),
        ],
      ),
    );
  }

  Widget _buildStep3Media(bool isEn) {
    final selectedPlan = _selectedPlan;
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final supportsProfileImage =
        selectedPlan?.capabilities.profileImage == true;
    final galleryMax = selectedPlan?.capabilities.galleryMax ?? 0;
    return Form(
      key: _step3Key,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Profile Pic
          Text(
            isEn ? 'Profile Picture' : 'Photo de profil',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          const SizedBox(height: 8),
          Center(
            child: Semantics(
              button: true,
              enabled: supportsProfileImage,
              label: _localizationService.tr(
                _profileImage == null
                    ? 'choose_profile_photo'
                    : 'change_profile_photo',
              ),
              excludeSemantics: true,
              child: Tooltip(
                message: _localizationService.tr(
                  _profileImage == null
                      ? 'choose_profile_photo'
                      : 'change_profile_photo',
                ),
                child: Material(
                  color: Colors.transparent,
                  shape: const CircleBorder(),
                  child: InkWell(
                    onTap: supportsProfileImage ? _pickProfileImage : null,
                    customBorder: const CircleBorder(),
                    child: CircleAvatar(
                      radius: 50,
                      backgroundColor: Colors.grey.shade200,
                      backgroundImage: _profileImage != null
                          ? MemoryImage(_profileImage!)
                          : null,
                      child: _profileImage == null
                          ? const Icon(
                              Icons.add_a_photo,
                              size: 40,
                              color: Colors.grey,
                            )
                          : null,
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (!supportsProfileImage)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                isEn
                    ? 'Profile images are not included with the selected plan.'
                    : 'La photo de profil n’est pas incluse avec le forfait sélectionné.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey[600]),
              ),
            ),
          const SizedBox(height: 24),

          // Socials
          Text(
            isEn ? 'Social Networks' : 'Réseaux Sociaux',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          const SizedBox(height: 8),
          _socialField(_facebookController, 'Facebook', Icons.facebook),
          const SizedBox(height: 8),
          _socialField(_instagramController, 'Instagram', Icons.camera_alt),
          const SizedBox(height: 8),
          _socialField(_tiktokController, 'TikTok', Icons.music_note),
          const SizedBox(height: 8),
          _socialField(_youtubeController, 'YouTube', Icons.play_circle),
          const SizedBox(height: 8),
          _socialField(_whatsappController, 'WhatsApp', Icons.phone),

          const SizedBox(height: 24),

          // Gallery
          Row(
            children: [
              Icon(Icons.collections_outlined, color: colors.primary, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  isEn ? 'Photo gallery' : 'Galerie photo',
                  style: theme.textTheme.titleMedium,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            galleryMax > 0
                ? (isEn
                      ? 'The selected plan includes up to $galleryMax images.'
                      : 'Le forfait sélectionné inclut jusqu’à $galleryMax images.')
                : (isEn
                      ? 'Select a plan that includes a gallery, then return to this step.'
                      : 'Choisissez un forfait incluant une galerie, puis revenez à cette étape.'),
            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
          ),
          const SizedBox(height: 8),
          if (_galleryImages.isNotEmpty)
            SizedBox(
              height: 80,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _galleryImages.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (ctx, i) => Stack(
                  children: [
                    Image.memory(
                      _galleryImages[i],
                      width: 80,
                      height: 80,
                      fit: BoxFit.cover,
                    ),
                    Positioned(
                      right: 0,
                      top: 0,
                      child: IconButton(
                        onPressed: () =>
                            setState(() => _galleryImages.removeAt(i)),
                        tooltip: _localizationService.tr(
                          'remove_gallery_image',
                          ['${i + 1}'],
                        ),
                        icon: const Icon(
                          Icons.close,
                          color: Colors.white,
                          size: 20,
                        ),
                        style: IconButton.styleFrom(
                          backgroundColor: Colors.black54,
                          minimumSize: const Size.square(48),
                          tapTargetSize: MaterialTapTargetSize.padded,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 8),
          if (galleryMax > 0 && _galleryImages.length < galleryMax)
            OutlinedButton.icon(
              onPressed: _pickGalleryImages,
              icon: const Icon(Icons.add_photo_alternate),
              label: Text(isEn ? 'Add Gallery Image' : 'Ajouter une image'),
            ),
        ],
      ),
    );
  }

  Widget _socialField(
    TextEditingController controller,
    String label,
    IconData icon,
  ) {
    final colors = Theme.of(context).colorScheme;
    return TextFormField(
      controller: controller,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: colors.onSurfaceVariant),
      ),
    );
  }

  void _selectPaymentPlan(PaymentPlanQuote plan) {
    if (!_isPlanSupported(plan)) {
      _showErrorMessage(
        _localizationService.tr('paid_payment_web_unavailable'),
      );
      return;
    }
    setState(() => _selectedPlanId = plan.id);
  }

  Widget _buildPlanCard(PaymentPlanQuote plan, bool isEn) {
    final isAvailable = _isPlanSupported(plan);
    final isSelected = isAvailable && _selectedPlanId == plan.id;
    final features = isEn ? plan.featuresEn : plan.featuresFr;
    final theme = Theme.of(context);
    final planName = isEn ? plan.labelEn : plan.labelFr;
    final price = _formatPlanPrice(plan, isEn);
    final unavailableMessage = _localizationService.tr('paid_plan_mobile_only');
    return Semantics(
      container: true,
      button: true,
      enabled: isAvailable,
      selected: isSelected,
      label: isAvailable
          ? '$planName, $price'
          : '$planName, $price. $unavailableMessage',
      child: Card(
        color: !isAvailable
            ? theme.colorScheme.surfaceContainerHighest
            : isSelected
            ? theme.colorScheme.primaryContainer.withValues(alpha: 0.32)
            : theme.colorScheme.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.card),
          side: BorderSide(
            color: isSelected
                ? theme.colorScheme.primary
                : theme.colorScheme.outlineVariant,
            width: isSelected ? 2 : 1,
          ),
        ),
        margin: const EdgeInsets.only(bottom: AppSpacing.md),
        child: InkWell(
          onTap: isAvailable ? () => _selectPaymentPlan(plan) : null,
          borderRadius: BorderRadius.circular(AppRadii.card),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  isSelected
                      ? Icons.radio_button_checked
                      : isAvailable
                      ? Icons.radio_button_unchecked
                      : Icons.block,
                  color: isSelected
                      ? theme.colorScheme.primary
                      : isAvailable
                      ? theme.colorScheme.onSurfaceVariant
                      : theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              planName,
                              style: theme.textTheme.titleMedium?.copyWith(
                                color: isAvailable
                                    ? theme.colorScheme.onSurface
                                    : theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                          if (isSelected) ...[
                            const SizedBox(width: AppSpacing.xs),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: AppSpacing.sm,
                                vertical: AppSpacing.xxs,
                              ),
                              decoration: BoxDecoration(
                                color: theme.colorScheme.primary,
                                borderRadius: BorderRadius.circular(
                                  AppRadii.pill,
                                ),
                              ),
                              child: Text(
                                isEn ? 'Selected' : 'Sélectionné',
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: theme.colorScheme.onPrimary,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        price,
                        key: ValueKey('plan-price-${plan.id}'),
                        style: theme.textTheme.titleLarge?.copyWith(
                          color: isAvailable
                              ? theme.colorScheme.primary
                              : theme.colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      ...features.map(
                        (feature) => Padding(
                          padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                Icons.check_circle_outline,
                                size: 18,
                                color: isAvailable
                                    ? theme.colorScheme.tertiary
                                    : theme.colorScheme.onSurfaceVariant,
                              ),
                              const SizedBox(width: AppSpacing.xs),
                              Expanded(
                                child: Text(
                                  feature,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (!isAvailable) ...[
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Icon(
                              Icons.phone_iphone_outlined,
                              size: 16,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                unavailableMessage,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPublicationReviewNotice(bool isEn) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Semantics(
      container: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.tertiaryContainer,
          borderRadius: BorderRadius.circular(AppRadii.control),
        ),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.verified_user_outlined,
                color: colors.onTertiaryContainer,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isEn
                          ? 'Reviewed before publication'
                          : 'Validation avant publication',
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: colors.onTertiaryContainer,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xxs),
                    Text(
                      isEn
                          ? 'After submission, the Index Canada team reviews your profile before it becomes visible. Payment does not result in immediate publication.'
                          : 'Après l’envoi, l’équipe Index Canada vérifie votre fiche avant sa mise en ligne. Le paiement n’entraîne pas une publication immédiate.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.onTertiaryContainer,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildWebPaymentAvailabilityNotice() {
    final theme = Theme.of(context);
    return Semantics(
      container: true,
      liveRegion: true,
      child: Card(
        color: theme.colorScheme.secondaryContainer,
        margin: const EdgeInsets.only(bottom: 12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.info_outline,
                color: theme.colorScheme.onSecondaryContainer,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  _localizationService.tr('paid_payment_web_unavailable'),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSecondaryContainer,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStep4Plan(bool isEn) {
    final theme = Theme.of(context);
    final hasUnsupportedPlans = _paymentPlans.any(
      (plan) => !_isPlanSupported(plan),
    );
    return Form(
      key: _step4Key,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            isEn
                ? 'Choose your annual plan'
                : 'Choisissez votre forfait annuel',
            style: theme.textTheme.titleLarge,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            isEn
                ? 'Compare every option and its full annual price before completing your profile.'
                : 'Comparez toutes les options et leur prix annuel complet avant de remplir votre fiche.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          _buildPublicationReviewNotice(isEn),
          const SizedBox(height: AppSpacing.lg),
          if (_isLoadingPlans)
            const Center(child: CircularProgressIndicator())
          else if (_plansUnavailable || _paymentPlans.isEmpty)
            Card(
              color: Theme.of(context).colorScheme.errorContainer,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Text(
                      isEn
                          ? 'Plans are temporarily unavailable. Registration remains disabled until the current options can be verified.'
                          : 'Les forfaits sont temporairement indisponibles. L’inscription reste désactivée jusqu’à la vérification des options actuelles.',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onErrorContainer,
                      ),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: _loadPaymentPlans,
                      icon: const Icon(Icons.refresh),
                      label: Text(isEn ? 'Retry' : 'Réessayer'),
                    ),
                  ],
                ),
              ),
            )
          else ...[
            if (hasUnsupportedPlans) _buildWebPaymentAvailabilityNotice(),
            for (final plan in _paymentPlans) _buildPlanCard(plan, isEn),
          ],

          const Divider(height: 40),

          if (_selectedPlan?.capabilities.coupon == true)
            ExpansionTile(
              title: Text(
                isEn
                    ? 'Add a Coupon (Optional)'
                    : 'Ajouter un coupon (Optionnel)',
              ),
              leading: Icon(
                Icons.local_offer_outlined,
                color: theme.colorScheme.primary,
              ),
              children: [
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Column(
                    children: [
                      TextFormField(
                        controller: _couponTitleController,
                        decoration: InputDecoration(
                          labelText: isEn ? 'Coupon Title' : 'Titre du coupon',
                          border: const OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _couponCodeController,
                        decoration: InputDecoration(
                          labelText: isEn ? 'Code' : 'Code',
                          border: const OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _couponDescriptionController,
                        maxLines: 3,
                        decoration: InputDecoration(
                          labelText: isEn ? 'Description' : 'Description',
                          border: const OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 8),
                      ListTile(
                        title: Text(
                          _couponExpirationDate == null
                              ? (isEn
                                    ? 'Pick Expiration Date'
                                    : 'Choisir date d\'expiration')
                              : '${_couponExpirationDate!.year}-${_couponExpirationDate!.month}-${_couponExpirationDate!.day}',
                        ),
                        trailing: const Icon(Icons.calendar_today),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                          side: const BorderSide(color: Colors.grey),
                        ),
                        onTap: () async {
                          final date = await showDatePicker(
                            context: context,
                            initialDate: DateTime.now().add(
                              const Duration(days: 30),
                            ),
                            firstDate: DateTime.now(),
                            lastDate: DateTime.now().add(
                              const Duration(days: 365 * 2),
                            ),
                          );
                          if (!mounted) return;
                          if (date != null) {
                            setState(() => _couponExpirationDate = date);
                          }
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isEn = _localizationService.currentLanguage == 'en';
    final stepperType = MediaQuery.sizeOf(context).width < 600
        ? StepperType.vertical
        : StepperType.horizontal;

    // Le choix tarifaire précède volontairement la saisie détaillée.
    final steps = [
      Step(
        title: Text(isEn ? 'Plan' : 'Forfait'),
        content: _buildStep4Plan(isEn),
        isActive: _currentStep >= 0,
        state: _currentStep > 0 ? StepState.complete : StepState.editing,
      ),
      Step(
        title: Text(isEn ? 'Identity' : 'Identité'),
        content: _buildStep1Identity(isEn),
        isActive: _currentStep >= 1,
        state: _currentStep > 1 ? StepState.complete : StepState.editing,
      ),
      Step(
        title: Text(isEn ? 'Location' : 'Lieu'),
        content: _buildStep2Location(isEn),
        isActive: _currentStep >= 2,
        state: _currentStep > 2 ? StepState.complete : StepState.editing,
      ),
      Step(
        title: Text(isEn ? 'Media' : 'Médias'),
        content: _buildStep3Media(isEn),
        isActive: _currentStep >= 3,
        state: _currentStep == 3 ? StepState.complete : StepState.editing,
      ),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(
          isEn
              ? 'Create your professional profile'
              : 'Créer votre profil professionnel',
        ),
        actions: [LanguageSelector(onLanguageChanged: (_) => setState(() {}))],
      ),
      body: _isSubmitting
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 20),
                  Text(
                    isEn
                        ? 'Processing registration...'
                        : 'Traitement de l\'inscription...',
                  ),
                ],
              ),
            )
          : Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1120),
                child: SizedBox.expand(
                  child: Stepper(
                    type: stepperType,
                    currentStep: _currentStep,
                    onStepTapped: (index) {
                      // Only allow tapping on previous steps or the immediate next if validated
                      if (index < _currentStep) {
                        setState(() => _currentStep = index);
                      }
                    },
                    onStepContinue: () {
                      // Validate current step
                      bool isValid = false;
                      switch (_currentStep) {
                        case 0: // Plan
                          final selectedPlan = _selectedPlan;
                          isValid =
                              !_isLoadingPlans &&
                              !_plansUnavailable &&
                              selectedPlan != null &&
                              _isPlanSupported(selectedPlan);
                          break;
                        case 1: // Identity
                          isValid = _step1Key.currentState?.validate() ?? false;
                          if (_selectedCategory == null) isValid = false;
                          break;
                        case 2: // Location
                          isValid = _step2Key.currentState?.validate() ?? false;
                          break;
                        case 3: // Media
                          isValid = true; // Optional mostly
                          break;
                      }

                      if (isValid) {
                        if (_currentStep < steps.length - 1) {
                          setState(() => _currentStep += 1);
                        } else {
                          // Final submit
                          _submitForm();
                        }
                      } else {
                        _showErrorMessage(
                          isEn
                              ? 'Please correct invalid fields'
                              : 'Veuillez corriger les erreurs',
                        );
                      }
                    },
                    onStepCancel: () {
                      if (_currentStep > 0) {
                        setState(() => _currentStep -= 1);
                      } else {
                        Navigator.pop(context);
                      }
                    },
                    controlsBuilder: (context, details) {
                      final isLast = _currentStep == steps.length - 1;
                      final selectedPlan = _selectedPlan;
                      final canSubmit =
                          !isLast ||
                          (!_isLoadingPlans &&
                              !_plansUnavailable &&
                              selectedPlan != null &&
                              _isPlanSupported(selectedPlan));
                      return Padding(
                        padding: const EdgeInsets.only(top: AppSpacing.lg),
                        child: Row(
                          children: [
                            if (_currentStep > 0) ...[
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: details.onStepCancel,
                                  child: Text(isEn ? 'Back' : 'Retour'),
                                ),
                              ),
                              const SizedBox(width: AppSpacing.sm),
                            ],
                            Expanded(
                              child: FilledButton(
                                onPressed: canSubmit
                                    ? details.onStepContinue
                                    : null,
                                child: Text(
                                  isLast
                                      ? (selectedPlan?.requiresPayment == true
                                            ? (isEn
                                                  ? 'Submit and pay'
                                                  : 'Envoyer et payer')
                                            : (isEn ? 'Submit' : 'Envoyer'))
                                      : (isEn ? 'Continue' : 'Continuer'),
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                    steps: steps,
                  ),
                ),
              ),
            ),
    );
  }
}
