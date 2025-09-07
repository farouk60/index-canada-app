import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:crypto/crypto.dart';

class ReviewVerificationService {
  static final ReviewVerificationService _instance =
      ReviewVerificationService._internal();
  factory ReviewVerificationService() => _instance;
  ReviewVerificationService._internal();

  // Durée de cooldown entre les avis (en minutes)
  static const int cooldownMinutes = 30;

  // Mots-clés suspects pour la détection de spam
  static const List<String> spamKeywords = [
    'www.',
    'http',
    'https',
    '.com',
    '.fr',
    '.ca',
    'email',
    'telephone',
    'whatsapp',
    'telegram',
    'contact',
    'promo',
    'discount',
    'gratuit',
    'free',
    'offre',
    'urgent',
    'cliquez',
    'visitez',
    'site',
    'argent',
    'money',
    'bitcoin',
  ];

  /// Vérifie si un utilisateur peut poster un avis
  Future<ReviewVerificationResult> canPostReview(
    String professionalId,
    String authorName,
    String message,
    String title,
  ) async {
    // 1. Vérifier le cooldown
    final cooldownResult = await _checkCooldown(professionalId, authorName);
    if (!cooldownResult.canPost) {
      await _recordBlockedAttempt(
        cooldownResult.reason,
        professionalId,
        authorName,
      );
      return cooldownResult;
    }

    // 2. Vérifier le contenu pour spam
    final spamResult = _checkForSpam(message, title, authorName);
    if (!spamResult.canPost) {
      await _recordBlockedAttempt(
        spamResult.reason,
        professionalId,
        authorName,
      );
      return spamResult;
    }

    // 3. Vérifier la qualité du contenu
    final qualityResult = _checkContentQuality(message, title);
    if (!qualityResult.canPost) {
      await _recordBlockedAttempt(
        qualityResult.reason,
        professionalId,
        authorName,
      );
      return qualityResult;
    }

    // 4. Vérifier les doublons
    final duplicateResult = await _checkForDuplicates(
      professionalId,
      message,
      authorName,
    );
    if (!duplicateResult.canPost) {
      await _recordBlockedAttempt(
        duplicateResult.reason,
        professionalId,
        authorName,
      );
      return duplicateResult;
    }

    return ReviewVerificationResult(
      canPost: true,
      reason: 'Avis valide',
      severity: VerificationSeverity.success,
    );
  }

  /// Enregistre qu'un avis a été posté
  Future<void> recordReviewPost(
    String professionalId,
    String authorName,
    String message,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final timestamp = DateTime.now().millisecondsSinceEpoch;

    // Créer une clé unique pour cet utilisateur et ce professionnel
    final userKey = _createUserKey(authorName);
    final reviewKey = 'review_${userKey}_${professionalId}_$timestamp';

    await prefs.setString(
      reviewKey,
      jsonEncode({
        'timestamp': timestamp,
        'professionalId': professionalId,
        'authorName': authorName,
        'messageHash': _hashString(message),
      }),
    );

    // Nettoyer les anciennes entrées (plus de 24h)
    await _cleanupOldEntries();
  }

  /// Vérifie le cooldown
  Future<ReviewVerificationResult> _checkCooldown(
    String professionalId,
    String authorName,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final userKey = _createUserKey(authorName);
    final currentTime = DateTime.now().millisecondsSinceEpoch;

    // Vérifier tous les avis récents de cet utilisateur
    final allKeys = prefs.getKeys();
    for (String key in allKeys) {
      if (key.startsWith('review_$userKey')) {
        final reviewData = prefs.getString(key);
        if (reviewData != null) {
          final data = jsonDecode(reviewData);
          final timestamp = data['timestamp'] as int;
          final minutesAgo = (currentTime - timestamp) / (1000 * 60);

          if (minutesAgo < cooldownMinutes) {
            final remainingMinutes = (cooldownMinutes - minutesAgo).ceil();
            return ReviewVerificationResult(
              canPost: false,
              reason:
                  'Vous devez attendre $remainingMinutes minutes avant de pouvoir poster un nouvel avis.',
              severity: VerificationSeverity.warning,
            );
          }
        }
      }
    }

    return ReviewVerificationResult(canPost: true, reason: 'Cooldown OK');
  }

  /// Vérifie le contenu pour détecter le spam
  ReviewVerificationResult _checkForSpam(
    String message,
    String title,
    String authorName,
  ) {
    final fullText = '$message $title $authorName'.toLowerCase();

    // Vérifier les mots-clés suspects
    for (String keyword in spamKeywords) {
      if (fullText.contains(keyword.toLowerCase())) {
        return ReviewVerificationResult(
          canPost: false,
          reason:
              'Contenu suspect détecté. Veuillez éviter les liens et informations de contact.',
          severity: VerificationSeverity.error,
        );
      }
    }

    // Vérifier la répétition excessive de caractères
    if (_hasExcessiveRepetition(fullText)) {
      return ReviewVerificationResult(
        canPost: false,
        reason: 'Contenu suspect : répétition excessive de caractères.',
        severity: VerificationSeverity.error,
      );
    }

    // Vérifier si le texte est entièrement en majuscules
    if (message.length > 20 && message == message.toUpperCase()) {
      return ReviewVerificationResult(
        canPost: false,
        reason: 'Veuillez éviter d\'écrire entièrement en majuscules.',
        severity: VerificationSeverity.warning,
      );
    }

    return ReviewVerificationResult(canPost: true, reason: 'Contenu valide');
  }

