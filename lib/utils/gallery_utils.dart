import 'dart:convert';
import 'package:flutter/material.dart';

/// Fonction utilitaire pour construire une galerie média à partir d'un professionnel
/// Gère les formats d'objets Wix avec src, title, type, settings
Widget buildMediaGallery(
  dynamic professional, {
  double height = 200.0,
  double width = 160.0,
}) {
  List<dynamic> mediaGallery = [];

  // Récupération sécurisée de la galerie
  if (professional != null && professional["mediagallery"] != null) {
    final gallery = professional["mediagallery"];
    if (gallery is List && gallery.isNotEmpty) {
      mediaGallery = gallery;
    }
  }

  // Si aucune image, afficher un message
  if (mediaGallery.isEmpty) {
    return SizedBox(
      height: height,
      child: const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.image_not_supported, size: 48, color: Colors.grey),
            SizedBox(height: 8),
            Text(
              "Aucune image disponible",
              style: TextStyle(color: Colors.grey, fontSize: 16),
            ),
          ],
        ),
      ),
    );
  }

  return SizedBox(
    height: height,
    child: ListView.builder(
      scrollDirection: Axis.horizontal,
      itemCount: mediaGallery.length,
      itemBuilder: (context, index) {
        final imageObj = mediaGallery[index];

        // Extraire le src depuis l'objet
        String? src;
        if (imageObj is String) {
          // Format ancien: string directe
          src = imageObj;
        } else if (imageObj is Map<String, dynamic>) {
          // Format Wix: objet avec src, title, type, settings
          src = imageObj['src'];
        }

        Widget imageWidget;

        if (src != null && src.startsWith("data:image")) {
          // Cas Base64
          try {
            final base64String = src.split(',').last;
            final bytes = base64Decode(base64String);
            imageWidget = Image.memory(
              bytes,
              width: width,
              height: height,
              fit: BoxFit.cover,
            );
          } catch (e) {
            imageWidget = _buildErrorImage(width, height);
          }
        } else if (src != null && src.startsWith("http")) {
          // Cas URL
          imageWidget = Image.network(
            src,
            width: width,
            height: height,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) =>
                _buildErrorImage(width, height),
          );
        } else {
          imageWidget = _buildErrorImage(width, height);
        }

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8.0),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: imageWidget,
          ),
        );
      },
    ),
  );
}

/// Widget d'erreur pour les images manquantes
Widget _buildErrorImage(double width, double height) {
  return Container(
    width: width,
    height: height,
    color: Colors.grey[300],
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.broken_image, color: Colors.grey[700], size: 40),
        const SizedBox(height: 8),
        const Text(
          'Image\nindisponible',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.grey, fontSize: 12),
        ),
      ],
    ),
  );
}

/// Fonction pour extraire les URLs d'images depuis un objet professionnel
/// Retourne une liste de strings utilisable avec un widget d'images classique
List<String> extractImageUrls(dynamic professional) {
  List<String> imageUrls = [];

  if (professional != null && professional["mediagallery"] != null) {
    final gallery = professional["mediagallery"];
    if (gallery is List) {
      for (final item in gallery) {
        if (item is String && item.isNotEmpty) {
          imageUrls.add(item);
        } else if (item is Map<String, dynamic>) {
          final src = item['src'];
          if (src is String && src.isNotEmpty) {
            imageUrls.add(src);
          }
        }
      }
    }
  }

  return imageUrls;
}
