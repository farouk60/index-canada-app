class SousCategorie {
  final String id;
  final String title;
  final String titleEn; // Nouvelle propriété pour la traduction anglaise
  final String image;   // Image par défaut (FR)
  final String imageEn; // Image anglais (si fournie)

  SousCategorie({
    required this.id,
    required this.title,
    required this.titleEn,
  required this.image,
  this.imageEn = '',
  });

  factory SousCategorie.fromJson(Map<String, dynamic> json) {
    try {
      // L'image peut être une String ou un objet Wix { src/url/... }
      String imageValueFr = '';
      dynamic rawImage = json['image'];
      
      if (rawImage == null || (rawImage is String && rawImage.isEmpty)) {
        // Fallback: certaines collections peuvent utiliser 'icon'
        rawImage = json['icon'];
      }

      if (rawImage is String) {
        imageValueFr = rawImage;
      } else if (rawImage is Map<String, dynamic>) {
        // Essayer plusieurs clés possibles pour Wix
        imageValueFr = rawImage['src'] ??
            rawImage['url'] ??
            rawImage['image'] ??
            rawImage['fileUrl'] ??
            rawImage['mediaUrl'] ??
            rawImage['filename'] ??
            rawImage['alt'] ??
            '';
            
        // Si on n'a toujours rien, essayer d'extraire depuis un objet imbriqué
        if (imageValueFr.isEmpty && rawImage.containsKey('media')) {
          final media = rawImage['media'];
          if (media is Map<String, dynamic>) {
            imageValueFr = media['src'] ?? media['url'] ?? '';
          }
        }
      }

      // Si l'image est vide, essayer d'autres champs comme fallback
      if (imageValueFr.isEmpty) {
        // Chercher dans d'autres champs possibles
        final fallbackFields = ['imageUrl', 'photo', 'picture', 'thumbnail'];
        for (String field in fallbackFields) {
          if (json.containsKey(field) && json[field] != null) {
            if (json[field] is String && json[field].isNotEmpty) {
              imageValueFr = json[field];
              break;
            } else if (json[field] is Map<String, dynamic>) {
              final fallbackObj = json[field] as Map<String, dynamic>;
              imageValueFr = fallbackObj['src'] ?? fallbackObj['url'] ?? '';
              if (imageValueFr.isNotEmpty) {
                break;
              }
            }
          }
        }
      }

      // Image anglaise (si disponible)
      String imageValueEn = '';
      dynamic rawImageEn = json['imageEn'] ?? json['imageEN'] ?? json['image_en'] ?? json['iconEn'] ?? json['iconEN'] ?? json['icon_en'];
      if (rawImageEn is String) {
        imageValueEn = rawImageEn;
      } else if (rawImageEn is Map<String, dynamic>) {
        imageValueEn = rawImageEn['src'] ?? rawImageEn['url'] ?? rawImageEn['image'] ?? rawImageEn['fileUrl'] ?? rawImageEn['mediaUrl'] ?? '';
      }

      return SousCategorie(
        id: json['_id']?.toString() ?? '',
        title: json['title']?.toString() ?? '',
        titleEn: json['titleEn']?.toString() ?? json['title']?.toString() ?? '',
        image: imageValueFr,
        imageEn: imageValueEn,
      );
    } catch (e) {
      print('Erreur lors de la création de SousCategorie depuis JSON: $e');
      return SousCategorie(
        id: '',
        title: 'Erreur de chargement',
        titleEn: 'Loading error',
        image: '',
        imageEn: '',
      );
    }
  }

  /// Obtenir le titre dans la langue spécifiée
  String getTitleInLanguage(String languageCode) {
    if (languageCode == 'en' && titleEn.isNotEmpty) {
      return titleEn;
    }
    return title;
  }

  /// Obtenir l'image selon la langue
  String getImageInLanguage(String languageCode) {
    if (languageCode == 'en' && imageEn.isNotEmpty) {
      return imageEn;
    }
    return image;
  }
}

class Professionnel {
  final String id;
  final String title;
  final String subtitle;
  final String ville;
  final String address;
  final String numroDeTlphone;
  final String image;
  final List<dynamic> gallery; // Nouvelle propriété pour la galerie (objets Wix ou strings)
  final String sousCategorie;
  final String plan; // Plan du professionnel (remplace sponsor)
  final double averageRating; // Note moyenne des avis
  final int reviewCount; // Nombre d'avis

