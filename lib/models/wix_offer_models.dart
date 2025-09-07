/// Modèle pour une offre exclusive de partenaire Wix
class WixOffer {
  final String id;
  final String title;
  final String titleEn;
  final String description;
  final String descriptionEn;
  final String image;
  final String link;
  final DateTime? startDate;
  final DateTime? endDate;
  final bool isExclusive;
  final bool isRecommended;
  final String partnerId;

  WixOffer({
    required this.id,
    required this.title,
    required this.titleEn,
    required this.description,
    required this.descriptionEn,
    required this.image,
    required this.link,
    this.startDate,
    this.endDate,
    required this.isExclusive,
    required this.isRecommended,
    required this.partnerId,
  });

  /// Factory pour créer depuis les données Wix
  factory WixOffer.fromWixData(Map<String, dynamic> data) {
    return WixOffer(
      id: data['_id'] ?? '',
      title: data['title'] ?? '',
      titleEn: data['titleEn'] ?? '',
      description: data['description'] ?? '',
      descriptionEn: data['descriptionEn'] ?? '',
      image: data['image'] ?? '',
      link: data['link'] ?? '',
      startDate: data['startDate'] != null
          ? DateTime.tryParse(data['startDate'].toString())
          : null,
      endDate: data['endDate'] != null
          ? DateTime.tryParse(data['endDate'].toString())
          : null,
      isExclusive: data['isExclusive'] ?? false,
      isRecommended: data['isRecommended'] ?? false,
      partnerId: data['partnerId'] ?? '',
    );
  }

  /// Obtenir le titre dans la langue actuelle
  String getTitleInLanguage(String languageCode) {
    return languageCode == 'en' && titleEn.isNotEmpty ? titleEn : title;
  }

  /// Obtenir la description dans la langue actuelle
  String getDescriptionInLanguage(String languageCode) {
    return languageCode == 'en' && descriptionEn.isNotEmpty
        ? descriptionEn
        : description;
  }

  /// Vérifier si l'offre est encore valide
  bool get isValid {
    final now = DateTime.now();
    // TEMPORAIRE : Accepter les offres futures pour test
    // if (startDate != null && now.isBefore(startDate!)) return false;
    if (endDate != null && now.isAfter(endDate!)) return false;
    return true;
  }

  /// Vérifier si l'offre expire bientôt (dans les 7 prochains jours)
  bool get isExpiringSoon {
    if (endDate == null) return false;
    final now = DateTime.now();
    final daysUntilExpiry = endDate!.difference(now).inDays;
    return daysUntilExpiry <= 7 && daysUntilExpiry >= 0;
  }

  @override
  String toString() =>
      'WixOffer(id: $id, title: $title, isExclusive: $isExclusive, isValid: $isValid)';
}
