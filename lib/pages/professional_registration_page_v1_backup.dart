import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'dart:async';
import 'dart:convert';
import '../data_service.dart';
import '../data/canadian_cities.dart'; // Import des villes
import '../models.dart';
import '../services/localization_service.dart';
import '../services/stripe_native_payment_service.dart';
import '../widgets/language_selector.dart';
import 'payment_plan_page.dart';
import 'payment_success_page.dart';

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
  State<ProfessionalRegistrationPage> createState() =>
      _ProfessionalRegistrationPageState();
}

class _ProfessionalRegistrationPageState
    extends State<ProfessionalRegistrationPage>
    with WidgetsBindingObserver {
  final LocalizationService _localizationService = LocalizationService();
  final _formKey = GlobalKey<FormState>();

  // Contrôleurs pour les champs du formulaire
  final _businessNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _addressController = TextEditingController();
  final _cityController = TextEditingController();
  final FocusNode _cityFocusNode = FocusNode(); // Ajout du FocusNode pour l'autocomplétion
  final _descriptionController = TextEditingController();
  final _websiteController = TextEditingController();

  // Réseaux sociaux
  final _facebookController = TextEditingController();
  final _instagramController = TextEditingController();
  final _tiktokController = TextEditingController();
  final _youtubeController = TextEditingController();
  final _whatsappController = TextEditingController();

  // Coupons
  final _couponTitleController = TextEditingController();
  final _couponCodeController = TextEditingController();
  final _couponDescriptionController = TextEditingController();

  String _selectedPlan = 'basic'; // basic, premium, professional
  bool _isSubmitting = false;

  // Images - Fonctionnalité réactivée avec choix appareil photo/galerie
  static const bool _enableImageSelection = true;

  // Images
  File? _profileImage;
  final List<File> _galleryImages = [];

  // Date d'expiration du coupon
  DateTime? _couponExpirationDate;

  // Options de tarification (en dollars canadiens par année)
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

  // Catégories disponibles - récupérées dynamiquement depuis Wix
  List<SousCategorie> _sousCategories = [];
  String _selectedCategoryId = ''; // Stocke l'ID de la catégorie sélectionnée

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // Charger toutes les catégories disponibles depuis le service de données
    _loadAllCategories();

    print('🏥 ProfessionalRegistrationPage: initState completed');
  }

  void _loadAllCategories() async {
    try {
      print('🔄 Chargement de toutes les catégories...');
      final DataService dataService = DataService();
      final categories = await dataService.fetchSousCategories();

      if (mounted) {
        setState(() {
          _sousCategories = categories;
        });
        print('✅ ${categories.length} catégories chargées avec succès');
      }
    } catch (e) {
      print('⚠️ Erreur lors du chargement des catégories: $e');

      // En cas d'erreur, utiliser des catégories de base
      if (mounted) {
        setState(() {
          _sousCategories = [
            SousCategorie(
              id: 'default-1',
              title: 'Médecins',
              titleEn: 'Doctors',
              image: '',
            ),
            SousCategorie(
              id: 'default-2',
              title: 'Dentistes',
              titleEn: 'Dentists',
              image: '',
            ),
            SousCategorie(
              id: 'default-3',
              title: 'Avocats',
              titleEn: 'Lawyers',
              image: '',
            ),
            SousCategorie(
              id: 'default-4',
              title: 'Comptables',
              titleEn: 'Accountants',
              image: '',
            ),
            SousCategorie(
              id: 'default-5',
              title: 'Restaurants',
              titleEn: 'Restaurants',
              image: '',
            ),
            SousCategorie(
              id: 'default-6',
              title: 'Coiffeurs',
              titleEn: 'Hairdressers',
              image: '',
            ),
            SousCategorie(
              id: 'default-7',
              title: 'Mécaniciens',
              titleEn: 'Mechanics',
              image: '',
            ),
            SousCategorie(
              id: 'default-8',
              title: 'Électriciens',
              titleEn: 'Electricians',
              image: '',
            ),
            SousCategorie(
              id: 'default-9',
              title: 'Plombiers',
              titleEn: 'Plumbers',
              image: '',
            ),
            SousCategorie(
              id: 'default-10',
              title: 'Consultants',
              titleEn: 'Consultants',
              image: '',
            ),
          ];
        });
        print('🔄 Catégories de base utilisées en cas d\'erreur');
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _businessNameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    _cityController.dispose();
    _cityFocusNode.dispose(); // Dispose focus node
    _descriptionController.dispose();
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
    switch (state) {
      case AppLifecycleState.resumed:
        print('✅ App resumed - Page d\'inscription');
        break;
      case AppLifecycleState.paused:
        print('⏸️ App paused - Page d\'inscription');
        break;
      case AppLifecycleState.detached:
        print('🔌 App detached - Page d\'inscription');
        break;
      case AppLifecycleState.inactive:
        print('😴 App inactive - Page d\'inscription');
        break;
      case AppLifecycleState.hidden:
        print('👁️ App hidden - Page d\'inscription');
        break;
    }
  }

  // Fonction pour normaliser les accents français pour un meilleur tri
  String _normalizeForSorting(String text) {
    return text
        .toLowerCase()
        .replaceAll('à', 'a')
        .replaceAll('á', 'a')
        .replaceAll('â', 'a')
        .replaceAll('ä', 'a')
        .replaceAll('è', 'e')
        .replaceAll('é', 'e')
        .replaceAll('ê', 'e')
        .replaceAll('ë', 'e')
        .replaceAll('ì', 'i')
        .replaceAll('í', 'i')
        .replaceAll('î', 'i')
        .replaceAll('ï', 'i')
        .replaceAll('ò', 'o')
        .replaceAll('ó', 'o')
        .replaceAll('ô', 'o')
        .replaceAll('ö', 'o')
        .replaceAll('ù', 'u')
        .replaceAll('ú', 'u')
        .replaceAll('û', 'u')
        .replaceAll('ü', 'u')
        .replaceAll('ç', 'c')
        .replaceAll('ñ', 'n');
  }

  // Fonction pour enlever les accents
  String _removeDiacritics(String str) {
    var withDia = 'ÀÁÂÃÄÅàáâãäåÒÓÔÕÕÖØòóôõöøÈÉÊËèéêëðÇçÐÌÍÎÏìíîïÙÚÛÜùúûüÑñŠšŸÿýŽž';
    var withoutDia = 'AAAAAAaaaaaaOOOOOOOooooooEEEEeeeeeCcDIIIIiiiiUUUUuuuuNnSsYyyZz';

    for (int i = 0; i < withDia.length; i++) {
      str = str.replaceAll(withDia[i], withoutDia[i]);
    }
    return str;
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

      // Utiliser la normalisation pour un tri alphabétique correct avec accents
      final normalizedA = _normalizeForSorting(titleA);
      final normalizedB = _normalizeForSorting(titleB);

      return normalizedA.compareTo(normalizedB);
    });
    return categories;
  }

  // ========== NOUVELLES MÉTHODES POUR APPAREIL PHOTO + GALERIE ==========

  Future<void> _pickProfileImage() async {
    if (!_enableImageSelection) {
      _showImageDisabledMessage();
      return;
    }

    if (!mounted) return;
    _showImageSourceChoice();
  }

  void _showImageDisabledMessage() {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _localizationService.currentLanguage == 'fr'
                ? '🚧 Sélection d\'images temporairement désactivée.'
                : '🚧 Image selection temporarily disabled.',
          ),
          backgroundColor: Colors.orange,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  void _showImageSourceChoice() {
    final isEnglish = _localizationService.currentLanguage == 'en';

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (BuildContext context) {
        return Container(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                isEnglish
                    ? 'Select Image Source'
                    : 'Choisir la source de l\'image',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 20),

              // Option Appareil Photo
              ListTile(
                leading: const Icon(
                  Icons.camera_alt,
                  color: Colors.blue,
                  size: 30,
                ),
                title: Text(
                  isEnglish ? 'Camera' : 'Appareil photo',
                  style: const TextStyle(fontSize: 16),
                ),
                subtitle: Text(
                  isEnglish ? 'Take a new photo' : 'Prendre une nouvelle photo',
                  style: TextStyle(color: Colors.grey[600]),
                ),
                onTap: () {
                  Navigator.pop(context);
                  _pickImageFromCamera();
                },
              ),

              const Divider(),

              // Option Galerie
              ListTile(
                leading: const Icon(
                  Icons.photo_library,
                  color: Colors.green,
                  size: 30,
                ),
                title: Text(
                  isEnglish ? 'Gallery' : 'Galerie',
                  style: const TextStyle(fontSize: 16),
                ),
                subtitle: Text(
                  isEnglish
                      ? 'Choose from gallery'
                      : 'Choisir depuis la galerie',
                  style: TextStyle(color: Colors.grey[600]),
                ),
                onTap: () {
                  Navigator.pop(context);
                  _pickImageFromGallery();
                },
              ),

              const SizedBox(height: 10),

              // Bouton Annuler
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(
                  isEnglish ? 'Cancel' : 'Annuler',
                  style: const TextStyle(color: Colors.grey),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _pickImageFromCamera() async {
    try {
      final ImagePicker picker = ImagePicker();
      final XFile? image = await picker.pickImage(
        source: ImageSource.camera,
        maxWidth: 600, // Réduit de 1024 à 600px pour backend Wix
        maxHeight: 600, // Réduit de 1024 à 600px pour backend Wix
        imageQuality: 40, // Réduit de 80% à 40% pour backend Wix
      );

      if (image != null && mounted) {
        final File imageFile = File(image.path);

        // Vérifier la taille du fichier (max 5MB)
        final int fileSize = await imageFile.length();
        if (fileSize > 5 * 1024 * 1024) {
          _showErrorMessage(
            _localizationService.currentLanguage == 'fr'
                ? '❌ Image trop grande (max 5MB)'
                : '❌ Image too large (max 5MB)',
          );
          return;
        }

        setState(() {
          _profileImage = imageFile;
        });

        _showSuccessMessage(
          _localizationService.currentLanguage == 'fr'
              ? '✅ Photo de profil ajoutée'
              : '✅ Profile photo added',
        );
      }
    } catch (e) {
      print('Erreur appareil photo: $e');
      _showErrorMessage(
        _localizationService.currentLanguage == 'fr'
            ? '❌ Erreur lors de la prise de photo'
            : '❌ Error taking photo',
      );
    }
  }

  Future<void> _pickImageFromGallery() async {
    try {
      final ImagePicker picker = ImagePicker();
      final XFile? image = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 600, // Réduit de 1024 à 600px pour backend Wix
        maxHeight: 600, // Réduit de 1024 à 600px pour backend Wix
        imageQuality: 40, // Réduit de 80% à 40% pour backend Wix
      );

      if (image != null && mounted) {
        final File imageFile = File(image.path);

        // Vérifier la taille du fichier (max 5MB)
        final int fileSize = await imageFile.length();
        if (fileSize > 5 * 1024 * 1024) {
          _showErrorMessage(
            _localizationService.currentLanguage == 'fr'
                ? '❌ Image trop grande (max 5MB)'
                : '❌ Image too large (max 5MB)',
          );
          return;
        }

        setState(() {
          _profileImage = imageFile;
        });

        _showSuccessMessage(
          _localizationService.currentLanguage == 'fr'
              ? '✅ Photo de profil ajoutée depuis la galerie'
              : '✅ Profile photo added from gallery',
        );
      }
    } catch (e) {
      print('Erreur galerie: $e');
      _showErrorMessage(
        _localizationService.currentLanguage == 'fr'
            ? '❌ Erreur lors de la sélection d\'image'
            : '❌ Error selecting image',
      );
    }
  }

  Future<void> _pickGalleryImages() async {
    if (!_enableImageSelection) {
      _showImageDisabledMessage();
      return;
    }

    if (_galleryImages.length >= 5) {
      _showErrorMessage(
        _localizationService.currentLanguage == 'fr'
            ? '❌ Maximum 5 images de galerie'
            : '❌ Maximum 5 gallery images',
      );
      return;
    }

    if (!mounted) return;
    _showGalleryImageSourceChoice();
  }

  void _showGalleryImageSourceChoice() {
    final isEnglish = _localizationService.currentLanguage == 'en';

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (BuildContext context) {
        return Container(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                isEnglish ? 'Add Gallery Image' : 'Ajouter image galerie',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 20),

              // Option Appareil Photo
              ListTile(
                leading: const Icon(
                  Icons.camera_alt,
                  color: Colors.blue,
                  size: 30,
                ),
                title: Text(
                  isEnglish ? 'Camera' : 'Appareil photo',
                  style: const TextStyle(fontSize: 16),
                ),
                subtitle: Text(
                  isEnglish ? 'Take a new photo' : 'Prendre une nouvelle photo',
                  style: TextStyle(color: Colors.grey[600]),
                ),
                onTap: () {
                  Navigator.pop(context);
                  _pickGalleryImageFromCamera();
                },
              ),

              const Divider(),

              // Option Galerie
              ListTile(
                leading: const Icon(
                  Icons.photo_library,
                  color: Colors.green,
                  size: 30,
                ),
                title: Text(
                  isEnglish ? 'Gallery' : 'Galerie',
                  style: const TextStyle(fontSize: 16),
                ),
                subtitle: Text(
                  isEnglish
                      ? 'Choose from gallery'
                      : 'Choisir depuis la galerie',
                  style: TextStyle(color: Colors.grey[600]),
                ),
                onTap: () {
                  Navigator.pop(context);
                  _pickGalleryImageFromGallery();
                },
              ),

              const SizedBox(height: 10),

              // Bouton Annuler
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(
                  isEnglish ? 'Cancel' : 'Annuler',
                  style: const TextStyle(color: Colors.grey),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _pickGalleryImageFromCamera() async {
    try {
      final ImagePicker picker = ImagePicker();
      final XFile? image = await picker.pickImage(
        source: ImageSource.camera,
        maxWidth: 600, // Réduit de 1024 à 600px pour backend Wix
        maxHeight: 600, // Réduit de 1024 à 600px pour backend Wix
        imageQuality: 40, // Réduit de 80% à 40% pour backend Wix
      );

      if (image != null && mounted) {
        final File imageFile = File(image.path);

        // Vérifier la taille du fichier (max 5MB)
        final int fileSize = await imageFile.length();
        if (fileSize > 5 * 1024 * 1024) {
          _showErrorMessage(
            _localizationService.currentLanguage == 'fr'
                ? '❌ Image trop grande (max 5MB)'
                : '❌ Image too large (max 5MB)',
          );
          return;
        }

        setState(() {
          _galleryImages.add(imageFile);
        });

        _showSuccessMessage(
          _localizationService.currentLanguage == 'fr'
              ? '✅ Image ajoutée à la galerie'
              : '✅ Image added to gallery',
        );
      }
    } catch (e) {
      print('Erreur appareil photo galerie: $e');
      _showErrorMessage(
        _localizationService.currentLanguage == 'fr'
            ? '❌ Erreur lors de la prise de photo'
            : '❌ Error taking photo',
      );
    }
  }

  Future<void> _pickGalleryImageFromGallery() async {
    try {
      final ImagePicker picker = ImagePicker();
      final XFile? image = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 600, // Réduit de 1024 à 600px pour backend Wix
        maxHeight: 600, // Réduit de 1024 à 600px pour backend Wix
        imageQuality: 40, // Réduit de 80% à 40% pour backend Wix
      );

      if (image != null && mounted) {
        final File imageFile = File(image.path);

        // Vérifier la taille du fichier (max 5MB)
        final int fileSize = await imageFile.length();
        if (fileSize > 5 * 1024 * 1024) {
          _showErrorMessage(
            _localizationService.currentLanguage == 'fr'
                ? '❌ Image trop grande (max 5MB)'
                : '❌ Image too large (max 5MB)',
          );
          return;
        }

        setState(() {
          _galleryImages.add(imageFile);
        });

        _showSuccessMessage(
          _localizationService.currentLanguage == 'fr'
              ? '✅ Image ajoutée à la galerie depuis la galerie'
              : '✅ Image added to gallery from gallery',
        );
      }
    } catch (e) {
      print('Erreur galerie galerie: $e');
      _showErrorMessage(
        _localizationService.currentLanguage == 'fr'
            ? '❌ Erreur lors de la sélection d\'image'
            : '❌ Error selecting image',
      );
    }
  }

  void _removeGalleryImage(int index) {
    setState(() {
      _galleryImages.removeAt(index);
    });
  }

  void _showSuccessMessage(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  void _showErrorMessage(
    String message, {
    String? title,
    Color? backgroundColor,
  }) {
    if (mounted) {
      final isEnglish = _localizationService.currentLanguage == 'en';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: title != null
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(message),
                  ],
                )
              : Text(message),
          backgroundColor: backgroundColor ?? Colors.red,
          duration: const Duration(seconds: 4),
          behavior: SnackBarBehavior.floating,
          action: SnackBarAction(
            label: isEnglish ? 'OK' : 'OK',
            textColor: Colors.white,
            onPressed: () {
              ScaffoldMessenger.of(context).hideCurrentSnackBar();
            },
          ),
        ),
      );
    }
  }

  // ========== AUTRES MÉTHODES ==========

  Future<void> _selectCouponExpirationDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now().add(const Duration(days: 30)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      helpText: _localizationService.currentLanguage == 'fr'
          ? 'Sélectionner la date d\'expiration'
          : 'Select expiration date',
    );

    if (picked != null) {
      setState(() {
        _couponExpirationDate = picked;
      });
    }
  }

  List<String> _getPlanFeatures(String planKey, bool isEnglish) {
    final Map<String, Map<String, List<String>>> planFeatures = {
      'basic': {
        'fr': [
          'Fiche professionnel de base',
          'Informations de contact',
          'Photo de profil',
          'Visible dans les recherches',
          'Réseaux sociaux',
          'Coupons de réduction',
        ],
        'en': [
          'Basic professional profile',
          'Contact information',
          'Profile photo',
          'Visible in searches',
          'Social networks',
          'Discount coupons',
        ],
      },
      'premium': {
        'fr': [
          'Tout du plan de base',
          'Galerie de photos (jusqu\'à 5 images)',
          'Résumé d\'activité mis en avant',
          'Support prioritaire',
          'Réseaux sociaux améliorés',
          'Coupons de réduction exclusifs',
        ],
        'en': [
          'Everything from basic plan',
          'Photo gallery (up to 5 images)',
          'Featured business summary',
          'Priority support',
          'Enhanced social networks',
          'Exclusive discount coupons',
        ],
      },
      'professional': {
        'fr': [
          'Tout du plan premium',
          'Mise en avant sur la page d\'accueil',
          'Priorité dans les résultats',
          'Support technique dédié',
          'Personnalisation avancée',
          'Intégration API',
        ],
        'en': [
          'Everything from premium plan',
          'Featured on home page',
          'Priority in search results',
          'Dedicated technical support',
          'Advanced customization',
          'API integration',
        ],
      },
    };

    return planFeatures[planKey]?[isEnglish ? 'en' : 'fr'] ?? [];
  }

  Future<void> _submitForm() async {
    // Vérifier d'abord si le formulaire est valide
    if (!_formKey.currentState!.validate()) {
      // Afficher un message d'erreur global amélioré
      final isEnglish = _localizationService.currentLanguage == 'en';
      _showErrorMessage(
        isEnglish
            ? 'Please check and fill in all required fields marked with an asterisk (*)'
            : 'Veuillez vérifier et remplir tous les champs obligatoires marqués d\'un astérisque (*)',
        title: isEnglish
            ? '📋 Form Validation Error'
            : '📋 Erreur de validation du formulaire',
      );
      return;
    }

    // Vérifier si l'image de profil est présente (recommandée)
    final isEnglish = _localizationService.currentLanguage == 'en';
    if (_profileImage == null) {
      final shouldContinue = await showDialog<bool>(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            title: Text(
              isEnglish
                  ? '📸 Profile Image Missing'
                  : '📸 Image de profil manquante',
            ),
            content: Text(
              isEnglish
                  ? 'A profile image helps customers recognize your business. Do you want to continue without one?'
                  : 'Une image de profil aide les clients à reconnaître votre entreprise. Voulez-vous continuer sans image ?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: Text(
                  isEnglish ? 'Add Image' : 'Ajouter Image',
                  style: const TextStyle(color: Colors.blue),
                ),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: Text(
                  isEnglish ? 'Continue' : 'Continuer',
                  style: const TextStyle(color: Colors.orange),
                ),
              ),
            ],
          );
        },
      );

      if (shouldContinue != true) {
        return; // L'utilisateur veut ajouter une image
      }
    }

    setState(() {
      _isSubmitting = true;
    });
    try {
      final isEnglish = _localizationService.currentLanguage == 'en';

      // ÉTAPE 1: Préparer les images si présentes
      String? profileImageBase64;
      List<String>? galleryImagesBase64;

      if (_profileImage != null) {
        try {
          print('🖼️ Conversion de l\'image de profil en base64...');
          print('📍 Chemin du fichier: ${_profileImage!.path}');

          // Vérifier que le fichier existe
          final exists = await _profileImage!.exists();
          print('📂 Fichier existe: $exists');

          if (!exists) {
            throw Exception('Le fichier image n\'existe pas');
          }

          final bytes = await _profileImage!.readAsBytes();
          print(
            '📊 Taille du fichier: ${bytes.length} bytes (${(bytes.length / 1024).toStringAsFixed(1)} KB)',
          );

          // Vérifier que les bytes ne sont pas vides
          if (bytes.isEmpty) {
            throw Exception('Le fichier image est vide');
          }

          profileImageBase64 = base64Encode(bytes);
          print(
            '✅ Image de profil convertie en base64 (${profileImageBase64.length} caractères)',
          );
          print(
            '🔍 Début de la chaîne base64: ${profileImageBase64.substring(0, 50)}...',
          );

          if (mounted) {
            _showSuccessMessage(
              _localizationService.currentLanguage == 'fr'
                  ? '📸 Image de profil préparée (${(bytes.length / 1024).toStringAsFixed(1)} KB)'
                  : '📸 Profile image prepared (${(bytes.length / 1024).toStringAsFixed(1)} KB)',
            );
          }
        } catch (e) {
          print('❌ Erreur conversion image profil: $e');
          if (mounted) {
            _showErrorMessage(
              _localizationService.currentLanguage == 'fr'
                  ? '❌ Erreur lors de la préparation de l\'image: $e'
                  : '❌ Error preparing image: $e',
            );
          }
        }
      }
      if (_galleryImages.isNotEmpty) {
        try {
          print(
            '🖼️ Conversion de ${_galleryImages.length} images de galerie...',
          );
          galleryImagesBase64 = [];
          for (int i = 0; i < _galleryImages.length; i++) {
            final bytes = await _galleryImages[i].readAsBytes();
            galleryImagesBase64.add(base64Encode(bytes));
            print('✅ Image galerie ${i + 1} convertie (${bytes.length} bytes)');
          }

          if (mounted) {
            _showSuccessMessage(
              _localizationService.currentLanguage == 'fr'
                  ? '🖼️ ${_galleryImages.length} images de galerie préparées...'
                  : '🖼️ ${_galleryImages.length} gallery images prepared...',
            );
          }
        } catch (e) {
          print('⚠️ Erreur conversion images galerie: $e');
        }
      }

      // ÉTAPE 2: Créer un ID temporaire (ne pas envoyer à Wix avant le paiement)
      print('🔄 Préparation des données pour le paiement...');

      // Créer un ID temporaire pour le paiement
      final tempProfessionalId =
          'temp_${DateTime.now().millisecondsSinceEpoch}';

      print('🆔 ID temporaire créé: $tempProfessionalId');

      if (mounted) {
        _showSuccessMessage(
          isEnglish
              ? '✅ Registration data prepared for payment!'
              : '✅ Données d\'inscription préparées pour le paiement !',
        );

        // ÉTAPE 3: Récupérer les informations de la catégorie sélectionnée
        final selectedCategory = _sousCategories.firstWhere(
          (cat) => cat.id == _selectedCategoryId,
          orElse: () =>
              SousCategorie(id: '', title: '', titleEn: '', image: '', imageEn: ''),
        );

        // Utiliser les informations de catégorie (widget si disponible, sinon sélection du formulaire)
        final categoryId = widget.categoryId ?? selectedCategory.id;
        final categoryName = widget.categoryName ?? selectedCategory.title;
        final categoryNameEn =
            widget.categoryNameEn ?? selectedCategory.titleEn;

        final registrationData = {
          'businessName': _businessNameController.text,
          'category': _selectedCategoryId,
          'email': _emailController.text,
          'phone': _phoneController.text,
          'address': _addressController.text,
          'city': _cityController.text,
          'description': _descriptionController.text,
          'selectedPlan': _selectedPlan,
          'planPrice': _pricingPlans[_selectedPlan]!['price'],
          'website': _websiteController.text.isNotEmpty
              ? _websiteController.text
              : null,
          'businessSummary': _descriptionController.text,
          'facebook': _facebookController.text.isNotEmpty
              ? _facebookController.text
              : null,
          'instagram': _instagramController.text.isNotEmpty
              ? _instagramController.text
              : null,
          'tiktok': _tiktokController.text.isNotEmpty
              ? _tiktokController.text
              : null,
          'youtube': _youtubeController.text.isNotEmpty
              ? _youtubeController.text
              : null,
          'whatsapp': _whatsappController.text.isNotEmpty
              ? _whatsappController.text
              : null,
          'couponTitle': _couponTitleController.text.isNotEmpty
              ? _couponTitleController.text
              : null,
          'couponCode': _couponCodeController.text.isNotEmpty
              ? _couponCodeController.text
              : null,
          'couponDescription': _couponDescriptionController.text.isNotEmpty
              ? _couponDescriptionController.text
              : null,
          'couponExpirationDate': _couponExpirationDate?.toIso8601String(),
          'hasProfileImage': _profileImage != null,
          'galleryImagesCount': _galleryImages.length,
          'profileImageBase64': profileImageBase64,
          'galleryImagesBase64': galleryImagesBase64,
        };

        if (_selectedPlan == 'basic') {
          // POUR LE PLAN GRATUIT : Création directe sans page de paiement
          if (mounted) {
            _showSuccessMessage(
              isEnglish
                  ? 'Creating your free profile...'
                  : 'Création de votre profil gratuit...',
            );
          }

          // 1. Simuler le processus de paiement (retourne succès immédiat pour basic)
          final result = await StripeNativePaymentService.processNativePayment(
            context: context,
            planId: 'basic',
            professionalId: tempProfessionalId,
            email: _emailController.text,
            businessName: _businessNameController.text,
            categoryId: categoryId,
            ville: _cityController.text,
            phone: _phoneController.text,
            registrationData: registrationData,
          );

          if (result.success && result.paymentIntentId != null) {
            // 2. Confirmer sur le serveur (crée le pro dans la DB)
            final confirmationData =
                await StripeNativePaymentService.confirmPaymentOnServer(
                  paymentIntentId: result.paymentIntentId!,
                  professionalId: tempProfessionalId,
                  planId: 'basic',
                  businessName: _businessNameController.text,
                  email: _emailController.text,
                  categoryId: categoryId,
                  ville: _cityController.text,
                  phone: _phoneController.text,
                  registrationData: registrationData,
                );

            if (confirmationData != null &&
                confirmationData['success'] == true) {
              
              final data = confirmationData['data'] as Map<String, dynamic>;
              final realProfessionalId =
                  data['professionalId'] ?? tempProfessionalId;

              // 3. Redirection vers succès
              if (mounted) {
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(
                    builder: (context) => PaymentSuccessPage(
                      professionalId: realProfessionalId,
                      businessName: _businessNameController.text,
                      planType: 'basic',
                      amountPaid: 0.0,
                      paymentId: result.paymentIntentId!,
                      professionalEmail: _emailController.text,
                      categoryId: categoryId,
                      categoryName: categoryName,
                      categoryNameEn: categoryNameEn,
                    ),
                  ),
                );
              }
            } else {
              _showErrorMessage(
                isEnglish
                    ? 'Error creating profile. Please try again.'
                    : 'Erreur lors de la création du profil. Veuillez réessayer.',
              );
            }
          } else {
             _showErrorMessage(
                isEnglish
                    ? 'Error processing request.'
                    : 'Erreur lors du traitement de la demande.',
              );
          }
        } else {
          // POUR LES PLANS PAYANTS : Navigation vers Plan -> Paiement
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => PaymentPlanPage(
                businessName: _businessNameController.text,
                email: _emailController.text,
                selectedPlan: _selectedPlan,
                professionalId: tempProfessionalId,
                categoryId: categoryId,
                categoryName: categoryName,
                categoryNameEn: categoryNameEn,
                registrationData: registrationData,
              ),
            ),
          );
        }
      }
    } catch (e) {
      print('❌ Erreur lors de la préparation des données: $e');

      if (mounted) {
        _showErrorMessage(
          _localizationService.currentLanguage == 'fr'
              ? '❌ Erreur lors de la préparation des données: ${e.toString()}'
              : '❌ Error preparing data: ${e.toString()}',
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEnglish = _localizationService.currentLanguage == 'en';

    return Scaffold(
      appBar: AppBar(
        title: Text(isEnglish ? 'Join Our Directory' : 'Rejoindre l\'annuaire'),
        backgroundColor: Colors.blue.shade600,
        foregroundColor: Colors.white,
        actions: [
          LanguageSelector(
            onLanguageChanged: (String languageCode) {
              setState(() {}); // Reconstruire la page
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header avec avantages
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Colors.blue.shade50, Colors.blue.shade100],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isEnglish
                          ? 'Boost Your Business'
                          : 'Développez votre entreprise',
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Colors.blue,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      isEnglish
                          ? 'Join thousands of professionals who trust our platform to connect with new clients.'
                          : 'Rejoignez des milliers de professionnels qui font confiance à notre plateforme pour trouver de nouveaux clients.',
                      style: TextStyle(fontSize: 16, color: Colors.grey[700]),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // Plans de tarification
              Text(
                isEnglish ? 'Choose Your Plan' : 'Choisissez votre plan',
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),

              ...(_pricingPlans.entries.map((entry) {
                final planKey = entry.key;
                final plan = entry.value;
                final isSelected = _selectedPlan == planKey;

                return Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: InkWell(
                    onTap: () => setState(() => _selectedPlan = planKey),
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: isSelected ? Colors.blue : Colors.grey[300]!,
                          width: isSelected ? 2 : 1,
                        ),
                        borderRadius: BorderRadius.circular(12),
                        color: isSelected ? Colors.blue.shade50 : Colors.white,
                      ),
                      child: Row(
                        children: [
                          Radio<String>(
                            value: planKey,
                            groupValue: _selectedPlan,
                            onChanged: (value) =>
                                setState(() => _selectedPlan = value!),
                          ),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      planKey == 'professional'
                                          ? (isEnglish
                                                ? 'FEATURED'
                                                : 'EN VEDETTE')
                                          : planKey.toUpperCase(),
                                      style: const TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    Text(
                                      planKey == 'basic'
                                          ? (isEnglish ? 'Free' : 'Gratuit')
                                          : '${plan['price']}/${isEnglish ? 'year' : 'année'}',
                                      style: TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                        color: planKey == 'basic'
                                            ? Colors.green
                                            : Colors.blue,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                ...(_getPlanFeatures(planKey, isEnglish)
                                    .map(
                                      (feature) => Padding(
                                        padding: const EdgeInsets.only(
                                          bottom: 4,
                                        ),
                                        child: Row(
                                          children: [
                                            const Icon(
                                              Icons.check,
                                              color: Colors.green,
                                              size: 16,
                                            ),
                                            const SizedBox(width: 8),
                                            Expanded(child: Text(feature)),
                                          ],
                                        ),
                                      ),
                                    )
                                    .toList()),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }).toList()),

              const SizedBox(height: 24),

              // Formulaire d'inscription
              Text(
                isEnglish
                    ? 'Professional Information'
                    : 'Information du professionnel',
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),

              // Nom du professionnel
              TextFormField(
                controller: _businessNameController,
                decoration: InputDecoration(
                  labelText: isEnglish
                      ? 'Professional Name *'
                      : 'Nom du professionnel *',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return isEnglish
                        ? 'Please enter professional name'
                        : 'Veuillez saisir le nom du professionnel';
                  }
                  if (value.length < 2) {
                    return isEnglish
                        ? 'Professional name must be at least 2 characters'
                        : 'Le nom du professionnel doit contenir au moins 2 caractères';
                  }
                  return null;
                },
              ),

              const SizedBox(height: 16),

              // Catégorie
              DropdownButtonFormField<String>(
                value: _selectedCategoryId.isEmpty ? null : _selectedCategoryId,
                decoration: InputDecoration(
                  labelText: isEnglish ? 'Category *' : 'Catégorie *',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                items: _getSortedCategories()
                    .map(
                      (category) => DropdownMenuItem(
                        value: category.id,
                        child: Text(
                          isEnglish
                              ? category.getTitleInLanguage('en')
                              : category.getTitleInLanguage('fr'),
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (value) =>
                    setState(() => _selectedCategoryId = value ?? ''),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return isEnglish
                        ? 'Please select a category'
                        : 'Veuillez sélectionner une catégorie';
                  }
                  return null;
                },
              ),

              const SizedBox(height: 16),

              // Email
              TextFormField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                decoration: InputDecoration(
                  labelText: 'Email *',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return isEnglish
                        ? 'Please enter email'
                        : 'Veuillez saisir l\'email';
                  }
                  if (!RegExp(
                    r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$',
                  ).hasMatch(value)) {
                    return isEnglish
                        ? 'Please enter a valid email address'
                        : 'Veuillez saisir une adresse email valide';
                  }
                  return null;
                },
              ),

              const SizedBox(height: 16),

              // Téléphone
              TextFormField(
                controller: _phoneController,
                keyboardType: TextInputType.phone,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: InputDecoration(
                  labelText: isEnglish ? 'Phone *' : 'Téléphone *',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return isEnglish
                        ? 'Please enter phone number'
                        : 'Veuillez saisir le numéro de téléphone';
                  }
                  if (value.length < 8) {
                    return isEnglish
                        ? 'Phone number must be at least 8 digits'
                        : 'Le numéro de téléphone doit contenir au moins 8 chiffres';
                  }
                  return null;
                },
              ),

              const SizedBox(height: 16),

              // Adresse
              TextFormField(
                controller: _addressController,
                decoration: InputDecoration(
                  labelText: _localizationService.currentLanguage == 'en' ? 'Address *' : 'Adresse *',
                  hintText: _localizationService.currentLanguage == 'en'
                      ? 'Enter your address'
                      : 'Saisissez votre adresse',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                onChanged: (value) {
                  if (value.trim().isEmpty) {
                    _cityController.clear();
                  }
                },
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return _localizationService.currentLanguage == 'en'
                        ? 'Please enter address'
                        : 'Veuillez saisir l\'adresse';
                  }
                  return null;
                },
              ),

              const SizedBox(height: 16),

              // Ville avec Autocomplétion
              RawAutocomplete<String>(
                textEditingController: _cityController,
                focusNode: _cityFocusNode,
                optionsBuilder: (TextEditingValue textEditingValue) {
                  if (textEditingValue.text.isEmpty) {
                    return const Iterable<String>.empty();
                  }
                  // Recherche insensible à la casse et aux accents (basique)
                  return kCanadianCities.where((String option) {
                    final normalizedOption = _removeDiacritics(option.toLowerCase());
                    final normalizedInput = _removeDiacritics(textEditingValue.text.toLowerCase());
                    return normalizedOption.contains(normalizedInput);
                  });
                },
                fieldViewBuilder: (BuildContext context,
                    TextEditingController textEditingController,
                    FocusNode focusNode,
                    VoidCallback onFieldSubmitted) {
                  return TextFormField(
                    controller: textEditingController,
                    focusNode: focusNode,
                    textCapitalization: TextCapitalization.words,
                    decoration: InputDecoration(
                      labelText: isEnglish ? 'City *' : 'Ville *',
                      hintText: isEnglish ? 'Start typing...' : 'Commencez à taper...',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      suffixIcon: const Icon(Icons.arrow_drop_down),
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return isEnglish
                            ? 'Please enter city'
                            : 'Veuillez saisir la ville';
                      }
                      return null;
                    },
                  );
                },
                optionsViewBuilder: (BuildContext context,
                    AutocompleteOnSelected<String> onSelected,
                    Iterable<String> options) {
                  return Align(
                    alignment: Alignment.topLeft,
                    child: Material(
                      elevation: 4.0,
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        width: MediaQuery.of(context).size.width - 32, // Largeur écran - padding
                        constraints: const BoxConstraints(maxHeight: 250),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.grey.shade300),
                        ),
                        child: ListView.builder(
                          padding: EdgeInsets.zero,
                          shrinkWrap: true,
                          itemCount: options.length,
                          itemBuilder: (BuildContext context, int index) {
                            final String option = options.elementAt(index);
                            return InkWell(
                              onTap: () {
                                onSelected(option);
                              },
                              child: Padding(
                                padding: const EdgeInsets.all(16.0),
                                child: Text(option),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  );
                },
              ),

              const SizedBox(height: 16),

              // Site web (optionnel)
              TextFormField(
                controller: _websiteController,
                keyboardType: TextInputType.url,
                decoration: InputDecoration(
                  labelText: isEnglish
                      ? 'Website (optional)'
                      : 'Site web (optionnel)',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),

              const SizedBox(height: 16),

              TextFormField(
                controller: _descriptionController,
                maxLines: 4,
                decoration: InputDecoration(
                  labelText: isEnglish
                      ? 'Business Summary (optional)'
                      : 'Résumé d\'activité (optionnel)',
                  hintText: isEnglish
                      ? 'Tell us about your business, services, and what makes you unique...'
                      : 'Parlez-nous de votre entreprise, vos services, et ce qui vous rend unique...',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                validator: (value) {
                  // Pas de validation requise - champ optionnel
                  return null;
                },
              ),

              const SizedBox(height: 24),

              // Section Photos
              Text(
                isEnglish ? 'Photos' : 'Photos',
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),

              // Photo de profil
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isEnglish ? 'Profile Photo' : 'Photo de profil',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          // Affichage de l'image réelle
                          if (_profileImage != null) ...[
                            Container(
                              width: 80,
                              height: 80,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(8),
                                image: DecorationImage(
                                  image: FileImage(_profileImage!),
                                  fit: BoxFit.cover,
                                ),
                              ),
                            ),
                            const SizedBox(width: 16),
                          ],
                          ElevatedButton.icon(
                            onPressed: _pickProfileImage,
                            icon: Icon(
                              _profileImage != null
                                  ? Icons.edit
                                  : Icons.add_a_photo,
                            ),
                            label: Text(
                              _profileImage != null
                                  ? (isEnglish ? 'Change' : 'Changer')
                                  : (isEnglish ? 'Add Photo' : 'Ajouter photo'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // Galerie de photos (pour premium/professional)
              if (_selectedPlan != 'basic') ...[
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isEnglish
                              ? 'Photo Gallery (up to 5 photos)'
                              : 'Galerie de photos (jusqu\'à 5 photos)',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.black,
                          ),
                        ),
                        const SizedBox(height: 8),

                        // Affichage des images sélectionnées
                        if (_galleryImages.isNotEmpty) ...[
                          Text(
                            isEnglish
                                ? 'Selected images (${_galleryImages.length}/5):'
                                : 'Images sélectionnées (${_galleryImages.length}/5) :',
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: _galleryImages.asMap().entries.map((
                              entry,
                            ) {
                              final index = entry.key;
                              final image = entry.value;
                              return Stack(
                                children: [
                                  Container(
                                    width: 80,
                                    height: 80,
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                        color: Colors.grey.shade300,
                                        width: 1,
                                      ),
                                      image: DecorationImage(
                                        image: FileImage(image),
                                        fit: BoxFit.cover,
                                      ),
                                    ),
                                  ),
                                  Positioned(
                                    top: 4,
                                    right: 4,
                                    child: GestureDetector(
                                      onTap: () => _removeGalleryImage(index),
                                      child: Container(
                                        width: 20,
                                        height: 20,
                                        decoration: const BoxDecoration(
                                          color: Colors.red,
                                          shape: BoxShape.circle,
                                        ),
                                        child: const Icon(
                                          Icons.close,
                                          color: Colors.white,
                                          size: 12,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              );
                            }).toList(),
                          ),
                          const SizedBox(height: 12),
                        ],

                        ElevatedButton.icon(
                          onPressed: _galleryImages.length < 5
                              ? _pickGalleryImages
                              : null,
                          icon: const Icon(Icons.add_photo_alternate),
                          label: Text(
                            isEnglish
                                ? 'Add Photos (${_galleryImages.length}/5)'
                                : 'Ajouter photos (${_galleryImages.length}/5)',
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // Section Réseaux sociaux
              Text(
                isEnglish ? 'Social Networks' : 'Réseaux sociaux',
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),

              // Facebook
              TextFormField(
                controller: _facebookController,
                decoration: InputDecoration(
                  labelText: 'Facebook (optionnel)',
                  hintText: 'https://facebook.com/votre-page',
                  prefixIcon: const Icon(Icons.facebook, color: Colors.blue),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // Instagram
              TextFormField(
                controller: _instagramController,
                decoration: InputDecoration(
                  labelText: 'Instagram (optionnel)',
                  hintText: 'https://instagram.com/votre-compte',
                  prefixIcon: const Icon(
                    Icons.camera_alt,
                    color: Colors.purple,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // TikTok
              TextFormField(
                controller: _tiktokController,
                decoration: InputDecoration(
                  labelText: 'TikTok (optionnel)',
                  hintText: 'https://tiktok.com/@votre-compte',
                  prefixIcon: const Icon(Icons.music_note, color: Colors.black),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // YouTube
              TextFormField(
                controller: _youtubeController,
                decoration: InputDecoration(
                  labelText: 'YouTube (optionnel)',
                  hintText: 'https://youtube.com/votre-chaine',
                  prefixIcon: const Icon(Icons.play_circle, color: Colors.red),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // WhatsApp Business
              TextFormField(
                controller: _whatsappController,
                keyboardType: TextInputType.phone,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: InputDecoration(
                  labelText: 'WhatsApp Business (optionnel)',
                  hintText: '+1234567890',
                  prefixIcon: const Icon(Icons.phone, color: Colors.green),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),

              const SizedBox(height: 24),

              // Section Coupons de réduction
              Text(
                isEnglish ? 'Discount Coupon' : 'Coupon de réduction',
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                isEnglish
                    ? 'Offer a discount to attract new customers (optional)'
                    : 'Offrez une réduction pour attirer de nouveaux clients (optionnel)',
                style: TextStyle(fontSize: 14, color: Colors.grey[600]),
              ),
              const SizedBox(height: 16),

              // Titre du coupon
              TextFormField(
                controller: _couponTitleController,
                decoration: InputDecoration(
                  labelText: isEnglish ? 'Coupon Title' : 'Titre du coupon',
                  hintText: isEnglish
                      ? 'e.g., "First consultation 50% off"'
                      : 'ex. "Première consultation 50% de réduction"',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // Code du coupon
              TextFormField(
                controller: _couponCodeController,
                decoration: InputDecoration(
                  labelText: isEnglish ? 'Coupon Code' : 'Code du coupon',
                  hintText: isEnglish
                      ? 'e.g., "WELCOME50"'
                      : 'ex. "BIENVENUE50"',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // Description du coupon
              TextFormField(
                controller: _couponDescriptionController,
                maxLines: 2,
                decoration: InputDecoration(
                  labelText: isEnglish
                      ? 'Coupon Description'
                      : 'Description du coupon',
                  hintText: isEnglish
                      ? 'Describe the offer, conditions, etc.'
                      : 'Décrivez l\'offre, les conditions, etc.',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // Date d'expiration du coupon
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isEnglish ? 'Expiration Date' : 'Date d\'expiration',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              _couponExpirationDate != null
                                  ? '${_couponExpirationDate!.day}/${_couponExpirationDate!.month}/${_couponExpirationDate!.year}'
                                  : (isEnglish
                                        ? 'No date selected'
                                        : 'Aucune date sélectionnée'),
                              style: TextStyle(
                                fontSize: 16,
                                color: _couponExpirationDate != null
                                    ? Colors.black
                                    : Colors.grey,
                              ),
                            ),
                          ),
                          ElevatedButton.icon(
                            onPressed: _selectCouponExpirationDate,
                            icon: const Icon(Icons.calendar_today),
                            label: Text(
                              isEnglish ? 'Select Date' : 'Sélectionner',
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 32),

              // Bouton de soumission
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: _isSubmitting ? null : _submitForm,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue.shade600,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: _isSubmitting
                      ? const CircularProgressIndicator(color: Colors.white)
                      : Text(
                          isEnglish
                              ? 'Submit Application'
                              : 'Soumettre la demande',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                ),
              ),

              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }
}
