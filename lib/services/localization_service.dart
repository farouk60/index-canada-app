import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'firebase_analytics_service.dart';

class LocalizationService extends ChangeNotifier {
  static final LocalizationService _instance = LocalizationService._internal();
  factory LocalizationService() => _instance;
  LocalizationService._internal();

  static const String _languageKey = 'selected_language';
  static const Set<String> supportedLanguageCodes = {'fr', 'en'};
  static const List<Map<String, String>> supportedLanguages = [
    {'code': 'fr', 'name': 'Français', 'flag': 'FR'},
    {'code': 'en', 'name': 'English', 'flag': 'EN'},
  ];

  String _currentLanguage = 'fr'; // Français par défaut

  String get currentLanguage => _currentLanguage;
  bool get isFrench => _currentLanguage == 'fr';
  bool get isEnglish => _currentLanguage == 'en';

  final Map<String, Map<String, String>> _translations = {
    'fr': {
      // Page d'accueil
      'home_eyebrow': 'Le repère canadien',
      'welcome_title': 'Trouvez les services utiles pour vos prochaines étapes',
      'welcome_subtitle': 'Explorez des professionnels et des ressources pour avancer dans votre installation au Canada.',
      'home_browse_hint':
          'Parcourez par service, par ville ou par professionnel.',
      'explore_services': 'Trouver un service',
      'sponsored_professionals': 'Professionnels en vedette',
      'favorites': 'Favoris',
      'no_sponsored': 'Aucun professionnel sponsor pour le moment.',
      'loading_error': 'Erreur de chargement',
      'try_again': 'Réessayer',

      // Navigation et actions
      'refresh': 'Actualiser',
      'refreshing_data': 'Actualisation des données...',
      'data_refreshed': 'Données actualisées !',
      'refresh_error': 'Erreur lors de l\'actualisation',
      'search': 'Rechercher',
      'filter': 'Filtrer',
      'back': 'Retour',
      'cancel': 'Annuler',
      'save': 'Sauvegarder',
      'delete': 'Supprimer',
      'edit': 'Modifier',
      'add': 'Ajouter',
      'close': 'Fermer',
      'phone_call_error':
          'Impossible d’ouvrir l’application Téléphone. Veuillez réessayer.',
      'unexpected_error_title': 'Un problème est survenu.',
      'unexpected_error_body': 'Veuillez réessayer. Si le problème persiste, redémarrez l’application.',

      // Navigation
      'home': 'Accueil',
      'partners': 'Partenaires',

      // Services
      'services': 'Services',
      'all_services': 'Tous les services',
      'no_services': 'Aucun service disponible.',

      // Professionnels
      'professionals': 'Professionnels',
      'professional_details': 'Détails du professionnel',
      'search_professional': 'Rechercher un professionnel',
      'search_by_city': 'Rechercher par ville',
      'no_professionals': 'Aucun professionnel trouvé.',
      'no_professionals_search': 'Aucun professionnel trouvé pour',
      'no_professionals_city': 'Aucun professionnel trouvé dans',
      'clear_filters': 'Effacer les filtres',

      // Favoris
      'add_to_favorites': 'Ajouter aux favoris',
      'remove_from_favorites': 'Supprimer des favoris',
      'added_to_favorites': 'Ajouté aux favoris',
      'removed_from_favorites': 'Supprimé des favoris',
      'my_favorites': 'Mes favoris',
      'no_favorites': 'Aucun favori pour le moment.',
      'favorites_subtitle': 'Retrouvez ici vos professionnels favoris.',
      'error_loading_favorites': 'Impossible de charger vos favoris.',
      'favorite_save_error': 'Impossible de modifier ce favori.',

      // Avis
      'reviews': 'Avis',
      'add_review': 'Ajouter un avis',
      'your_review': 'Votre avis',
      'review_title': 'Titre de votre avis',
      'review_comment': 'Votre commentaire',
      'review_name': 'Votre nom',
      'review_rating': 'Note générale',
      'publish_review': 'Publier l\'avis',
      'review_success': 'Avis envoyé pour validation.',
      'review_error': 'Erreur lors de l\'ajout de l\'avis',
      'share_experience': 'Partagez votre expérience',
      'help_others':
          'Votre avis aidera d\'autres personnes à faire le bon choix.',
      'stars': 'étoiles',
      'no_reviews': 'Aucun avis pour le moment.',
      'no_reviews_first':
          'Aucun avis pour l\'instant.\nSoyez le premier à laisser un avis !',
      'client_reviews': 'Avis clients',
      'review_count_one': '1 avis',
      'review_count_many': '{0} avis',
      'client_reviews_one': 'Avis client (1)',
      'client_reviews_many': 'Avis clients ({0})',
      'recommended_professional': 'Professionnel en vedette',
      'image_gallery': 'Galerie d\'images',
      'gallery_no_images': 'Aucune image disponible',
      'image_unavailable': 'Image indisponible',
      'loading_image': 'Chargement de l\'image {number}…',
      'previous_image': 'Image précédente',
      'next_image': 'Image suivante',
      'open_gallery_image': 'Ouvrir l\'image {number} dans la galerie',
      'gallery_preview_one': 'Ouvrir la galerie, 1 image',
      'gallery_preview_many': 'Ouvrir la galerie, {0} images',
      'choose_profile_photo': 'Choisir une photo de profil',
      'change_profile_photo': 'Modifier la photo de profil',
      'remove_gallery_image': 'Supprimer l’image {0} de la galerie',
      'sending': 'Envoi en cours...',
      'review_minimum': 'Le commentaire doit contenir au moins 10 caractères',
      'review_cooldown': 'Veuillez attendre encore {minutes} minute(s) avant de publier un autre avis.',
      'review_suspicious_content':
          'Retirez les liens et les coordonnées de votre commentaire.',
      'review_excessive_repetition':
          'Le commentaire contient trop de caractères répétés.',
      'review_all_caps': 'Évitez d’écrire entièrement en majuscules.',
      'review_too_few_words':
          'Le commentaire doit contenir au moins trois mots.',
      'review_low_quality': 'Rédigez un commentaire constructif.',
      'review_duplicate_professional':
          'Vous avez déjà publié un avis pour ce professionnel.',
      'review_duplicate_content': 'Vous avez déjà publié un avis similaire.',
      'enter_name': 'Veuillez entrer votre nom',
      'enter_comment': 'Veuillez entrer un commentaire',
      'review_placeholder':
          'Décrivez votre expérience avec ce professionnel...',
      'review_title_placeholder': 'Ex: Excellent service, très professionnel',
      'temporal_limitation': 'Limitation temporaire',
      'important_info': 'Informations importantes',
      'review_info_text':
          '• Votre avis sera vérifié avant sa publication.\n'
          '• Vous ne pouvez poster qu\'un seul avis par professionnel.\n'
          '• Un délai de 30 minutes est requis entre chaque avis.\n'
          '• Les avis contenant des liens ou du contenu promotionnel seront rejetés.\n'
          '• Rédigez un avis constructif et respectueux.',
      'clear_filter': 'Effacer le filtre',
      'filter_by': 'Filtre:',
      'sort_by': 'Trier par',

      // Options de tri
      'sort_options': 'Options de tri',
      'sort_default': 'Tri par défaut (En vedette puis nom)',
      'sort_name_az': 'Nom (A à Z)',
      'sort_name_za': 'Nom (Z à A)',
      'sort_sponsor_first': 'En vedette en premier',
      'sort_best_rated': 'Les mieux notés',
      'featured_badge': 'EN VEDETTE',

      // Coupons de réduction
      'exclusive_offer': 'Offre exclusive',
      'coupon_code': 'Code promo',
      'expires_on': 'Expire le',
      'expires_soon': 'Expire bientôt',
      'days_remaining': 'jours restants',
      'coupon_code_copied': 'Code promo copié !',
      'copy_coupon_code': 'Copier le code promo',
      'special_discount': 'Réduction spéciale',
      'app_exclusive': 'Exclusif à l\'app',

      // Informations de contact
      'contact_info': 'Informations de contact',
      'phone': 'Téléphone',
      'email': 'Email',
      'address': 'Adresse',
      'city': 'Ville',
      'website': 'Site web',
      'social_networks': 'Réseaux sociaux',
      'call': 'Appeler',
      'open_maps': 'Ouvrir dans Maps',
      'error_opening_maps': 'Impossible d\'ouvrir l\'application de cartes.',

      // Galerie
      'gallery': 'Galerie',
      'view_gallery': 'Voir la galerie',
      'photos': 'photos',

      // Erreurs et messages
      'error': 'Erreur',
      'loading': 'Chargement...',
      'retry': 'Réessayer',
      'success': 'Succès',
      'warning': 'Attention',
      'info': 'Information',
      'no_data': 'Aucune donnée disponible',
      'network_error': 'Erreur de réseau',
      'timeout_error': 'Délai d\'attente dépassé',

      // Validation
      'required_field': 'Ce champ est requis',
      'min_length': 'Minimum {0} caractères',
      'max_length': 'Maximum {0} caractères',
      'select_rating': 'Veuillez sélectionner une note',

      // Langues
      'language': 'Langue',
      'french': 'Français',
      'english': 'English',
      'change_language': 'Changer de langue',

      // Partenaires et sponsors
      'our_partners': 'Partenaires à découvrir',
      'official_partner': 'Partenaire officiel',
      'partner': 'Partenaire',
      'exclusive_offers': 'Offres exclusives',
      'exclusive': 'Exclusif',
      'offers_available': 'offres disponibles',
      'all_categories': 'Toutes les catégories',
      'error_loading_partners': 'Erreur lors du chargement des partenaires',
      'no_partners_in_category': 'Aucun partenaire dans cette catégorie',
      'no_partners_available': 'Aucun partenaire disponible',
      'show_all_partners': 'Afficher tous les partenaires',
      'about': 'À propos',
      'contact': 'Contact',
      'visit_website': 'Visiter le site web',
      'open_offer': 'Ouvrir l\'offre',
      'call_partner': 'Appeler',
      'error_opening_link': 'Erreur lors de l\'ouverture du lien',
      'promo_code': 'Code promo',
      'trusted_partners': 'Partenaires de confiance',
      'exclusive_offers_section': 'Offres exclusives pour nouveaux arrivants',
      'valid_until': 'Valide jusqu\'au',
      'no_offers_available': 'Aucune offre disponible',
      'featured_professionals': 'Professionnels en vedette',
      'professional_cta_eyebrow': 'Pour les entreprises',
      'are_you_professional': 'Vous offrez des services?',
      'register_here': 'Créer mon profil',
      'grow_your_business': 'Créez votre profil professionnel et présentez vos services à la communauté.',
      'see_all': 'Voir tout',
      'featured': 'En vedette',
      'official': 'Officiel',

      // Autres traductions ajoutées
      'learn_more': 'En savoir plus',
      'information': 'Informations',
      'category': 'Catégorie',
      'member_since': 'Partenaire depuis',
      'status': 'Statut',
      'active': 'Actif',
      'inactive': 'Inactif',
      'actions': 'Actions',
      'paid_payment_web_unavailable': 'Le paiement des forfaits payants n’est pas offert sur le Web. Choisissez le forfait gratuit ou utilisez l’application iOS ou Android.',
      'paid_plan_mobile_only': 'Achat offert dans l’application iOS ou Android',
      'payment_unavailable_on_web': 'Paiement indisponible sur le Web',
    },
    'en': {
      // Home page
      'home_eyebrow': 'Your Canadian starting point',
      'welcome_title': 'Find useful services for your next steps',
      'welcome_subtitle': 'Explore professionals and resources for your settlement journey in Canada.',
      'home_browse_hint': 'Browse by service, city, or professional.',
      'explore_services': 'Find a service',
      'sponsored_professionals': 'Featured Professionals',
      'favorites': 'Favorites',
      'no_sponsored': 'No sponsored professionals at the moment.',
      'loading_error': 'Loading error',
      'try_again': 'Try Again',

      // Navigation and actions
      'refresh': 'Refresh',
      'refreshing_data': 'Refreshing data...',
      'data_refreshed': 'Data refreshed!',
      'refresh_error': 'Error refreshing data',
      'search': 'Search',
      'filter': 'Filter',
      'back': 'Back',
      'cancel': 'Cancel',
      'save': 'Save',
      'delete': 'Delete',
      'edit': 'Edit',
      'add': 'Add',
      'close': 'Close',
      'phone_call_error': 'Unable to open the Phone app. Please try again.',
      'unexpected_error_title': 'Something went wrong.',
      'unexpected_error_body':
          'Please try again. If the problem persists, restart the app.',

      // Navigation
      'home': 'Home',
      'partners': 'Partners',
      'featured': 'Featured',
      'official': 'Official',

      // Services
      'services': 'Services',
      'all_services': 'All Services',
      'no_services': 'No services available.',

      // Professionals
      'professionals': 'Professionals',
      'professional_details': 'Professional Details',
      'search_professional': 'Search for a professional',
      'search_by_city': 'Search by city',
      'no_professionals': 'No professionals found.',
      'no_professionals_search': 'No professionals found for',
      'no_professionals_city': 'No professionals found in',
      'clear_filters': 'Clear filters',

      // Favorites
      'add_to_favorites': 'Add to favorites',
      'remove_from_favorites': 'Remove from favorites',
      'added_to_favorites': 'Added to favorites',
      'removed_from_favorites': 'Removed from favorites',
      'my_favorites': 'My Favorites',
      'no_favorites': 'No favorites yet.',
      'favorites_subtitle': 'Find your favorite professionals here.',
      'error_loading_favorites': 'Unable to load your favorites.',
      'favorite_save_error': 'Unable to update this favorite.',

      // Reviews
      'reviews': 'Reviews',
      'add_review': 'Add Review',
      'your_review': 'Your Review',
      'review_title': 'Review Title',
      'review_comment': 'Your Comment',
      'review_name': 'Your Name',
      'review_rating': 'Overall Rating',
      'publish_review': 'Publish Review',
      'review_success': 'Review submitted for approval.',
      'review_error': 'Error adding review',
      'share_experience': 'Share Your Experience',
      'help_others': 'Your review will help others make the right choice.',
      'stars': 'stars',
      'no_reviews': 'No reviews yet.',
      'no_reviews_first': 'No reviews yet.\nBe the first to leave a review!',
      'client_reviews': 'Client Reviews',
      'review_count_one': '1 review',
      'review_count_many': '{0} reviews',
      'client_reviews_one': 'Client review (1)',
      'client_reviews_many': 'Client reviews ({0})',
      'recommended_professional': 'Featured Professional',
      'image_gallery': 'Image Gallery',
      'gallery_no_images': 'No images available',
      'image_unavailable': 'Image unavailable',
      'loading_image': 'Loading image {number}…',
      'previous_image': 'Previous image',
      'next_image': 'Next image',
      'open_gallery_image': 'Open image {number} in the gallery',
      'gallery_preview_one': 'Open gallery, 1 image',
      'gallery_preview_many': 'Open gallery, {0} images',
      'choose_profile_photo': 'Choose a profile photo',
      'change_profile_photo': 'Change the profile photo',
      'remove_gallery_image': 'Remove gallery image {0}',
      'sending': 'Sending...',
      'review_minimum': 'The comment must contain at least 10 characters',
      'review_cooldown':
          'Please wait {minutes} more minute(s) before posting another review.',
      'review_suspicious_content':
          'Remove links and contact details from your review.',
      'review_excessive_repetition':
          'The review contains too many repeated characters.',
      'review_all_caps': 'Avoid writing entirely in capital letters.',
      'review_too_few_words': 'The review must contain at least three words.',
      'review_low_quality': 'Please write a constructive review.',
      'review_duplicate_professional':
          'You have already posted a review for this professional.',
      'review_duplicate_content': 'You have already posted a similar review.',
      'enter_name': 'Please enter your name',
      'enter_comment': 'Please enter a comment',
      'review_placeholder':
          'Describe your experience with this professional...',
      'review_title_placeholder': 'Ex: Excellent service, very professional',
      'temporal_limitation': 'Temporal Limitation',
      'important_info': 'Important Information',
      'review_info_text':
          '• Your review will be checked before publication.\n'
          '• You can only post one review per professional.\n'
          '• A 30-minute delay is required between each review.\n'
          '• Reviews containing links or promotional content will be rejected.\n'
          '• Write a constructive and respectful review.',
      'clear_filter': 'Clear Filter',
      'filter_by': 'Filter:',
      'sort_by': 'Sort by',

      // Sort options
      'sort_options': 'Sort Options',
      'sort_default': 'Default Sort (Featured then name)',
      'sort_name_az': 'Name (A to Z)',
      'sort_name_za': 'Name (Z to A)',
      'sort_sponsor_first': 'Featured First',
      'sort_best_rated': 'Best Rated',
      'featured_badge': 'FEATURED',

      // Discount coupons
      'exclusive_offer': 'Exclusive Offer',
      'coupon_code': 'Promo Code',
      'expires_on': 'Expires on',
      'expires_soon': 'Expires Soon',
      'days_remaining': 'days remaining',
      'coupon_code_copied': 'Promo code copied!',
      'copy_coupon_code': 'Copy promo code',
      'special_discount': 'Special Discount',
      'app_exclusive': 'App Exclusive',

      // Contact information
      'contact_info': 'Contact Information',
      'phone': 'Phone',
      'email': 'Email',
      'address': 'Address',
      'city': 'City',
      'website': 'Website',
      'social_networks': 'Social Networks',
      'call': 'Call',
      'open_maps': 'Open in Maps',
      'error_opening_maps': 'Unable to open the maps application.',

      // Gallery
      'gallery': 'Gallery',
      'view_gallery': 'View Gallery',
      'photos': 'photos',

      // Errors and messages
      'error': 'Error',
      'loading': 'Loading...',
      'retry': 'Retry',
      'success': 'Success',
      'warning': 'Warning',
      'info': 'Information',
      'no_data': 'No data available',
      'network_error': 'Network error',
      'timeout_error': 'Timeout error',

      // Validation
      'required_field': 'This field is required',
      'min_length': 'Minimum {0} characters',
      'max_length': 'Maximum {0} characters',
      'select_rating': 'Please select a rating',

      // Languages
      'language': 'Language',
      'french': 'Français',
      'english': 'English',
      'change_language': 'Change Language',

      // Partenaires et sponsors
      'our_partners': 'Partners to discover',
      'official_partner': 'Official Partner',
      'partner': 'Partner',
      'exclusive_offers': 'Exclusive Offers',
      'exclusive': 'Exclusive',
      'offers_available': 'offers available',
      'all_categories': 'All Categories',
      'error_loading_partners': 'Error loading partners',
      'no_partners_in_category': 'No partners in this category',
      'no_partners_available': 'No partners available',
      'show_all_partners': 'Show all partners',
      'about': 'About',
      'contact': 'Contact',
      'visit_website': 'Visit Website',
      'open_offer': 'Open offer',
      'call_partner': 'Call',
      'error_opening_link': 'Error opening link',
      'promo_code': 'Promo code',
      'trusted_partners': 'Trusted Partners',
      'exclusive_offers_section': 'Exclusive offers for new arrivals',
      'valid_until': 'Valid until',
      'no_offers_available': 'No offers available',
      'featured_professionals': 'Featured Professionals',
      'professional_cta_eyebrow': 'For businesses',
      'are_you_professional': 'Do you offer services?',
      'register_here': 'Create my profile',
      'grow_your_business': 'Create a professional profile and present your services to the community.',
      'see_all': 'See all',
      'learn_more': 'Learn more',
      'information': 'Information',
      'category': 'Category',
      'member_since': 'Partner since',
      'status': 'Status',
      'active': 'Active',
      'inactive': 'Inactive',
      'actions': 'Actions',
      'paid_payment_web_unavailable': 'Paid plans cannot currently be purchased on the web. Choose the free plan or use the iOS or Android app.',
      'paid_plan_mobile_only': 'Purchase available in the iOS or Android app',
      'payment_unavailable_on_web': 'Payment unavailable on the web',
    },
  };

