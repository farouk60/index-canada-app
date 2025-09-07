import 'package:shared_preferences/shared_preferences.dart';

class FavoriteService {
  static const String _favoritesKey = 'favorites';
  static FavoriteService? _instance;

  FavoriteService._internal();

  static FavoriteService get instance {
    _instance ??= FavoriteService._internal();
    return _instance!;
  }

  // Obtenir tous les favoris
  Future<List<String>> getFavorites() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_favoritesKey) ?? [];
  }

  // Vérifier si un professionnel est en favori
  Future<bool> isFavorite(String professionnelId) async {
    final favorites = await getFavorites();
    return favorites.contains(professionnelId);
  }

  // Ajouter un professionnel aux favoris
  Future<bool> addFavorite(String professionnelId) async {
    final prefs = await SharedPreferences.getInstance();
    final favorites = await getFavorites();

    if (!favorites.contains(professionnelId)) {
      favorites.add(professionnelId);
      return await prefs.setStringList(_favoritesKey, favorites);
    }
    return true; // Déjà en favori
  }

  // Supprimer un professionnel des favoris
  Future<bool> removeFavorite(String professionnelId) async {
    final prefs = await SharedPreferences.getInstance();
    final favorites = await getFavorites();

    if (favorites.contains(professionnelId)) {
      favorites.remove(professionnelId);
      return await prefs.setStringList(_favoritesKey, favorites);
    }
    return true; // Pas en favori
  }

  // Basculer l'état d'un favori (toggle)
  Future<bool> toggleFavorite(String professionnelId) async {
    final isCurrentlyFavorite = await isFavorite(professionnelId);

    if (isCurrentlyFavorite) {
      await removeFavorite(professionnelId);
      return false; // Plus en favori
    } else {
      await addFavorite(professionnelId);
      return true; // Maintenant en favori
    }
  }

  // Effacer tous les favoris
  Future<bool> clearAllFavorites() async {
    final prefs = await SharedPreferences.getInstance();
    return await prefs.remove(_favoritesKey);
  }
}
