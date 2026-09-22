import 'package:flutter/material.dart';

import 'dart:async';

import '../models.dart';
import '../models/wix_partner_models.dart';
import '../models/wix_offer_models.dart';
import '../data_service.dart';
import '../image_cache_service.dart';
import '../services/localization_service.dart';
import '../services/firebase_analytics_service.dart';
import '../services/cache_manager_service.dart';
import '../widgets/language_selector.dart';
import '../widgets/home_discovery_hero.dart';
import '../widgets/wix_partner_widgets.dart';
import '../widgets/wix_offers_widgets.dart';
import 'services_page.dart';
import 'professionnels_page.dart';
import 'professionnel_detail_page.dart';
import 'favorites_page.dart';
import 'professional_registration_page.dart';
import '../utils.dart'; // Importer utils.dart pour getValidImageUrl

class HomePage extends StatefulWidget {
  const HomePage({super.key, this.onExploreServices, this.onOpenFavorites});

  final VoidCallback? onExploreServices;
  final VoidCallback? onOpenFavorites;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  final PageController _pageController = PageController();
  final PageController _partnersPageController = PageController();
  final LocalizationService _localizationService = LocalizationService();
  final FirebaseAnalyticsService _analytics = FirebaseAnalyticsService();
  final DataService _dataService = DataService();
  List<Professionnel> _featured = [];
  List<WixPartner> _partners = [];
  List<WixOffer> _offers = [];
  List<SousCategorie> _sousCategories =
      []; // Pour afficher les noms des catégories
  bool _isLoadingPartners = false;
  bool _isLoadingSousCategories = false;
  bool _isLoadingHome = true;
  bool _hasLoadError = false;
  int _homeLoadGeneration = 0;

