import '../models/partner_models.dart';

/// Service pour gérer les partenaires et offres exclusives
class PartnerService {
  static final PartnerService _instance = PartnerService._internal();
  factory PartnerService() => _instance;
  PartnerService._internal();

  // Données de démonstration - à remplacer par un appel API
  static final List<Partner> _mockPartners = [
    Partner(
      id: 'desjardins',
      name: 'Desjardins',
      nameEN: 'Desjardins',
      description: 'Institution financière coopérative du Québec',
      descriptionEN: 'Quebec\'s cooperative financial institution',
      logo:
          'https://www.desjardins.com/ressources/images/a-propos/logos/logo-desjardins.png',
      category: 'banque',
      website: 'https://www.desjardins.com',
      phone: '1-800-224-7737',
      priority: 1,
      offers: [
        Offer(
          id: 'desjardins_welcome',
          title: 'Carte cadeau de 50\$ offerte',
          titleEN: '\$50 gift card offered',
          description: 'Ouvrez un compte et recevez une carte cadeau de 50\$',
          descriptionEN: 'Open an account and receive a \$50 gift card',
          badge: '50\$ offerts',
          badgeEN: '\$50 offered',
          terms: 'Valide pour nouveaux clients seulement',
          termsEN: 'Valid for new customers only',
          icon: '🏦',
          isExclusive: true,
        ),
      ],
    ),
    Partner(
      id: 'fizz',
      name: 'Fizz',
      nameEN: 'Fizz',
      description: 'Forfaits mobiles flexibles et sans engagement',
      descriptionEN: 'Flexible mobile plans without commitment',
      logo: 'https://fizz.ca/sites/all/themes/fizz/logo.svg',
      category: 'telecom',
      website: 'https://fizz.ca',
      phone: '1-833-FIZZ-CA',
      priority: 2,
      offers: [
        Offer(
          id: 'fizz_2months',
          title: '2 mois gratuits',
          titleEN: '2 months free',
          description: 'Profitez de 2 mois gratuits sur votre forfait mobile',
          descriptionEN: 'Enjoy 2 free months on your mobile plan',
          badge: '2 mois gratuits',
          badgeEN: '2 months free',
          terms: 'Engagement de 12 mois requis',
          termsEN: '12-month commitment required',
          promoCode: 'NOUVEAU2024',
          icon: '📱',
          isExclusive: true,
        ),
      ],
    ),
    Partner(
      id: 'sunlife',
      name: 'Sun Life',
      nameEN: 'Sun Life',
      description: 'Assurance santé et vie au Canada',
      descriptionEN: 'Health and life insurance in Canada',
      logo:
          'https://www.sunlife.ca/content/dam/sunlife/global/images/logo/sunlife-logo.svg',
      category: 'assurance',
      website: 'https://www.sunlife.ca',
      phone: '1-877-786-5433',
      priority: 3,
      offers: [
        Offer(
          id: 'sunlife_health',
          title: 'Consultation gratuite',
          titleEN: 'Free consultation',
          description: 'Évaluation gratuite de vos besoins d\'assurance',
          descriptionEN: 'Free assessment of your insurance needs',
          badge: 'Consultation gratuite',
          badgeEN: 'Free consultation',
          terms: 'Sur rendez-vous seulement',
          termsEN: 'By appointment only',
          icon: '🏥',
          isExclusive: false,
        ),
      ],
    ),
    Partner(
      id: 'communauto',
      name: 'Communauto',
      nameEN: 'Communauto',
      description: 'Service d\'autopartage au Québec',
      descriptionEN: 'Car-sharing service in Quebec',
      logo: 'https://www.communauto.com/images/logo-communauto.svg',
      category: 'transport',
      website: 'https://www.communauto.com',
      phone: '1-888-944-2112',
      priority: 4,
      offers: [
        Offer(
          id: 'communauto_noFees',
          title: 'Inscription sans frais',
          titleEN: 'No registration fees',
          description: 'Inscrivez-vous sans frais d\'inscription',
          descriptionEN: 'Register without registration fees',
          badge: 'Sans frais',
          badgeEN: 'No fees',
          terms: 'Valide jusqu\'au 31 décembre 2024',
          termsEN: 'Valid until December 31, 2024',
          validUntil: DateTime(2024, 12, 31),
          icon: '🚗',
          isExclusive: true,
        ),
      ],
    ),
  ];

