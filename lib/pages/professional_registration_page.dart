// ignore_for_file: use_build_context_synchronously, deprecated_member_use

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:io';
import 'dart:convert';
import 'dart:async';
import 'package:image_picker/image_picker.dart';
import '../data_service.dart';
import '../models.dart';
import '../services/localization_service.dart';
import '../services/stripe_native_payment_service.dart';
import '../widgets/language_selector.dart';
import 'payment_plan_page.dart';
import 'payment_success_page.dart';
import '../data/canadian_cities.dart'; 

class ProfessionalRegistrationPage extends StatefulWidget {
  final String? categoryId;
  final String? categoryName;
  final String? categoryNameEn;

  const ProfessionalRegistrationPage({
    super.key,
    this.categoryId,
    this.categoryName,
    this.categoryNameEn,
  });

  @override
  State<ProfessionalRegistrationPage> createState() => _ProfessionalRegistrationPageState();
}

class _ProfessionalRegistrationPageState extends State<ProfessionalRegistrationPage> with WidgetsBindingObserver {
  final LocalizationService _localizationService = LocalizationService();

  // Clés de formulaire pour chaque étape
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
  String _selectedPlan = 'basic';
  bool _isSubmitting = false;
  
  // Images
  File? _profileImage;
  final List<File> _galleryImages = [];

  // Date d'expiration du coupon
  DateTime? _couponExpirationDate;

  // Catégories
  List<SousCategorie> _sousCategories = [];
  String _selectedCategoryId = '';

