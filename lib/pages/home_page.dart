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
import '../theme/app_theme.dart';
import '../widgets/language_selector.dart';
import '../widgets/engagement_visibility_tracker.dart';
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
  const HomePage({
    super.key,
    this.onExploreServices,
    this.onOpenFavorites,
    this.analyticsService,
    this.dataService,
  });

  final VoidCallback? onExploreServices;
  final VoidCallback? onOpenFavorites;
  final FirebaseAnalyticsService? analyticsService;
  final DataService? dataService;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  final PageController _pageController = PageController();
  final LocalizationService _localizationService = LocalizationService();
  late final FirebaseAnalyticsService _analytics;
  late final DataService _dataService;
  final Set<String> _recordedFeaturedImpressions = <String>{};
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

  Widget _sectionIcon(IconData icon, Color accent) {
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: accent.withValues(alpha: 0.12),
        border: Border.all(color: accent.withValues(alpha: 0.22)),
      ),
      child: Icon(icon, color: accent, size: 20),
    );
  }

  @override
  void initState() {
    super.initState();
    _analytics = widget.analyticsService ?? FirebaseAnalyticsService();
    _dataService = widget.dataService ?? DataService();
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

    _pageController.dispose();

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
      final dataService = _dataService;
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
              ProfessionnelsPage(
                sousCategorie: sousCategorie,
                analyticsService: _analytics,
                dataService: _dataService,
              ),
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
  void _setScreenName() {
    _runAnalytics(() => _analytics.setCurrentScreen('home_page'));
  }

  void _runAnalytics(Future<void> Function() event) {
    try {
      unawaited(event().catchError((Object _) {}));
    } catch (_) {
      // La télémétrie ne doit jamais affecter le parcours principal.
    }
  }

  void _trackFeaturedImpression(Professionnel professionnel) {
    final impressionKey = '${professionnel.id}|home_featured';
    if (!_recordedFeaturedImpressions.add(impressionKey)) return;

    _runAnalytics(
      () => _analytics.trackProfessionalImpression(
        professionalId: professionnel.id,
        placement: 'home_featured',
        locale: _localizationService.currentLanguage,
      ),
    );
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
              _sectionIcon(Icons.groups_rounded, AppTheme.trustTeal),
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
              : HomePartnerRail(
                  children: [
                    for (final partner in _partners)
                      WixPartnerCard(partner: partner),
                  ],
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
              _sectionIcon(Icons.local_offer_rounded, AppTheme.mapleRed),
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

  Future<void> _openProfessionalRegistration() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ProfessionalRegistrationPage()),
    );
    if (mounted) {
      setState(() {});
    }
  }

  Widget _buildProfessionalCta() {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final accent = Theme.of(context).brightness == Brightness.dark
        ? colorScheme.tertiary
        : AppTheme.trustTeal;

    final message = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(AppRadii.compact),
          ),
          child: Icon(Icons.storefront_rounded, color: accent),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _localizationService
                    .tr('professional_cta_eyebrow')
                    .toUpperCase(),
                style: textTheme.labelSmall?.copyWith(
                  color: accent,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.7,
                ),
              ),
              const SizedBox(height: AppSpacing.xxs),
              Text(
                _localizationService.tr('are_you_professional'),
                style: textTheme.titleMedium,
              ),
              const SizedBox(height: AppSpacing.xxs),
              Text(
                _localizationService.tr('grow_your_business'),
                style: textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
    final action = OutlinedButton.icon(
      onPressed: _openProfessionalRegistration,
      icon: const Icon(Icons.arrow_forward_rounded),
      label: Text(_localizationService.tr('register_here')),
      style: OutlinedButton.styleFrom(
        foregroundColor: accent,
        side: BorderSide(color: accent.withValues(alpha: 0.52)),
      ),
    );

    return Card(
      key: const Key('home_professional_cta'),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth < 620) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  message,
                  const SizedBox(height: AppSpacing.md),
                  action,
                ],
              );
            }

            return Row(
              children: [
                Expanded(child: message),
                const SizedBox(width: AppSpacing.lg),
                action,
              ],
            );
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

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
                        child: Row(
                          children: [
                            _sectionIcon(
                              Icons.workspace_premium_rounded,
                              AppTheme.mapleRed,
                            ),
                            const SizedBox(width: AppSpacing.sm),
                            Expanded(
                              child: Text(
                                _localizationService.tr(
                                  'sponsored_professionals',
                                ),
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                            ),
                          ],
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
                                    elevation: 0,
                                    child: Stack(
                                      children: [
                                        InkWell(
                                          onTap: () async {
                                            _runAnalytics(
                                              () =>
                                                  _analytics.trackSponsorClick(
                                                    sponsorId: pro.id,
                                                    clickType: 'professional',
                                                    sourceScreen:
                                                        'home_featured',
                                                    locale: _localizationService
                                                        .currentLanguage,
                                                  ),
                                            );

                                            await Navigator.push(
                                              context,
                                              MaterialPageRoute(
                                                builder: (_) =>
                                                    ProfessionnelDetailPage(
                                                      professionnel: pro,
                                                      sourcePlacement:
                                                          'home_featured',
                                                      analyticsService:
                                                          _analytics,
                                                      dataService: _dataService,
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
                                                  backgroundColor: colorScheme
                                                      .surfaceContainerHighest,
                                                  child: pro.image.isNotEmpty
                                                      ? ClipRRect(
                                                          borderRadius:
                                                              BorderRadius.circular(
                                                                40,
                                                              ),
                                                          child: ImageCacheService().buildOptimizedImage(
                                                            imageUrl: pro.image,
                                                            width: 80,
                                                            height: 80,
                                                            fit: BoxFit.cover,
                                                            placeholder:
                                                                const SizedBox(
                                                                  width: 80,
                                                                  height: 80,
                                                                  child: Center(
                                                                    child: CircularProgressIndicator(
                                                                      strokeWidth:
                                                                          2,
                                                                    ),
                                                                  ),
                                                                ),
                                                            errorWidget: Icon(
                                                              Icons.person,
                                                              size: 40,
                                                              color: colorScheme
                                                                  .onSurfaceVariant,
                                                            ),
                                                          ),
                                                        )
                                                      : Icon(
                                                          Icons.person,
                                                          size: 40,
                                                          color: colorScheme
                                                              .onSurfaceVariant,
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
                                                            color: AppTheme
                                                                .trustTeal,
                                                            borderRadius:
                                                                BorderRadius.circular(
                                                                  16,
                                                                ),
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
                                                            color: AppTheme
                                                                .mapleRedDark,
                                                            borderRadius:
                                                                BorderRadius.circular(
                                                                  8,
                                                                ),
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
                                              color: AppTheme.ink,
                                              borderRadius:
                                                  BorderRadius.circular(12),
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
                                                  _localizationService.tr(
                                                    'featured_badge',
                                                  ),
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
                                                color: AppTheme.mapleRedDark,
                                                borderRadius:
                                                    BorderRadius.circular(12),
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
                                ).trackEngagementVisibility(
                                  key: ValueKey(
                                    'home_featured_impression_${pro.id}',
                                  ),
                                  onQualifiedVisibility: () =>
                                      _trackFeaturedImpression(pro),
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
                const SizedBox(height: AppSpacing.lg),
                _buildProfessionalCta(),

                const SizedBox(height: AppSpacing.sm),
                _buildOffersSection(),

                const SizedBox(height: AppSpacing.sm),
                _buildPartnersSection(),
                const SizedBox(height: AppSpacing.lg),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
