import 'package:flutter/material.dart';
import 'dart:async';
import '../models.dart';
import '../data_service.dart';
import '../utils.dart';
import '../utils/string_utils.dart';
import '../widgets/gallery_preview_widget.dart';
import '../widgets/coupon_widget.dart';
import '../widgets/fast_image_widget.dart';
import '../services/favorite_service.dart';
import '../services/maps_service.dart';
import '../services/localization_service.dart';
import '../services/firebase_analytics_service.dart';
import '../services/cache_manager_service.dart';
import '../widgets/language_selector.dart';
import 'professionnel_detail_page.dart';
import '../theme/app_theme.dart';

// Énumération pour les options de tri
enum SortOption { defaultOrder, alphabeticalAZ, alphabeticalZA, bestRated }

class ProfessionnelsPage extends StatefulWidget {
  final SousCategorie sousCategorie;

  const ProfessionnelsPage({super.key, required this.sousCategorie});

  @override
  State<ProfessionnelsPage> createState() => _ProfessionnelsPageState();
}

class _ProfessionnelsPageState extends State<ProfessionnelsPage>
    with WidgetsBindingObserver {
  final LocalizationService _localizationService = LocalizationService();
  final FirebaseAnalyticsService _analytics = FirebaseAnalyticsService();
  Timer? _searchTrackingTimer; // Timer pour éviter trop de tracking
  String _searchQuery = '';
  String _citySearchQuery = '';
  bool _isSearchingByCity = false;
  List<Professionnel> _allProfessionnels = [];
  List<Professionnel> _filteredProfessionnels = [];
  bool _isLoading = true;
  String? _error;
  Timer? _refreshTimer;
  Set<String> _favoriteIds = {}; // Pour stocker les IDs des favoris
  List<String> _availableCities = []; // Liste des villes disponibles
  SortOption _currentSortOption = SortOption
      .defaultOrder; // Option de tri actuelle - Tri par défaut avec en vedette en premier

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadProfessionnels(
      forceRefresh: true,
    ); // Toujours forcer le refresh au démarrage
    _startPeriodicRefresh();
    _loadFavorites(); // Charger les favoris
    _setScreenName();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _refreshTimer?.cancel();
    _searchTrackingTimer?.cancel();
    super.dispose();
  }

  // Refresh automatique quand l'app revient au premier plan
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _loadProfessionnels(forceRefresh: true);
    }
  }

  // Timer pour refresh automatique toutes les 3 minutes
  void _startPeriodicRefresh() {
    _refreshTimer = Timer.periodic(const Duration(minutes: 3), (timer) {
      if (mounted) {
        _loadProfessionnels(forceRefresh: true);
      }
    });
  }

  Future<void> _loadProfessionnels({bool forceRefresh = false}) async {
    try {
      setState(() {
        _isLoading = true;
        _error = null;
      });

      final wixApi = DataService();

      print('🔍 DIAGNOSTIC PROFESSIONNELS PAGE');
      print('📂 Sous-catégorie recherchée: "${widget.sousCategorie.id}"');
      print('📝 Titre de la sous-catégorie: "${widget.sousCategorie.title}"');

      // Si c'est un refresh forcé, vider le cache ET forcer la sync Wix
      if (forceRefresh) {
        print('🔄 Forçage de la synchronisation avec Wix...');
        await wixApi.forceSyncWithWix();
      }

      // Utiliser la méthode standard pour récupérer les professionnels
      final professionnels = await wixApi.fetchProfessionnels(
        sousCategorie: widget.sousCategorie.id,
      );

      print(
        '🎯 RÉSULTAT FINAL: ${professionnels.length} professionnels trouvés pour "${widget.sousCategorie.id}"',
      );

      if (mounted) {
        setState(() {
          _allProfessionnels = professionnels;
          _isLoading = false;
          _error = null;

          // Extraire les villes disponibles et les trier
          _availableCities =
              professionnels
                  .map((prof) => prof.ville)
                  .where((ville) => ville.isNotEmpty)
                  .toSet()
                  .toList()
                ..sort();
        });

        // Appliquer les filtres et le tri après avoir mis à jour les données
        _applyFilters();

        print(
          '✅ ${professionnels.length} professionnels chargés et synchronisés',
        );

        // Précharger les images des premiers professionnels pour améliorer la performance
        _preloadVisibleImages();
      }
    } catch (e) {
      print('❌ Erreur lors du chargement des professionnels: $e');
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  // Méthode pour précharger les images des professionnels visibles
  void _preloadVisibleImages() {
    if (_filteredProfessionnels.isEmpty) return;

    // Précharger les images des 10 premiers professionnels
    final imagesToPreload = _filteredProfessionnels
        .take(10)
        .where((prof) => prof.image.isNotEmpty)
        .map((prof) => getValidImageUrl(prof.image))
        .toList();

    for (String imageUrl in imagesToPreload) {
      if (imageUrl.isNotEmpty && !imageUrl.startsWith('data:')) {
        try {
          // Précharger l'image en arrière-plan
          precacheImage(NetworkImage(imageUrl), context);
        } catch (e) {
          print('Erreur préchargement image: $e');
        }
      }
    }
  }

  // Charger les favoris depuis le stockage local
  Future<void> _loadFavorites() async {
    final favoriteService = FavoriteService.instance;
    final favorites = await favoriteService.getFavorites();
    if (mounted) {
      setState(() {
        _favoriteIds = favorites.toSet();
      });
    }
  }

  // Basculer l'état d'un favori
  Future<void> _toggleFavorite(String professionnelId) async {
    try {
      final favoriteService = FavoriteService.instance;
      final newFavoriteStatus = await favoriteService.toggleFavorite(
        professionnelId,
      );

      if (mounted) {
        setState(() {
          if (newFavoriteStatus) {
            _favoriteIds.add(professionnelId);
          } else {
            _favoriteIds.remove(professionnelId);
          }
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              newFavoriteStatus ? 'Ajouté aux favoris' : 'Supprimé des favoris',
            ),
            duration: const Duration(seconds: 2),
            backgroundColor: newFavoriteStatus ? Colors.green : Colors.orange,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Erreur lors de la sauvegarde'),
            duration: Duration(seconds: 2),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _filterProfessionnels(String query) {
    setState(() {
      _searchQuery = query;
      _applyFilters();
    });

    // Tracker la recherche avec un délai pour éviter trop de calls
    _searchTrackingTimer?.cancel();
    if (query.isNotEmpty) {
      _searchTrackingTimer = Timer(const Duration(milliseconds: 500), () {
        _trackSearch(query, 'professional');
      });
    }
  }

  void _filterByCity(String city) {
    setState(() {
      _citySearchQuery = city;
      _isSearchingByCity = city.isNotEmpty;
      _applyFilters();
    });

    // Tracker la recherche par ville
    if (city.isNotEmpty) {
      _trackSearch(city, 'city');
    }
  }

  // Tracker les recherches
  void _trackSearch(String query, String type) async {
    final resultsCount = _filteredProfessionnels.length;
    await _analytics.trackSearch(
      searchQuery: query,
      searchType: type,
      resultsCount: resultsCount,
    );
  }

  void _applyFilters() {
    List<Professionnel> filtered = _allProfessionnels;

    // Filtrer par recherche générale avec recherche intelligente
    if (_searchQuery.isNotEmpty) {
      print('🔍 RECHERCHE ACTIVE: "${_searchQuery}"');
      print('📊 Nombre total de professionnels: ${_allProfessionnels.length}');

      filtered = filtered.where((prof) {
        final matches = _smartSearch(prof, _searchQuery);
        if (!matches) {
          // Log silencieux des non-matches pour le debug si nécessaire
          // print('❌ Pas de match: ${prof.title}');
        }
        return matches;
      }).toList();

      print('📊 Nombre de résultats: ${filtered.length}');
      print('---');
    }

    // Filtrer par ville spécifique
    if (_citySearchQuery.isNotEmpty) {
      filtered = filtered
          .where(
            (prof) => prof.ville.toLowerCase().contains(
              _citySearchQuery.toLowerCase(),
            ),
          )
          .toList();
    }

    // Appliquer le tri
    _applySorting(filtered);

    _filteredProfessionnels = filtered;
  }

  // Fonction de recherche STRICTE - seulement mots qui commencent par la requête
  bool _smartSearch(Professionnel prof, String query) {
    if (query.isEmpty) return true;

    final q = query.toLowerCase();
    final title = prof.title.toLowerCase();

    // Découper le titre en mots
    final words = title.split(RegExp(r'[\s\-_.,;:]+'));

    // Mots vides à ignorer (stop words français et anglais)
    final stopWords = {
      'de',
      'du',
      'des',
      'le',
      'la',
      'les',
      'un',
      'une',
      'et',
      'ou',
      'à',
      'au',
      'aux',
      'the',
      'a',
      'an',
      'and',
      'or',
      'of',
      'in',
      'on',
      'at',
      'for',
      'with',
      'by',
    };

    // Trouver le PREMIER mot significatif (non vide et pas stop word)
    for (String word in words) {
      if (word.isNotEmpty && !stopWords.contains(word)) {
        // Vérifier SEULEMENT le premier mot principal
        return word.startsWith(q);
      }
    }

    return false;
  }

  // Méthode pour appliquer le tri selon l'option sélectionnée
  void _applySorting(List<Professionnel> list) {
    switch (_currentSortOption) {
      case SortOption.defaultOrder:
        // Tri par défaut : en vedette en premier, puis par titre
        list.sort((a, b) {
          if (a.sponsor && !b.sponsor) return -1;
          if (!a.sponsor && b.sponsor) return 1;
          return normalizeForSorting(
            a.title,
          ).compareTo(normalizeForSorting(b.title));
        });
        break;
      case SortOption.alphabeticalAZ:
        list.sort(
          (a, b) => normalizeForSorting(
            a.title,
          ).compareTo(normalizeForSorting(b.title)),
        );
        break;
      case SortOption.alphabeticalZA:
        list.sort(
          (a, b) => normalizeForSorting(
            b.title,
          ).compareTo(normalizeForSorting(a.title)),
        );
        break;
      case SortOption.bestRated:
        list.sort((a, b) {
          // Tri par note moyenne décroissante, puis par nombre d'avis décroissant
          int ratingComparison = b.averageRating.compareTo(a.averageRating);
          if (ratingComparison != 0) return ratingComparison;
          return b.reviewCount.compareTo(a.reviewCount);
        });
        break;
    }
  }

  // Méthode pour changer l'option de tri
  void _changeSortOption(SortOption newOption) async {
    setState(() {
      _currentSortOption = newOption;
    });

    // Si on sélectionne "mieux noté", forcer une synchronisation pour avoir les données de rating à jour
    if (newOption == SortOption.bestRated) {
      print(
        '🏆 Tri "mieux noté" sélectionné - synchronisation des données de rating...',
      );

      // Forcer un refresh complet pour avoir les données de rating les plus récentes
      await _forceCompleteRefresh();
    } else {
      // Pour les autres tris, simplement appliquer les filtres
      _applyFilters();
    }
  }

  // Méthode pour obtenir le texte de l'option de tri
  String _getSortOptionText(SortOption option) {
    switch (option) {
      case SortOption.defaultOrder:
        return _localizationService.tr('sort_default');
      case SortOption.alphabeticalAZ:
        return _localizationService.tr('sort_name_az');
      case SortOption.alphabeticalZA:
        return _localizationService.tr('sort_name_za');
      case SortOption.bestRated:
        return _localizationService.tr('sort_best_rated');
    }
  }

  // Méthode pour afficher le menu de tri
  void _showSortMenu() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (BuildContext context) {
        return Container(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.sort, color: Colors.blue.shade600),
                  const SizedBox(width: 8),
                  Text(
                    _localizationService.tr('sort_options'),
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.blue.shade600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              ...SortOption.values.map((option) {
                final isSelected = _currentSortOption == option;
                return ListTile(
                  leading: Icon(
                    _getSortOptionIcon(option),
                    color: isSelected ? Colors.blue : Colors.grey,
                  ),
                  title: Text(
                    _getSortOptionText(option),
                    style: TextStyle(
                      fontWeight: isSelected
                          ? FontWeight.bold
                          : FontWeight.normal,
                      color: isSelected ? Colors.blue : Colors.black,
                    ),
                  ),
                  trailing: isSelected
                      ? Icon(Icons.check_circle, color: Colors.blue)
                      : null,
                  onTap: () {
                    _changeSortOption(option);
                    Navigator.of(context).pop();
                  },
                );
              }),
              const SizedBox(height: 10),
            ],
          ),
        );
      },
    );
  }

  // Méthode pour obtenir l'icône de l'option de tri
  IconData _getSortOptionIcon(SortOption option) {
    switch (option) {
      case SortOption.defaultOrder:
        return Icons.auto_awesome;
      case SortOption.alphabeticalAZ:
        return Icons.sort_by_alpha;
      case SortOption.alphabeticalZA:
        return Icons.sort_by_alpha;
      case SortOption.bestRated:
        return Icons.star_rate;
    }
  }

  // Ouvrir Google Maps avec l'adresse
  Future<void> _openMaps(String address) async {
    try {
      final mapsService = MapsService.instance;
      final success = await mapsService.openNativeMaps(address);

      if (!success && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Impossible d\'ouvrir l\'application Maps'),
            duration: Duration(seconds: 2),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Erreur lors de l\'ouverture de Maps'),
            duration: Duration(seconds: 2),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // Afficher la boîte de dialogue pour filtrer par ville
  void _showCityFilterDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(_localizationService.tr('search_by_city')),
          content: SizedBox(
            width: double.maxFinite,
            height: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Bouton pour effacer le filtre
                if (_isSearchingByCity)
                  Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(bottom: 16),
                    child: ElevatedButton.icon(
                      onPressed: () {
                        _clearAllFilters();
                        Navigator.of(context).pop();
                      },
                      icon: const Icon(Icons.clear),
                      label: Text(_localizationService.tr('clear_filter')),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.orange,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ),
                // Liste des villes
                Expanded(
                  child: ListView.builder(
                    itemCount: _availableCities.length,
                    itemBuilder: (context, index) {
                      final city = _availableCities[index];
                      final isSelected = _citySearchQuery == city;

                      return ListTile(
                        leading: Icon(
                          Icons.location_on,
                          color: isSelected ? Colors.blue : Colors.grey,
                        ),
                        title: Text(
                          city,
                          style: TextStyle(
                            fontWeight: isSelected
                                ? FontWeight.bold
                                : FontWeight.normal,
                            color: isSelected ? Colors.blue : Colors.black,
                          ),
                        ),
                        trailing: isSelected
                            ? const Icon(Icons.check_circle, color: Colors.blue)
                            : null,
                        onTap: () {
                          _filterByCity(city);
                          Navigator.of(context).pop();
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: Text(_localizationService.tr('cancel')),
            ),
          ],
        );
      },
    );
  }

  void _clearAllFilters() {
    setState(() {
      _searchQuery = '';
      _citySearchQuery = '';
      _isSearchingByCity = false;
      _currentSortOption = SortOption
          .defaultOrder; // Garder le tri par défaut avec en vedette en premier
      _applyFilters(); // Utiliser _applyFilters pour une application cohérente
    });
  }

  // Forcer un rafraîchissement complet avec feedback utilisateur
  Future<void> _forceCompleteRefresh() async {
    try {
      // Utiliser le service global de gestion de cache
      final cacheManager = CacheManagerService();
      await cacheManager.performCompleteRefresh(
        context: context,
        showMessages: true,
      );

      // Recharger les données spécifiques à cette page
      await _loadProfessionnels(forceRefresh: true);

      print('✅ Rafraîchissement complet ProfessionnelsPage terminé');
    } catch (e) {
      print('❌ Erreur lors du rafraîchissement complet ProfessionnelsPage: $e');
      // Les messages d'erreur sont gérés par le CacheManagerService
    }
  }

  // Définir le nom de l'écran pour Analytics
  void _setScreenName() async {
    await _analytics.setCurrentScreen('professionals_page');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.sousCategorie.getTitleInLanguage(
            _localizationService.currentLanguage,
          ),
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        foregroundColor: Colors.white,
        elevation: 0,
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [AppTheme.brandPrimary, AppTheme.brandSecondary],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        actions: [
          // Bouton de tri
          IconButton(
            icon: Icon(
              Icons.sort,
              color: _currentSortOption != SortOption.defaultOrder
                  ? AppTheme.brandTertiary
                  : Colors.white,
            ),
            onPressed: _showSortMenu,
            tooltip: _localizationService.tr('sort_options'),
          ),
          // Sélecteur de langue
          LanguageSelector(
            onLanguageChanged: (String languageCode) {
              setState(() {}); // Reconstruire la page avec la nouvelle langue
            },
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _forceCompleteRefresh,
            tooltip: _localizationService.tr('refresh'),
          ),
        ],
      ),
      body: Column(
        children: [
          // Barre de recherche
          Container(
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [AppTheme.brandPrimary, AppTheme.brandSecondary],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.only(
                bottomLeft: Radius.circular(20),
                bottomRight: Radius.circular(20),
              ),
            ),
            child: Column(
              children: [
                TextField(
                  decoration: InputDecoration(
                    labelText: _localizationService.tr('search_professional'),
                    labelStyle: const TextStyle(color: Colors.white70),
                    prefixIcon: const Icon(Icons.search, color: Colors.white70),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(
                              Icons.clear,
                              color: Colors.white70,
                            ),
                            onPressed: () => _filterProfessionnels(''),
                          )
                        : IconButton(
                            icon: Icon(
                              _isSearchingByCity
                                  ? Icons.location_city
                                  : Icons.location_on,
                              color: _isSearchingByCity
                                  ? AppTheme.brandTertiary
                                  : Colors.white70,
                            ),
                            onPressed: _showCityFilterDialog,
                            tooltip: _localizationService.tr('search_by_city'),
                          ),
                    filled: true,
                    fillColor: Colors.white.withOpacity(0.12),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(25),
                      borderSide: BorderSide.none,
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(25),
                      borderSide: const BorderSide(color: Colors.white, width: 2),
                    ),
                  ),
                  style: const TextStyle(color: Colors.white),
                  onChanged: _filterProfessionnels,
                ),
                // Indicateur de filtre par ville
                if (_isSearchingByCity)
                  Container(
                    margin: const EdgeInsets.only(top: 12),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: AppTheme.brandTertiary.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: AppTheme.brandTertiary, width: 1),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.location_on,
                          color: AppTheme.brandTertiary,
                          size: 16,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '${_localizationService.tr('filter_by')} $_citySearchQuery',
                          style: const TextStyle(
                            color: AppTheme.brandTertiary,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(width: 6),
                        GestureDetector(
                          onTap: _clearAllFilters,
                          child: const Icon(
                            Icons.close,
                            color: AppTheme.brandTertiary,
                            size: 16,
                          ),
                        ),
                      ],
                    ),
                  ),
                // Indicateur de tri actif
                if (_currentSortOption != SortOption.defaultOrder)
                  Container(
                    margin: EdgeInsets.only(top: _isSearchingByCity ? 8 : 12),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: AppTheme.brandTertiary.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: AppTheme.brandTertiary, width: 1),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _getSortOptionIcon(_currentSortOption),
                          color: AppTheme.brandTertiary,
                          size: 16,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          _getSortOptionText(_currentSortOption),
                          style: const TextStyle(
                            color: AppTheme.brandTertiary,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(width: 6),
                        GestureDetector(
                          onTap: () =>
                              _changeSortOption(SortOption.defaultOrder),
                          child: const Icon(
                            Icons.close,
                            color: AppTheme.brandTertiary,
                            size: 16,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          // Liste des professionnels
          Expanded(
            child: RefreshIndicator(
              onRefresh: _forceCompleteRefresh,
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                  ? SingleChildScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      child: SizedBox(
                        height: MediaQuery.of(context).size.height * 0.5,
                        child: Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.error,
                                size: 64,
                                color: Colors.red.shade300,
                              ),
                              const SizedBox(height: 16),
                              Text('Erreur: $_error'),
                              const SizedBox(height: 16),
                              ElevatedButton(
                                onPressed: () =>
                                    _loadProfessionnels(forceRefresh: true),
                                child: const Text('Réessayer'),
                              ),
                            ],
                          ),
                        ),
                      ),
                    )
                  : _filteredProfessionnels.isEmpty &&
                        (_searchQuery.isNotEmpty || _isSearchingByCity)
                  ? SingleChildScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      child: SizedBox(
                        height: MediaQuery.of(context).size.height * 0.5,
                        child: Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.search_off,
                                size: 64,
                                color: Colors.grey[400],
                              ),
                              const SizedBox(height: 16),
                              Text(
                                _isSearchingByCity
                                    ? '${_localizationService.tr('no_professionals_city')} "$_citySearchQuery"'
                                    : '${_localizationService.tr('no_professionals_search')} "$_searchQuery"',
                                style: TextStyle(
                                  fontSize: 16,
                                  color: Colors.grey[600],
                                ),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 16),
                              ElevatedButton(
                                onPressed: _clearAllFilters,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppTheme.brandPrimary,
                                  foregroundColor: Colors.white,
                                ),
                                child: Text(
                                  _localizationService.tr('clear_filters'),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    )
                  : _filteredProfessionnels.isEmpty
                  ? SingleChildScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      child: SizedBox(
                        height: MediaQuery.of(context).size.height * 0.5,
                        child: Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.person_search,
                                size: 64,
                                color: Colors.grey[400],
                              ),
                              const SizedBox(height: 16),
                              Text(
                                _localizationService.tr('no_professionals'),
                                style: TextStyle(
                                  fontSize: 16,
                                  color: Colors.grey[600],
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        ),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: _filteredProfessionnels.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (context, index) {
                        final prof = _filteredProfessionnels[index];
                        return AnimatedContainer(
                          duration: Duration(milliseconds: 300 + (index * 50)),
                          curve: Curves.easeOutBack,
                          child: Hero(
                            tag: 'prof_${prof.id}',
                            child: Material(
                              elevation: 4,
                              borderRadius: BorderRadius.circular(12),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(12),
                                onTap: () {
                                  Navigator.push(
                                    context,
                                    PageRouteBuilder(
                                      pageBuilder:
                                          (
                                            context,
                                            animation,
                                            secondaryAnimation,
                                          ) => ProfessionnelDetailPage(
                                            professionnel: prof,
                                          ),
                                      transitionsBuilder:
                                          (
                                            context,
                                            animation,
                                            secondaryAnimation,
                                            child,
                                          ) {
                                            const begin = Offset(1.0, 0.0);
                                            const end = Offset.zero;
                                            const curve = Curves.easeInOutQuart;

                                            var tween = Tween(
                                              begin: begin,
                                              end: end,
                                            ).chain(CurveTween(curve: curve));

                                            return SlideTransition(
                                              position: animation.drive(tween),
                                              child: FadeTransition(
                                                opacity: animation,
                                                child: child,
                                              ),
                                            );
                                          },
                                      transitionDuration: const Duration(
                                        milliseconds: 500,
                                      ),
                                    ),
                                  );
                                },
                                child: Container(
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(12),
                                    gradient: LinearGradient(
                                      colors: [Colors.white, Colors.grey.shade50],
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                    ),
                                  ),
                                  padding: const EdgeInsets.all(16),
                                  child: Row(
                                    children: [
                                      // Photo du professionnel
                                      Container(
                                        width: 60,
                                        height: 60,
                                        decoration: BoxDecoration(
                                          borderRadius: BorderRadius.circular(
                                            30,
                                          ),
                                          gradient: LinearGradient(
                                            colors: [
                                              AppTheme.brandPrimary,
                                              AppTheme.brandSecondary,
                                            ],
                                          ),
                                        ),
                                        child: prof.image.isNotEmpty
                                            ? ClipRRect(
                                                borderRadius:
                                                    BorderRadius.circular(30),
                                                child: FastImageWidget(
                                                  imageUrl: getValidImageUrl(
                                                    prof.image,
                                                  ),
                                                  width: 60,
                                                  height: 60,
                                                  fit: BoxFit.cover,
                                                  timeout: const Duration(
                                                    seconds: 8,
                                                  ), // Timeout plus long pour les images
                                                  placeholder: Container(
                                                    width: 60,
                                                    height: 60,
                                                    decoration: BoxDecoration(
                                                      color: Colors.grey[300],
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                            30,
                                                          ),
                                                    ),
                                                    child: const Icon(
                                                      Icons.person,
                                                      color: Colors.white,
                                                      size: 30,
                                                    ),
                                                  ),
                                                  errorWidget: const Icon(
                                                    Icons.person,
                                                    color: Colors.white,
                                                    size: 30,
                                                  ),
                                                ),
                                              )
                                            : const Icon(
                                                Icons.person,
                                                color: Colors.white,
                                                size: 30,
                                              ),
                                      ),
                                      const SizedBox(width: 16),
                                      // Informations du professionnel
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              children: [
                                                Expanded(
                                                  child: Text(
                                                    prof.title,
                                                    style: const TextStyle(
                                                      fontSize: 16,
                                                      fontWeight: FontWeight.bold,
                                                    ),
                                                  ),
                                                ),
                                                if (prof.sponsor)
                                                  Container(
                                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                    decoration: BoxDecoration(
                                                      gradient: const LinearGradient(
                                                        colors: [AppTheme.brandSecondary, AppTheme.brandTertiary],
                                                        begin: Alignment.topLeft,
                                                        end: Alignment.bottomRight,
                                                      ),
                                                      borderRadius: BorderRadius.circular(8),
                                                    ),
                                                    child: Row(
                                                      mainAxisSize: MainAxisSize.min,
                                                      children: const [
                                                        Icon(Icons.star, color: Colors.white, size: 10),
                                                        SizedBox(width: 2),
                                                        Text('En vedette', style: TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.bold)),
                                                      ],
                                                    ),
                                                  ),
                                              ],
                                            ),
                                            if (prof.subtitle.isNotEmpty) ...[
                                              const SizedBox(height: 4),
                                              Text(
                                                prof.subtitle,
                                                style: const TextStyle(
                                                  fontSize: 14,
                                                  color: Colors.black87,
                                                  fontWeight: FontWeight.w500,
                                                ),
                                              ),
                                            ],
                                            if (prof.reviewCount > 0) ...[
                                              const SizedBox(height: 4),
                                              Row(
                                                children: [
                                                  ...List.generate(5, (index) {
                                                    return Icon(
                                                      index < prof.averageRating.round() ? Icons.star : Icons.star_border,
                                                      color: Colors.amber,
                                                      size: 16,
                                                    );
                                                  }),
                                                  const SizedBox(width: 4),
                                                  Text(
                                                    '${prof.averageRating.toStringAsFixed(1)} (${prof.reviewCount} avis)',
                                                    style: TextStyle(
                                                      fontSize: 12,
                                                      color: Colors.grey[600],
                                                      fontWeight: FontWeight.w500,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ],
                                            if (prof.address.isNotEmpty) ...[
                                              const SizedBox(height: 4),
                                              GestureDetector(
                                                onTap: () => _openMaps(prof.address),
                                                child: Text(
                                                  prof.address,
                                                  style: const TextStyle(
                                                    fontSize: 14,
                                                    color: AppTheme.brandPrimary,
                                                    decoration: TextDecoration.underline,
                                                  ),
                                                  maxLines: 2,
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                              ),
                                            ],
                                            if (prof.ville.isNotEmpty) ...[
                                              const SizedBox(height: 8),
                                              Row(
                                                children: [
                                                  Icon(Icons.location_on, size: 16, color: Colors.grey[500]),
                                                  const SizedBox(width: 4),
                                                  Expanded(
                                                    child: Text(
                                                      prof.ville,
                                                      style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                                                      overflow: TextOverflow.ellipsis,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ],
                                            CouponWidget(professionnel: prof, isCompact: true),
                                          ],
                                        ),
                                      ),

                                      // Indicateur de galerie si le professionnel a des images
                                      if (prof.gallery.isNotEmpty) ...[
                                        const SizedBox(width: 8),
                                        GalleryPreviewWidget(
                                          images: prof.gallery.cast<String>(),
                                          size: 40,
                                          onTap: () {
                                            Navigator.push(
                                              context,
                                              MaterialPageRoute(
                                                builder: (_) =>
                                                    ProfessionnelDetailPage(
                                                      professionnel: prof,
                                                    ),
                                              ),
                                            );
                                          },
                                        ),
                                      ],

                                      // Bouton favoris
                                      IconButton(
                                        icon: Icon(
                                          _favoriteIds.contains(prof.id)
                                              ? Icons.favorite
                                              : Icons.favorite_border,
                                          color: _favoriteIds.contains(prof.id)
                                              ? Colors.red
                                              : Colors.grey,
                                        ),
                                        onPressed: () =>
                                            _toggleFavorite(prof.id),
                                        tooltip: _favoriteIds.contains(prof.id)
                                            ? 'Supprimer des favoris'
                                            : 'Ajouter aux favoris',
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
