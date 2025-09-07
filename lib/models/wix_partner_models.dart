/// Modèle Partner adapté à la structure Wix
import 'partner_models.dart';

class WixPartner {
  final String id;
  final String title; // Nom de la compagnie
  final String titleEn; // Nom anglais
  final String description; // Description
  final String descriptionEn; // Description anglaise
  final String logo; // Logo (Image)
  final String category; // Catégorie partenaire
  final String website; // Lien vers site web
  final String banner; // Image promotionnelle
  final bool isOfficial; // Est partenaire officiel ?
  final bool isFeatured; // En vedette ?
  final int displayOrder; // Ordre d'affichage
  final bool isActive; // Actif ?
  final DateTime? createdAt; // Date d'ajout

  WixPartner({
    required this.id,
    required this.title,
    required this.titleEn,
    required this.description,
    required this.descriptionEn,
    required this.logo,
    required this.category,
    required this.website,
    this.banner = '',
    this.isOfficial = true,
    this.isFeatured = false,
    this.displayOrder = 0,
    this.isActive = true,
    this.createdAt,
  });

  factory WixPartner.fromJson(Map<String, dynamic> json) {
    return WixPartner(
      id: json['_id'] ?? json['id'] ?? '',
      title: json['title'] ?? '',
      titleEn: json['titleEn'] ?? json['title'] ?? '',
      description: json['description'] ?? '',
      descriptionEn: json['descriptionEn'] ?? json['description'] ?? '',
      logo: json['logo'] ?? '',
      category: json['category'] ?? '',
      website: json['website'] ?? '',
      banner: json['banner'] ?? '',
      isOfficial: json['isOfficial'] ?? true,
      isFeatured: json['isFeatured'] ?? false,
      displayOrder: json['displayOrder'] ?? 0,
      isActive: json['isActive'] ?? true,
      createdAt: json['createdAt'] != null
          ? DateTime.tryParse(json['createdAt'].toString())
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      '_id': id,
      'title': title,
      'titleEn': titleEn,
      'description': description,
      'descriptionEn': descriptionEn,
      'logo': logo,
      'category': category,
      'website': website,
      'banner': banner,
      'isOfficial': isOfficial,
      'isFeatured': isFeatured,
      'displayOrder': displayOrder,
      'isActive': isActive,
      'createdAt': createdAt?.toIso8601String(),
    };
  }

  String getTitleInLanguage(String language) {
    return language == 'en' ? titleEn : title;
  }

  String getDescriptionInLanguage(String language) {
    return language == 'en' ? descriptionEn : description;
  }

  /// Détermine si le partenaire doit être affiché
  bool get shouldDisplay => isActive && isOfficial;

  /// Détermine si le partenaire est en vedette et actif
  bool get isActiveFeatured => isActive && isOfficial && isFeatured;

  /// Retourne l'URL de l'image à utiliser (logo par défaut, banner si disponible)
  String get primaryImageUrl => banner.isNotEmpty ? banner : logo;

  /// Convertit en Partner pour compatibilité avec le code existant
  Partner toPartner() {
    return Partner(
      id: id,
      name: title,
      nameEN: titleEn,
      description: description,
      descriptionEN: descriptionEn,
      logo: logo,
      category: category,
      website: website,
      phone: '', // Pas de téléphone dans la structure Wix
      isActive: isActive,
      priority: displayOrder,
      offers: [], // Pas d'offres dans la structure Wix pour l'instant
    );
  }
}

/// Classe pour les catégories de partenaires avec traductions
class PartnerCategory {
  final String id;
  final String nameFr;
  final String nameEn;
  final String icon;

  const PartnerCategory({
    required this.id,
    required this.nameFr,
    required this.nameEn,
    required this.icon,
  });

  String getNameInLanguage(String language) {
    return language == 'en' ? nameEn : nameFr;
  }

  static const List<PartnerCategory> predefinedCategories = [
    PartnerCategory(
      id: 'banque',
      nameFr: 'Banque et Finance',
      nameEn: 'Banking & Finance',
      icon: '🏦',
    ),
    PartnerCategory(
      id: 'telecom',
      nameFr: 'Télécommunications',
      nameEn: 'Telecommunications',
      icon: '📱',
    ),
    PartnerCategory(
      id: 'assurance',
      nameFr: 'Assurance',
      nameEn: 'Insurance',
      icon: '🏥',
    ),
    PartnerCategory(
      id: 'transport',
      nameFr: 'Transport',
      nameEn: 'Transportation',
      icon: '🚗',
    ),
    PartnerCategory(
      id: 'logement',
      nameFr: 'Logement',
      nameEn: 'Housing',
      icon: '🏠',
    ),
    PartnerCategory(
      id: 'education',
      nameFr: 'Éducation',
      nameEn: 'Education',
      icon: '📚',
    ),
    PartnerCategory(
      id: 'sante',
      nameFr: 'Santé',
      nameEn: 'Healthcare',
      icon: '🏥',
    ),
    PartnerCategory(
      id: 'emploi',
      nameFr: 'Emploi',
      nameEn: 'Employment',
      icon: '💼',
    ),
    PartnerCategory(
      id: 'commerce',
      nameFr: 'Commerce',
      nameEn: 'Retail',
      icon: '🛍️',
    ),
    PartnerCategory(
      id: 'services',
      nameFr: 'Services',
      nameEn: 'Services',
      icon: '🔧',
    ),
  ];

  static PartnerCategory? getCategoryById(String id) {
    try {
      return predefinedCategories.firstWhere((cat) => cat.id == id);
    } catch (e) {
      return null;
    }
  }
}