  // Propriétés pour les coupons de réduction
  final String couponTitle; // Titre du coupon (français)
  final String couponTitleEN; // Titre du coupon en anglais
  final String couponCode; // Code du coupon
  final DateTime? couponExpirationDate; // Date d'expiration
  final String couponDescription; // Description du coupon (français)
  final String couponDescriptionEN; // Description du coupon (anglais)

  // Champs individuels pour les images de galerie (nouvelle stratégie)
  final String galerieImage1;
  final String galerieImage2;
  final String galerieImage3;
  final String galerieImage4;
  final String galerieImage5;

  // Champs pour les réseaux sociaux et contact
  final String email;
  final String website;
  final String facebook;
  final String instagram;
  final String linkedin;
  final String whatsapp;
  final String tiktok;
  final String youtube;

  // Champs pour le système de paiement et activation
  final bool isActive;
  final String paymentStatus; // 'pending', 'paid', 'failed'
  final String stripeCustomerId;
  final String stripeSubscriptionId;
  final DateTime? subscriptionExpiryDate;

  Professionnel({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.ville,
    required this.address,
    required this.numroDeTlphone,
    required this.image,
    required this.gallery,
    required this.sousCategorie,
    required this.plan,
    this.averageRating = 0.0,
    this.reviewCount = 0,
    this.couponTitle = '',
    this.couponTitleEN = '',
    this.couponCode = '',
    this.couponExpirationDate,
    this.couponDescription = '',
    this.couponDescriptionEN = '',
    this.galerieImage1 = '',
    this.galerieImage2 = '',
    this.galerieImage3 = '',
    this.galerieImage4 = '',
    this.galerieImage5 = '',
    this.email = '',
    this.website = '',
    this.facebook = '',
    this.instagram = '',
    this.linkedin = '',
    this.whatsapp = '',
    this.tiktok = '',
    this.youtube = '',
    this.isActive = false,
    this.paymentStatus = '',
    this.stripeCustomerId = '',
    this.stripeSubscriptionId = '',
    this.subscriptionExpiryDate,
  });

