String _stringValue(Object? value) => value?.toString().trim() ?? '';

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

bool _boolValue(Object? value) {
  if (value is bool) return value;
  if (value is num) return value != 0;
  if (value is String) {
    return switch (value.trim().toLowerCase()) {
      'true' || '1' => true,
      _ => false,
    };
  }
  return false;
}

DateTime? _dateValue(Object? value) {
  final raw = _stringValue(value);
  return raw.isEmpty ? null : DateTime.tryParse(raw);
}

/// Modèle immuable pour une offre de partenaire Wix.
class WixOffer {
  const WixOffer({
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

  /// Crée une offre à partir d'une réponse Wix, sans faire confiance aux types.
  factory WixOffer.fromWixData(Map<String, dynamic> data) {
    final title = _stringValue(data['title']);
    final description = _stringValue(data['description']);
    final titleEn = _stringValue(data['titleEn']);
    final descriptionEn = _stringValue(data['descriptionEn']);

    return WixOffer(
      id: _stringValue(data['_id'] ?? data['id']),
      title: title,
      titleEn: titleEn.isEmpty ? title : titleEn,
      description: description,
      descriptionEn: descriptionEn.isEmpty ? description : descriptionEn,
      image: _mediaValue(data['image']),
      link: _stringValue(data['link']),
      startDate: _dateValue(data['startDate']),
      endDate: _dateValue(data['endDate']),
      isExclusive: _boolValue(data['isExclusive']),
      isRecommended: _boolValue(data['isRecommended']),
      partnerId: _stringValue(data['partnerId']),
    );
  }

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

  bool isValidAt(DateTime now) {
    if (startDate != null && now.isBefore(startDate!)) return false;
    if (endDate != null && now.isAfter(endDate!)) return false;
    return true;
  }

  /// Vérifie la fenêtre de publication complète, début et fin inclus.
  bool get isValid => isValidAt(DateTime.now());

  /// Vérifier si l'offre expire bientôt (dans les 7 prochains jours)
  bool isExpiringSoonAt(DateTime now) {
    if (endDate == null) return false;
    final remaining = endDate!.difference(now);
    return !remaining.isNegative && remaining <= const Duration(days: 7);
  }

  bool get isExpiringSoon => isExpiringSoonAt(DateTime.now());

  @override
  String toString() =>
      'WixOffer(id: $id, title: $title, isExclusive: $isExclusive, isValid: $isValid)';
}
