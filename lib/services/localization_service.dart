import 'package:shared_preferences/shared_preferences.dart';
import 'firebase_analytics_service.dart';

class LocalizationService {
  static final LocalizationService _instance = LocalizationService._internal();
  factory LocalizationService() => _instance;
  LocalizationService._internal();

  static const String _languageKey = 'selected_language';

  String _currentLanguage = 'fr'; // Français par défaut

  String get currentLanguage => _currentLanguage;
  bool get isFrench => _currentLanguage == 'fr';
  bool get isEnglish => _currentLanguage == 'en';

  final Map<String, Map<String, String>> _translations = {
    'fr': {
      // Page d'accueil
      'welcome_title': 'Bienvenue sur Index',
      'welcome_subtitle':
          'Trouvez et recommandez des professionnels de confiance dans votre communauté.',
      'explore_services': 'Explorer les services',
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

      // Avis
      'reviews': 'Avis',
      'add_review': 'Ajouter un avis',
      'your_review': 'Votre avis',
      'review_title': 'Titre de votre avis',
      'review_comment': 'Votre commentaire',
      'review_name': 'Votre nom',
      'review_rating': 'Note générale',
      'publish_review': 'Publier l\'avis',
      'review_success': 'Avis ajouté avec succès !',
      'review_error': 'Erreur lors de l\'ajout de l\'avis',
      'share_experience': 'Partagez votre expérience',
      'help_others':
          'Votre avis aidera d\'autres personnes à faire le bon choix.',
      'stars': 'étoiles',
      'no_reviews': 'Aucun avis pour le moment.',
      'no_reviews_first':
          'Aucun avis pour l\'instant.\nSoyez le premier à laisser un avis !',
      'client_reviews': 'Avis clients',
      'recommended_professional': 'Professionnel en vedette',
      'image_gallery': 'Galerie d\'images',
      'sending': 'Envoi en cours...',
      'review_minimum': 'Le commentaire doit contenir au moins 10 caractères',
      'enter_name': 'Veuillez entrer votre nom',
      'enter_comment': 'Veuillez entrer un commentaire',
      'review_placeholder':
          'Décrivez votre expérience avec ce professionnel...',
      'review_title_placeholder': 'Ex: Excellent service, très professionnel',
      'temporal_limitation': 'Limitation temporaire',
      'important_info': 'Informations importantes',
      'review_info_text':
          '• Votre avis sera publié immédiatement et restera visible publiquement.\n'
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
      'our_partners': 'Nos partenaires',
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
      'call_partner': 'Appeler',
      'error_opening_link': 'Erreur lors de l\'ouverture du lien',
      'promo_code': 'Code promo',
      'trusted_partners': 'Partenaires de confiance',
      'exclusive_offers_section': 'Offres exclusives pour nouveaux arrivants',
      'valid_until': 'Valide jusqu\'au',
      'no_offers_available': 'Aucune offre disponible',
      'featured_professionals': 'Professionnels en vedette',
      'are_you_professional': 'Vous êtes un professionnel?',
      'register_here': 'Inscrivez-vous ici',
      'see_all': 'Voir tout',

      // Autres traductions ajoutées
      'learn_more': 'En savoir plus',
      'information': 'Informations',
      'category': 'Catégorie',
      'member_since': 'Partenaire depuis',
      'status': 'Statut',
      'active': 'Actif',
      'inactive': 'Inactif',
      'actions': 'Actions',
    },
    'en': {
      // Home page
      'welcome_title': 'Welcome to Index',
      'welcome_subtitle':
          'Find and recommend trusted professionals in your community.',
      'explore_services': 'Explore Services',
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

      // Reviews
      'reviews': 'Reviews',
      'add_review': 'Add Review',
      'your_review': 'Your Review',
      'review_title': 'Review Title',
      'review_comment': 'Your Comment',
      'review_name': 'Your Name',
      'review_rating': 'Overall Rating',
      'publish_review': 'Publish Review',
      'review_success': 'Review added successfully!',
      'review_error': 'Error adding review',
      'share_experience': 'Share Your Experience',
      'help_others': 'Your review will help others make the right choice.',
      'stars': 'stars',
      'no_reviews': 'No reviews yet.',
      'no_reviews_first': 'No reviews yet.\nBe the first to leave a review!',
      'client_reviews': 'Client Reviews',
      'recommended_professional': 'Featured Professional',
      'image_gallery': 'Image Gallery',
      'sending': 'Sending...',
      'review_minimum': 'The comment must contain at least 10 characters',
      'enter_name': 'Please enter your name',
      'enter_comment': 'Please enter a comment',
      'review_placeholder':
          'Describe your experience with this professional...',
      'review_title_placeholder': 'Ex: Excellent service, very professional',
      'temporal_limitation': 'Temporal Limitation',
      'important_info': 'Important Information',
      'review_info_text':
          '• Your review will be published immediately and will remain publicly visible.\n'
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
      'our_partners': 'Our Partners',
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
      'call_partner': 'Call',
      'error_opening_link': 'Error opening link',
      'promo_code': 'Promo code',
      'trusted_partners': 'Trusted Partners',
      'exclusive_offers_section': 'Exclusive offers for new arrivals',
      'valid_until': 'Valid until',
      'no_offers_available': 'No offers available',
      'featured_professionals': 'Featured Professionals',
      'are_you_professional': 'Are you a professional?',
      'register_here': 'Register here',
      'see_all': 'See all',
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

  /// Changer la langue
  Future<void> setLanguage(String languageCode) async {
    final previousLanguage = _currentLanguage;
    _currentLanguage = languageCode;

    // Tracker le changement de langue
    final analytics = FirebaseAnalyticsService();
    await analytics.trackLanguageChange(
      fromLanguage: previousLanguage,
      toLanguage: languageCode,
    );

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_languageKey, languageCode);
  }

  /// Charger la langue sauvegardée
  Future<void> loadSavedLanguage() async {
    final prefs = await SharedPreferences.getInstance();
    _currentLanguage = prefs.getString(_languageKey) ?? 'fr';
  }

  /// Obtenir les langues disponibles
  List<Map<String, String>> getAvailableLanguages() {
    return [
      {'code': 'fr', 'name': 'Français', 'flag': '🇫🇷'},
      {'code': 'en', 'name': 'English', 'flag': '🇺🇸'},
    ];
  }
}
