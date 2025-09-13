import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'dart:async';
import '../models.dart';
import '../models/wix_partner_models.dart';
import '../models/wix_offer_models.dart';
import '../data_service.dart';
import '../image_cache_service.dart';
import '../services/localization_service.dart';
import '../services/firebase_analytics_service.dart';
import '../services/payment_status_service.dart';
import '../services/cache_manager_service.dart';
import '../widgets/language_selector.dart';
import '../widgets/wix_partner_widgets.dart';
import '../widgets/wix_offers_widgets.dart';
import 'services_page.dart';
import 'professionnels_page.dart';
import 'professionnel_detail_page.dart';
import 'favorites_page.dart';
import 'review_admin_page.dart';
import 'professional_registration_page.dart';
import '../utils.dart'; // Importer utils.dart pour getValidImageUrl

class HomePage extends StatefulWidget {
  const HomePage({super.key});

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
  bool _isLoadingOffers = false;
  bool _isLoadingSousCategories = false;
  Timer? _timer;
  Timer? _partnersTimer; // Timer pour carrousel partenaires
  Timer? _refreshTimer; // Timer pour refresh automatique
  int _adminTapCount = 0;
  Timer? _adminTapTimer;

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
            color: gradientColors.first.withOpacity(0.25),
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
    _checkPaymentStatus();
  }

  // Initialisation optimisée: chargements parallèles et un seul setState
  Future<void> _initializeData() async {
    await _loadAllData(forceRefresh: false);
    if (mounted) {
      _startOffersAutoRefresh();
      _startPeriodicRefresh();
    }
  }

  // Charge toutes les sections en parallèle et applique l'état une seule fois
  Future<void> _loadAllData({bool forceRefresh = false}) async {
    try {
      final ds = _dataService;
      final futures = await Future.wait([
        ds.fetchSousCategories(),
        ds.fetchSponsoredProfessionnels(forceRefresh: forceRefresh),
        ds.fetchPartners(forceRefresh: forceRefresh),
        ds
            .fetchExclusiveOffers()
            .timeout(const Duration(seconds: 8), onTimeout: () => <WixOffer>[]),
      ], eagerError: false);

      if (!mounted) return;

      final sousCategories = futures[0] as List<SousCategorie>;
      final featured = futures[1] as List<Professionnel>;
      final partners = futures[2] as List<WixPartner>;
      final offers = futures[3] as List<WixOffer>;

  setState(() {
        _sousCategories = sousCategories;
        _featured = featured;
        _partners = partners;
        _offers = offers;
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

      // (Re)définir l'auto-scroll pour les sections
      // 1) Featured: démarrer uniquement si > 1 élément
      _timer?.cancel();
      if (featured.length > 1) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _startAutoScroll();
        });
      }

      // 2) Démarrer le carrousel partenaires si nécessaire
      if (partners.isNotEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _startPartnersAutoScroll();
        });
      }
    } catch (e) {
      // En cas d'erreur, préserver une UI stable
      if (mounted) {
        setState(() {
          _offers = _offers; // pas de changement
          _partners = _partners;
          _featured = _featured;
          _sousCategories = _sousCategories;
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

    // Annuler tous les timers de manière explicite
    _timer?.cancel();
    _timer = null;

    _partnersTimer?.cancel();
    _partnersTimer = null;

    _refreshTimer?.cancel();
    _refreshTimer = null;

    _adminTapTimer?.cancel();
    _adminTapTimer = null;

    // Arrêter le rafraîchissement automatique des offres
    _stopOffersAutoRefresh();

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
      _checkPaymentStatus();
    }
  }

  // Vérifier le statut des paiements en attente
  Future<void> _checkPaymentStatus() async {
    try {
      final paymentSuccess =
          await PaymentStatusService.checkAndShowPaymentSuccess();
      if (paymentSuccess && mounted) {
        _showPaymentSuccessDialog();
      }
    } catch (e) {
      print('Erreur vérification paiement: $e');
    }
  }

  // Afficher dialog de succès de paiement
  void _showPaymentSuccessDialog() {
    final isEnglish = _localizationService.currentLanguage == 'en';
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.check_circle, color: Colors.green[700], size: 32),
            const SizedBox(width: 12),
            Text(
              isEnglish ? 'Payment Successful!' : 'Paiement réussi !',
              style: TextStyle(color: Colors.green[700]),
            ),
          ],
        ),
        content: Text(
          isEnglish
              ? 'Your professional plan has been activated successfully. Welcome aboard!'
              : 'Votre plan professionnel a été activé avec succès. Bienvenue à bord !',
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green[700],
              foregroundColor: Colors.white,
            ),
            child: Text(isEnglish ? 'Great!' : 'Parfait !'),
          ),
        ],
      ),
    );
  }

  // Timer pour refresh automatique toutes les 5 minutes (moins fréquent)
  void _startPeriodicRefresh() {
    _refreshTimer = Timer.periodic(const Duration(minutes: 5), (timer) {
      if (mounted) {
        _loadAllData(forceRefresh: true);
      }
    });
  }

  Future<void> _loadFeatured({bool forceRefresh = false}) async {
    try {
      final dataService = DataService();
      final featured = await dataService.fetchSponsoredProfessionnels(
        forceRefresh: forceRefresh,
      );

      if (!mounted) return;

      setState(() {
        _featured = featured;
      });

      // Charger aussi les sous-catégories pour afficher les noms
      _loadSousCategories();

      // Précharger les images des professionnels en vedette pour améliorer les performances
      if (featured.isNotEmpty) {
        _preloadFeaturedImages(featured);

        // Démarrer le défilement automatique après un délai, mais seulement si on a plus d'1 professionnel
        if (featured.length > 1) {
          Future.delayed(const Duration(milliseconds: 500), () {
            if (mounted && _featured.isNotEmpty && _featured.length > 1) {
              _startAutoScroll();
            }
          });
        }
      } else {
        // Si pas de professionnels en vedette, arrêter le timer existant
        _timer?.cancel();
        _timer = null;
      }
    } catch (e) {
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
      print('🏠 HomePage: Chargement des sous-catégories déjà en cours...');
      return;
    }

    _isLoadingSousCategories = true;
    try {
      print('🏠 HomePage: Chargement des sous-catégories...');
      final sousCategories = await _dataService.fetchSousCategories();
      print('🏠 HomePage: Reçu ${sousCategories.length} sous-catégories');
      if (mounted) {
        setState(() {
          _sousCategories = sousCategories;
        });
        print('🏠 HomePage: Sous-catégories mises à jour dans l\'état');
        
        // Forcer un nouveau rebuild pour mettre à jour les noms de catégories
        if (_featured.isNotEmpty) {
          print('🏠 HomePage: Déclenchement setState pour mise à jour des noms de catégories');
          setState(() {
            // Force rebuild des cartes professionnels avec les noms de catégories
          });
        }
      }
    } catch (e) {
      print('❌ Erreur chargement sous-catégories: $e');
    } finally {
      _isLoadingSousCategories = false;
    }
  }

  /// Effectue un rafraîchissement complet en vidant tous les caches
  Future<void> _performCompleteRefresh() async {
    try {
      // Réinitialiser d'abord les listes locales pour éviter l'affichage de données obsolètes
      setState(() {
        _sousCategories = []; // Vider la liste des sous-catégories
        _featured = [];       // Vider temporairement la liste des professionnels en vedette
      });

      // Utiliser le service global de gestion de cache
      final cacheManager = CacheManagerService();
      await cacheManager.performCompleteRefresh(
        context: context,
        showMessages: true,
      );

      // Recharger toutes les données spécifiques à cette page
      // L'ordre est important : d'abord les sous-catégories, puis les professionnels
      await _loadSousCategories();
      await _loadFeatured(forceRefresh: true);
      await _loadPartners(forceRefresh: true);

      print('✅ Rafraîchissement complet HomePage terminé');
    } catch (e) {
      print('❌ Erreur lors du rafraîchissement complet HomePage: $e');
      // Les messages d'erreur sont gérés par le CacheManagerService
    }
  }

  // Récupérer le nom de la sous-catégorie à partir de son ID
  String _getSousCategorieTitle(String sousCategorieId) {
    try {
      // Si les sous-catégories ne sont pas encore chargées, retourner un placeholder
      if (_sousCategories.isEmpty) {
        print('🏠 HomePage: Sous-catégories vides pour ID: $sousCategorieId');
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
      print('🏠 HomePage: Trouvé catégorie "$title" pour ID: $sousCategorieId');
      return title;
    } catch (e) {
      print('🏠 HomePage: Catégorie non trouvée pour ID: $sousCategorieId (${_sousCategories.length} catégories disponibles)');
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
    } catch (e) {
      print('Erreur navigation vers catégorie: $e');
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
  void _preloadPartnerAndOfferImages(List<WixPartner> partners, List<WixOffer> offers) {
    final imageService = ImageCacheService();

    final partnerUrls = partners
        .map((p) => getValidImageUrl(p.banner.isNotEmpty ? p.banner : p.logo))
        .where((u) => u.isNotEmpty)
        .toList();

    final offerUrls = offers
        .map((o) => getValidImageUrl(o.image))
        .where((u) => u.isNotEmpty)
        .toList();

    final all = <String>[]
      ..addAll(partnerUrls)
      ..addAll(offerUrls);

    if (all.isNotEmpty) {
      imageService.preloadImages(all, context);
    }
  }

  void _startAutoScroll() {
    // Annuler le timer existant avant d'en créer un nouveau
    _timer?.cancel();

    // Ne démarrer le timer que si on a des professionnels en vedette
  if (_featured.length < 2) return; // au moins 2 pour faire un carrousel

    // CORRECTION: Augmenter l'intervalle à 10 secondes pour réduire le scroll automatique
    // Vous pouvez également commenter cette section pour désactiver complètement le scroll automatique
    _timer = Timer.periodic(const Duration(seconds: 10), (timer) {
      // Vérifications supplémentaires pour éviter le scroll infini
      if (!mounted || _featured.length < 2 || !_pageController.hasClients) {
        timer.cancel();
        return;
      }

      try {
        int currentPage = _pageController.page?.round() ?? 0;
        int nextPage = currentPage + 1;

        if (nextPage >= _featured.length) {
          nextPage = 0;
        }

        _pageController.animateToPage(
          nextPage,
          duration: const Duration(milliseconds: 500),
          curve: Curves.easeInOut,
        );
      } catch (e) {
        // En cas d'erreur, arrêter le timer
        timer.cancel();
      }
    });
  }

  void _startPartnersAutoScroll() {
    // Annuler le timer existant avant d'en créer un nouveau
    _partnersTimer?.cancel();

    if (_partners.isNotEmpty) {
      _partnersTimer = Timer.periodic(const Duration(seconds: 4), (timer) {
        if (_partnersPageController.hasClients && _partners.isNotEmpty) {
          int totalPages = (_partners.length / 3).ceil();
          int nextPage = (_partnersPageController.page?.round() ?? 0) + 1;
          if (nextPage >= totalPages) {
            nextPage = 0;
          }
          _partnersPageController.animateToPage(
            nextPage,
            duration: const Duration(milliseconds: 400),
            curve: Curves.easeInOut,
          );
        }
      });
    }
  }

  void _onLogoTap() async {
    _adminTapCount++;

    // Démarrer/réinitialiser le timer
    _adminTapTimer?.cancel();
    _adminTapTimer = Timer(const Duration(seconds: 2), () {
      _adminTapCount = 0;
    });

    // Si 7 taps en 2 secondes, ouvrir la page d'admin
    if (_adminTapCount >= 7) {
      _adminTapCount = 0;
      _adminTapTimer?.cancel();

      await Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => const ReviewAdminPage()),
      );
      // Forcer la mise à jour de la page d'accueil quand on revient
      if (mounted) {
        setState(() {});
      }
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

      final partners = await _dataService.fetchPartners(
        forceRefresh: forceRefresh,
      );

      if (mounted) {
        setState(() {
          _partners = partners;
          _isLoadingPartners = false;
        });

        // Démarrer le carrousel automatique des partenaires
        if (_partners.isNotEmpty) {
          Future.delayed(const Duration(milliseconds: 500), () {
            if (mounted) {
              _startPartnersAutoScroll();
            }
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingPartners = false;
          _partners = [];
        });
      }
    }
  }

  // Charger les offres exclusives depuis Wix
  Future<void> _loadOffers() async {
    if (!mounted) return;

    try {
      setState(() {
        _isLoadingOffers = true;
      });

      // Timeout pour éviter les blocages
      final offers = await _dataService.fetchExclusiveOffers().timeout(
        const Duration(seconds: 8),
        onTimeout: () => <WixOffer>[],
      );

      if (mounted) {
        setState(() {
          _offers = offers;
          _isLoadingOffers = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _offers = [];
          _isLoadingOffers = false;
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
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
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
                      'Aucun partenaire disponible',
                      style: TextStyle(color: Colors.grey[600], fontSize: 16),
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
                      int endIndex = (startIndex + 3).clamp(
                        0,
                        _partners.length,
                      );

                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8.0),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            for (int i = startIndex; i < endIndex; i++)
                              Container(
                                width:
                                    110, // Réduire légèrement pour éviter débordement
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
              _sectionIcon(Icons.local_offer_rounded, [Colors.orange, Colors.redAccent]),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _localizationService.tr('exclusive_offers'),
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Contenu de la section
          _isLoadingOffers
              ? Container(
                  height: 120,
                  child: const Center(child: CircularProgressIndicator()),
                )
              : _offers.isNotEmpty
              ? WixOfferCarousel(
                  offers: _offers,
                  title: '', // Pas de titre ici car déjà affiché au-dessus
                )
              : Container(
                  height: 80,
                  child: Center(
                    child: Text(
                      _localizationService.tr('no_offers_available'),
                      style: TextStyle(color: Colors.grey[600], fontSize: 16),
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
        title: const Text('Index'),
        backgroundColor: Colors.blue.shade600,
        foregroundColor: Colors.white,
        actions: [
          // Debug actions removed
          // Sélecteur de langue
          LanguageSelector(
            onLanguageChanged: (String languageCode) {
              setState(() {}); // Reconstruire la page avec la nouvelle langue
            },
          ),
          // Bouton Favoris
          IconButton(
            icon: const Icon(Icons.favorite),
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const FavoritesPage()),
              );
              // Forcer la mise à jour de la page d'accueil quand on revient
              if (mounted) {
                setState(() {});
              }
            },
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
          physics:
              const AlwaysScrollableScrollPhysics(), // Permet le pull-to-refresh même si le contenu ne scroll pas
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              children: [
                const SizedBox(height: 20), // Réduit de 40 à 20
                GestureDetector(
                  onTap: _onLogoTap,
                  child: Container(
                    height: 100, // Réduit de 120 à 100
                    width: 100, // Réduit de 120 à 100
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.transparent,
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(
                        50,
                      ), // Ajusté pour la nouvelle taille
                      child: ColorFiltered(
                        colorFilter: const ColorFilter.mode(
                          Colors.white,
                          BlendMode.multiply,
                        ),
                        child: Image.asset(
                          'assets/images/store.png',
                          height: 100, // Réduit de 120 à 100
                          width: 100, // Réduit de 120 à 100
                          fit: BoxFit.cover,
                          key: const ValueKey('store_logo_updated'),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16), // Réduit de 32 à 16
                Text(
                  _localizationService.tr('welcome_title'),
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12), // Réduit de 16 à 12
                Text(
                  _localizationService.tr('welcome_subtitle'),
                  style: const TextStyle(fontSize: 16),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24), // Réduit de 40 à 24
                Hero(
                  tag: 'explore_button',
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeInOut,
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.business_center),
                      label: Text(_localizationService.tr('explore_services')),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 32,
                          vertical: 16,
                        ),
                        textStyle: const TextStyle(fontSize: 18),
                        elevation: 8,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(30),
                        ),
                      ),
                      onPressed: () async {
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const ServicesPage(),
                          ),
                        );
                        // Forcer la mise à jour de la page d'accueil quand on revient
                        if (mounted) {
                          setState(() {});
                        }
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 20), // Réduit de 40 à 20
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
                                                        onTap: () => _navigateToCategory(
                                                          pro.sousCategorie,
                                                        ),
                                                        borderRadius: BorderRadius.circular(16),
                                                        child: Container(
                                                          padding: const EdgeInsets.symmetric(
                                                            horizontal: 10,
                                                            vertical: 6,
                                                          ),
                                                          decoration: BoxDecoration(
                                                            gradient: LinearGradient(
                                                              colors: [
                                                                Colors.teal,
                                                                Colors.cyan,
                                                              ],
                                                              begin: Alignment.topLeft,
                                                              end: Alignment.bottomRight,
                                                            ),
                                                            borderRadius: BorderRadius.circular(16),
                                                            boxShadow: [
                                                              BoxShadow(
                                                                color: Colors.teal.withOpacity(0.25),
                                                                blurRadius: 6,
                                                                offset: const Offset(0, 2),
                                                              ),
                                                            ],
                                                          ),
                                                          child: Text(
                                                            _getSousCategorieTitle(
                                                              pro.sousCategorie,
                                                            ),
                                                            style: const TextStyle(
                                                              color: Colors.white,
                                                              fontSize: 12,
                                                              fontWeight: FontWeight.w600,
                                                            ),
                                                            maxLines: 1,
                                                            overflow: TextOverflow.ellipsis,
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
                                                          padding: const EdgeInsets.symmetric(
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
                                    color: Colors.blue.withValues(alpha: 0.3),
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
                          color: Colors.grey[100],
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          children: [
                            Icon(Icons.info_outline, color: Colors.grey[600]),
                            const SizedBox(height: 8),
                            Text(
                              _localizationService.currentLanguage == 'en'
                                  ? 'No featured professionals for now.'
                                  : 'Aucun professionnel en vedette pour le moment.',
                              style: TextStyle(color: Colors.grey[700]),
                            ),
                            const SizedBox(height: 8),
                            TextButton.icon(
                              onPressed: () => _loadFeatured(forceRefresh: true),
                              icon: const Icon(Icons.refresh),
                              label: Text(
                                _localizationService.currentLanguage == 'en'
                                    ? 'Refresh'
                                    : 'Rafraîchir',
                              ),
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
                    gradient: LinearGradient(
                      colors: [Colors.green.shade400, Colors.green.shade600],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.green.shade200,
                        blurRadius: 8,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      Icon(
                        Icons.business_center,
                        size: 40,
                        color: Colors.white,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _localizationService.currentLanguage == 'fr'
                            ? 'Vous êtes un professionnel ?'
                            : 'Are you a professional?',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _localizationService.currentLanguage == 'fr'
                            ? 'Rejoignez notre annuaire et développez votre clientèle'
                            : 'Join our directory and grow your business',
                        style: const TextStyle(
                          fontSize: 14,
                          color: Colors.white70,
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
                          backgroundColor: Colors.white,
                          foregroundColor: Colors.green.shade600,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 12,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(25),
                          ),
                        ),
                        child: Text(
                          _localizationService.currentLanguage == 'fr'
                              ? 'S\'inscrire maintenant'
                              : 'Join Now',
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

  // Démarrer le rafraîchissement automatique des offres
  void _startOffersAutoRefresh() {
    print(
      'HomePage: Démarrage du rafraîchissement automatique des offres (1 minute)',
    );

    // Annuler le timer existant s'il y en a un
    _refreshTimer?.cancel();

    // Créer un nouveau timer qui se répète toutes les 1 minute
    _refreshTimer = Timer.periodic(const Duration(minutes: 1), (timer) {
      if (mounted) {
        print('HomePage: Rafraîchissement automatique des offres...');
        _loadOffers(); // Recharger les offres
      } else {
        // Si le widget n'est plus monté, annuler le timer
        timer.cancel();
      }
    });
  }

  // Arrêter le rafraîchissement automatique
  void _stopOffersAutoRefresh() {
    _refreshTimer?.cancel();
    _refreshTimer = null;
    print('HomePage: Rafraîchissement automatique des offres arrêté');
  }
}
