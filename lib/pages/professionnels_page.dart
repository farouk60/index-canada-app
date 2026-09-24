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
import '../widgets/engagement_visibility_tracker.dart';
import 'professionnel_detail_page.dart';
import '../theme/app_theme.dart';

// Énumération pour les options de tri
enum SortOption { defaultOrder, alphabeticalAZ, alphabeticalZA, bestRated }

class ProfessionnelsPage extends StatefulWidget {
  final SousCategorie sousCategorie;
  final FirebaseAnalyticsService? analyticsService;
  final DataService? dataService;
  final Future<bool> Function(String address)? mapsLauncher;

  const ProfessionnelsPage({
    super.key,
    required this.sousCategorie,
    this.analyticsService,
    this.dataService,
    this.mapsLauncher,
  });

  @override
  State<ProfessionnelsPage> createState() => _ProfessionnelsPageState();
}

class _ProfessionnelsPageState extends State<ProfessionnelsPage>
    with WidgetsBindingObserver {
  final LocalizationService _localizationService = LocalizationService();
  late final FirebaseAnalyticsService _analytics;
  late final DataService _dataService;
  final Set<String> _recordedDirectoryImpressions = <String>{};
  Timer? _searchTrackingTimer; // Timer pour éviter trop de tracking
  String _searchQuery = '';
  String _citySearchQuery = '';
  bool _isSearchingByCity = false;
  List<Professionnel> _allProfessionnels = [];
  List<Professionnel> _filteredProfessionnels = [];
  bool _isLoading = true;
  String? _errorKey;
  Set<String> _favoriteIds = {}; // Pour stocker les IDs des favoris
  int _professionalsLoadGeneration = 0;
  int _favoritesLoadGeneration = 0;
  Future<void> _favoriteWriteQueue = Future<void>.value();
  List<String> _availableCities = []; // Liste des villes disponibles
  SortOption _currentSortOption = SortOption.defaultOrder; // Option de tri actuelle - Tri par défaut avec en vedette en premier

  @override
  void initState() {
    super.initState();
    _analytics = widget.analyticsService ?? FirebaseAnalyticsService();
    _dataService = widget.dataService ?? DataService();
    WidgetsBinding.instance.addObserver(this);
    _loadProfessionnels(
      forceRefresh: true,
    ); // Toujours forcer le refresh au démarrage
    _loadFavorites(); // Charger les favoris
    _setScreenName();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
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

  Future<void> _loadProfessionnels({bool forceRefresh = false}) async {
    if (!mounted) return;

    final loadGeneration = ++_professionalsLoadGeneration;
    try {
      setState(() {
        _isLoading = true;
        _errorKey = null;
      });

      final wixApi = _dataService;

      // Si c'est un refresh forcé, vider le cache ET forcer la sync Wix
      if (forceRefresh) {
        await wixApi.forceSyncWithWix();
        if (!mounted || loadGeneration != _professionalsLoadGeneration) {
          return;
        }
      }

      // Utiliser la méthode standard pour récupérer les professionnels
      final professionnels = await wixApi.fetchProfessionnels(
        sousCategorie: widget.sousCategorie.id,
      );

      if (mounted && loadGeneration == _professionalsLoadGeneration) {
        setState(() {
          _allProfessionnels = professionnels;
          _isLoading = false;
          _errorKey = null;

          // Extraire les villes disponibles et les trier
          _availableCities =
              professionnels
                  .map((prof) => prof.ville)
                  .where((ville) => ville.isNotEmpty)
                  .toSet()
                  .toList()
                ..sort();

          _applyFilters();
        });

        // Précharger les images des premiers professionnels pour améliorer la performance
        _preloadVisibleImages();
      }
    } on Exception {
      if (mounted && loadGeneration == _professionalsLoadGeneration) {
        setState(() {
          _errorKey = 'loading_error';
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
        } catch (_) {
          // Le préchargement est une optimisation non bloquante.
        }
      }
    }
  }

  // Charger les favoris depuis le stockage local
  Future<void> _loadFavorites() async {
    final loadGeneration = ++_favoritesLoadGeneration;
    final favoriteService = FavoriteService.instance;
    final favorites = await favoriteService.getFavorites();
    if (mounted && loadGeneration == _favoritesLoadGeneration) {
      setState(() {
        _favoriteIds = favorites.toSet();
      });
    }
  }

  // Basculer l'état d'un favori
  Future<void> _toggleFavorite(String professionnelId) {
    // Invalider tout chargement antérieur et sérialiser les écritures afin que
    // deux interactions rapides ne s'écrasent pas dans le stockage local.
    ++_favoritesLoadGeneration;
    final operation = _favoriteWriteQueue.then<void>((_) async {
      await _performFavoriteToggle(professionnelId);
    });
    _favoriteWriteQueue = operation;
    return operation;
  }

  Future<void> _performFavoriteToggle(String professionnelId) async {
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
              _localizationService.tr(
                newFavoriteStatus
                    ? 'added_to_favorites'
                    : 'removed_from_favorites',
              ),
            ),
            duration: const Duration(seconds: 2),
            backgroundColor: newFavoriteStatus ? Colors.green : Colors.orange,
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_localizationService.tr('favorite_save_error')),
            duration: const Duration(seconds: 2),
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
    final resultsCount = _filteredProfessionnels.length;

    // Tracker la recherche avec un délai pour éviter trop de calls
    _searchTrackingTimer?.cancel();
    if (query.isNotEmpty) {
      _searchTrackingTimer = Timer(const Duration(milliseconds: 500), () {
        _trackSearch('professional', resultsCount);
      });
    }
  }

  void _filterByCity(String city) {
    setState(() {
      _citySearchQuery = city;
      _isSearchingByCity = city.isNotEmpty;
      _applyFilters();
    });
    final resultsCount = _filteredProfessionnels.length;

    // Tracker la recherche par ville
    if (city.isNotEmpty) {
      _trackSearch('city', resultsCount);
    }
  }

  // Tracker les recherches
  void _trackSearch(String type, int resultsCount) {
    _runAnalytics(
      () => _analytics.trackSearch(
        searchType: type,
        resultsCount: resultsCount,
        locale: _localizationService.currentLanguage,
      ),
    );
  }

  void _applyFilters() {
    List<Professionnel> filtered = _allProfessionnels;

    // Filtrer par recherche générale avec recherche intelligente
    if (_searchQuery.isNotEmpty) {
      filtered = filtered.where((prof) {
        return _smartSearch(prof, _searchQuery);
      }).toList();
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
          return normalizeForSorting(a.title)
              .compareTo(normalizeForSorting(b.title));
        });
        break;
      case SortOption.alphabeticalAZ:
        list.sort(
          (a, b) =>
              normalizeForSorting(a.title)
                  .compareTo(normalizeForSorting(b.title)),
        );
        break;
      case SortOption.alphabeticalZA:
        list.sort(
          (a, b) =>
              normalizeForSorting(b.title)
                  .compareTo(normalizeForSorting(a.title)),
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
  Future<void> _openMaps(Professionnel professionnel) async {
    try {
      final launcher =
          widget.mapsLauncher ?? MapsService.instance.openNativeMaps;
      final success = await launcher(professionnel.address);

      if (success) {
        _runAnalytics(
          () => _analytics.trackMapNavigation(
            professionalId: professionnel.id,
            placement: 'directory',
            locale: _localizationService.currentLanguage,
          ),
        );
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_localizationService.tr('error_opening_maps')),
            duration: const Duration(seconds: 2),
            backgroundColor: Colors.red,
          ),
        );
      }
    } on Exception {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_localizationService.tr('error_opening_maps')),
            duration: const Duration(seconds: 2),
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
      if (!mounted) return;

      // Le gestionnaire vient de synchroniser Wix; relire son instantané cache.
      await _loadProfessionnels();
    } catch (_) {
      // Les messages d'erreur sont gérés par le CacheManagerService
    }
  }

  // Définir le nom de l'écran pour Analytics
  void _setScreenName() {
    _runAnalytics(() => _analytics.setCurrentScreen('professionals_page'));
  }

  void _runAnalytics(Future<void> Function() event) {
    try {
      unawaited(event().catchError((Object _) {}));
    } catch (_) {
      // La télémétrie ne doit jamais affecter le parcours principal.
    }
  }

  void _trackDirectoryImpression(Professionnel professionnel) {
    final impressionKey = '${professionnel.id}|directory';
    if (!_recordedDirectoryImpressions.add(impressionKey)) return;

    _runAnalytics(
      () => _analytics.trackProfessionalImpression(
        professionalId: professionnel.id,
        placement: 'directory',
        locale: _localizationService.currentLanguage,
      ),
    );
  }

  String _localized(String french, String english) {
    return _localizationService.currentLanguage == 'en' ? english : french;
  }

  String _ratingSemanticsLabel(Professionnel professionnel) {
    if (professionnel.reviewCount == 0) {
      return _localized('Aucun avis client', 'No customer reviews');
    }
    return _localized(
      'Note ${professionnel.averageRating.toStringAsFixed(1)} sur 5, '
          '${professionnel.reviewCount} avis',
      'Rating ${professionnel.averageRating.toStringAsFixed(1)} out of 5, '
          '${professionnel.reviewCount} reviews',
    );
  }

  Widget _buildCompactRating(Professionnel professionnel) {
    if (professionnel.reviewCount == 0) return const SizedBox.shrink();

    return Semantics(
      key: ValueKey('directory_rating_${professionnel.id}'),
      label: _ratingSemanticsLabel(professionnel),
      readOnly: true,
      child: ExcludeSemantics(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.star_rounded, color: Color(0xFFE09B16), size: 18),
            const SizedBox(width: 4),
            Text(
              professionnel.averageRating.toStringAsFixed(1),
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(width: 4),
            Text(
              '(${_localizationService.reviewCountLabel(professionnel.reviewCount)})',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSponsoredBadge(Professionnel professionnel) {
    final label = _localized('Sponsorisé', 'Sponsored');
    final semanticsLabel = _localized(
      'Placement sponsorisé. Ce badge ne signifie pas que le professionnel est vérifié.',
      'Sponsored placement. This badge does not mean the professional is verified.',
    );

    return Semantics(
      key: ValueKey('directory_sponsored_${professionnel.id}'),
      label: semanticsLabel,
      readOnly: true,
      child: ExcludeSemantics(
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: AppSpacing.xs,
          ),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.secondaryContainer,
            borderRadius: BorderRadius.circular(AppRadii.pill),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.campaign_outlined,
                color: Theme.of(context).colorScheme.onSecondaryContainer,
                size: 16,
              ),
              const SizedBox(width: AppSpacing.xs),
              Text(
                label,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSecondaryContainer,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.sousCategorie.getTitleInLanguage(
            _localizationService.currentLanguage,
          ),
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
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
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 920),
                child: Column(
                  children: [
                    TextField(
                      decoration: InputDecoration(
                        labelText: _localizationService.tr(
                          'search_professional',
                        ),
                        labelStyle: const TextStyle(color: Colors.white70),
                        prefixIcon: const Icon(
                          Icons.search,
                          color: Colors.white70,
                        ),
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
                                tooltip: _localizationService.tr(
                                  'search_by_city',
                                ),
                              ),
                        filled: true,
                        fillColor: Colors.white.withValues(alpha: 0.12),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(25),
                          borderSide: BorderSide.none,
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(25),
                          borderSide: const BorderSide(
                            color: Colors.white,
                            width: 2,
                          ),
                        ),
                      ),
                      style: const TextStyle(color: Colors.white),
                      onChanged: _filterProfessionnels,
                    ),
                    // Indicateur de filtre par ville
                    if (_isSearchingByCity)
                      Padding(
                        padding: const EdgeInsets.only(top: AppSpacing.sm),
                        child: Semantics(
                          button: true,
                          label: _localized(
                            'Filtre ville $_citySearchQuery. Retirer le filtre.',
                            'City filter $_citySearchQuery. Remove filter.',
                          ),
                          child: InputChip(
                            avatar: const Icon(Icons.location_on, size: 18),
                            label: Text(
                              '${_localizationService.tr('filter_by')} $_citySearchQuery',
                            ),
                            onDeleted: _clearAllFilters,
                            deleteButtonTooltipMessage: _localized(
                              'Retirer le filtre de ville',
                              'Remove city filter',
                            ),
                            backgroundColor: Colors.white.withValues(
                              alpha: 0.14,
                            ),
                            side: BorderSide(
                              color: Colors.white.withValues(alpha: 0.72),
                            ),
                            labelStyle: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                            ),
                            iconTheme: const IconThemeData(color: Colors.white),
                          ),
                        ),
                      ),
                    // Indicateur de tri actif
                    if (_currentSortOption != SortOption.defaultOrder)
                      Padding(
                        padding: EdgeInsets.only(
                          top: _isSearchingByCity
                              ? AppSpacing.xs
                              : AppSpacing.sm,
                        ),
                        child: Semantics(
                          button: true,
                          label: _localized(
                            'Tri ${_getSortOptionText(_currentSortOption)}. Revenir au tri par defaut.',
                            'Sort ${_getSortOptionText(_currentSortOption)}. Return to default sort.',
                          ),
                          child: InputChip(
                            avatar: Icon(
                              _getSortOptionIcon(_currentSortOption),
                              size: 18,
                            ),
                            label: Text(_getSortOptionText(_currentSortOption)),
                            onDeleted: () =>
                                _changeSortOption(SortOption.defaultOrder),
                            deleteButtonTooltipMessage: _localized(
                              'Retirer ce tri',
                              'Remove this sort',
                            ),
                            backgroundColor: Colors.white.withValues(
                              alpha: 0.14,
                            ),
                            side: BorderSide(
                              color: Colors.white.withValues(alpha: 0.72),
                            ),
                            labelStyle: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                            ),
                            iconTheme: const IconThemeData(color: Colors.white),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          // Liste des professionnels
          Expanded(
            child: RefreshIndicator(
              onRefresh: _forceCompleteRefresh,
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _errorKey != null
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
                              Text(_localizationService.tr(_errorKey!)),
                              const SizedBox(height: 16),
                              ElevatedButton(
                                onPressed: () =>
                                    _loadProfessionnels(forceRefresh: true),
                                child: Text(
                                  _localizationService.tr('try_again'),
                                ),
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
                      separatorBuilder: (_, _) => const SizedBox(height: 12),
                      itemBuilder: (context, index) {
                        final prof = _filteredProfessionnels[index];
                        final galleryImages = prof.getAllGalleryImages();
                        return Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 920),
                            child:
                                AnimatedContainer(
                                  duration: Duration(
                                    milliseconds:
                                        220 + (index.clamp(0, 6) * 35),
                                  ),
                                  curve: Curves.easeOutCubic,
                                  child: Hero(
                                    tag: 'prof_${prof.id}',
                                    child: Material(
                                      elevation: 0,
                                      color: Theme.of(context)
                                          .colorScheme
                                          .surface,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(
                                          AppRadii.card,
                                        ),
                                        side: BorderSide(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .outlineVariant,
                                        ),
                                      ),
                                      child: InkWell(
                                        borderRadius: BorderRadius.circular(
                                          AppRadii.card,
                                        ),
                                        onTap: () async {
                                          await Navigator.push(
                                            context,
                                            PageRouteBuilder(
                                              pageBuilder:
                                                  (
                                                    context,
                                                    animation,
                                                    secondaryAnimation,
                                                  ) => ProfessionnelDetailPage(
                                                    professionnel: prof,
                                                    sourcePlacement:
                                                        'directory',
                                                    analyticsService:
                                                        _analytics,
                                                    dataService: _dataService,
                                                  ),
                                              transitionsBuilder:
                                                  (
                                                    context,
                                                    animation,
                                                    secondaryAnimation,
                                                    child,
                                                  ) {
                                                    const begin = Offset(
                                                      1.0,
                                                      0.0,
                                                    );
                                                    const end = Offset.zero;
                                                    const curve =
                                                        Curves.easeInOutQuart;

                                                    var tween =
                                                        Tween(
                                                          begin: begin,
                                                          end: end,
                                                        ).chain(
                                                          CurveTween(
                                                            curve: curve,
                                                          ),
                                                        );

                                                    return SlideTransition(
                                                      position: animation.drive(
                                                        tween,
                                                      ),
                                                      child: FadeTransition(
                                                        opacity: animation,
                                                        child: child,
                                                      ),
                                                    );
                                                  },
                                              transitionDuration:
                                                  const Duration(
                                                    milliseconds: 500,
                                                  ),
                                            ),
                                          );
                                          if (!mounted) return;
                                          await _loadFavorites();
                                        },
                                        child: Container(
                                          decoration: BoxDecoration(
                                            borderRadius: BorderRadius.circular(
                                              AppRadii.card,
                                            ),
                                          ),
                                          padding: const EdgeInsets.all(
                                            AppSpacing.md,
                                          ),
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.stretch,
                                            children: [
                                              Row(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  // Photo du professionnel
                                                  Container(
                                                    width: 72,
                                                    height: 72,
                                                    decoration: BoxDecoration(
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                            AppRadii.control,
                                                          ),
                                                      gradient: LinearGradient(
                                                        colors: [
                                                          AppTheme.brandPrimary,
                                                          AppTheme
                                                              .brandSecondary,
                                                        ],
                                                      ),
                                                    ),
                                                    child: prof.image.isNotEmpty
                                                        ? ClipRRect(
                                                            borderRadius:
                                                                BorderRadius.circular(
                                                                  AppRadii
                                                                      .control,
                                                                ),
                                                            child: FastImageWidget(
                                                              imageUrl:
                                                                  getValidImageUrl(
                                                                    prof.image,
                                                                  ),
                                                              width: 72,
                                                              height: 72,
                                                              fit: BoxFit.cover,
                                                              placeholder: Container(
                                                                width: 72,
                                                                height: 72,
                                                                decoration: BoxDecoration(
                                                                  color: Colors
                                                                      .grey[300],
                                                                  borderRadius:
                                                                      BorderRadius.circular(
                                                                        AppRadii
                                                                            .control,
                                                                      ),
                                                                ),
                                                                child: const Icon(
                                                                  Icons.person,
                                                                  color: Colors
                                                                      .white,
                                                                  size: 30,
                                                                ),
                                                              ),
                                                              errorWidget:
                                                                  const Icon(
                                                                    Icons
                                                                        .person,
                                                                    color: Colors
                                                                        .white,
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
                                                      crossAxisAlignment:
                                                          CrossAxisAlignment
                                                              .start,
                                                      children: [
                                                        Text(
                                                          prof.title,
                                                          style:
                                                              Theme.of(context)
                                                                  .textTheme
                                                                  .titleMedium,
                                                          maxLines: 2,
                                                          overflow: TextOverflow
                                                              .ellipsis,
                                                        ),
                                                        if (prof.sponsor) ...[
                                                          const SizedBox(
                                                            height:
                                                                AppSpacing.xs,
                                                          ),
                                                          Align(
                                                            alignment: Alignment
                                                                .centerLeft,
                                                            child:
                                                                _buildSponsoredBadge(
                                                                  prof,
                                                                ),
                                                          ),
                                                        ],
                                                        const SizedBox(
                                                          height: AppSpacing.xs,
                                                        ),
                                                        Wrap(
                                                          spacing:
                                                              AppSpacing.sm,
                                                          runSpacing:
                                                              AppSpacing.xs,
                                                          crossAxisAlignment:
                                                              WrapCrossAlignment
                                                                  .center,
                                                          children: [
                                                            Semantics(
                                                              label: _localized(
                                                                'Categorie ${widget.sousCategorie.getTitleInLanguage(_localizationService.currentLanguage)}',
                                                                'Category ${widget.sousCategorie.getTitleInLanguage(_localizationService.currentLanguage)}',
                                                              ),
                                                              child: ConstrainedBox(
                                                                constraints:
                                                                    const BoxConstraints(
                                                                      maxWidth:
                                                                          220,
                                                                    ),
                                                                child: Row(
                                                                  children: [
                                                                    Icon(
                                                                      Icons
                                                                          .work_outline,
                                                                      size: 16,
                                                                      color: Theme.of(
                                                                        context,
                                                                      ).colorScheme.onSurfaceVariant,
                                                                    ),
                                                                    const SizedBox(
                                                                      width:
                                                                          AppSpacing
                                                                              .xs,
                                                                    ),
                                                                    Expanded(
                                                                      child: Text(
                                                                        widget
                                                                            .sousCategorie
                                                                            .getTitleInLanguage(
                                                                              _localizationService.currentLanguage,
                                                                            ),
                                                                        maxLines:
                                                                            1,
                                                                        overflow:
                                                                            TextOverflow.ellipsis,
                                                                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                                                                          color: Theme.of(
                                                                            context,
                                                                          ).colorScheme.onSurfaceVariant,
                                                                        ),
                                                                      ),
                                                                    ),
                                                                  ],
                                                                ),
                                                              ),
                                                            ),
                                                            if (prof
                                                                .ville
                                                                .isNotEmpty)
                                                              Semantics(
                                                                label: _localized(
                                                                  'Ville ${prof.ville}',
                                                                  'City ${prof.ville}',
                                                                ),
                                                                child: Row(
                                                                  mainAxisSize:
                                                                      MainAxisSize
                                                                          .min,
                                                                  children: [
                                                                    Icon(
                                                                      Icons
                                                                          .location_on_outlined,
                                                                      size: 16,
                                                                      color: Theme.of(
                                                                        context,
                                                                      ).colorScheme.onSurfaceVariant,
                                                                    ),
                                                                    const SizedBox(
                                                                      width: AppSpacing
                                                                          .xxs,
                                                                    ),
                                                                    Text(
                                                                      prof.ville,
                                                                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                                                        color: Theme.of(
                                                                          context,
                                                                        ).colorScheme.onSurfaceVariant,
                                                                      ),
                                                                    ),
                                                                  ],
                                                                ),
                                                              ),
                                                            _buildCompactRating(
                                                              prof,
                                                            ),
                                                          ],
                                                        ),
                                                        if (prof
                                                            .subtitle
                                                            .isNotEmpty) ...[
                                                          const SizedBox(
                                                            height:
                                                                AppSpacing.xs,
                                                          ),
                                                          Text(
                                                            prof.subtitle,
                                                            style:
                                                                Theme.of(
                                                                      context,
                                                                    )
                                                                    .textTheme
                                                                    .bodyMedium
                                                                    ?.copyWith(
                                                                      color: Theme.of(
                                                                        context,
                                                                      ).colorScheme.onSurfaceVariant,
                                                                    ),
                                                            maxLines: 2,
                                                            overflow:
                                                                TextOverflow
                                                                    .ellipsis,
                                                          ),
                                                        ],
                                                        if (prof
                                                            .address
                                                            .isNotEmpty) ...[
                                                          const SizedBox(
                                                            height:
                                                                AppSpacing.xs,
                                                          ),
                                                          Semantics(
                                                            button: true,
                                                            label: _localized(
                                                              'Ouvrir l itineraire vers ${prof.address}',
                                                              'Open directions to ${prof.address}',
                                                            ),
                                                            child: TextButton.icon(
                                                              key: ValueKey(
                                                                'directory_address_${prof.id}',
                                                              ),
                                                              onPressed: () =>
                                                                  _openMaps(
                                                                    prof,
                                                                  ),
                                                              style: TextButton.styleFrom(
                                                                alignment: Alignment
                                                                    .centerLeft,
                                                                minimumSize:
                                                                    const Size(
                                                                      48,
                                                                      48,
                                                                    ),
                                                                padding: const EdgeInsets.symmetric(
                                                                  horizontal:
                                                                      AppSpacing
                                                                          .xs,
                                                                ),
                                                              ),
                                                              icon: const Icon(
                                                                Icons
                                                                    .directions_outlined,
                                                                size: 18,
                                                              ),
                                                              label: Text(
                                                                prof.address,
                                                                maxLines: 2,
                                                                overflow:
                                                                    TextOverflow
                                                                        .ellipsis,
                                                              ),
                                                            ),
                                                          ),
                                                        ],
                                                        CouponWidget(
                                                          professionnel: prof,
                                                          isCompact: true,
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                ],
                                              ),
                                              const SizedBox(
                                                height: AppSpacing.xs,
                                              ),
                                              Row(
                                                mainAxisAlignment:
                                                    MainAxisAlignment.end,
                                                children: [
                                                  // Indicateur de galerie si le professionnel a des images
                                                  if (galleryImages
                                                      .isNotEmpty) ...[
                                                    const SizedBox(width: 8),
                                                    Semantics(
                                                      button: true,
                                                      label: _localized(
                                                        'Ouvrir la galerie de ${prof.title}',
                                                        'Open ${prof.title} gallery',
                                                      ),
                                                      child: GalleryPreviewWidget(
                                                        images: galleryImages,
                                                        size: 48,
                                                        onTap: () {
                                                          Navigator.push(
                                                            context,
                                                            MaterialPageRoute(
                                                              builder: (_) => ProfessionnelDetailPage(
                                                                professionnel:
                                                                    prof,
                                                                sourcePlacement:
                                                                    'directory',
                                                                analyticsService:
                                                                    _analytics,
                                                                dataService:
                                                                    _dataService,
                                                              ),
                                                            ),
                                                          );
                                                        },
                                                      ),
                                                    ),
                                                  ],

                                                  // Bouton favoris
                                                  Semantics(
                                                    button: true,
                                                    toggled: _favoriteIds
                                                        .contains(prof.id),
                                                    label: _localized(
                                                      _favoriteIds.contains(
                                                            prof.id,
                                                          )
                                                          ? 'Retirer ${prof.title} des favoris'
                                                          : 'Ajouter ${prof.title} aux favoris',
                                                      _favoriteIds.contains(
                                                            prof.id,
                                                          )
                                                          ? 'Remove ${prof.title} from favorites'
                                                          : 'Add ${prof.title} to favorites',
                                                    ),
                                                    child: IconButton(
                                                      icon: Icon(
                                                        _favoriteIds.contains(
                                                              prof.id,
                                                            )
                                                            ? Icons.favorite
                                                            : Icons
                                                                  .favorite_border,
                                                        color:
                                                            _favoriteIds
                                                                .contains(
                                                                  prof.id,
                                                                )
                                                            ? Theme.of(context)
                                                                  .colorScheme
                                                                  .error
                                                            : Theme.of(context)
                                                                  .colorScheme
                                                                  .onSurfaceVariant,
                                                      ),
                                                      onPressed: () =>
                                                          _toggleFavorite(
                                                            prof.id,
                                                          ),
                                                      tooltip: _localized(
                                                        _favoriteIds.contains(
                                                              prof.id,
                                                            )
                                                            ? 'Supprimer des favoris'
                                                            : 'Ajouter aux favoris',
                                                        _favoriteIds.contains(
                                                              prof.id,
                                                            )
                                                            ? 'Remove from favorites'
                                                            : 'Add to favorites',
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ).trackEngagementVisibility(
                                  key: ValueKey(
                                    'directory_impression_${prof.id}',
                                  ),
                                  onQualifiedVisibility: () =>
                                      _trackDirectoryImpression(prof),
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
