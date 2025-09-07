import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/partner_models.dart';
import '../services/partner_service.dart';
import '../services/localization_service.dart';
import '../widgets/language_selector.dart';
import '../widgets/fast_image_widget.dart';
import '../utils.dart';

class PartnersPage extends StatefulWidget {
  const PartnersPage({super.key});

  @override
  State<PartnersPage> createState() => _PartnersPageState();
}

class _PartnersPageState extends State<PartnersPage> {
  final LocalizationService _localizationService = LocalizationService();
  final PartnerService _partnerService = PartnerService();

  List<Partner> _partners = [];
  List<String> _categories = [];
  String? _selectedCategory;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      setState(() {
        _isLoading = true;
        _error = null;
      });

      final partners = await _partnerService.getPartners();
      final categories = await _partnerService.getPartnerCategories();

      setState(() {
        _partners = partners;
        _categories = categories;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  List<Partner> get _filteredPartners {
    if (_selectedCategory == null) return _partners;
    return _partners.where((p) => p.category == _selectedCategory).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const Text('🤝', style: TextStyle(fontSize: 24)),
            const SizedBox(width: 8),
            Text(_localizationService.tr('our_partners')),
          ],
        ),
        backgroundColor: Colors.blue.shade600,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          LanguageSelector(
            onLanguageChanged: (String languageCode) {
              setState(() {}); // Reconstruire la page avec la nouvelle langue
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Filtre par catégorie
          if (_categories.isNotEmpty) _buildCategoryFilter(),

          // Contenu principal
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                ? _buildErrorWidget()
                : _filteredPartners.isEmpty
                ? _buildEmptyWidget()
                : _buildPartnersList(),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryFilter() {
    return Container(
      height: 60,
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: Colors.blue.shade600,
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(20),
          bottomRight: Radius.circular(20),
        ),
      ),
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          // Filtre "Tous"
          _buildCategoryChip(null, _localizationService.tr('all_categories')),

          // Filtres par catégorie
          ..._categories.map((category) {
            final icon = _partnerService.getCategoryIcon(category);
            final name = _partnerService.getCategoryName(
              category,
              _localizationService.currentLanguage,
            );
            return _buildCategoryChip(category, '$icon $name');
          }),
        ],
      ),
    );
  }

  Widget _buildCategoryChip(String? category, String label) {
    final isSelected = _selectedCategory == category;

    return Container(
      margin: const EdgeInsets.only(right: 8),
      child: FilterChip(
        label: Text(label),
        selected: isSelected,
        onSelected: (selected) {
          setState(() {
            _selectedCategory = selected ? category : null;
          });
        },
        backgroundColor: Colors.white.withValues(alpha: 0.1),
        selectedColor: Colors.white.withValues(alpha: 0.3),
        labelStyle: TextStyle(
          color: isSelected ? Colors.white : Colors.white70,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        ),
        side: BorderSide(color: isSelected ? Colors.white : Colors.white54),
      ),
    );
  }

  Widget _buildPartnersList() {
    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: _filteredPartners.length,
        separatorBuilder: (_, __) => const SizedBox(height: 16),
        itemBuilder: (context, index) {
          final partner = _filteredPartners[index];
          return _PartnerListCard(partner: partner);
        },
      ),
    );
  }

  Widget _buildErrorWidget() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.error_outline, size: 64, color: Colors.red.shade300),
          const SizedBox(height: 16),
          Text(
            _localizationService.tr('error_loading_partners'),
            style: const TextStyle(fontSize: 16),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: _loadData,
            child: Text(_localizationService.tr('retry')),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyWidget() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.business_outlined, size: 64, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(
            _selectedCategory != null
                ? _localizationService.tr('no_partners_in_category')
                : _localizationService.tr('no_partners_available'),
            style: const TextStyle(fontSize: 16),
            textAlign: TextAlign.center,
          ),
          if (_selectedCategory != null) ...[
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () {
                setState(() {
                  _selectedCategory = null;
                });
              },
              child: Text(_localizationService.tr('show_all_partners')),
            ),
          ],
        ],
      ),
    );
  }
}

/// Carte de partenaire pour la liste
class _PartnerListCard extends StatelessWidget {
  final Partner partner;

  const _PartnerListCard({required this.partner});

  @override
  Widget build(BuildContext context) {
    final localization = LocalizationService();

    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () async {
          // Redirection directe vers le site web du partenaire
          if (partner.website.isNotEmpty) {
            final url = partner.website.startsWith('http')
                ? partner.website
                : 'https://${partner.website}';
            try {
              if (await canLaunchUrl(Uri.parse(url))) {
                await launchUrl(
                  Uri.parse(url),
                  mode: LaunchMode.externalApplication,
                );
              }
            } catch (e) {
              // En cas d'erreur, ne rien faire (silencieux)
            }
          }
        },
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // Logo du partenaire
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: FastImageWidget(
                    imageUrl: getValidImageUrl(partner.logo),
                    width: 60,
                    height: 60,
                    fit: BoxFit.contain,
                    placeholder: Container(
                      decoration: BoxDecoration(
                        color: Colors.grey[200],
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        Icons.business,
                        color: Colors.grey,
                        size: 30,
                      ),
                    ),
                    errorWidget: Container(
                      decoration: BoxDecoration(
                        color: Colors.grey[200],
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        Icons.business,
                        color: Colors.grey,
                        size: 30,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),

              // Informations du partenaire
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Nom et badge
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            partner.getNameInLanguage(
                              localization.currentLanguage,
                            ),
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.black87,
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.blue.shade100,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.verified,
                                color: Colors.blue.shade600,
                                size: 14,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                localization.tr('partner'),
                                style: TextStyle(
                                  color: Colors.blue.shade600,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),

                    // Description
                    Text(
                      partner.getDescriptionInLanguage(
                        localization.currentLanguage,
                      ),
                      style: const TextStyle(
                        fontSize: 14,
                        color: Colors.black54,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),

                    // Nombre d'offres si disponibles
                    if (partner.offers.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          const Icon(
                            Icons.local_offer,
                            color: Colors.orange,
                            size: 16,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '${partner.offers.length} ${localization.tr('offers_available')}',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.orange,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),

              // Icône de navigation
              const Icon(Icons.arrow_forward_ios, color: Colors.grey, size: 16),
            ],
          ),
        ),
      ),
    );
  }
}