  /// Vérifie la qualité du contenu
  ReviewVerificationResult _checkContentQuality(String message, String title) {
    // Vérifier la longueur minimale
    if (message.trim().length < 10) {
      return ReviewVerificationResult(
        canPost: false,
        reason: 'Votre commentaire doit contenir au moins 10 caractères.',
        severity: VerificationSeverity.error,
      );
    }

    // Vérifier que le message contient des mots réels
    final words = message.trim().split(RegExp(r'\s+'));
    if (words.length < 3) {
      return ReviewVerificationResult(
        canPost: false,
        reason: 'Votre commentaire doit contenir au moins 3 mots.',
        severity: VerificationSeverity.error,
      );
    }

    // Vérifier que ce n'est pas juste des caractères répétés
    if (_isJustRepeatedCharacters(message)) {
      return ReviewVerificationResult(
        canPost: false,
        reason: 'Veuillez écrire un commentaire constructif.',
        severity: VerificationSeverity.error,
      );
    }

    return ReviewVerificationResult(canPost: true, reason: 'Qualité OK');
  }

  /// Vérifie les doublons
  Future<ReviewVerificationResult> _checkForDuplicates(
    String professionalId,
    String message,
    String authorName,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final userKey = _createUserKey(authorName);
    final messageHash = _hashString(message);

    // Vérifier les avis récents de cet utilisateur
    final allKeys = prefs.getKeys();
    for (String key in allKeys) {
      if (key.startsWith('review_$userKey')) {
        final reviewData = prefs.getString(key);
        if (reviewData != null) {
          final data = jsonDecode(reviewData);

          // Vérifier le même professionnel
          if (data['professionalId'] == professionalId) {
            return ReviewVerificationResult(
              canPost: false,
              reason: 'Vous avez déjà posté un avis pour ce professionnel.',
              severity: VerificationSeverity.error,
            );
          }

          // Vérifier le contenu similaire
          if (data['messageHash'] == messageHash) {
            return ReviewVerificationResult(
              canPost: false,
              reason: 'Vous avez déjà posté un avis similaire.',
              severity: VerificationSeverity.error,
            );
          }
        }
      }
    }

    return ReviewVerificationResult(canPost: true, reason: 'Pas de doublon');
  }

  /// Crée une clé unique pour un utilisateur
  String _createUserKey(String authorName) {
    return _hashString(authorName.toLowerCase().trim());
  }

  /// Crée un hash d'une chaîne
  String _hashString(String input) {
    var bytes = utf8.encode(input);
    var digest = sha256.convert(bytes);
    return digest.toString().substring(
      0,
      16,
    ); // Prendre les 16 premiers caractères
  }

  /// Vérifie la répétition excessive
  bool _hasExcessiveRepetition(String text) {
    if (text.length < 10) return false;

    // Vérifier les caractères répétés
    for (int i = 0; i < text.length - 4; i++) {
      String char = text[i];
      int count = 1;
      for (int j = i + 1; j < text.length && j < i + 10; j++) {
        if (text[j] == char) {
          count++;
        } else {
          break;
        }
      }
      if (count > 4) return true;
    }

    return false;
  }

  /// Vérifie si c'est juste des caractères répétés
  bool _isJustRepeatedCharacters(String text) {
    if (text.length < 5) return false;

    final cleanText = text.replaceAll(RegExp(r'\s+'), '');
    if (cleanText.length < 3) return true;

    // Vérifier si plus de 70% du texte est constitué du même caractère
    final charCounts = <String, int>{};
    for (String char in cleanText.split('')) {
      charCounts[char] = (charCounts[char] ?? 0) + 1;
    }

    final maxCount = charCounts.values.reduce((a, b) => a > b ? a : b);
    return maxCount / cleanText.length > 0.7;
  }

  /// Nettoie les anciennes entrées
  Future<void> _cleanupOldEntries() async {
    final prefs = await SharedPreferences.getInstance();
    final currentTime = DateTime.now().millisecondsSinceEpoch;
    const maxAge = 24 * 60 * 60 * 1000; // 24 heures en millisecondes

    final allKeys = prefs.getKeys();
    final keysToRemove = <String>[];

    for (String key in allKeys) {
      if (key.startsWith('review_')) {
        final reviewData = prefs.getString(key);
        if (reviewData != null) {
          try {
            final data = jsonDecode(reviewData);
            final timestamp = data['timestamp'] as int;
            if (currentTime - timestamp > maxAge) {
              keysToRemove.add(key);
            }
          } catch (e) {
            // Supprimer les entrées corrompues
            keysToRemove.add(key);
          }
        }
      }
    }

    for (String key in keysToRemove) {
      await prefs.remove(key);
    }
  }

  /// Enregistre une tentative bloquée pour les statistiques
  Future<void> _recordBlockedAttempt(
    String reason,
    String professionalId,
    String authorName,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final timestamp = DateTime.now().millisecondsSinceEpoch;

    final blockedKey =
        'blocked_review_${timestamp}_${_createUserKey(authorName)}';
    await prefs.setString(
      blockedKey,
      jsonEncode({
        'timestamp': timestamp,
        'reason': reason,
        'professionalId': professionalId,
        'authorName': authorName,
      }),
    );
  }
}

/// Résultat de la vérification d'un avis
class ReviewVerificationResult {
  final bool canPost;
  final String reason;
  final VerificationSeverity severity;

  ReviewVerificationResult({
    required this.canPost,
    required this.reason,
    this.severity = VerificationSeverity.info,
  });
}

/// Niveau de sévérité de la vérification
enum VerificationSeverity { success, info, warning, error }
