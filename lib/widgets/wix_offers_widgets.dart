import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/wix_offer_models.dart';
import '../models/wix_partner_models.dart';
import '../services/localization_service.dart';
import '../data_service.dart';
import '../utils.dart';

/// Fonction utilitaire pour nettoyer le HTML
String _cleanHtmlText(String htmlText) {
  if (htmlText.isEmpty) return htmlText;

  // Supprimer les balises HTML courantes
  String cleaned = htmlText
      .replaceAll(RegExp(r'<[^>]*>'), '') // Supprimer toutes les balises HTML
      .replaceAll('&nbsp;', ' ') // Remplacer les espaces insécables
      .replaceAll('&amp;', '&') // Remplacer les entités HTML
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .trim(); // Supprimer les espaces en début/fin

  return cleaned;
}

/// Carousel d'offres exclusives Wix
class WixOfferCarousel extends StatefulWidget {
  final List<WixOffer> offers;
  final String title;

  const WixOfferCarousel({super.key, required this.offers, this.title = ''});

  @override
  State<WixOfferCarousel> createState() => _WixOfferCarouselState();
}

class _WixOfferCarouselState extends State<WixOfferCarousel> {
  late PageController _pageController;
  int _currentPage = 0;
  List<WixPartner> _partners = [];

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    _loadPartners();

    // Auto-scroll si il y a plusieurs offres
    if (widget.offers.length > 1) {
      _startAutoScroll();
    }
  }

  void _loadPartners() async {
    try {
      final partners = await DataService().fetchPartners();
      print('🏦 WixOfferCarousel: Loaded ${partners.length} partners');
      for (var partner in partners) {
        print('🏦 Partner: ${partner.title} - ID: ${partner.id}');
      }
      if (mounted) {
        setState(() {
          _partners = partners;
        });
      }
    } catch (e) {
      print('❌ Erreur lors du chargement des partenaires: $e');
    }
  }

  void _startAutoScroll() {
    Future.delayed(const Duration(seconds: 5), () {
      if (mounted && widget.offers.length > 1) {
        int nextPage = (_currentPage + 1) % widget.offers.length;
        _pageController.animateToPage(
          nextPage,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
        );
        _currentPage = nextPage;
        _startAutoScroll(); // Répéter
      }
    });
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Filtrer les offres valides et exclusives
    final validExclusiveOffers = widget.offers
        .where((offer) => offer.isExclusive && offer.isValid)
        .toList();

    if (validExclusiveOffers.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.title.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(
              widget.title,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
          ),
        SizedBox(
          height: 160, // Hauteur augmentée pour afficher logo + image promo
          child: PageView.builder(
            controller: _pageController,
            itemCount: validExclusiveOffers.length, // Une offre par page
            itemBuilder: (context, pageIndex) {
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: _WixOfferCard(
                  offer: validExclusiveOffers[pageIndex],
                  partners: _partners,
                ),
              );
            },
          ),
        ),

        // Indicateurs de page si plus d'une offre
        if (validExclusiveOffers.length > 1)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: validExclusiveOffers.asMap().entries.map((entry) {
                return Container(
                  width: 8,
                  height: 8,
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _currentPage == entry.key
                        ? Colors.orange
                        : Colors.grey.shade300,
                  ),
                );
              }).toList(),
            ),
          ),
      ],
    );
  }
}

/// Carte individuelle d'offre exclusive
class _WixOfferCard extends StatelessWidget {
  final WixOffer offer;
  final List<WixPartner> partners;

  const _WixOfferCard({required this.offer, required this.partners});

  // Trouver le partenaire correspondant à cette offre
  WixPartner? get _relatedPartner {
    print('🔍 Recherche partenaire pour offre: ${offer.title}');
    print('🔍 PartnerID de l\'offre: "${offer.partnerId}"');
    print('🔍 Nombre de partenaires disponibles: ${partners.length}');

    if (offer.partnerId.isEmpty) {
      print('🔍 ❌ PartnerID vide');
      return null;
    }

    try {
      final partner = partners.firstWhere(
        (partner) => partner.id == offer.partnerId,
      );
      print('🔍 ✅ Partenaire trouvé: ${partner.title}');
      print('🔍 Logo URL: ${partner.logo}');
      return partner;
    } catch (e) {
      print('🔍 ❌ Aucun partenaire trouvé avec ID: ${offer.partnerId}');
      print('🔍 IDs disponibles: ${partners.map((p) => p.id).toList()}');
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final localization = LocalizationService();
    final partner = _relatedPartner;

    return GestureDetector(
      onTap: () => _launchOffer(),
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Colors.orange.shade400, Colors.deepOrange.shade600],
          ),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.orange.withValues(alpha: 0.3),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child:
            // Contenu principal - Layout horizontal
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  // Image promotionnelle de l'offre à gauche (format carré)
                  Container(
                    width: 90, // Largeur fixe pour l'image
                    height: 90, // Hauteur égale à la largeur pour un carré
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      color: Colors.white.withValues(alpha: 0.9),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: offer.image.isNotEmpty
                          ? CachedNetworkImage(
                              imageUrl: getValidImageUrl(offer.image),
                              fit: BoxFit.cover,
                              placeholder: (context, url) => Container(
                                color: Colors.white.withValues(alpha: 0.3),
                                child: const Center(
                                  child: CircularProgressIndicator(
                                    color: Colors.orange,
                                    strokeWidth: 2,
                                  ),
                                ),
                              ),
                              errorWidget: (context, url, error) => Container(
                                color: Colors.white.withValues(alpha: 0.3),
                                child: const Icon(
                                  Icons.local_offer,
                                  color: Colors.orange,
                                  size: 24,
                                ),
                              ),
                            )
                          : Container(
                              color: Colors.white.withValues(alpha: 0.3),
                              child: const Icon(
                                Icons.local_offer,
                                color: Colors.orange,
                                size: 24,
                              ),
                            ),
                    ),
                  ),

                  const SizedBox(width: 12),

                  // Contenu texte - à droite
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // Nom du partenaire (si disponible)
                        if (partner != null)
                          Text(
                            partner.title,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.8),
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),

                        if (partner != null) const SizedBox(height: 2),

                        // Titre de l'offre
                        Text(
                          _cleanHtmlText(
                            offer.getTitleInLanguage(
                              localization.currentLanguage,
                            ),
                          ),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),

                        const SizedBox(height: 6),

                        // Description courte si disponible
                        if (offer.description.isNotEmpty)
                          Text(
                            _cleanHtmlText(
                              offer.getDescriptionInLanguage(
                                localization.currentLanguage,
                              ),
                            ),
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.9),
                              fontSize: 12,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),

                        const SizedBox(height: 8),

                        // Indicateur d'expiration si nécessaire
                        if (offer.isExpiringSoon)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.red.shade700,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              '⏰ ${localization.tr('expires_soon')}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
      ),
    );
  }

  void _launchOffer() async {
    if (offer.link.isNotEmpty) {
      try {
        final uri = Uri.parse(offer.link);
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        }
      } catch (e) {
        print('Erreur lors de l\'ouverture du lien: $e');
      }
    }
  }
}
