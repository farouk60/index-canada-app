import 'package:flutter/material.dart';
import '../models.dart';
import '../data_service.dart';
import 'smart_image_widget.dart';

class UniversalSearchDelegate extends SearchDelegate<Professionnel?> {
  final DataService _dataService = DataService();

  @override
  String get searchFieldLabel => 'Rechercher par nom, ville, service...';

  @override
  List<Widget> buildActions(BuildContext context) {
    return [
      IconButton(icon: const Icon(Icons.clear), onPressed: () => query = ''),
    ];
  }

  @override
  Widget buildLeading(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.arrow_back),
      onPressed: () => close(context, null),
    );
  }

  @override
  Widget buildResults(BuildContext context) {
    return _buildSearchResults();
  }

  @override
  Widget buildSuggestions(BuildContext context) {
    if (query.length < 2) {
      return const Center(
        child: Text('Tapez au moins 2 caractères pour rechercher'),
      );
    }
    return _buildSearchResults();
  }

  Widget _buildSearchResults() {
    return FutureBuilder<List<Professionnel>>(
      future: _searchProfessionnels(query),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return Center(child: Text('Erreur: ${snapshot.error}'));
        }

        final professionals = snapshot.data ?? [];
        if (professionals.isEmpty) {
          return const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.search_off, size: 64, color: Colors.grey),
                SizedBox(height: 16),
                Text('Aucun professionnel trouvé'),
              ],
            ),
          );
        }

        return ListView.builder(
          itemCount: professionals.length,
          itemBuilder: (context, index) {
            final pro = professionals[index];
            return ListTile(
              leading: CircleAvatar(
                child: ClipOval(
                  child: SmartImageWidget(
                    imageUrl: pro.image,
                    width: 40,
                    height: 40,
                    fit: BoxFit.cover,
                    errorWidget: const Icon(Icons.person, color: Colors.grey),
                  ),
                ),
              ),
              title: Text(pro.title),
              subtitle: Text(
                '${pro.ville} • ${_getCategoryName(pro.sousCategorie)}',
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (pro.averageRating > 0) ...[
                    const Icon(Icons.star, color: Colors.amber, size: 16),
                    Text('${pro.averageRating.toStringAsFixed(1)}'),
                  ],
                ],
              ),
              onTap: () => close(context, pro),
            );
          },
        );
      },
    );
  }

  Future<List<Professionnel>> _searchProfessionnels(String query) async {
    try {
      final allProfessionnels = await _dataService.fetchProfessionnels();
      final lowercaseQuery = query.toLowerCase();

      return allProfessionnels.where((pro) {
        return pro.title.toLowerCase().contains(lowercaseQuery) ||
            pro.ville.toLowerCase().contains(lowercaseQuery) ||
            pro.subtitle.toLowerCase().contains(lowercaseQuery) ||
            _getCategoryName(
              pro.sousCategorie,
            ).toLowerCase().contains(lowercaseQuery);
      }).toList();
    } catch (e) {
      throw Exception('Erreur lors de la recherche: $e');
    }
  }

  String _getCategoryName(String categoryId) {
    // TODO: Implémenter la récupération du nom de catégorie
    return 'Service';
  }
}
