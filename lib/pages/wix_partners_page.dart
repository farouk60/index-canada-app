import 'package:flutter/material.dart';
import '../models/wix_partner_models.dart';
import '../services/wix_partner_service.dart';
import '../services/localization_service.dart';
import '../widgets/language_selector.dart';
import '../widgets/wix_partner_widgets.dart';

class WixPartnersPage extends StatefulWidget {
  const WixPartnersPage({super.key});

  @override
  State<WixPartnersPage> createState() => _WixPartnersPageState();
}

class _WixPartnersPageState extends State<WixPartnersPage> {
  final LocalizationService _localizationService = LocalizationService();
  final WixPartnerService _partnerService = WixPartnerService();

  List<WixPartner> _partners = [];
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

      final partners = await _partnerService.fetchPartners(forceRefresh: true);
      final categories = await _partnerService.getAvailableCategories();

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

  List<WixPartner> get _filteredPartners {
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
          // Statistiques en en-tête
          _buildStatsHeader(),

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

  Widget _buildStatsHeader() {
    if (_partners.isEmpty) return const SizedBox.shrink();

    final featuredCount = _partners.where((p) => p.isFeatured).length;
    final officialCount = _partners.where((p) => p.isOfficial).length;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.blue.shade600,
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(20),
          bottomRight: Radius.circular(20),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildStatItem(
            icon: Icons.business,
            count: _partners.length,
            label: _localizationService.tr('partners'),
          ),
          _buildStatItem(
            icon: Icons.star,
            count: featuredCount,
            label: _localizationService.tr('featured'),
          ),
          _buildStatItem(
            icon: Icons.verified,
            count: officialCount,
            label: _localizationService.tr('official'),
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem({
    required IconData icon,
    required int count,
    required String label,
  }) {
    return Column(
      children: [
        Icon(icon, color: Colors.white, size: 24),
        const SizedBox(height: 4),
        Text(
          count.toString(),
          style: const TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          label,
          style: const TextStyle(color: Colors.white70, fontSize: 12),
        ),
      ],
    );
  }

  Widget _buildCategoryFilter() {
    return Container(
      height: 60,
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          // Filtre "Tous"
          _buildCategoryChip(null, _localizationService.tr('all_categories')),

          // Filtres par catégorie
          ..._categories.map((category) {
            final categoryInfo = PartnerCategory.getCategoryById(category);
            final icon = categoryInfo?.icon ?? '📋';
            final name =
                categoryInfo?.getNameInLanguage(
                  _localizationService.currentLanguage,
                ) ??
                category;
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
        backgroundColor: Colors.grey.shade100,
        selectedColor: Colors.blue.shade100,
        labelStyle: TextStyle(
          color: isSelected ? Colors.blue.shade800 : Colors.black87,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        ),
        side: BorderSide(
          color: isSelected ? Colors.blue.shade300 : Colors.grey.shade300,
        ),
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
          return WixPartnerListCard(partner: partner);
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
          const SizedBox(height: 8),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                _error!,
                style: const TextStyle(fontSize: 12, color: Colors.grey),
                textAlign: TextAlign.center,
              ),
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
