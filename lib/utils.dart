// Cache simple (versionné) pour éviter les appels répétés
const String _imageCacheVersion = 'v2';
final Map<String, String> _imageUrlCache = {};

String getValidImageUrl(String imageUrl) {
  // ⚠️ CACHE: Vérifier si l'URL a déjà été traitée (clé versionnée)
  final cacheKey = '$_imageCacheVersion|$imageUrl';
  if (_imageUrlCache.containsKey(cacheKey)) {
    return _imageUrlCache[cacheKey]!;
  }

  String result;

  if (imageUrl.isEmpty) {
    result = '';
  } else if (imageUrl.startsWith('data:image/')) {
    // Gérer les data URLs (base64)
    result = imageUrl;
  } else if (imageUrl.startsWith('wix:image://')) {
    // Gérer les URLs Wix (avec nom de fichier et paramètres de fit pour meilleure compatibilité)
    final regex = RegExp(r'wix:image://v1/([^/]+)/([^#]+)(?:#(.+))?');
    final match = regex.firstMatch(imageUrl);

    if (match != null) {
      final wixId = match.group(1);
      final rawFileName = match.group(2);
      // Sécuriser le nom de fichier: décoder puis ré-encoder pour gérer ' et autres caractères
      String safeFileName;
      try {
        final decoded = Uri.decodeComponent(rawFileName ?? '');
        safeFileName = Uri.encodeComponent(decoded);
      } catch (_) {
        // Fallback: encoder directement si le décodage échoue
        safeFileName = Uri.encodeComponent(rawFileName ?? '');
      }
      final params = match.group(3);

      // Dimensions raisonnables pour des vignettes/grilles
      int targetW = 512;
      int targetH = 512;
      // Si on a les dimensions d'origine, limiter proportionnellement
      if (params != null && params.isNotEmpty) {
        final widthMatch = RegExp(r'originWidth=(\d+)').firstMatch(params);
        final heightMatch = RegExp(r'originHeight=(\d+)').firstMatch(params);
        if (widthMatch != null && heightMatch != null) {
          final ow = int.tryParse(widthMatch.group(1) ?? '0') ?? 0;
          final oh = int.tryParse(heightMatch.group(1) ?? '0') ?? 0;
          if (ow > 0 && oh > 0) {
            // Conserver l'aspect tout en plafonnant à 512
            final scale = (ow > oh ? 512 / ow : 512 / oh).clamp(0.0, 1.0);
            targetW = (ow * scale).round().clamp(64, 1024);
            targetH = (oh * scale).round().clamp(64, 1024);
          }
        }
      }

  result = 'https://static.wixstatic.com/media/$wixId/v1/fit/w_${targetW},h_${targetH},q_85/$safeFileName';
    } else {
      // Fallback vers l'ancienne méthode (sans nom de fichier)
      final basicRegex = RegExp(r'wix:image://v1/([^/]+)');
      final basicMatch = basicRegex.firstMatch(imageUrl);
      if (basicMatch != null) {
        final wixId = basicMatch.group(1);
        result = 'https://static.wixstatic.com/media/$wixId';
      } else {
        result = '';
      }
    }
  } else if (imageUrl.startsWith('http://') ||
      imageUrl.startsWith('https://')) {
    // Gérer les URLs web normales
    result = imageUrl;
  } else {
    // Retourner l'URL telle quelle
    result = imageUrl;
  }

  // ⚠️ CACHE: Sauvegarder le résultat
  _imageUrlCache[cacheKey] = result;

  return result;
}

