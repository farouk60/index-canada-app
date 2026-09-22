import 'partner_models.dart';

String _stringValue(Object? value) {
  if (value == null) return '';
  return value.toString().trim();
}

String _mediaValue(Object? value) {
  if (value is Map<String, dynamic>) {
    for (final key in const ['url', 'src', 'fileUrl']) {
      final candidate = _stringValue(value[key]);
      if (candidate.isNotEmpty) return candidate;
    }
    return '';
  }
  return _stringValue(value);
}

bool _boolValue(Object? value, {required bool fallback}) {
  if (value is bool) return value;
  if (value is num) return value != 0;
  if (value is String) {
    switch (value.trim().toLowerCase()) {
      case 'true':
      case '1':
        return true;
      case 'false':
      case '0':
        return false;
    }
  }
  return fallback;
}

int _intValue(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(_stringValue(value)) ?? 0;
}

/// Partenaire tel qu'exposé par la collection Wix publique.
class WixPartner {
  const WixPartner({
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
    final title = _stringValue(json['title']);
    final description = _stringValue(json['description']);
    final titleEn = _stringValue(json['titleEn']);
    final descriptionEn = _stringValue(json['descriptionEn']);

    return WixPartner(
      id: _stringValue(json['_id'] ?? json['id']),
      title: title,
      titleEn: titleEn.isEmpty ? title : titleEn,
      description: description,
      descriptionEn: descriptionEn.isEmpty ? description : descriptionEn,
      logo: _mediaValue(json['logo']),
      category: _stringValue(json['category']),
      website: _stringValue(json['website']),
      banner: _mediaValue(json['banner']),
      isOfficial: _boolValue(json['isOfficial'], fallback: true),
      isFeatured: _boolValue(json['isFeatured'], fallback: false),
      displayOrder: _intValue(json['displayOrder']),
      isActive: _boolValue(json['isActive'], fallback: true),
      createdAt: DateTime.tryParse(_stringValue(json['createdAt'])),
    );
  }

  final String id;
  final String title;
  final String titleEn;
  final String description;
  final String descriptionEn;
  final String logo;
  final String category;
  final String website;
  final String banner;
  final bool isOfficial;
  final bool isFeatured;
  final int displayOrder;
  final bool isActive;
  final DateTime? createdAt;

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
    return language == 'en' && titleEn.isNotEmpty ? titleEn : title;
  }

  String getDescriptionInLanguage(String language) {
    return language == 'en' && descriptionEn.isNotEmpty
        ? descriptionEn
        : description;
  }

  bool get shouldDisplay => isActive && isOfficial;

  bool get isActiveFeatured => shouldDisplay && isFeatured;

  String get primaryImageUrl => banner.isNotEmpty ? banner : logo;

  /// Adaptateur maintenu pour les consommateurs historiques du modèle Partner.
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
      phone: '',
      isActive: isActive,
      priority: displayOrder,
      offers: const [],
    );
  }
}

class PartnerCategory {
  const PartnerCategory({
    required this.id,
    required this.nameFr,
    required this.nameEn,
    required this.icon,
  });

  final String id;
  final String nameFr;
  final String nameEn;
  final String icon;

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
    final normalizedId = id.trim().toLowerCase();
    for (final category in predefinedCategories) {
      if (category.id == normalizedId) return category;
    }
    return null;
  }
}