  /// Obtenir une traduction
  String tr(String key, [List<String>? args]) {
    String translation = _translations[_currentLanguage]?[key] ?? key;

    // Remplacer les placeholders {0}, {1}, etc. par les arguments
    if (args != null) {
      for (int i = 0; i < args.length; i++) {
        translation = translation.replaceAll('{$i}', args[i]);
      }
    }

    return translation;
  }

  /// Libellé localisé et correctement pluralisé pour un nombre d’avis.
  String reviewCountLabel(int count) {
    final safeCount = count < 0 ? 0 : count;
    return safeCount == 1
        ? tr('review_count_one')
        : tr('review_count_many', [safeCount.toString()]);
  }

  /// Titre localisé de la section des avis avec son compteur.
  String clientReviewsLabel(int count) {
    final safeCount = count < 0 ? 0 : count;
    return safeCount == 1
        ? tr('client_reviews_one')
        : tr('client_reviews_many', [safeCount.toString()]);
  }

  /// Description vocale localisée d’un aperçu de galerie.
  String galleryPreviewLabel(int count) {
    final safeCount = count < 0 ? 0 : count;
    return safeCount == 1
        ? tr('gallery_preview_one')
        : tr('gallery_preview_many', [safeCount.toString()]);
  }

  /// Changer la langue
  Future<void> setLanguage(String languageCode) async {
    if (!supportedLanguageCodes.contains(languageCode)) {
      throw ArgumentError.value(
        languageCode,
        'languageCode',
        'Unsupported language',
      );
    }

    final previousLanguage = _currentLanguage;
    if (previousLanguage == languageCode) {
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_languageKey, languageCode);
    _currentLanguage = languageCode;
    notifyListeners();

    // Analytics must never prevent a user preference from being applied.
    try {
      await FirebaseAnalyticsService().trackLanguageChange(
        fromLanguage: previousLanguage,
        toLanguage: languageCode,
      );
    } on Exception {
      // Intentionally ignored: language selection is the source of truth.
    }
  }

  /// Charger la langue sauvegardée
  Future<void> loadSavedLanguage() async {
    final prefs = await SharedPreferences.getInstance();
    final savedLanguage = prefs.getString(_languageKey);
    final nextLanguage = supportedLanguageCodes.contains(savedLanguage)
        ? savedLanguage!
        : 'fr';
    if (_currentLanguage != nextLanguage) {
      _currentLanguage = nextLanguage;
      notifyListeners();
    }
  }

  /// Obtenir les langues disponibles
  List<Map<String, String>> getAvailableLanguages() {
    return supportedLanguages;
  }
}