  factory Professionnel.fromJson(Map<String, dynamic> json) {
    try {
      // sousCatgorie peut être un String ou un Map
      String sousCategorieStr = '';
      if (json['sousCatgorie'] is String) {
        sousCategorieStr = json['sousCatgorie'] ?? '';
      } else if (json['sousCatgorie'] is Map) {
        sousCategorieStr = (json['sousCatgorie'] as Map<String, dynamic>?)?['_id']?.toString() ?? '';
      }

      // address peut être un String ou un Map complexe
      String addressStr = '';
      if (json['address'] is String) {
        addressStr = json['address'] ?? '';
      } else if (json['address'] is Map) {
        // Extraire l'adresse formatée de l'objet complexe
        final addressMap = json['address'] as Map<String, dynamic>?;
        if (addressMap != null) {
          addressStr =
              addressMap['formatted']?.toString() ??
              addressMap['streetAddress']?['formattedAddressLine']?.toString() ??
              '';
        }
      }

    // Traiter la galerie d'images (deux stratégies: ancienne avec mediagallery et nouvelle avec champs individuels)
    List<dynamic> galleryList = [];

    // STRATÉGIE 1: Chercher dans les nouveaux champs individuels
    final List<String> individualFields = [
      'galerieImage1',
      'galerieImage2',
      'galerieImage3',
      'galerieImage4',
      'galerieImage5',
    ];

    bool hasIndividualFields = false;
    for (final field in individualFields) {
      if (json[field] != null && json[field].toString().isNotEmpty) {
        hasIndividualFields = true;
        galleryList.add(json[field]);
      }
    }

    if (!hasIndividualFields) {
      // STRATÉGIE 2: Fallback vers mediagallery (ancienne stratégie)
      if (json['mediagallery'] != null) {
        final mediaGallery = json['mediagallery'];

        if (mediaGallery is List) {
          for (final item in mediaGallery) {
            if (item is String && item.isNotEmpty) {
              galleryList.add(item);
            } else if (item is Map<String, dynamic>) {
              final src =
                  item['src'] ??
                  item['url'] ??
                  item['image'] ??
                  item['fileUrl'] ??
                  item['mediaUrl'] ??
                  item['link'] ??
                  item['href'] ??
                  '';

              if (src != null && src.isNotEmpty) {
                galleryList.add(item);
              }
            }
          }
        } else if (mediaGallery is String && mediaGallery.isNotEmpty) {
          galleryList.add(mediaGallery);
        }
      }
    }

    // Fallback: chercher dans 'gallery'
    if (galleryList.isEmpty && json['gallery'] is List) {
      galleryList = (json['gallery'] as List)
          .where((item) => item != null && item.toString().isNotEmpty)
          .toList();
    }

    // Traiter la date d'expiration du coupon
    DateTime? couponExpiration;
    if (json['couponExpirationDate'] != null) {
      try {
        // Gestion différents formats de date Wix
        final dateValue = json['couponExpirationDate'];
        if (dateValue is String) {
          couponExpiration = DateTime.parse(dateValue);
        } else if (dateValue is Map && dateValue['\$date'] != null) {
          // Format Wix avec timestamp
          couponExpiration = DateTime.fromMillisecondsSinceEpoch(
            dateValue['\$date'],
          );
        }
      } catch (e) {
        // En cas d'erreur de parsing, ignorer la date
        couponExpiration = null;
      }
    }

    // Traiter l'image de profil (format unifié avec mediagallery)
    String imageUrl = '';
    if (json['image'] != null) {
      final imageData = json['image'];

      if (imageData is String && imageData.isNotEmpty) {
        // Ancien format: data URL directe
        imageUrl = imageData;
      } else if (imageData is Map<String, dynamic>) {
        // Nouveau format unifié: objet avec src
        imageUrl = imageData['src'] ?? '';
      }
    }

    final professionnel = Professionnel(
      id: json['_id'] ?? '',
      title: json['title'] ?? '',
      subtitle: json['subtitle'] ?? '',
      ville: json['ville'] ?? '',
      address: addressStr,
      numroDeTlphone: json['numroDeTlphone'] ?? '',
      image: imageUrl,
      gallery: galleryList,
      sousCategorie: sousCategorieStr,
      plan:
          json['plan']?.toString() ?? '', // Récupérer le plan du professionnel
      averageRating: (json['averageRating'] ?? 0.0).toDouble(),
      reviewCount: json['reviewCount'] ?? 0,
      couponTitle: _cleanHtmlString(json['couponTitle']?.toString() ?? ''),
      couponTitleEN: _cleanHtmlString(json['couponTitleEn']?.toString() ?? ''),
      couponCode: _safeStringFromJson(json['couponCode']),
      couponExpirationDate: couponExpiration,
      couponDescription: _cleanHtmlString(
        json['couponDescription']?.toString() ?? '',
      ),
      couponDescriptionEN: _cleanHtmlString(
        json['couponDescriptionEn']?.toString() ?? '',
      ),
      galerieImage1: _safeStringFromJson(json['galerieImage1']),
      galerieImage2: _safeStringFromJson(json['galerieImage2']),
      galerieImage3: _safeStringFromJson(json['galerieImage3']),
      galerieImage4: _safeStringFromJson(json['galerieImage4']),
      galerieImage5: _safeStringFromJson(json['galerieImage5']),
      email: _safeStringFromJson(json['email']),
      website: _safeStringFromJson(json['siteWeb']),
      facebook: _safeStringFromJson(json['lienFacebook']),
      instagram: _safeStringFromJson(json['lienInstagram']),
      linkedin: _safeStringFromJson(json['linkedin']),
      whatsapp: _safeStringFromJson(json['lienWhatsapp']),
      tiktok: _safeStringFromJson(json['lienTiktok']),
      youtube: _safeStringFromJson(json['lienYoutube']),
      isActive: json['isActive'] ?? false,
      paymentStatus: _safeStringFromJson(json['paymentStatus']),
      stripeCustomerId: _safeStringFromJson(json['stripeCustomerId']),
      stripeSubscriptionId: _safeStringFromJson(json['stripeSubscriptionId']),
      subscriptionExpiryDate: _parseDateFromJson(
        json['subscriptionExpiryDate'],
      ),
    );

    return professionnel;
  } catch (e) {
    print('Erreur lors de la création de Professionnel depuis JSON: $e');
    print('JSON problématique: ${json.toString()}');
    
    // Retourner un professionnel avec des valeurs par défaut
    return Professionnel(
      id: json['_id']?.toString() ?? '',
      title: json['title']?.toString() ?? 'Erreur de chargement',
      subtitle: json['subtitle']?.toString() ?? '',
      ville: json['ville']?.toString() ?? '',
      address: '',
      numroDeTlphone: json['numroDeTlphone']?.toString() ?? '',
      image: '',
      gallery: [],
      sousCategorie: '',
      plan: json['plan']?.toString() ?? '',
    );
  }
  }

  /// Obtenir le titre du coupon dans la langue spécifiée
  String getCouponTitleInLanguage(String languageCode) {
    if (languageCode == 'en' && couponTitleEN.isNotEmpty) {
      return couponTitleEN;
    }
    return couponTitle.isNotEmpty ? couponTitle : couponTitleEN;
  }

