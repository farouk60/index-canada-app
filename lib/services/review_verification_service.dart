import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ReviewVerificationService {
  static const String _installationSaltKey = 'review_verification_salt_v1';

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
        cooldownResult.code.name,
        professionalId,
        authorName,
      );
      return cooldownResult;
    }

    // 2. Vérifier le contenu pour spam
    final spamResult = _checkForSpam(message, title, authorName);
    if (!spamResult.canPost) {
      await _recordBlockedAttempt(
        spamResult.code.name,
        professionalId,
        authorName,
      );
      return spamResult;
    }

    // 3. Vérifier la qualité du contenu
    final qualityResult = _checkContentQuality(message);
    if (!qualityResult.canPost) {
      await _recordBlockedAttempt(
        qualityResult.code.name,
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
        duplicateResult.code.name,
        professionalId,
        authorName,
      );
      return duplicateResult;
    }

    return const ReviewVerificationResult.allowed();
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
    final userKey = await _createUserKey(authorName);
    final reviewKey = 'review_${userKey}_${professionalId}_$timestamp';

    await prefs.setString(
      reviewKey,
      jsonEncode({
        'timestamp': timestamp,
        'professionalId': professionalId,
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
    final userKey = await _createUserKey(authorName);
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
              code: ReviewVerificationCode.cooldown,
              remainingMinutes: remainingMinutes,
              severity: VerificationSeverity.warning,
            );
          }
        }
      }
    }

    return const ReviewVerificationResult.allowed();
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
          code: ReviewVerificationCode.suspiciousContent,
          severity: VerificationSeverity.error,
        );
      }
    }

    // Vérifier la répétition excessive de caractères
    if (_hasExcessiveRepetition(fullText)) {
      return ReviewVerificationResult(
        canPost: false,
        code: ReviewVerificationCode.excessiveRepetition,
        severity: VerificationSeverity.error,
      );
    }

    // Vérifier si le texte est entièrement en majuscules
    if (message.length > 20 && message == message.toUpperCase()) {
      return ReviewVerificationResult(
        canPost: false,
        code: ReviewVerificationCode.allCaps,
        severity: VerificationSeverity.warning,
      );
    }

    return const ReviewVerificationResult.allowed();
  }

  /// Vérifie la qualité du contenu
  ReviewVerificationResult _checkContentQuality(String message) {
    // Vérifier la longueur minimale
    if (message.trim().length < 10) {
      return ReviewVerificationResult(
        canPost: false,
        code: ReviewVerificationCode.tooShort,
        severity: VerificationSeverity.error,
      );
    }

    // Vérifier que le message contient des mots réels
    final words = message.trim().split(RegExp(r'\s+'));
    if (words.length < 3) {
      return ReviewVerificationResult(
        canPost: false,
        code: ReviewVerificationCode.tooFewWords,
        severity: VerificationSeverity.error,
      );
    }

    // Vérifier que ce n'est pas juste des caractères répétés
    if (_isJustRepeatedCharacters(message)) {
      return ReviewVerificationResult(
        canPost: false,
        code: ReviewVerificationCode.lowQuality,
        severity: VerificationSeverity.error,
      );
    }

    return const ReviewVerificationResult.allowed();
  }

  /// Vérifie les doublons
  Future<ReviewVerificationResult> _checkForDuplicates(
    String professionalId,
    String message,
    String authorName,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final userKey = await _createUserKey(authorName);
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
              code: ReviewVerificationCode.duplicateProfessional,
              severity: VerificationSeverity.error,
            );
          }

          // Vérifier le contenu similaire
          if (data['messageHash'] == messageHash) {
            return ReviewVerificationResult(
              canPost: false,
              code: ReviewVerificationCode.duplicateContent,
              severity: VerificationSeverity.error,
            );
          }
        }
      }
    }

    return const ReviewVerificationResult.allowed();
  }

  /// Crée une clé unique pour un utilisateur
  Future<String> _createUserKey(String authorName) async {
    final prefs = await SharedPreferences.getInstance();
    var installationSalt = prefs.getString(_installationSaltKey);
    if (installationSalt == null || installationSalt.isEmpty) {
      final random = Random.secure();
      installationSalt = base64UrlEncode(
        List<int>.generate(32, (_) => random.nextInt(256)),
      );
      await prefs.setString(_installationSaltKey, installationSalt);
    }

    final normalizedName = authorName.toLowerCase().trim();
    return _hashString('$installationSalt|$normalizedName');
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
      final isReviewEntry =
          key.startsWith('review_') && key != _installationSaltKey;
      if (isReviewEntry || key.startsWith('blocked_review_')) {
        final reviewData = prefs.getString(key);
        if (reviewData != null) {
          try {
            final decoded = jsonDecode(reviewData);
            if (decoded is! Map<String, dynamic>) {
              keysToRemove.add(key);
              continue;
            }
            final data = Map<String, dynamic>.from(decoded);
            final timestamp = data['timestamp'] as int;
            if (currentTime - timestamp > maxAge) {
              keysToRemove.add(key);
            } else if (data.remove('authorName') != null) {
              await prefs.setString(key, jsonEncode(data));
            }
          } on Object {
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

    final userKey = await _createUserKey(authorName);
    final blockedKey = 'blocked_review_${timestamp}_$userKey';
    await prefs.setString(
      blockedKey,
      jsonEncode({
        'timestamp': timestamp,
        'reason': reason,
        'professionalId': professionalId,
      }),
    );
    await _cleanupOldEntries();
  }
}

/// Résultat de la vérification d'un avis
class ReviewVerificationResult {
  const ReviewVerificationResult({
    required this.canPost,
    required this.code,
    this.severity = VerificationSeverity.info,
    this.remainingMinutes,
  });

  const ReviewVerificationResult.allowed()
    : canPost = true,
      code = ReviewVerificationCode.allowed,
      severity = VerificationSeverity.success,
      remainingMinutes = null;

  final bool canPost;
  final ReviewVerificationCode code;
  final VerificationSeverity severity;
  final int? remainingMinutes;
}

/// Niveau de sévérité de la vérification
enum VerificationSeverity { success, info, warning, error }

/// Codes métier indépendants de la langue affichée.
enum ReviewVerificationCode {
  allowed,
  cooldown,
  suspiciousContent,
  excessiveRepetition,
  allCaps,
  tooShort,
  tooFewWords,
  lowQuality,
  duplicateProfessional,
  duplicateContent,
}
