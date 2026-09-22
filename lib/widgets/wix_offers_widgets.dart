import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data_service.dart';
import '../models/wix_offer_models.dart';
import '../models/wix_partner_models.dart';
import '../services/localization_service.dart';
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

Uri? _offerUri(String value) {
  final uri = Uri.tryParse(value.trim());
  if (uri == null || (uri.scheme != 'https' && uri.scheme != 'http')) {
    return null;
  }
  return uri;
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
  late final PageController _pageController;
  int _currentPage = 0;
  List<WixPartner> _partners = [];

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    _loadPartners();
  }

  void _loadPartners() async {
    try {
      final partners = await DataService().fetchPartners();
      if (mounted) {
        setState(() {
          _partners = partners;
        });
      }
    } on Exception {
      // Le carrousel reste utilisable sans enrichissement partenaire.
    }
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
              style: Theme.of(context).textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
          ),
        SizedBox(
          height: 160, // Hauteur augmentée pour afficher logo + image promo
          child: PageView.builder(
            controller: _pageController,
            itemCount: validExclusiveOffers.length, // Une offre par page
            onPageChanged: (page) {
              if (mounted) {
                setState(() => _currentPage = page);
              }
            },
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
    if (offer.partnerId.isEmpty) return null;
    for (final partner in partners) {
      if (partner.id == offer.partnerId) return partner;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final localization = LocalizationService();
    final partner = _relatedPartner;
    final offerTitle = _cleanHtmlText(
      offer.getTitleInLanguage(localization.currentLanguage),
    );
    final offerUri = _offerUri(offer.link);

    return Semantics(
      link: offerUri != null,
      label: '${localization.tr('open_offer')}: $offerTitle',
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: offerUri == null
              ? null
              : () => _launchOffer(context, offerUri, localization),
          borderRadius: BorderRadius.circular(16),
          child: Ink(
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
                                  errorWidget: (context, url, error) =>
                                      Container(
                                        color: Colors.white.withValues(
                                          alpha: 0.3,
                                        ),
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
                                partner.getTitleInLanguage(
                                  localization.currentLanguage,
                                ),
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
                              offerTitle,
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
        ),
      ),
    );
  }

  Future<void> _launchOffer(
    BuildContext context,
    Uri uri,
    LocalizationService localization,
  ) async {
    try {
      final launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      if (launched || !context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(localization.tr('error_opening_link'))),
      );
    } on Exception {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(localization.tr('error_opening_link'))),
        );
      }
    }
  }
}