  // Options de tarification
  final Map<String, Map<String, dynamic>> _pricingPlans = {
    'basic': {
      'price': 'Gratuit',
      'features': [
        'Fiche professionnel de base',
        'Informations de contact',
        'Photo de profil',
        'Visible dans les recherches',
        'Réseaux sociaux',
        'Coupons de réduction',
      ],
    },
    'premium': {
      'price': '49,99 CAD',
      'features': [
        'Tout du plan de base',
        'Galerie de photos (jusqu\'à 5 images)',
        'Résumé d\'activité mis en avant',
        'Support prioritaire',
        'Réseaux sociaux améliorés',
        'Coupons de réduction exclusifs',
      ],
    },
    'professional': {
      'price': '119,99 CAD',
      'features': [
        'Tout du plan premium',
        'Mise en avant sur la page d\'accueil',
        'Priorité dans les résultats',
        'Support technique dédié',
        'Personnalisation avancée',
        'Intégration API',
      ],
    },
  };

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (widget.categoryId != null) {
      _selectedCategoryId = widget.categoryId!;
    }
    _loadAllCategories();
  }

  void _loadAllCategories() async {
    try {
      final DataService dataService = DataService();
      final categories = await dataService.fetchSousCategories();
      if (mounted) {
        setState(() => _sousCategories = categories);
      }
    } catch (e) {
      if (mounted) {
         setState(() {
          _sousCategories = [
            SousCategorie(id: 'default-1', title: 'Consultants', titleEn: 'Consultants', image: ''),
             // ... autres cas par défaut si nécessaire
          ];
        });
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
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

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      print('✅ App resumed - Page d\'inscription');
    }
  }

  // --- Helpers ---

  // ignore: unused_element
  String _removeDiacritics(String str) {
    var withDia = 'ÀÁÂÃÄÅàáâãäåÒÓÔÕÕÖØòóôõöøÈÉÊËèéêëðÇçÐÌÍÎÏìíîïÙÚÛÜùúûüÑñŠšŸÿýŽž';
    var withoutDia = 'AAAAAAaaaaaaOOOOOOOooooooEEEEeeeeeCcDIIIIiiiiUUUUuuuuNnSsYyyZz';
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
      final titleA = _localizationService.currentLanguage == 'en' ? a.titleEn : a.title;
      final titleB = _localizationService.currentLanguage == 'en' ? b.titleEn : b.title;
      return _normalizeForSorting(titleA).compareTo(_normalizeForSorting(titleB));
    });
    return categories;
  }

  void _showSuccessMessage(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(message),
        backgroundColor: Colors.green,
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  void _showErrorMessage(String message, {String? title}) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: title != null 
          ? Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.bold)), 
                Text(message)
              ]) 
          : Text(message),
        backgroundColor: Colors.red.shade700,
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  // --- Image Logic ---
  Future<void> _pickImageFromCamera() async {
    try {
      final ImagePicker picker = ImagePicker();
      final XFile? image = await picker.pickImage(
        source: ImageSource.camera,
        maxWidth: 600,
        maxHeight: 600,
        imageQuality: 50,
      );
      if (image != null && mounted) {
        final File imageFile = File(image.path);
        final int fileSize = await imageFile.length();
        if (fileSize > 5 * 1024 * 1024) {
          _showErrorMessage('Image too large (>5MB)');
          return;
        }
        setState(() {
          _profileImage = imageFile;
        });
      }
    } catch (e) {
      print('Camera error: $e');
    }
  }

  Future<void> _pickImageFromGallery() async {
    try {
      final ImagePicker picker = ImagePicker();
      final XFile? image = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 600,
        maxHeight: 600,
        imageQuality: 50,
      );
      if (image != null && mounted) {
        final File imageFile = File(image.path);
        // Check size
        if (await imageFile.length() > 5 * 1024 * 1024) {
          _showErrorMessage('Image too large (>5MB)');
          return;
        }
        setState(() {
          _profileImage = imageFile;
        });
      }
    } catch (e) {
      print('Gallery error: $e');
    }
  }

  Future<void> _pickProfileImage() async => _showImageSourceChoice(false);

  Future<void> _pickGalleryImages() async {
     if (_galleryImages.length >= 5) {
       _showErrorMessage(_localizationService.currentLanguage == 'fr' 
         ? 'Maximum 5 images' : 'Maximum 5 images');
       return;
     }
     _showImageSourceChoice(true);
  }

  void _showImageSourceChoice(bool isGallery) {
    final isEn = _localizationService.currentLanguage == 'en';
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt, color: Colors.blue),
              title: Text(isEn ? 'Camera' : 'Appareil photo'),
              onTap: () { Navigator.pop(context); _processImage(ImageSource.camera, isGallery); },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library, color: Colors.green),
              title: Text(isEn ? 'Gallery' : 'Galerie'),
              onTap: () { Navigator.pop(context); _processImage(ImageSource.gallery, isGallery); },
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
        source: source, maxWidth: 600, maxHeight: 600, imageQuality: 50
      );
      
      if (image != null && mounted) {
        final file = File(image.path);
        if (await file.length() > 5 * 1024 * 1024) {
          _showErrorMessage('Image too large (>5MB)');
          return;
        }
        setState(() {
          if (isGallery) {
            _galleryImages.add(file);
          } else {
            _profileImage = file;
          }
        });
      }
    } catch (e) {
      print('Image error: $e');
      _showErrorMessage('Error selecting image');
    }
  }

  // --- Form Logic ---

  Future<void> _submitForm() async {
    // Validation finale au cas où
    if (_businessNameController.text.isEmpty || _selectedCategoryId.isEmpty) {
      setState(() => _currentStep = 0);
      _showErrorMessage(_localizationService.currentLanguage == 'en' ? 'Missing info' : 'Infos manquantes');
      return;
    }

    setState(() => _isSubmitting = true);
    final isEn = _localizationService.currentLanguage == 'en';

    try {
      // 1. Prepare Images
      String? profileImageBase64;
      List<String>? galleryImagesBase64;
      if (_profileImage != null) {
        final bytes = await _profileImage!.readAsBytes();
        profileImageBase64 = base64Encode(bytes);
      }

      // N'envoyer les images de galerie que si le plan n'est pas basic
      if (_galleryImages.isNotEmpty && _selectedPlan != 'basic') {
        galleryImagesBase64 = [];
        for (var file in _galleryImages) {
          final bytes = await file.readAsBytes();
          galleryImagesBase64.add(base64Encode(bytes));
        }
      }

      // 2. Prepare Data
      final tempId = 'temp_${DateTime.now().millisecondsSinceEpoch}';
      
      final selectedCategory = _sousCategories.firstWhere(
        (c) => c.id == _selectedCategoryId,
        orElse: () => SousCategorie(id: '', title: '', titleEn: '', image: ''),
      );

      final registrationData = {
        'businessName': _businessNameController.text.trim(),
        'category': _selectedCategoryId,
        'email': _emailController.text.trim(),
        'phone': _phoneController.text.trim(),
        'address': _addressController.text.trim(),
        'city': _cityController.text.trim(),
        'description': _descriptionController.text.trim(),
        'selectedPlan': _selectedPlan,
        'planPrice': _pricingPlans[_selectedPlan]!['price'],
        'website': _websiteController.text.isNotEmpty ? _websiteController.text.trim() : null,
        'businessSummary': _descriptionController.text, // Mapped to businessSummary
        'facebook': _facebookController.text.isNotEmpty ? _facebookController.text.trim() : null,
        'instagram': _instagramController.text.isNotEmpty ? _instagramController.text.trim() : null,
        'tiktok': _tiktokController.text.isNotEmpty ? _tiktokController.text.trim() : null,
        'youtube': _youtubeController.text.isNotEmpty ? _youtubeController.text.trim() : null,
        'whatsapp': _whatsappController.text.isNotEmpty ? _whatsappController.text.trim() : null,
        'couponTitle': _couponTitleController.text.isNotEmpty ? _couponTitleController.text.trim() : null,
        'couponCode': _couponCodeController.text.isNotEmpty ? _couponCodeController.text.trim() : null,
        'couponDescription': _couponDescriptionController.text.isNotEmpty ? _couponDescriptionController.text.trim() : null,
        'couponExpirationDate': _couponExpirationDate?.toIso8601String(),
        'hasProfileImage': _profileImage != null,
        'galleryImagesCount': galleryImagesBase64?.length ?? 0,
        'profileImageBase64': profileImageBase64,
        'galleryImagesBase64': galleryImagesBase64,
      };

      // 3. Process Payment/Create
      if (_selectedPlan == 'basic') {
        _showSuccessMessage(isEn ? 'Creating free profile...' : 'Création du profil gratuit...');
        
        final result = await StripeNativePaymentService.processNativePayment(
          context: context,
          planId: 'basic',
          professionalId: tempId,
          email: _emailController.text,
          businessName: _businessNameController.text,
          categoryId: selectedCategory.id,
          ville: _cityController.text,
          phone: _phoneController.text,
          registrationData: registrationData,
        );

        if (result.success && result.paymentIntentId != null) {
          final confirm = await StripeNativePaymentService.confirmPaymentOnServer(
            paymentIntentId: result.paymentIntentId!,
            professionalId: tempId,
            planId: 'basic',
            businessName: _businessNameController.text,
            email: _emailController.text,
            categoryId: selectedCategory.id,
            ville: _cityController.text,
            phone: _phoneController.text,
            registrationData: registrationData,
          );

          if (confirm != null && confirm['success'] == true) {
            final realId = (confirm['data'] as Map<String, dynamic>)['professionalId'] ?? tempId;
            Navigator.pushReplacement(context, MaterialPageRoute(
              builder: (_) => PaymentSuccessPage(
                professionalId: realId,
                businessName: _businessNameController.text,
                planType: 'basic',
                amountPaid: 0.0,
                paymentId: result.paymentIntentId!,
                professionalEmail: _emailController.text,
                categoryId: selectedCategory.id,
                categoryName: selectedCategory.title,
                categoryNameEn: selectedCategory.titleEn,
              ),
            ));
          } else {
            throw Exception('Confirmation failed');
          }
        } else {
           throw Exception('Process failed');
        }
      } else {
        // Paid Plan
        Navigator.push(context, MaterialPageRoute(
          builder: (_) => PaymentPlanPage(
            businessName: _businessNameController.text,
            email: _emailController.text,
            selectedPlan: _selectedPlan,
            professionalId: tempId,
            categoryId: selectedCategory.id,
            categoryName: selectedCategory.title,
            categoryNameEn: selectedCategory.titleEn,
            registrationData: registrationData,
          ),
        ));
      }

    } catch (e) {
      _showErrorMessage(isEn ? 'Error: $e' : 'Erreur: $e');
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  // --- UI Building Blocks ---

  Widget _buildStep1Identity(bool isEn) {
    return Form(
      key: _step1Key,
      child: Column(
        children: [
          TextFormField(
            controller: _businessNameController,
            decoration: InputDecoration(
              labelText: isEn ? 'Professional/Business Name *' : 'Nom du professionnel/entreprise *',
              border: const OutlineInputBorder(),
              prefixIcon: const Icon(Icons.business),
            ),
            validator: (v) => (v == null || v.length < 2) 
              ? (isEn ? 'Min 2 chars' : 'Min 2 caractères') : null,
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            value: _selectedCategoryId.isEmpty ? null : _selectedCategoryId,
            isExpanded: true,
            decoration: InputDecoration(
              labelText: isEn ? 'Category *' : 'Catégorie *',
              border: const OutlineInputBorder(),
              prefixIcon: const Icon(Icons.category),
            ),
            items: _getSortedCategories().map((c) => DropdownMenuItem(
              value: c.id,
              child: Text(isEn ? c.titleEn : c.title, overflow: TextOverflow.ellipsis),
            )).toList(),
            onChanged: (v) => setState(() => _selectedCategoryId = v ?? ''),
            validator: (v) => (v == null || v.isEmpty) ? (isEn ? 'Required' : 'Requis') : null,
          ),
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
            validator: (v) => (v == null || !v.contains('@')) ? (isEn ? 'Invalid email' : 'Email invalide') : null,
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
            validator: (v) => (v == null || v.length < 8) ? (isEn ? 'Invalid phone' : 'Téléphone invalide') : null,
          ),
          const SizedBox(height: 16),
          TextFormField(
             controller: _addressController,
             decoration: InputDecoration(
               labelText: isEn ? 'Address *' : 'Adresse *',
               border: const OutlineInputBorder(),
               prefixIcon: const Icon(Icons.location_on),
             ),
             validator: (v) => (v == null || v.isEmpty) ? (isEn ? 'Required' : 'Requis') : null,
          ),
          const SizedBox(height: 16),
          // Autocomplete Ville
          RawAutocomplete<String>(
            textEditingController: _cityController,
            focusNode: _cityFocusNode,
            optionsBuilder: (TextEditingValue textEditingValue) {
              if (textEditingValue.text.isEmpty) return const Iterable<String>.empty();
              return kCanadianCities.where((String option) {
                final normalizedOption = _removeDiacritics(option.toLowerCase());
                final normalizedInput = _removeDiacritics(textEditingValue.text.toLowerCase());
                return normalizedOption.contains(normalizedInput);
              });
            },
            fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
              return TextFormField(
                controller: controller,
                focusNode: focusNode,
                decoration: InputDecoration(
                  labelText: isEn ? 'City *' : 'Ville *',
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.location_city),
                  suffixIcon: const Icon(Icons.arrow_drop_down),
                ),
                validator: (v) => (v == null || v.isEmpty) ? (isEn ? 'Required' : 'Requis') : null,
              );
            },
            optionsViewBuilder: (context, onSelected, options) {
              return Align(
                alignment: Alignment.topLeft,
                child: Material(
                  elevation: 4,
                  child: Container(
                    width: MediaQuery.of(context).size.width - 64, // Ajustement largeur
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
          ),
        ],
      ),
    );
  }

  Widget _buildStep3Media(bool isEn) {
    return Form(
      key: _step3Key,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Profile Pic
          Text(isEn ? 'Profile Picture' : 'Photo de profil', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 8),
          Center(
            child: GestureDetector(
              onTap: _pickProfileImage,
              child: CircleAvatar(
                radius: 50,
                backgroundColor: Colors.grey.shade200,
                backgroundImage: _profileImage != null ? FileImage(_profileImage!) : null,
                child: _profileImage == null 
                  ? const Icon(Icons.add_a_photo, size: 40, color: Colors.grey)
                  : null,
              ),
            ),
          ),
          const SizedBox(height: 24),

          // Socials
          Text(isEn ? 'Social Networks' : 'Réseaux Sociaux', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 8),
          _socialField(_facebookController, 'Facebook', Icons.facebook, Colors.blue),
          const SizedBox(height: 8),
          _socialField(_instagramController, 'Instagram', Icons.camera_alt, Colors.purple),
          const SizedBox(height: 8),
          _socialField(_whatsappController, 'WhatsApp', Icons.phone, Colors.green),
          
          const SizedBox(height: 24),
          
          // Gallery
          Row(
            children: [
              Icon(Icons.star, color: Colors.amber, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  isEn ? 'Gallery (Premium Feature)' : 'Galerie (Fonction Premium)', 
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.indigo)
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            isEn ? 'Images will only be visible if you select a Premium plan.' 
                 : 'Les images ne seront visibles que si vous choisissez un plan Premium.',
            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
          ),
          const SizedBox(height: 8),
          if (_galleryImages.isNotEmpty)
             SizedBox(
               height: 80,
               child: ListView.separated(
                 scrollDirection: Axis.horizontal,
                 itemCount: _galleryImages.length,
                 separatorBuilder: (_, __) => const SizedBox(width: 8),
                 itemBuilder: (ctx, i) => Stack(
                   children: [
                     Image.file(_galleryImages[i], width: 80, height: 80, fit: BoxFit.cover),
                     Positioned(right: 0, top: 0, child: GestureDetector(
                       onTap: () => setState(() => _galleryImages.removeAt(i)),
                       child: Container(color: Colors.black54, child: const Icon(Icons.close, color: Colors.white, size: 16)),
                     ))
                   ],
                 ),
               ),
             ),
           const SizedBox(height: 8),
           if (_galleryImages.length < 5)
             OutlinedButton.icon(
               onPressed: _pickGalleryImages,
               icon: const Icon(Icons.add_photo_alternate),
               label: Text(isEn ? 'Add Gallery Image' : 'Ajouter une image'),
             ),
        ],
      ),
    );
  }

  Widget _socialField(TextEditingController controller, String label, IconData icon, Color color) {
    return TextFormField(
      controller: controller,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: color),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
    );
  }

  Widget _buildStep4Plan(bool isEn) {
    return Form(
      key: _step4Key,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(isEn ? 'Select Your Plan' : 'Choisissez votre plan', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
          const SizedBox(height: 16),
          // Plans List
           ...['basic', 'premium', 'professional'].map((planId) {
             final plan = _pricingPlans[planId]!;
             final isSelected = _selectedPlan == planId;
             return Card(
               elevation: isSelected ? 4 : 1,
               shape: RoundedRectangleBorder(
                 borderRadius: BorderRadius.circular(12),
                 side: BorderSide(color: isSelected ? Colors.blue : Colors.transparent, width: 2),
               ),
               margin: const EdgeInsets.only(bottom: 12),
               child: InkWell(
                 onTap: () => setState(() => _selectedPlan = planId),
                 borderRadius: BorderRadius.circular(12),
                 child: Padding(
                   padding: const EdgeInsets.all(16),
                   child: Row(
                     children: [
                       Radio<String>(
                         value: planId, 
                         groupValue: _selectedPlan, 
                         onChanged: (v) => setState(() => _selectedPlan = v!)
                       ),
                       Expanded(
                         child: Column(
                           crossAxisAlignment: CrossAxisAlignment.start,
                           children: [
                             Row(
                               mainAxisAlignment: MainAxisAlignment.spaceBetween,
                               children: [
                                 Text(planId.toUpperCase(), style: const TextStyle(fontWeight: FontWeight.bold)),
                                 Text(plan['price'], style: TextStyle(
                                   color: planId == 'basic' ? Colors.green : Colors.blue, fontWeight: FontWeight.bold)
                                 ),
                               ],
                             ),
                             if (isSelected) ...[
                               const Divider(),
                               ...(plan['features'] as List).take(3).map((f) => Text('• $f', style: const TextStyle(fontSize: 12))),
                             ]
                           ],
                         ),
                       )
                     ],
                   ),
                 ),
               ),
             );
           }).toList(),
          
          const Divider(height: 40),
          
          // Coupons
          ExpansionTile(
            title: Text(isEn ? 'Add a Coupon (Optional)' : 'Ajouter un coupon (Optionnel)'),
            leading: const Icon(Icons.local_offer, color: Colors.orange),
            children: [
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: Column(
                  children: [
                    TextFormField(
                      controller: _couponTitleController,
                      decoration: InputDecoration(labelText: isEn ? 'Coupon Title' : 'Titre du coupon', border: const OutlineInputBorder()),
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _couponCodeController,
                      decoration: InputDecoration(labelText: isEn ? 'Code' : 'Code', border: const OutlineInputBorder()),
                    ),
                    const SizedBox(height: 8),
                    ListTile(
                      title: Text(_couponExpirationDate == null 
                        ? (isEn ? 'Pick Expiration Date' : 'Choisir date d\'expiration')
                        : '${_couponExpirationDate!.year}-${_couponExpirationDate!.month}-${_couponExpirationDate!.day}'),
                      trailing: const Icon(Icons.calendar_today),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8), side: const BorderSide(color: Colors.grey)),
                      onTap: () async {
                        final date = await showDatePicker(
                          context: context, 
                          initialDate: DateTime.now().add(const Duration(days: 30)),
                          firstDate: DateTime.now(), 
                          lastDate: DateTime.now().add(const Duration(days: 365*2))
                        );
                        if (date != null) setState(() => _couponExpirationDate = date);
                      },
                    ),
                  ],
                ),
              )
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isEn = _localizationService.currentLanguage == 'en';
    
    // Steps Definition
    final steps = [
      Step(
        title: Text(isEn ? 'Identity' : 'Identité'),
        content: _buildStep1Identity(isEn),
        isActive: _currentStep >= 0,
        state: _currentStep > 0 ? StepState.complete : StepState.editing,
      ),
      Step(
        title: Text(isEn ? 'Location' : 'Lieu'),
        content: _buildStep2Location(isEn),
        isActive: _currentStep >= 1,
        state: _currentStep > 1 ? StepState.complete : StepState.editing,
      ),
      Step(
        title: Text(isEn ? 'Media' : 'Média'),
        content: _buildStep3Media(isEn),
        isActive: _currentStep >= 2,
        state: _currentStep > 2 ? StepState.complete : StepState.editing,
      ),
      Step(
        title: Text(isEn ? 'Plan' : 'Plan'),
        content: _buildStep4Plan(isEn),
        isActive: _currentStep >= 3,
        state: _currentStep == 3 ? StepState.complete : StepState.editing,
      ),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(isEn ? 'Registration Wizard' : 'Inscription Pro'),
        actions: [
          LanguageSelector(onLanguageChanged: (_) => setState(() {})),
        ],
      ),
      body: _isSubmitting 
        ? Center(child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 20),
              Text(isEn ? 'Processing registration...' : 'Traitement de l\'inscription...'),
            ],
          ))
        : Stepper(
            type: StepperType.horizontal,
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
                case 0: // Identity
                  isValid = _step1Key.currentState!.validate();
                  if (_selectedCategoryId.isEmpty) isValid = false;
                  break;
                case 1: // Location
                  isValid = _step2Key.currentState!.validate();
                  break;
                case 2: // Media
                   isValid = true; // Optional mostly
                   break;
                case 3: // Plan
                   isValid = true;
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
                 _showErrorMessage(isEn ? 'Please correct invalid fields' : 'Veuillez corriger les erreurs');
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
              return Padding(
                padding: const EdgeInsets.only(top: 24.0),
                child: Row(
                  children: [
                    Expanded(
                      child: ElevatedButton(
                        onPressed: details.onStepContinue,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue.shade700,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        child: Text(isLast 
                          ? (isEn ? 'FINISH & PAY' : 'TERMINER & PAYER')
                          : (isEn ? 'NEXT' : 'SUIVANT'),
                          style: const TextStyle(fontWeight: FontWeight.bold)
                        ),
                      ),
                    ),
                    if (_currentStep > 0) ...[
                      const SizedBox(width: 12),
                      Expanded(
                        child: OutlinedButton(
                          onPressed: details.onStepCancel,
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          child: Text(isEn ? 'BACK' : 'RETOUR'),
                        ),
                      ),
                    ],
                  ],
                ),
              );
            },
            steps: steps,
          ),
    );
  }
}
