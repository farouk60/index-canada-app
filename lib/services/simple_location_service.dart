import 'package:flutter/material.dart';
import 'dart:math' as math;
import '../models.dart';

// Service de localisation simplifié - utilisable immédiatement
class SimpleLocationService {
  static SimpleLocationService? _instance;
  static SimpleLocationService get instance =>
      _instance ??= SimpleLocationService._();
  SimpleLocationService._();

  // Simule une position utilisateur (pour test)
  Map<String, dynamic>? _userLocation;

  // Villes québécoises populaires avec coordonnées approximatives
  final Map<String, Map<String, double>> _cityCoordinates = {
    'montreal': {'lat': 45.5017, 'lng': -73.5673},
    'quebec': {'lat': 46.8139, 'lng': -71.2080},
    'gatineau': {'lat': 45.4765, 'lng': -75.7013},
    'sherbrooke': {'lat': 45.4042, 'lng': -71.8929},
    'laval': {'lat': 45.5831, 'lng': -73.7514},
    'longueuil': {'lat': 45.5312, 'lng': -73.5180},
    'trois-rivieres': {'lat': 46.3432, 'lng': -72.5432},
    'terrebonne': {'lat': 45.7061, 'lng': -73.6274},
    'brossard': {'lat': 45.4584, 'lng': -73.4650},
    'drummondville': {'lat': 45.8839, 'lng': -72.4819},
  };

  // Simule l'obtention de la position utilisateur
  Future<bool> requestLocationPermission() async {
    try {
      // Simulation d'une demande de permission
      await Future.delayed(const Duration(milliseconds: 500));

      // Pour le test, on simule que l'utilisateur est à Montréal
      _userLocation = {'lat': 45.5017, 'lng': -73.5673, 'city': 'Montréal'};

      return true;
    } catch (e) {
      print('Erreur simulation localisation: $e');
      return false;
    }
  }

  // Calculer la distance entre deux points (formule de Haversine)
  double calculateDistance(double lat1, double lng1, double lat2, double lng2) {
    const double earthRadius = 6371; // Rayon de la Terre en kilomètres

    double dLat = _degreesToRadians(lat2 - lat1);
    double dLng = _degreesToRadians(lng2 - lng1);

    double a =
        math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_degreesToRadians(lat1)) *
            math.cos(_degreesToRadians(lat2)) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);

    double c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));

    return earthRadius * c;
  }

  double _degreesToRadians(double degrees) {
    return degrees * (math.pi / 180);
  }

  // Obtenir les coordonnées d'une ville
  Map<String, double>? getCityCoordinates(String cityName) {
    String normalizedCity = cityName
        .toLowerCase()
        .replaceAll('é', 'e')
        .replaceAll('è', 'e')
        .replaceAll('ê', 'e')
        .replaceAll('à', 'a')
        .replaceAll(' ', '-');

    return _cityCoordinates[normalizedCity];
  }

  // Filtrer les professionnels par distance
  List<Professionnel> filterByDistance({
    required List<Professionnel> professionals,
    required double maxDistanceKm,
    String? userCity,
  }) {
    if (_userLocation == null && userCity == null) {
      return professionals; // Retourner tous si pas de localisation
    }

    List<Professionnel> filteredProfessionals = [];

    double userLat = _userLocation?['lat'] ?? 45.5017; // Montréal par défaut
    double userLng = _userLocation?['lng'] ?? -73.5673;

    // Si l'utilisateur spécifie une ville, utiliser ses coordonnées
    if (userCity != null) {
      final coords = getCityCoordinates(userCity);
      if (coords != null) {
        userLat = coords['lat']!;
        userLng = coords['lng']!;
      }
    }

    for (final professional in professionals) {
      final proCoords = getCityCoordinates(professional.ville);
      if (proCoords != null) {
        double distance = calculateDistance(
          userLat,
          userLng,
          proCoords['lat']!,
          proCoords['lng']!,
        );

        if (distance <= maxDistanceKm) {
          filteredProfessionals.add(professional);
        }
      } else {
        // Si on ne trouve pas les coordonnées, inclure le professionnel
        filteredProfessionals.add(professional);
      }
    }

    return filteredProfessionals;
  }

  // Trier les professionnels par distance
  List<Professionnel> sortByDistance({
    required List<Professionnel> professionals,
    String? userCity,
  }) {
    if (_userLocation == null && userCity == null) {
      return professionals;
    }

    double userLat = _userLocation?['lat'] ?? 45.5017;
    double userLng = _userLocation?['lng'] ?? -73.5673;

    if (userCity != null) {
      final coords = getCityCoordinates(userCity);
      if (coords != null) {
        userLat = coords['lat']!;
        userLng = coords['lng']!;
      }
    }

    List<Map<String, dynamic>> professionalsWithDistance = [];

    for (final professional in professionals) {
      final proCoords = getCityCoordinates(professional.ville);
      double distance = 999999; // Distance très élevée par défaut

      if (proCoords != null) {
        distance = calculateDistance(
          userLat,
          userLng,
          proCoords['lat']!,
          proCoords['lng']!,
        );
      }

      professionalsWithDistance.add({
        'professional': professional,
        'distance': distance,
      });
    }

    // Trier par distance
    professionalsWithDistance.sort(
      (a, b) => a['distance'].compareTo(b['distance']),
    );

    return professionalsWithDistance
        .map<Professionnel>((item) => item['professional'] as Professionnel)
        .toList();
  }

  // Obtenir la distance d'un professionnel
  String getDistanceText(Professionnel professional, {String? userCity}) {
    if (_userLocation == null && userCity == null) {
      return '';
    }

    double userLat = _userLocation?['lat'] ?? 45.5017;
    double userLng = _userLocation?['lng'] ?? -73.5673;

    if (userCity != null) {
      final coords = getCityCoordinates(userCity);
      if (coords != null) {
        userLat = coords['lat']!;
        userLng = coords['lng']!;
      }
    }

    final proCoords = getCityCoordinates(professional.ville);
    if (proCoords == null) return '';

    double distance = calculateDistance(
      userLat,
      userLng,
      proCoords['lat']!,
      proCoords['lng']!,
    );

    if (distance < 1) {
      return '< 1 km';
    } else if (distance < 10) {
      return '${distance.toStringAsFixed(1)} km';
    } else {
      return '${distance.round()} km';
    }
  }
}

