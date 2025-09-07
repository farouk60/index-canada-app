/// Modèles pour les partenaires et offres exclusives
class Partner {
  final String id;
  final String name;
  final String nameEN;
  final String description;
  final String descriptionEN;
  final String logo;
  final String category; // banque, telecom, assurance, transport, etc.
  final String website;
  final String phone;
  final bool isActive;
  final int priority; // Pour l'ordre d'affichage
  final List<Offer> offers;

  Partner({
    required this.id,
    required this.name,
    required this.nameEN,
    required this.description,
    required this.descriptionEN,
    required this.logo,
    required this.category,
    required this.website,
    required this.phone,
    this.isActive = true,
    this.priority = 0,
    this.offers = const [],
  });

  factory Partner.fromJson(Map<String, dynamic> json) {
    return Partner(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      nameEN: json['nameEN'] ?? json['name'] ?? '',
      description: json['description'] ?? '',
      descriptionEN: json['descriptionEN'] ?? json['description'] ?? '',
      logo: json['logo'] ?? '',
      category: json['category'] ?? '',
      website: json['website'] ?? '',
      phone: json['phone'] ?? '',
      isActive: json['isActive'] ?? true,
      priority: json['priority'] ?? 0,
      offers:
          (json['offers'] as List<dynamic>?)
              ?.map((offer) => Offer.fromJson(offer))
              .toList() ??
          [],
    );
  }

  String getNameInLanguage(String language) {
    return language == 'en' ? nameEN : name;
  }

  String getDescriptionInLanguage(String language) {
    return language == 'en' ? descriptionEN : description;
  }
}

class Offer {
  final String id;
  final String title;
  final String titleEN;
  final String description;
  final String descriptionEN;
  final String badge; // "2 mois gratuits", "50$ offerts", etc.
  final String badgeEN;
  final String terms; // Conditions d'utilisation
  final String termsEN;
  final String promoCode;
  final DateTime? validUntil;
  final bool isExclusive;
  final String icon; // emoji ou nom d'icône

  Offer({
    required this.id,
    required this.title,
    required this.titleEN,
    required this.description,
    required this.descriptionEN,
    required this.badge,
    required this.badgeEN,
    required this.terms,
    required this.termsEN,
    this.promoCode = '',
    this.validUntil,
    this.isExclusive = false,
    this.icon = '🎁',
  });

  factory Offer.fromJson(Map<String, dynamic> json) {
    return Offer(
      id: json['id'] ?? '',
      title: json['title'] ?? '',
      titleEN: json['titleEN'] ?? json['title'] ?? '',
      description: json['description'] ?? '',
      descriptionEN: json['descriptionEN'] ?? json['description'] ?? '',
      badge: json['badge'] ?? '',
      badgeEN: json['badgeEN'] ?? json['badge'] ?? '',
      terms: json['terms'] ?? '',
      termsEN: json['termsEN'] ?? json['terms'] ?? '',
      promoCode: json['promoCode'] ?? '',
      validUntil: json['validUntil'] != null
          ? DateTime.tryParse(json['validUntil'])
          : null,
      isExclusive: json['isExclusive'] ?? false,
      icon: json['icon'] ?? '🎁',
    );
  }

  String getTitleInLanguage(String language) {
    return language == 'en' ? titleEN : title;
  }

  String getDescriptionInLanguage(String language) {
    return language == 'en' ? descriptionEN : description;
  }

  String getBadgeInLanguage(String language) {
    return language == 'en' ? badgeEN : badge;
  }

  String getTermsInLanguage(String language) {
    return language == 'en' ? termsEN : terms;
  }

  bool get isValid {
    if (validUntil == null) return true;
    return DateTime.now().isBefore(validUntil!);
  }
}

/// Bannière sponsorisée pour insertion dans le fil
class SponsoredBanner {
  final String id;
  final String title;
  final String titleEN;
  final String description;
  final String descriptionEN;
  final String logo;
  final String backgroundColor;
  final String textColor;
  final String ctaText; // Call to action
  final String ctaTextEN;
  final String ctaLink;
  final bool isActive;
  final int displayPriority;

  SponsoredBanner({
    required this.id,
    required this.title,
    required this.titleEN,
    required this.description,
    required this.descriptionEN,
    required this.logo,
    this.backgroundColor = '#E3F2FD',
    this.textColor = '#1976D2',
    required this.ctaText,
    required this.ctaTextEN,
    required this.ctaLink,
    this.isActive = true,
    this.displayPriority = 0,
  });

  factory SponsoredBanner.fromJson(Map<String, dynamic> json) {
    return SponsoredBanner(
      id: json['id'] ?? '',
      title: json['title'] ?? '',
      titleEN: json['titleEN'] ?? json['title'] ?? '',
      description: json['description'] ?? '',
      descriptionEN: json['descriptionEN'] ?? json['description'] ?? '',
      logo: json['logo'] ?? '',
      backgroundColor: json['backgroundColor'] ?? '#E3F2FD',
      textColor: json['textColor'] ?? '#1976D2',
      ctaText: json['ctaText'] ?? '',
      ctaTextEN: json['ctaTextEN'] ?? json['ctaText'] ?? '',
      ctaLink: json['ctaLink'] ?? '',
      isActive: json['isActive'] ?? true,
      displayPriority: json['displayPriority'] ?? 0,
    );
  }

  String getTitleInLanguage(String language) {
    return language == 'en' ? titleEN : title;
  }

  String getDescriptionInLanguage(String language) {
    return language == 'en' ? descriptionEN : description;
  }

  String getCtaTextInLanguage(String language) {
    return language == 'en' ? ctaTextEN : ctaText;
  }
}
