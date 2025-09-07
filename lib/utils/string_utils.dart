/// Utilitaires pour la manipulation de chaînes de caractères

/// Fonction pour normaliser les chaînes pour un tri alphabétique correct avec les accents français
/// Cette fonction supprime les accents et convertit en minuscules pour permettre
/// un tri alphabétique correct où É vient avant F par exemple
String normalizeForSorting(String text) {
  return text
      .toLowerCase()
      .replaceAll('à', 'a')
      .replaceAll('á', 'a')
      .replaceAll('â', 'a')
      .replaceAll('ä', 'a')
      .replaceAll('ã', 'a')
      .replaceAll('å', 'a')
      .replaceAll('æ', 'ae')
      .replaceAll('ç', 'c')
      .replaceAll('è', 'e')
      .replaceAll('é', 'e')
      .replaceAll('ê', 'e')
      .replaceAll('ë', 'e')
      .replaceAll('ì', 'i')
      .replaceAll('í', 'i')
      .replaceAll('î', 'i')
      .replaceAll('ï', 'i')
      .replaceAll('ñ', 'n')
      .replaceAll('ò', 'o')
      .replaceAll('ó', 'o')
      .replaceAll('ô', 'o')
      .replaceAll('ö', 'o')
      .replaceAll('õ', 'o')
      .replaceAll('ø', 'o')
      .replaceAll('œ', 'oe')
      .replaceAll('ù', 'u')
      .replaceAll('ú', 'u')
      .replaceAll('û', 'u')
      .replaceAll('ü', 'u')
      .replaceAll('ý', 'y')
      .replaceAll('ÿ', 'y');
}

/// Normalisation plus agressive pour la recherche plein texte
/// - met en minuscules, enlève les accents (réutilise normalizeForSorting)
/// - supprime la ponctuation non alphanumérique
/// - comprime les espaces multiples
String normalizeForSearch(String text) {
  final base = normalizeForSorting(text);
  final withoutPunct = base.replaceAll(RegExp(r"[^a-z0-9\s]"), ' ');
  return withoutPunct.replaceAll(RegExp(r"\s+"), ' ').trim();
}

/// Liste de mots vides FR/EN courants à ignorer pendant la recherche
const Set<String> defaultStopWords = {
  // FR
  'de', 'du', 'des', 'le', 'la', 'les', 'un', 'une', 'et', 'ou', 'a', 'au', 'aux', 'd', 'l', 'en', 'sur', 'pour', 'avec', 'par', 'chez',
  // EN
  'the', /*'a',*/ 'an', 'and', 'or', 'of', 'in', 'on', 'at', 'for', 'with', 'by'
};

/// Découpe une chaîne normalisée en tokens, en retirant les mots vides
List<String> tokenizeWithoutStopWords(String normalized, {Set<String> stopWords = defaultStopWords}) {
  if (normalized.isEmpty) return const [];
  final parts = normalized.split(RegExp(r"[\s\-_.;,/:|]+"));
  return parts.where((p) => p.isNotEmpty && !stopWords.contains(p)).toList();
}

/// Calcule la distance de Levenshtein avec seuil d'arrêt anticipé pour la tolérance de fautes de frappe
int levenshteinDistance(String a, String b, {int maxDistance = 2}) {
  if (a == b) return 0;
  final la = a.length;
  final lb = b.length;
  if ((la - lb).abs() > maxDistance) return maxDistance + 1; // sortie rapide
  if (la == 0) return lb;
  if (lb == 0) return la;

  // Utilise deux lignes pour économiser la mémoire
  List<int> prev = List<int>.generate(lb + 1, (j) => j);
  List<int> curr = List<int>.filled(lb + 1, 0);

  for (int i = 1; i <= la; i++) {
    curr[0] = i;
    int rowMin = curr[0];
    final ca = a.codeUnitAt(i - 1);
    for (int j = 1; j <= lb; j++) {
      final cost = (ca == b.codeUnitAt(j - 1)) ? 0 : 1;
      curr[j] = _min3(
        prev[j] + 1, // suppression dans a
        curr[j - 1] + 1, // insertion dans a
        prev[j - 1] + cost, // substitution
      );
      if (curr[j] < rowMin) rowMin = curr[j];
    }
    if (rowMin > maxDistance) return maxDistance + 1; // arrêt anticipé
    // swap
    final tmp = prev;
    prev = curr;
    curr = tmp;
  }
  return prev[lb];
}

int _min3(int a, int b, int c) => (a < b) ? (a < c ? a : c) : (b < c ? b : c);

/// Vérifie si un token correspond approximativement à une requête
/// - vrai si le token contient la requête (sous-chaîne)
/// - ou si la distance de Levenshtein est petite (1 pour mots courts, 2 pour >=5)
bool fuzzyTokenMatch(String token, String query) {
  if (token.isEmpty || query.isEmpty) return false;
  if (token.contains(query) || query.contains(token)) return true;
  final threshold = token.length >= 5 || query.length >= 5 ? 2 : 1;
  return levenshteinDistance(token, query, maxDistance: threshold) <= threshold;
}