  Future<void> _openServices() async {
    final selectServices = widget.onExploreServices;
    if (selectServices != null) {
      selectServices();
      return;
    }

    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ServicesPage()),
    );
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _openFavorites() async {
    final selectFavorites = widget.onOpenFavorites;
    if (selectFavorites != null) {
      selectFavorites();
      return;
    }

    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const FavoritesPage()),
    );
    if (mounted) {
      setState(() {});
    }
  }

  // Petit helper pour un pictogramme moderne (icône dans un cercle en dégradé)
  Widget _sectionIcon(IconData icon, List<Color> gradientColors) {
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          colors: gradientColors,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: gradientColors.first.withValues(alpha: 0.25),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Icon(icon, color: Colors.white, size: 20),
    );
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // Chargement optimisé en séquence pour éviter la surcharge
    _initializeData();

    _setScreenName();
  }

  // Initialisation optimisée: chargements parallèles et un seul setState
  Future<void> _initializeData() async {
    await _loadAllData(forceRefresh: false);
  }

  // Charge toutes les sections en parallèle et applique l'état une seule fois
  Future<void> _loadAllData({bool forceRefresh = false}) async {
    if (!mounted) return;

    final loadGeneration = ++_homeLoadGeneration;
    setState(() {
      _isLoadingHome = true;
      _hasLoadError = false;
    });

    try {
      final ds = _dataService;
      if (forceRefresh) {
        await ds.forceSyncWithWix();
        if (!mounted || loadGeneration != _homeLoadGeneration) return;
      }

      // Toutes les sections lisent ensuite le même instantané mis en cache.
      final futures = await Future.wait([
        ds.fetchSousCategories(),
        ds.fetchSponsoredProfessionnels(),
        ds.fetchPartners(),
        ds.fetchExclusiveOffers().timeout(
          const Duration(seconds: 8),
          onTimeout: () => <WixOffer>[],
        ),
      ], eagerError: false);

      if (!mounted || loadGeneration != _homeLoadGeneration) return;

      final sousCategories = futures[0] as List<SousCategorie>;
      final featured = futures[1] as List<Professionnel>;
      final partners = futures[2] as List<WixPartner>;
      final offers = futures[3] as List<WixOffer>;

      setState(() {
        _sousCategories = sousCategories;
        _featured = featured;
        _partners = partners;
        _offers = offers;
        _isLoadingHome = false;
      });

      // Préchargement images après setState pour éviter les saccades
      if (featured.isNotEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _preloadFeaturedImages(featured);
        });
      }

      // Précharger partenaires et offres
      if (partners.isNotEmpty || offers.isNotEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _preloadPartnerAndOfferImages(partners, offers);
        });
      }
    } on Exception {
      if (mounted && loadGeneration == _homeLoadGeneration) {
        setState(() {
          _isLoadingHome = false;
          _hasLoadError = true;
        });
      }
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Se déclenche quand on revient sur cette page
    // Forcer la reconstruction pour actualiser la langue si nécessaire
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);

    // Disposer les contrôleurs
    _pageController.dispose();
    _partnersPageController.dispose();

    super.dispose();
  }

  // Refresh automatique quand l'app revient au premier plan
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _loadAllData(forceRefresh: true);
    }
  }

  Future<void> _loadFeatured({bool forceRefresh = false}) async {
    try {
      final dataService = DataService();
      if (forceRefresh) {
        await dataService.forceSyncWithWix();
      }
      final featured = await dataService.fetchSponsoredProfessionnels();

      if (!mounted) return;

      setState(() {
        _featured = featured;
      });

      // Charger aussi les sous-catégories pour afficher les noms
      _loadSousCategories();

      // Précharger les images des professionnels en vedette pour améliorer les performances
      if (featured.isNotEmpty) {
        _preloadFeaturedImages(featured);
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _featured = [];
        });
      }
    }
  }

  // Charger les sous-catégories pour pouvoir afficher les noms
  Future<void> _loadSousCategories() async {
    // Éviter les appels multiples simultanés
    if (_isLoadingSousCategories) {
      return;
    }

    _isLoadingSousCategories = true;
    try {
      final sousCategories = await _dataService.fetchSousCategories();
      if (mounted) {
        setState(() {
          _sousCategories = sousCategories;
        });

        // Forcer un nouveau rebuild pour mettre à jour les noms de catégories
        if (_featured.isNotEmpty) {
          setState(() {
            // Force rebuild des cartes professionnels avec les noms de catégories
          });
        }
      }
    } catch (_) {
      // Conserver silencieusement les données déjà affichées.
    } finally {
      _isLoadingSousCategories = false;
    }
  }

  /// Effectue un rafraîchissement complet en vidant tous les caches
  Future<void> _performCompleteRefresh() async {
    if (!mounted) return;

    try {
      // Réinitialiser d'abord les listes locales pour éviter l'affichage de données obsolètes
      setState(() {
        _sousCategories = []; // Vider la liste des sous-catégories
        _featured =
            []; // Vider temporairement la liste des professionnels en vedette
      });

      // Utiliser le service global de gestion de cache
      final cacheManager = CacheManagerService();
      await cacheManager.performCompleteRefresh(
        context: context,
        showMessages: true,
      );
      if (!mounted) return;

      // Un seul rechargement cohérent évite que des réponses concurrentes
      // remplacent partiellement les données les plus récentes.
      await _loadAllData();
    } catch (_) {
      // Les messages d'erreur sont gérés par le CacheManagerService
    }
  }

  // Récupérer le nom de la sous-catégorie à partir de son ID
  String _getSousCategorieTitle(String sousCategorieId) {
    try {
      // Si les sous-catégories ne sont pas encore chargées, retourner un placeholder
      if (_sousCategories.isEmpty) {
        // Déclencher le rechargement des sous-catégories si elles sont vides
        Future.microtask(() => _loadSousCategories());
        return '...'; // Placeholder au lieu de l'ID brut
      }

      final sousCategorie = _sousCategories.firstWhere(
        (sc) => sc.id == sousCategorieId,
      );
      final title = sousCategorie.getTitleInLanguage(
        _localizationService.currentLanguage,
      );
      return title;
    } catch (_) {
      // Si pas trouvé, essayer de recharger les sous-catégories et retourner un texte générique
      Future.microtask(() => _loadSousCategories());
      return _localizationService.currentLanguage == 'fr'
          ? 'Service'
          : 'Service';
    }
  }

  // Naviguer vers la page de la catégorie
  void _navigateToCategory(String sousCategorieId) {
    try {
      final sousCategorie = _sousCategories.firstWhere(
        (sc) => sc.id == sousCategorieId,
      );

      Navigator.push(
        context,
        PageRouteBuilder(
          pageBuilder: (context, animation, secondaryAnimation) =>
              ProfessionnelsPage(sousCategorie: sousCategorie),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            const begin = Offset(1.0, 0.0);
            const end = Offset.zero;
            const curve = Curves.easeInOutQuart;

            var tween = Tween(
              begin: begin,
              end: end,
            ).chain(CurveTween(curve: curve));

            return SlideTransition(
              position: animation.drive(tween),
              child: FadeTransition(opacity: animation, child: child),
            );
          },
          transitionDuration: const Duration(milliseconds: 500),
        ),
      );
    } catch (_) {
      // Fallback : naviguer vers la page services générale
      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => const ServicesPage()),
      );
    }
  }

  // Précharger les images des professionnels en vedette
  void _preloadFeaturedImages(List<Professionnel> featured) {
    final imageService = ImageCacheService();
    final imageUrls = featured
        .where((professional) => professional.image.isNotEmpty)
        .map((professional) => professional.image)
        .toList();

    // Précharger toutes les images en parallèle
    imageService.preloadImages(imageUrls, context);
  }

  // Précharger les images des partenaires et des offres
  void _preloadPartnerAndOfferImages(
    List<WixPartner> partners,
    List<WixOffer> offers,
  ) {
    final imageService = ImageCacheService();

    final partnerUrls = partners
        .map((p) => getValidImageUrl(p.banner.isNotEmpty ? p.banner : p.logo))
        .where((u) => u.isNotEmpty)
        .toList();

    final offerUrls = offers
        .map((o) => getValidImageUrl(o.image))
        .where((u) => u.isNotEmpty)
        .toList();

    final all = <String>[...partnerUrls, ...offerUrls];

    if (all.isNotEmpty) {
      imageService.preloadImages(all, context);
    }
  }

  // Vérifier si un professionnel a un coupon valide
  bool _hasValidCoupon(Professionnel professionnel) {
    // Un coupon est valide s'il a un code et un titre
    bool hasCodeAndTitle =
        professionnel.couponCode.isNotEmpty &&
        (professionnel.couponTitle.isNotEmpty ||
            professionnel.couponTitleEN.isNotEmpty);

    if (!hasCodeAndTitle) return false;

    // Si une date d'expiration est définie, elle doit être dans le futur
    final exp = professionnel.couponExpirationDate;
    if (exp != null) {
      return exp.isAfter(DateTime.now());
    }

    // Si pas de date d'expiration définie, le coupon est considéré comme valide
    return true;
  }

  // Définir le nom de l'écran pour Analytics
  void _setScreenName() async {
    await _analytics.setCurrentScreen('home_page');
  }

  Future<void> _loadPartners({bool forceRefresh = false}) async {
    if (!mounted) return;

    try {
      setState(() {
        _isLoadingPartners = true;
      });

      if (forceRefresh) {
        await _dataService.forceSyncWithWix();
        if (!mounted) return;
      }
      final partners = await _dataService.fetchPartners();

      if (mounted) {
        setState(() {
          _partners = partners;
          _isLoadingPartners = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _isLoadingPartners = false;
          _partners = [];
        });
      }
    }
  }

  Widget _buildPartnersSection() {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Titre de la section
          Row(
            children: [
              _sectionIcon(Icons.groups_rounded, [Colors.indigo, Colors.blue]),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  LocalizationService().tr('our_partners'),
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              IconButton(
                tooltip: _localizationService.tr('refresh'),
                icon: const Icon(Icons.refresh, size: 20),
                onPressed: () => _loadPartners(forceRefresh: true),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Contenu avec indicateur de chargement
          _isLoadingPartners
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(32.0),
                    child: CircularProgressIndicator(),
                  ),
                )
              : _partners.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32.0),
                    child: Text(
                      _localizationService.tr('no_partners_available'),
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                )
              : SizedBox(
                  height: 110, // Ajuster à la nouvelle taille
                  child: PageView.builder(
                    controller: _partnersPageController,
                    itemCount: (_partners.length / 3)
                        .ceil(), // Nombre de pages pour 3 items par page
                    itemBuilder: (context, pageIndex) {
                      // Calculer les indices pour cette page
                      int startIndex = pageIndex * 3;
                      int endIndex = (startIndex + 3)
                          .clamp(0, _partners.length)
                          .toInt();

                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8.0),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            for (int i = startIndex; i < endIndex; i++)
                              SizedBox(
                                width: 110, // Réduire légèrement pour éviter débordement
                                height: 110, // Garder proportionnel
                                child: WixPartnerCard(partner: _partners[i]),
                              ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
        ],
      ),
    );
  }

  // Construire la section des offres exclusives
  Widget _buildOffersSection() {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Titre de la section avec emoji "cible"
          Row(
            children: [
              _sectionIcon(Icons.local_offer_rounded, [
                Colors.orange,
                Colors.redAccent,
              ]),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _localizationService.tr('exclusive_offers'),
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Contenu de la section
          _isLoadingHome && _offers.isEmpty
              ? SizedBox(
                  height: 120,
                  child: const Center(child: CircularProgressIndicator()),
                )
              : _offers.isNotEmpty
              ? WixOfferCarousel(
                  offers: _offers,
                  title: '', // Pas de titre ici car déjà affiché au-dessus
                )
              : SizedBox(
                  height: 80,
                  child: Center(
                    child: Text(
                      _localizationService.tr('no_offers_available'),
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Index Canada'),
        actions: [
          // Debug actions removed
          // Sélecteur de langue
          LanguageSelector(
            onLanguageChanged: (String languageCode) {
              if (mounted) {
                setState(() {});
              }
            },
          ),
          // Bouton Favoris
          IconButton(
            icon: const Icon(Icons.favorite),
            onPressed: _openFavorites,
            tooltip: _localizationService.tr('favorites'),
          ),
          // Icône pour refresh manuel
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () async {
              // Vider tous les caches pour forcer une synchronisation complète
              await _performCompleteRefresh();
            },
            tooltip: _localizationService.tr('refresh'),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          await _performCompleteRefresh();
        },
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(), // Permet le pull-to-refresh même si le contenu ne scroll pas
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: MediaQuery.sizeOf(context).width < 600 ? 16 : 32,
              vertical: 24,
            ),
            child: Column(
              children: [
                HomeDiscoveryHero(onExplore: _openServices),
                if (_isLoadingHome)
                  const Padding(
                    padding: EdgeInsets.only(top: 16),
                    child: LinearProgressIndicator(),
                  ),
                if (_hasLoadError)
                  Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: HomeLoadErrorBanner(
                      onRetry: () =>
                          unawaited(_loadAllData(forceRefresh: true)),
                    ),
                  ),
                const SizedBox(height: 24),
                // Section des professionnels en vedette
                AnimatedOpacity(
                  opacity: _featured.isNotEmpty ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 800),
                  child: Column(
                    children: [
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          _localizationService.tr('sponsored_professionals'),
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                  ),
                ),
                // Section des professionnels en vedette avec gestion d'état propre
                _featured.isNotEmpty
                    ? Column(
                        children: [
                          SizedBox(
                            height: 200,
                            child: PageView.builder(
                              controller: _pageController,
                              itemCount: _featured.length,
                              itemBuilder: (context, index) {
                                final pro = _featured[index];
                                return AnimatedContainer(
                                  duration: Duration(
                                    milliseconds: 300 + (index * 100),
                                  ),
                                  curve: Curves.easeInOut,
                                  margin: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                  ),
                                  child: Card(
                                    elevation: 6,
                                    child: Stack(
                                      children: [
                                        InkWell(
                                          onTap: () async {
                                            // Tracker le clic sur le sponsor
                                            await _analytics.trackSponsorClick(
                                              sponsorId: pro.id,
                                              sponsorName: pro.title,
                                              clickType: 'carousel',
                                              sourceScreen: 'home_page',
                                            );
                                            if (!context.mounted) return;

                                            await Navigator.push(
                                              context,
                                              MaterialPageRoute(
                                                builder: (_) =>
                                                    ProfessionnelDetailPage(
                                                      professionnel: pro,
                                                    ),
                                              ),
                                            );
                                            // Forcer la mise à jour de la page d'accueil quand on revient
                                            if (mounted) {
                                              setState(() {});
                                            }
                                          },
                                          child: Padding(
                                            padding: const EdgeInsets.all(16),
                                            child: Row(
                                              children: [
                                                CircleAvatar(
                                                  radius: 40,
                                                  backgroundColor:
                                                      Colors.grey[200],
                                                  child: pro.image.isNotEmpty
                                                      ? ClipRRect(
                                                          borderRadius:
                                                              BorderRadius.circular(
                                                                40,
                                                              ),
                                                          child: ImageCacheService()
                                                              .buildOptimizedImage(
                                                                imageUrl:
                                                                    pro.image,
                                                                width: 80,
                                                                height: 80,
                                                                fit: BoxFit
                                                                    .cover,
                                                                placeholder: const SizedBox(
                                                                  width: 80,
                                                                  height: 80,
                                                                  child: Center(
                                                                    child: CircularProgressIndicator(
                                                                      strokeWidth:
                                                                          2,
                                                                    ),
                                                                  ),
                                                                ),
                                                                errorWidget:
                                                                    const Icon(
                                                                      Icons
                                                                          .person,
                                                                      size: 40,
                                                                      color: Colors
                                                                          .grey,
                                                                    ),
                                                              ),
                                                        )
                                                      : const Icon(
                                                          Icons.person,
                                                          size: 40,
                                                          color: Colors.grey,
                                                        ),
                                                ),
                                                const SizedBox(width: 16),
                                                Expanded(
                                                  child: Column(
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment
                                                            .start,
                                                    mainAxisAlignment:
                                                        MainAxisAlignment
                                                            .center,
                                                    children: [
                                                      Text(
                                                        pro.title,
                                                        style: const TextStyle(
                                                          fontSize: 18,
                                                          fontWeight:
                                                              FontWeight.bold,
                                                        ),
                                                        maxLines: 1,
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                      ),
                                                      const SizedBox(height: 4),
                                                      // Badge moderne cliquable pour le service (catégorie)
                                                      InkWell(
                                                        onTap: () =>
                                                            _navigateToCategory(
                                                              pro.sousCategorie,
                                                            ),
                                                        borderRadius:
                                                            BorderRadius.circular(
                                                              16,
                                                            ),
                                                        child: Container(
                                                          padding:
                                                              const EdgeInsets.symmetric(
                                                                horizontal: 10,
                                                                vertical: 6,
                                                              ),
                                                          decoration: BoxDecoration(
                                                            gradient: LinearGradient(
                                                              colors: [
                                                                Colors.teal,
                                                                Colors.cyan,
                                                              ],
                                                              begin: Alignment
                                                                  .topLeft,
                                                              end: Alignment
                                                                  .bottomRight,
                                                            ),
                                                            borderRadius:
                                                                BorderRadius.circular(
                                                                  16,
                                                                ),
                                                            boxShadow: [
                                                              BoxShadow(
                                                                color: Colors
                                                                    .teal
                                                                    .withValues(
                                                                      alpha:
                                                                          0.25,
                                                                    ),
                                                                blurRadius: 6,
                                                                offset:
                                                                    const Offset(
                                                                      0,
                                                                      2,
                                                                    ),
                                                              ),
                                                            ],
                                                          ),
                                                          child: Text(
                                                            _getSousCategorieTitle(
                                                              pro.sousCategorie,
                                                            ),
                                                            style:
                                                                const TextStyle(
                                                                  color: Colors
                                                                      .white,
                                                                  fontSize: 12,
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .w600,
                                                                ),
                                                            maxLines: 1,
                                                            overflow:
                                                                TextOverflow
                                                                    .ellipsis,
                                                          ),
                                                        ),
                                                      ),
                                                      // Afficher le coupon si disponible
                                                      if (_hasValidCoupon(
                                                        pro,
                                                      )) ...[
                                                        const SizedBox(
                                                          height: 6,
                                                        ),
                                                        Container(
                                                          padding:
                                                              const EdgeInsets.symmetric(
                                                                horizontal: 8,
                                                                vertical: 4,
                                                              ),
                                                          decoration: BoxDecoration(
                                                            gradient: LinearGradient(
                                                              colors: [
                                                                Colors
                                                                    .purple
                                                                    .shade400,
                                                                Colors
                                                                    .pink
                                                                    .shade400,
                                                              ],
                                                              begin: Alignment
                                                                  .topLeft,
                                                              end: Alignment
                                                                  .bottomRight,
                                                            ),
                                                            borderRadius:
                                                                BorderRadius.circular(
                                                                  8,
                                                                ),
                                                            boxShadow: [
                                                              BoxShadow(
                                                                color: Colors
                                                                    .purple
                                                                    .withValues(
                                                                      alpha:
                                                                          0.3,
                                                                    ),
                                                                blurRadius: 4,
                                                                offset:
                                                                    const Offset(
                                                                      0,
                                                                      2,
                                                                    ),
                                                              ),
                                                            ],
                                                          ),
                                                          child: Row(
                                                            mainAxisSize:
                                                                MainAxisSize
                                                                    .min,
                                                            children: [
                                                              const Icon(
                                                                Icons
                                                                    .local_offer,
                                                                color: Colors
                                                                    .white,
                                                                size: 14,
                                                              ),
                                                              const SizedBox(
                                                                width: 4,
                                                              ),
                                                              Text(
                                                                pro.getCouponTitleInLanguage(
                                                                  _localizationService
                                                                      .currentLanguage,
                                                                ),
                                                                style: const TextStyle(
                                                                  color: Colors
                                                                      .white,
                                                                  fontSize: 11,
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .bold,
                                                                ),
                                                                maxLines: 2,
                                                                overflow:
                                                                    TextOverflow
                                                                        .ellipsis,
                                                              ),
                                                            ],
                                                          ),
                                                        ),
                                                      ],
                                                    ],
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                        // Badge En vedette
                                        Positioned(
                                          top: 8,
                                          right: 8,
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 8,
                                              vertical: 4,
                                            ),
                                            decoration: BoxDecoration(
                                              color: Colors.orange.shade400,
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                              boxShadow: [
                                                BoxShadow(
                                                  color: Colors.orange.shade200,
                                                  blurRadius: 4,
                                                  offset: const Offset(0, 2),
                                                ),
                                              ],
                                            ),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                const Icon(
                                                  Icons.star,
                                                  color: Colors.white,
                                                  size: 12,
                                                ),
                                                const SizedBox(width: 4),
                                                Text(
                                                  _localizationService
                                                              .currentLanguage ==
                                                          'fr'
                                                      ? 'EN VEDETTE'
                                                      : 'FEATURED',
                                                  style: const TextStyle(
                                                    color: Colors.white,
                                                    fontSize: 10,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                        // Badge PROMO si coupon valide
                                        if (_hasValidCoupon(pro))
                                          Positioned(
                                            top: 8,
                                            left: 8,
                                            child: Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 8,
                                                    vertical: 4,
                                                  ),
                                              decoration: BoxDecoration(
                                                gradient: LinearGradient(
                                                  colors: [
                                                    Colors.purple.shade600,
                                                    Colors.pink.shade500,
                                                  ],
                                                  begin: Alignment.topLeft,
                                                  end: Alignment.bottomRight,
                                                ),
                                                borderRadius:
                                                    BorderRadius.circular(12),
                                                boxShadow: [
                                                  BoxShadow(
                                                    color: Colors.purple
                                                        .withValues(alpha: 0.4),
                                                    blurRadius: 6,
                                                    offset: const Offset(0, 2),
                                                  ),
                                                ],
                                              ),
                                              child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  const Icon(
                                                    Icons.local_offer,
                                                    color: Colors.white,
                                                    size: 12,
                                                  ),
                                                  const SizedBox(width: 4),
                                                  Text(
                                                    'PROMO',
                                                    style: const TextStyle(
                                                      color: Colors.white,
                                                      fontSize: 10,
                                                      fontWeight:
                                                          FontWeight.bold,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                          // Indicateur de page
                          Padding(
                            padding: const EdgeInsets.only(top: 12.0),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: List.generate(
                                _featured.length,
                                (index) => Container(
                                  margin: const EdgeInsets.symmetric(
                                    horizontal: 3,
                                  ),
                                  width: 8,
                                  height: 8,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: Theme.of(context).colorScheme.primary
                                        .withValues(alpha: 0.3),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      )
                    : Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.surfaceContainer,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          children: [
                            Icon(
                              Icons.info_outline,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              _localizationService.tr('no_sponsored'),
                              style: TextStyle(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: 8),
                            TextButton.icon(
                              onPressed: () =>
                                  _loadFeatured(forceRefresh: true),
                              icon: const Icon(Icons.refresh),
                              label: Text(_localizationService.tr('refresh')),
                            ),
                          ],
                        ),
                      ),
                const SizedBox(height: 16), // Réduit de 24 à 16
                // Section offres exclusives
                _buildOffersSection(),

                const SizedBox(height: 16), // Réduit de 24 à 16
                // Section partenaires de confiance
                _buildPartnersSection(),

                const SizedBox(height: 16), // Réduit de 24 à 16
                // Bouton pour les professionnels qui veulent s'inscrire
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.secondaryContainer,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Theme.of(context).colorScheme.shadow
                            .withValues(alpha: 0.12),
                        blurRadius: 16,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      Icon(
                        Icons.business_center,
                        size: 40,
                        color: Theme.of(context)
                            .colorScheme
                            .onSecondaryContainer,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _localizationService.tr('are_you_professional'),
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context)
                              .colorScheme
                              .onSecondaryContainer,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _localizationService.tr('grow_your_business'),
                        style: TextStyle(
                          fontSize: 14,
                          color: Theme.of(context)
                              .colorScheme
                              .onSecondaryContainer,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 12),
                      ElevatedButton(
                        onPressed: () async {
                          await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) =>
                                  const ProfessionalRegistrationPage(),
                            ),
                          );
                          // Forcer la mise à jour de la page d'accueil quand on revient
                          if (mounted) {
                            setState(() {});
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Theme.of(context)
                              .colorScheme
                              .onSecondaryContainer,
                          foregroundColor: Theme.of(context)
                              .colorScheme
                              .secondaryContainer,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 12,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(25),
                          ),
                        ),
                        child: Text(
                          _localizationService.tr('register_here'),
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24), // Réduit de 40 à 24
              ],
            ),
          ),
        ),
      ),
    );
  }
}
