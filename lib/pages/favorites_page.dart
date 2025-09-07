import 'package:flutter/material.dart';
import '../models.dart';
import '../data_service.dart';
import '../services/favorite_service.dart';
import '../services/localization_service.dart';
import '../widgets/gallery_preview_widget.dart';
import '../widgets/language_selector.dart';
import '../image_cache_service.dart';
import 'professionnel_detail_page.dart';

class FavoritesPage extends StatefulWidget {
  const FavoritesPage({super.key});

  @override
  State<FavoritesPage> createState() => _FavoritesPageState();
}

class _FavoritesPageState extends State<FavoritesPage> {
  final LocalizationService _localizationService = LocalizationService();
  List<Professionnel> _favoriteProfessionnels = [];
  List<SousCategorie> _sousCategories = [];
  Map<String, List<Professionnel>> _favoritesByService = {};
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadFavorites();
  }

  Future<void> _loadFavorites() async {
    try {
      setState(() {
        _isLoading = true;
        _error = null;
      });

      final favoriteService = FavoriteService.instance;
      final favoriteIds = await favoriteService.getFavorites();

      if (favoriteIds.isEmpty) {
        setState(() {
          _favoriteProfessionnels = [];
          _favoritesByService = {};
          _isLoading = false;
        });
        return;
      }

      final dataService = DataService();

      // Charger les professionnels favoris et les sous-catégories
      final futures = await Future.wait([
        dataService.fetchProfessionnels(),
        dataService.fetchSousCategories(),
      ]);

      final allProfessionnels = futures[0] as List<Professionnel>;
      _sousCategories = futures[1] as List<SousCategorie>;

      final favoriteProfessionnels = allProfessionnels
          .where((prof) => favoriteIds.contains(prof.id))
          .toList();

      // Grouper les favoris par service
      _favoritesByService = _groupFavoritesByService(favoriteProfessionnels);

      setState(() {
        _favoriteProfessionnels = favoriteProfessionnels;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  /// Groupe les professionnels favoris par service
  Map<String, List<Professionnel>> _groupFavoritesByService(
    List<Professionnel> professionals,
  ) {
    final Map<String, List<Professionnel>> grouped = {};

    for (final prof in professionals) {
      final serviceId = prof.sousCategorie;
      if (serviceId.isNotEmpty) {
        grouped.putIfAbsent(serviceId, () => []).add(prof);
      }
    }

    return grouped;
  }

  /// Obtient le nom du service dans la langue actuelle
  String _getServiceName(String serviceId) {
    final service = _sousCategories.firstWhere(
      (s) => s.id == serviceId,
      orElse: () => SousCategorie(
        id: serviceId,
        title: serviceId,
        titleEn: serviceId,
        image: '',
        imageEn: '',
      ),
    );

    return service.getTitleInLanguage(_localizationService.currentLanguage);
  }

  /// Construit la liste des favoris groupés par service
  Widget _buildGroupedFavoritesList() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        for (final entry in _favoritesByService.entries) ...[
          // Sous-titre du service
          Container(
            margin: const EdgeInsets.only(top: 16, bottom: 8),
            child: Row(
              children: [
                Icon(
                  Icons.category,
                  color: Theme.of(context).primaryColor,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  _getServiceName(entry.key),
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).primaryColor,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Container(
                    height: 1,
                    color: Theme.of(context).primaryColor.withOpacity(0.3),
                  ),
                ),
              ],
            ),
          ),
          // Liste des professionnels de ce service
          ...entry.value.map((prof) => _buildProfessionnelCard(prof)),
        ],
      ],
    );
  }

  /// Construit une carte de professionnel
  Widget _buildProfessionnelCard(Professionnel prof) {
    return Card(
      elevation: 4,
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: CircleAvatar(
          radius: 30,
          backgroundColor: Colors.grey[200],
          child: prof.image.isNotEmpty
              ? ClipRRect(
                  borderRadius: BorderRadius.circular(30),
                  child: ImageCacheService().buildOptimizedImage(
                    imageUrl: prof.image,
                    width: 60,
                    height: 60,
                    fit: BoxFit.cover,
                    placeholder: const CircularProgressIndicator(),
                    errorWidget: const Icon(
                      Icons.person,
                      size: 30,
                      color: Colors.grey,
                    ),
                  ),
                )
              : const Icon(Icons.person, size: 30, color: Colors.grey),
        ),
        title: Text(
          prof.title,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(prof.subtitle),
            const SizedBox(height: 4),
            Row(
              children: [
                const Icon(Icons.location_on, size: 14, color: Colors.grey),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    prof.ville,
                    style: TextStyle(color: Colors.grey[600], fontSize: 12),
                  ),
                ),
              ],
            ),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Galerie si disponible
            if (prof.gallery.isNotEmpty) ...[
              GalleryPreviewWidget(
                images: prof.gallery.cast<String>(),
                size: 40,
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          ProfessionnelDetailPage(professionnel: prof),
                    ),
                  );
                },
              ),
              const SizedBox(width: 8),
            ],
            // Bouton supprimer
            IconButton(
              icon: const Icon(Icons.favorite, color: Colors.red),
              onPressed: () => _removeFavorite(prof.id),
              tooltip: _localizationService.tr('remove_from_favorites'),
            ),
          ],
        ),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ProfessionnelDetailPage(professionnel: prof),
            ),
          );
        },
      ),
    );
  }

  Future<void> _removeFavorite(String professionnelId) async {
    final favoriteService = FavoriteService.instance;
    await favoriteService.removeFavorite(professionnelId);
    _loadFavorites(); // Recharger la liste

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_localizationService.tr('removed_from_favorites')),
          duration: Duration(seconds: 2),
          backgroundColor: Colors.orange,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_localizationService.tr('my_favorites')),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadFavorites,
            tooltip: _localizationService.tr('refresh'),
          ),
          LanguageSelector(
            onLanguageChanged: (String languageCode) {
              setState(() {
                // Forcer la reconstruction de la page pour mettre à jour la langue
              });
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadFavorites,
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
            ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.error, size: 64, color: Colors.red.shade300),
                    const SizedBox(height: 16),
                    Text('${_localizationService.tr('error')}: $_error'),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: _loadFavorites,
                      child: const Text('Réessayer'),
                    ),
                  ],
                ),
              )
            : _favoriteProfessionnels.isEmpty
            ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.favorite_border, size: 64, color: Colors.grey),
                    SizedBox(height: 16),
                    Text(
                      _localizationService.tr('no_favorites'),
                      style: TextStyle(fontSize: 18, color: Colors.grey),
                    ),
                    SizedBox(height: 8),
                    Text(
                      _localizationService.tr('favorites_subtitle'),
                      style: TextStyle(fontSize: 14, color: Colors.grey),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              )
            : _buildGroupedFavoritesList(),
      ),
    );
  }
}