String getHighQualityImageUrl(String imageUrl) {
  print(
    '🔍 getHighQualityImageUrl -> Input: ${imageUrl.substring(0, imageUrl.length.clamp(0, 100))}...',
  );

  if (imageUrl.isEmpty) {
    print('❌ getHighQualityImageUrl -> URL vide');
    return '';
  }

  // Gérer les data URLs (base64)
  if (imageUrl.startsWith('data:image/')) {
    print(
      '✅ getHighQualityImageUrl -> Data URL détectée: ${imageUrl.substring(0, 50)}...',
    );
    return imageUrl;
  }

  // Gérer les URLs Wix avec qualité MAXIMALE pour plein écran
  if (imageUrl.startsWith('wix:image://')) {
    print('🔄 getHighQualityImageUrl -> URL Wix détectée');

    // Nouvelle regex pour capturer l'ID, le nom du fichier et les paramètres
    final regex = RegExp(r'wix:image://v1/([^/]+)/([^#]+)(?:#(.+))?');
    final match = regex.firstMatch(imageUrl);

    if (match != null) {
      final wixId = match.group(1);
      final fileName = match.group(2);
      final params = match.group(3);

      // Pour l'affichage plein écran, utiliser des dimensions et qualité maximales
      String convertedUrl = 'https://static.wixstatic.com/media/$wixId';

      // Si on a des paramètres d'origine, utiliser des dimensions très élevées
      if (params != null && params.isNotEmpty) {
        final widthMatch = RegExp(r'originWidth=(\d+)').firstMatch(params);
        final heightMatch = RegExp(r'originHeight=(\d+)').firstMatch(params);

        if (widthMatch != null && heightMatch != null) {
          final width = int.parse(widthMatch.group(1)!);
          final height = int.parse(heightMatch.group(1)!);

          // LIMITE MAXIMALE pour éviter les erreurs de chargement
          // Essayer d'abord des dimensions plus petites pour les grosses images
          const maxAllowedWidth = 1200;
          const maxAllowedHeight = 1200;

          final limitedWidth = width > maxAllowedWidth
              ? maxAllowedWidth
              : width;
          final limitedHeight = height > maxAllowedHeight
              ? maxAllowedHeight
              : height;

          print(
            '🎯 Dimensions: original=${width}x$height, limitées=${limitedWidth}x$limitedHeight',
          );

          // Pour les très grosses images (>3000px), utiliser l'URL originale
          if (width > 3000 || height > 3000) {
            print('⚠️ Image très large détectée, utilisation URL originale');
            return convertedUrl;
          }

          convertedUrl +=
              '/v1/fit/w_$limitedWidth,h_$limitedHeight,q_85/$fileName';
        } else {
          // Fallback haute résolution mais raisonnable
          convertedUrl += '/v1/fit/w_1920,h_1920,q_95/$fileName';
        }
      } else {
        // Fallback original sans traitement
        print(
          '🎯 getHighQualityImageUrl -> Utilisation originale sans traitement',
        );
        return convertedUrl;
      }

      print('✅ getHighQualityImageUrl -> URL Wix haute qualité: $convertedUrl');
      return convertedUrl;
    }

    // Fallback vers l'ancienne méthode si la nouvelle regex échoue
    final basicRegex = RegExp(r'wix:image://v1/([^/]+)');
    final basicMatch = basicRegex.firstMatch(imageUrl);
    if (basicMatch != null) {
      final wixId = basicMatch.group(1);
      final convertedUrl = 'https://static.wixstatic.com/media/$wixId';
      print(
        '✅ getHighQualityImageUrl -> URL Wix convertie (basique): $convertedUrl',
      );
      return convertedUrl;
    }

    print('❌ getHighQualityImageUrl -> URL Wix invalide');
    return '';
  }

  // Gérer les URLs web normales
  if (imageUrl.startsWith('http://') || imageUrl.startsWith('https://')) {
    print('✅ getHighQualityImageUrl -> URL web normale: $imageUrl');
    return imageUrl;
  }

  // Retourner l'URL telle quelle si elle ne correspond à aucun pattern connu
  print(
    '⚠️ getHighQualityImageUrl -> URL inconnue, retournée telle quelle: $imageUrl',
  );
  return imageUrl;
}

/// Génère plusieurs variantes d'URL pour un meilleur fallback
List<String> getWixImageVariants(String imageUrl) {
  final variants = <String>[];

  if (!imageUrl.startsWith('wix:image://')) {
    return [imageUrl];
  }

  final regex = RegExp(r'wix:image://v1/([^/]+)/([^#]+)(?:#(.+))?');
  final match = regex.firstMatch(imageUrl);

  if (match != null) {
    final wixId = match.group(1);
    final fileName = match.group(2);
    final baseUrl = 'https://static.wixstatic.com/media/$wixId';

    // Stratégie optimisée : commencer par les petites tailles pour un chargement rapide
    
    // Variante 1: Très petite taille pour aperçu instantané
    variants.add('$baseUrl/v1/fit/w_400,h_300,q_70/$fileName');
    
    // Variante 2: Petite taille optimisée pour mobile
    variants.add('$baseUrl/v1/fit/w_600,h_450,q_75/$fileName');

    // Variante 3: Taille moyenne avec bonne qualité
    variants.add('$baseUrl/v1/fit/w_800,h_600,q_80/$fileName');

    // Variante 4: URL originale sans traitement (fallback final)
    variants.add(baseUrl);

    // Réduire les logs pour éviter de surcharger le système
    if (fileName != null && (fileName.contains('Entretien') || fileName.contains('Agence') || fileName.contains('Agent'))) {
      print('🔄 Variantes optimisées pour $fileName: ${variants.length}');
    }
  }

  return variants;
}

/// Construit une URL Wix redimensionnée aux dimensions cibles (fit) avec qualité donnée.
/// Si l'URL n'est pas Wix, retourne getValidImageUrl(imageUrl).
String getWixFittedUrl(String imageUrl, {required int targetW, required int targetH, int quality = 80}) {
  if (!imageUrl.startsWith('wix:image://')) {
    return getValidImageUrl(imageUrl);
  }

  final regex = RegExp(r'wix:image://v1/([^/]+)/([^#]+)(?:#(.+))?');
  final match = regex.firstMatch(imageUrl);
  if (match == null) {
    return getValidImageUrl(imageUrl);
  }

  final wixId = match.group(1);
  final rawFileName = match.group(2) ?? '';
  String safeFileName;
  try {
    final decoded = Uri.decodeComponent(rawFileName);
    safeFileName = Uri.encodeComponent(decoded);
  } catch (_) {
    safeFileName = Uri.encodeComponent(rawFileName);
  }

  // Clamp raisonnable pour éviter des images trop lourdes
  final w = targetW.clamp(64, 2000);
  final h = targetH.clamp(64, 2000);
  final q = quality.clamp(50, 95);

  return 'https://static.wixstatic.com/media/$wixId/v1/fit/w_${w},h_${h},q_${q}/$safeFileName';
}