// Widget pour la recherche par proximité simplifiée
class SimpleLocationSearch extends StatefulWidget {
  final List<Professionnel> professionals;
  final Function(List<Professionnel>) onFiltered;

  const SimpleLocationSearch({
    super.key,
    required this.professionals,
    required this.onFiltered,
  });

  @override
  State<SimpleLocationSearch> createState() => _SimpleLocationSearchState();
}

class _SimpleLocationSearchState extends State<SimpleLocationSearch> {
  double _radiusKm = 25.0;
  String? _selectedCity;
  bool _isLocationEnabled = false;

  final List<String> _popularCities = [
    'Montréal',
    'Québec',
    'Gatineau',
    'Sherbrooke',
    'Laval',
    'Longueuil',
    'Trois-Rivières',
  ];

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.location_on, color: Colors.blue),
                const SizedBox(width: 8),
                const Text(
                  'Recherche par proximité',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ],
            ),

            const SizedBox(height: 16),

            // Sélection de ville
            const Text('Votre ville:'),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              value: _selectedCity,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: 'Sélectionnez votre ville',
              ),
              items: _popularCities
                  .map(
                    (city) => DropdownMenuItem(value: city, child: Text(city)),
                  )
                  .toList(),
              onChanged: (value) {
                setState(() {
                  _selectedCity = value;
                  _isLocationEnabled = value != null;
                });
                if (value != null) {
                  _filterByLocation();
                }
              },
            ),

            if (_isLocationEnabled) ...[
              const SizedBox(height: 16),
              Text('Rayon: ${_radiusKm.round()} km'),
              Slider(
                value: _radiusKm,
                min: 5,
                max: 100,
                divisions: 19,
                label: '${_radiusKm.round()} km',
                onChanged: (value) {
                  setState(() {
                    _radiusKm = value;
                  });
                  _filterByLocation();
                },
              ),

              const SizedBox(height: 8),

              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _filterByLocation,
                      icon: const Icon(Icons.search),
                      label: const Text('Rechercher'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _sortByDistance,
                      icon: const Icon(Icons.sort),
                      label: const Text('Trier par distance'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _filterByLocation() {
    if (_selectedCity == null) return;

    final filtered = SimpleLocationService.instance.filterByDistance(
      professionals: widget.professionals,
      maxDistanceKm: _radiusKm,
      userCity: _selectedCity,
    );

    widget.onFiltered(filtered);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '${filtered.length} professionnel(s) trouvé(s) dans un rayon de ${_radiusKm.round()} km',
        ),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _sortByDistance() {
    if (_selectedCity == null) return;

    final sorted = SimpleLocationService.instance.sortByDistance(
      professionals: widget.professionals,
      userCity: _selectedCity,
    );

    widget.onFiltered(sorted);

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Professionnels triés par distance'),
        duration: Duration(seconds: 2),
      ),
    );
  }
}