  static final List<SponsoredBanner> _mockBanners = [
    SponsoredBanner(
      id: 'desjardins_banner',
      title: '🏦 Nouveau au Canada ?',
      titleEN: '🏦 New to Canada?',
      description:
          'Ouvrez un compte Desjardins et recevez une carte cadeau de 50\$.',
      descriptionEN: 'Open a Desjardins account and receive a \$50 gift card.',
      logo:
          'https://www.desjardins.com/ressources/images/a-propos/logos/logo-desjardins.png',
      backgroundColor: '#E8F5E8',
      textColor: '#2E7D32',
      ctaText: 'En savoir plus',
      ctaTextEN: 'Learn more',
      ctaLink: 'https://www.desjardins.com/nouveaux-arrivants',
      displayPriority: 1,
    ),
  ];

  /// Récupérer tous les partenaires actifs
  Future<List<Partner>> getPartners() async {
    // Simuler un délai d'API
    await Future.delayed(const Duration(milliseconds: 500));

    return _mockPartners.where((partner) => partner.isActive).toList()
      ..sort((a, b) => a.priority.compareTo(b.priority));
  }

  /// Récupérer les partenaires par catégorie
  Future<List<Partner>> getPartnersByCategory(String category) async {
    final partners = await getPartners();
    return partners.where((partner) => partner.category == category).toList();
  }

  /// Récupérer toutes les offres valides
  Future<List<Offer>> getActiveOffers() async {
    final partners = await getPartners();
    final offers = <Offer>[];

    for (final partner in partners) {
      offers.addAll(partner.offers.where((offer) => offer.isValid));
    }

    return offers;
  }

  /// Récupérer les offres exclusives
  Future<List<Offer>> getExclusiveOffers() async {
    final offers = await getActiveOffers();
    return offers.where((offer) => offer.isExclusive).toList();
  }

  /// Récupérer les bannières sponsorisées
  Future<List<SponsoredBanner>> getSponsoredBanners() async {
    await Future.delayed(const Duration(milliseconds: 300));

    return _mockBanners.where((banner) => banner.isActive).toList()
      ..sort((a, b) => a.displayPriority.compareTo(b.displayPriority));
  }

  /// Récupérer un partenaire par ID
  Future<Partner?> getPartnerById(String id) async {
    final partners = await getPartners();
    try {
      return partners.firstWhere((partner) => partner.id == id);
    } catch (e) {
      return null;
    }
  }

  /// Obtenir les catégories de partenaires disponibles
  Future<List<String>> getPartnerCategories() async {
    final partners = await getPartners();
    final categories = partners.map((p) => p.category).toSet().toList();
    categories.sort();
    return categories;
  }

  /// Obtenir l'icône pour une catégorie
  String getCategoryIcon(String category) {
    switch (category) {
      case 'banque':
        return '🏦';
      case 'telecom':
        return '📱';
      case 'assurance':
        return '🏥';
      case 'transport':
        return '🚗';
      case 'logement':
        return '🏠';
      case 'education':
        return '📚';
      default:
        return '🏢';
    }
  }

  /// Obtenir le nom de catégorie localisé
  String getCategoryName(String category, String language) {
    switch (category) {
      case 'banque':
        return language == 'en' ? 'Banking' : 'Banque';
      case 'telecom':
        return language == 'en' ? 'Telecom' : 'Télécommunications';
      case 'assurance':
        return language == 'en' ? 'Insurance' : 'Assurance';
      case 'transport':
        return language == 'en' ? 'Transport' : 'Transport';
      case 'logement':
        return language == 'en' ? 'Housing' : 'Logement';
      case 'education':
        return language == 'en' ? 'Education' : 'Éducation';
      default:
        return category;
    }
  }
}
