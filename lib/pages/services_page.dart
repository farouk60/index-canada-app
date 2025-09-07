import 'package:flutter/material.dart';
import 'dart:async';
import '../models.dart';
import '../data_service.dart';
import '../utils.dart';
import '../utils/string_utils.dart';
import '../services/localization_service.dart';
import '../services/firebase_analytics_service.dart';
import '../widgets/language_selector.dart';
import 'professionnels_page.dart';
import 'professional_registration_page.dart';
import '_wix_image_with_fallback.dart';
import '../theme/app_theme.dart';

class ServicesPage extends StatefulWidget {
  const ServicesPage({super.key});

  @override
  State<ServicesPage> createState() => _ServicesPageState();
}

class _ServicesPageState extends State<ServicesPage>
    with WidgetsBindingObserver {
  // Global toggle to disable heavy preloading on low-end devices
  static const bool _enablePreload = true; // Activé pour optimiser le chargement
  final LocalizationService _localizationService = LocalizationService();
  final FirebaseAnalyticsService _analytics = FirebaseAnalyticsService();
  String _searchQuery = '';
  List<SousCategorie> _allSousCategories = [];
  List<SousCategorie> _filteredSousCategories = [];
  bool _isLoading = true;
  String? _error;
  Timer? _refreshTimer;
  final ScrollController _scrollController = ScrollController();
  final Set<int> _preloadedIndexes = <int>{};

  // Contrôleur pour annuler les opérations en cours
  bool _isDisposed = false;

  // Débouncer pour le scroll
  Timer? _scrollDebounceTimer;

  // Construit un item de grille (isolé pour éviter les erreurs de parenthèses)
  Widget _buildCategoryTile(SousCategorie sc, int index) {
    return AnimatedContainer(
      key: ValueKey('svc_${sc.id}_${_localizationService.currentLanguage}'),
      duration: Duration(milliseconds: 150 + (index * 25)),
      curve: Curves.easeOut,
      child: Material(
        elevation: 4,
        borderRadius: BorderRadius.circular(16),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: LinearGradient(
              colors: [Colors.white, Colors.grey.shade50],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () async {
              await _analytics.trackCategoryView(
                categoryId: sc.id,
                categoryName: sc.title,
                categoryNameEn: sc.titleEn,
                sourceScreen: 'services_page',
              );
              if (!mounted || _isDisposed) return;
              Navigator.push(
                context,
                PageRouteBuilder(
                  pageBuilder: (
                    context,
                    animation,
                    secondaryAnimation,
                  ) => ProfessionnelsPage(
                    sousCategorie: sc,
                  ),
                  transitionsBuilder: (
                    context,
                    animation,
                    secondaryAnimation,
                    child,
                  ) {
                    const begin = Offset(0.0, 1.0);
                    const end = Offset.zero;
                    const curve = Curves.easeOut;
                    var tween =
                        Tween(begin: begin, end: end).chain(CurveTween(curve: curve));
                    return SlideTransition(
                      position: animation.drive(tween),
                      child: child,
                    );
                  },
                  transitionDuration: const Duration(milliseconds: 300),
                ),
              );
            },
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                gradient: LinearGradient(
                  colors: [
                    AppTheme.brandPrimary.withOpacity(0.95),
                    AppTheme.brandSecondary.withOpacity(0.95),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Stack(
                  children: [
          if (sc.getImageInLanguage(_localizationService.currentLanguage).isNotEmpty)
                      Positioned.fill(
            child: WixImageWithFallback(
              sc.getImageInLanguage(_localizationService.currentLanguage),
              index: index,
              // ensure a different widget identity per language
              key: ValueKey('img_${sc.id}_${_localizationService.currentLanguage}'),
            ),
                      )
                    else
                      Positioned.fill(
                        child: Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                AppTheme.brandPrimary,
                                AppTheme.brandSecondary,
                              ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                          ),
                          child: const Center(
                            child: Icon(
                              Icons.category,
                              color: Colors.white,
                              size: 60,
                            ),
                          ),
                        ),
                      ),
                    Positioned.fill(
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.transparent,
                              Colors.black.withOpacity(0.65),
                            ],
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      bottom: 0,
                      left: 0,
                      right: 0,
                      child: Container(
                        padding: const EdgeInsets.all(14),
                        child: Text(
                          sc.getTitleInLanguage(
                            _localizationService.currentLanguage,
                          ),
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                            shadows: [
                              Shadow(
                                offset: Offset(0, 1),
                                blurRadius: 2,
                                color: Colors.black54,
                              ),
                            ],
                          ),
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadSousCategories();
    if (_enablePreload) {
      _setupScrollListener();
    }
  }

  // Configuration de l'écoute du scroll pour le préchargement
  void _setupScrollListener() {
    _scrollController.addListener(() {
      if (_isDisposed) return;
      
      _scrollDebounceTimer?.cancel();
      _scrollDebounceTimer = Timer(const Duration(milliseconds: 100), () {
        if (_isDisposed) return;
        _preloadVisibleImages();
      });
    });
  }

  // Préchargement intelligent des images visibles et suivantes
  void _preloadVisibleImages() {
    if (_isDisposed || _filteredSousCategories.isEmpty || !_scrollController.hasClients) return;

    const itemHeight = 200.0; // Hauteur approximative d'un item
    const itemsPerRow = 2;
    
    final scrollOffset = _scrollController.offset;
    final viewportHeight = MediaQuery.of(context).size.height;
    
    // Calculer les index visibles + marge
    final firstVisibleIndex = (scrollOffset / itemHeight).floor() * itemsPerRow;
    final lastVisibleIndex = ((scrollOffset + viewportHeight * 1.5) / itemHeight).ceil() * itemsPerRow;
    
    // Précharger les images dans cette plage
    for (int i = firstVisibleIndex; i <= lastVisibleIndex && i < _filteredSousCategories.length; i++) {
      if (!_preloadedIndexes.contains(i)) {
        _preloadedIndexes.add(i);
        _preloadImageAtIndex(i);
      }
    }
  }

  // Préchargement d'une image spécifique
  void _preloadImageAtIndex(int index) async {
    if (_isDisposed || index >= _filteredSousCategories.length) return;
    
    try {
      final category = _filteredSousCategories[index];
      final imageForLang = category.getImageInLanguage(_localizationService.currentLanguage);
      if (imageForLang.isNotEmpty && mounted) {
        final imageUrl = imageForLang;
        if (imageUrl.startsWith('wix:image://')) {
          // Utiliser la première variante (la plus petite) pour le préchargement
          final variants = getWixImageVariants(imageUrl);
          if (variants.isNotEmpty) {
            await precacheImage(NetworkImage(variants.first), context);
          }
        }
      }
    } catch (e) {
      // Ignorer les erreurs de préchargement
    }
  }

  @override
  void dispose() {
    // Marquer le widget comme fermé pour arrêter toutes les opérations async
    _isDisposed = true;

    WidgetsBinding.instance.removeObserver(this);
    _refreshTimer?.cancel();
    _scrollDebounceTimer?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  // Refresh automatique quand l'app revient au premier plan
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _loadSousCategories(forceRefresh: true);
    }
  }

  Future<void> _loadSousCategories({bool forceRefresh = false}) async {
    try {
      setState(() {
        _isLoading = true;
        _error = null;
      });

      final wixApi = DataService();
      final categories = await wixApi.fetchSousCategories(
        forceRefresh: forceRefresh,
      );

      // Vérifier que le widget est encore monté avant d'utiliser le context
      if (!mounted || _isDisposed) return;

      // Vérifier si on a des données
      if (categories.isEmpty) {
        if (mounted && !_isDisposed) {
          setState(() {
            _error = _localizationService.tr('no_services');
            _isLoading = false;
          });
        }
        return;
      }

      // Tri alphabétique par défaut selon la langue actuelle
      categories.sort(
        (a, b) =>
            normalizeForSorting(
              a.getTitleInLanguage(_localizationService.currentLanguage),
            ).compareTo(
              normalizeForSorting(
                b.getTitleInLanguage(_localizationService.currentLanguage),
              ),
            ),
      );

      // Mettre à jour l'interface immédiatement avec tri selon l'ordre choisi
      if (mounted && !_isDisposed) {
        setState(() {
          _allSousCategories = categories;
          _filteredSousCategories = categories;
          _isLoading = false;
        });
        
        // Démarrer le préchargement des premières images après un court délai
        if (_enablePreload) {
          Future.delayed(const Duration(milliseconds: 500), () {
            if (mounted && !_isDisposed) {
              _preloadVisibleImages();
            }
          });
        }
      }
    } catch (e) {
      if (mounted && !_isDisposed) {
        setState(() {
          _error = 'Erreur chargement: $e';
          _isLoading = false;
        });
      }
    }
  }

  void _filterSousCategories(String query) {
    setState(() {
      _searchQuery = query;
      if (query.isEmpty) {
        _filteredSousCategories = _allSousCategories;
      } else {
        final qNorm = normalizeForSearch(query);
        final qTokens = tokenizeWithoutStopWords(qNorm);

        _filteredSousCategories = _allSousCategories.where((category) {
          final title = category.getTitleInLanguage(_localizationService.currentLanguage);
          final tNorm = normalizeForSearch(title);

          // Correspondance simple: sous-chaîne directe sur la version normalisée
          if (tNorm.contains(qNorm)) return true;

          // Tokenisation et fuzzy matching pour chaque mot significatif
          final tokens = tokenizeWithoutStopWords(tNorm);
          if (qTokens.isEmpty) return false;

          // Règle: chaque token de la requête doit matcher au moins un token du titre
          // avec sous-chaîne ou petite distance de Levenshtein
          for (final qt in qTokens) {
            bool matchedThisQueryToken = false;
            for (final tt in tokens) {
              if (fuzzyTokenMatch(tt, qt)) {
                matchedThisQueryToken = true;
                break;
              }
            }
            if (!matchedThisQueryToken) return false;
          }
          return true;
        }).toList();
      }
        
      // Maintenir le tri alphabétique après filtrage selon la langue actuelle
      _filteredSousCategories.sort((a, b) {
        final titleA = normalizeForSorting(a.getTitleInLanguage(_localizationService.currentLanguage));
        final titleB = normalizeForSorting(b.getTitleInLanguage(_localizationService.currentLanguage));
        return titleA.compareTo(titleB);
      });
      
      // Nettoyer le cache de préchargement après filtrage
      _preloadedIndexes.clear();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // When the inherited localization changes, refresh list so tiles get new keys
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _isDisposed) return;
      setState(() {
        // trigger rebuild; filtering stays the same
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _localizationService.tr('services'),
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        foregroundColor: Colors.white,
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
          LanguageSelector(
            onLanguageChanged: (String languageCode) {
              // Forcer la reconstruction ET le tri alphabétique selon la nouvelle langue
              setState(() {
                // Retrier alphabétiquement selon la nouvelle langue
                _allSousCategories.sort(
                  (a, b) =>
                      normalizeForSorting(
                        a.getTitleInLanguage(languageCode),
                      ).compareTo(
                        normalizeForSorting(
                          b.getTitleInLanguage(languageCode),
                        ),
                      ),
                );
                
                // Appliquer le même tri aux catégories filtrées
                _filteredSousCategories.sort(
                  (a, b) =>
                      normalizeForSorting(
                        a.getTitleInLanguage(languageCode),
                      ).compareTo(
                        normalizeForSorting(
                          b.getTitleInLanguage(languageCode),
                        ),
                      ),
                );
                
                // Nettoyer le cache de préchargement pour recharger avec le nouveau tri
                _preloadedIndexes.clear();
              });
              
              // Relancer le préchargement après le changement d'ordre
              if (_enablePreload) {
                Future.delayed(const Duration(milliseconds: 300), () {
                  if (mounted && !_isDisposed) {
                    _preloadVisibleImages();
                  }
                });
              }
            },
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => _loadSousCategories(forceRefresh: true),
            tooltip: _localizationService.tr('refresh'),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: TextField(
              decoration: InputDecoration(
                labelText: _localizationService.tr('search'),
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _filterSousCategories('');
                        },
                      )
                    : null,
              ),
              onChanged: _filterSousCategories,
            ),
          ),
          Container(
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppTheme.brandTertiary, AppTheme.brandPrimary],
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
              ),
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(color: AppTheme.brandPrimary.withOpacity(0.25), blurRadius: 8, offset: const Offset(0, 4)),
              ],
            ),
            child: InkWell(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const ProfessionalRegistrationPage(),
                  ),
                );
              },
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.business_center,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _localizationService.currentLanguage == 'fr'
                              ? 'Professionnel ?'
                              : 'Professional?',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        Text(
                          _localizationService.currentLanguage == 'fr'
                              ? 'Rejoignez notre annuaire'
                              : 'Join our directory',
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(
                    Icons.arrow_forward_ios,
                    color: Colors.white,
                    size: 16,
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async => _loadSousCategories(forceRefresh: true),
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
                                    Icons.error_outline,
                                    size: 64,
                                    color: Colors.red[400],
                                  ),
                                  const SizedBox(height: 16),
                                  Text(
                                    '${_localizationService.tr('error')}: $_error',
                                    style: TextStyle(
                                      fontSize: 16,
                                      color: Colors.red[600],
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                  const SizedBox(height: 16),
                                  ElevatedButton(
                                    onPressed: () => _loadSousCategories(forceRefresh: true),
                                    child: Text(
                                      _localizationService.tr('try_again'),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        )
                      : _filteredSousCategories.isEmpty && _searchQuery.isNotEmpty
                          ? Center(
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
                                    '${_localizationService.tr('no_professionals_search')} "$_searchQuery"',
                                    style: TextStyle(
                                      fontSize: 16,
                                      color: Colors.grey[600],
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                ],
                              ),
                            )
                          : _filteredSousCategories.isEmpty
                              ? Center(child: Text(_localizationService.tr('no_services')))
                              : GridView.builder(
                                  controller: _scrollController,
                                  padding: const EdgeInsets.all(16),
                                  physics: const BouncingScrollPhysics(),
                                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                                    crossAxisCount: 2,
                                    crossAxisSpacing: 12,
                                    mainAxisSpacing: 12,
                                    childAspectRatio: 1.0,
                                  ),
                                  itemCount: _filteredSousCategories.length,
                                  itemBuilder: (context, index) {
                                    final sc = _filteredSousCategories[index];
                                    return RepaintBoundary(
                                      child: _buildCategoryTile(sc, index),
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