  /// Obtenir la description du coupon dans la langue spécifiée
  String getCouponDescriptionInLanguage(String languageCode) {
    if (languageCode == 'en' && couponDescriptionEN.isNotEmpty) {
      return couponDescriptionEN; // Description anglaise
    }
    return couponDescription.isNotEmpty
        ? couponDescription
        : couponDescriptionEN;
  }

  /// Vérifier si le professionnel est en vedette (basé sur le plan)
  bool get isFeatured {
    if (plan.isEmpty) return false;

    // Les plans qui donnent le statut "en vedette"
    final featuredPlans = [
      'sponsor',
      'premium',
      'professional',
      'featured',
      'vedette',
    ];
    return featuredPlans.contains(plan.toLowerCase());
  }

  /// Vérifier si le professionnel a un plan actif (pour rétrocompatibilité)
  bool get sponsor => isFeatured;

  /// Obtenir toutes les images de galerie (champs individuels + ancienne galerie)
  List<String> getAllGalleryImages() {
    final List<String> allImages = [];

    // ÉTAPE 1: Ajouter les champs individuels non vides
    if (galerieImage1.isNotEmpty) allImages.add(galerieImage1);
    if (galerieImage2.isNotEmpty) allImages.add(galerieImage2);
    if (galerieImage3.isNotEmpty) allImages.add(galerieImage3);
    if (galerieImage4.isNotEmpty) allImages.add(galerieImage4);
    if (galerieImage5.isNotEmpty) allImages.add(galerieImage5);

    // ÉTAPE 2: Ajouter les images de l'ancienne galerie (mediagallery)
    for (final item in gallery) {
      String? imageUrl;

      if (item is String && item.isNotEmpty) {
        imageUrl = item;
      } else if (item is Map<String, dynamic>) {
        // Chercher l'URL dans différents champs possibles
        imageUrl =
            item['src'] ??
            item['url'] ??
            item['image'] ??
            item['fileUrl'] ??
            item['mediaUrl'] ??
            '';
      }

      // Ajouter seulement si l'image n'est pas déjà présente
      if (imageUrl != null &&
          imageUrl.isNotEmpty &&
          !allImages.contains(imageUrl)) {
        allImages.add(imageUrl);
      }
    }

    return allImages;
  }

  /// Obtenir le nombre d'images de galerie
  int getGalleryImageCount() {
    return getAllGalleryImages().length;
  }

  /// Vérifier si le professionnel a des images de galerie
  bool hasGalleryImages() {
    return getGalleryImageCount() > 0;
  }

  // Fonction utilitaire pour nettoyer les chaînes HTML
  static String _cleanHtmlString(String? htmlString) {
    if (htmlString == null || htmlString.isEmpty) return '';

    // Supprimer les balises HTML simples
    String cleaned = htmlString
        .replaceAll(RegExp(r'<[^>]*>'), '') // Supprimer toutes les balises HTML
        .replaceAll('&nbsp;', ' ') // Remplacer les espaces insécables
        .replaceAll('&amp;', '&') // Remplacer les entités HTML
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .trim(); // Supprimer les espaces en début/fin

    return cleaned;
  }

  // Fonction utilitaire pour convertir de manière sûre en String
  static String _safeStringFromJson(dynamic value) {
    if (value == null) return '';
    if (value is String) return value;
    try {
      return value.toString();
    } catch (e) {
      return '';
    }
  }

  // Fonction utilitaire pour parser les dates
  static DateTime? _parseDateFromJson(dynamic value) {
    if (value == null) return null;
    try {
      if (value is String) {
        return DateTime.parse(value);
      } else if (value is Map && value['\$date'] != null) {
        return DateTime.fromMillisecondsSinceEpoch(value['\$date']);
      }
    } catch (e) {
      // En cas d'erreur de parsing, retourner null
    }
    return null;
  }
}

class Review {
  final String id;
  final String professionalId;
  final String auteurNom;
  final int rating;
  final String message;
  final String title;

  Review({
    required this.id,
    required this.professionalId,
    required this.auteurNom,
    required this.rating,
    required this.message,
    required this.title,
  });

  factory Review.fromJson(Map<String, dynamic> json) {
    return Review(
      id: json['_id'] ?? '',
      professionalId: json['professionalId'] ?? '',
      auteurNom: json['auteurNom'] ?? '',
      rating: (json['rating'] is int)
          ? json['rating']
          : int.tryParse(json['rating']?.toString() ?? '0') ?? 0,
      message: json['message'] ?? '',
      title: json['title'] ?? '',
    );
  }
}
