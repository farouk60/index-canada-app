import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import '../models.dart';

class LocationService {
  static LocationService? _instance;
  static LocationService get instance => _instance ??= LocationService._();
  LocationService._();

  Position? _currentPosition;
  Position? get currentPosition => _currentPosition;

  Future<bool> requestPermission() async {
    try {
      // Vérifier si le service de localisation est activé
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        print('Service de localisation désactivé');
        return false;
      }

      // Vérifier et demander les permissions
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          print('Permission de localisation refusée');
          return false;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        print('Permission de localisation refusée définitivement');
        return false;
      }

      print('Permissions de localisation accordées');
      return true;
    } catch (e) {
      print('Erreur lors de la demande de permission: $e');
      return false;
    }
  }

  Future<Position?> getCurrentLocation() async {
    try {
      bool hasPermission = await requestPermission();
      if (!hasPermission) return null;

      _currentPosition = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      return _currentPosition;
    } catch (e) {
      print('Erreur géolocalisation: $e');
      return null;
    }
  }

  double calculateDistance(double lat1, double lon1, double lat2, double lon2) {
    return Geolocator.distanceBetween(lat1, lon1, lat2, lon2) / 1000; // en km
  }

  List<Professionnel> sortByDistance(
    List<Professionnel> professionals,
    Position userPosition,
  ) {
    // TODO: Ajouter latitude/longitude au modèle Professionnel
    // Pour l'instant, trier par ville
    return professionals;
  }
}

class LocationBasedSearch extends StatefulWidget {
  final List<Professionnel> professionals;
  final Function(List<Professionnel>) onFiltered;

  const LocationBasedSearch({
    super.key,
    required this.professionals,
    required this.onFiltered,
  });

  @override
  State<LocationBasedSearch> createState() => _LocationBasedSearchState();
}

class _LocationBasedSearchState extends State<LocationBasedSearch> {
  double _radiusKm = 10.0;
  Position? _userPosition;
  bool _isLoading = false;

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
                const Spacer(),
                if (_isLoading)
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),

            const SizedBox(height: 16),

            Text('Rayon: ${_radiusKm.round()} km'),
            Slider(
              value: _radiusKm,
              min: 1,
              max: 50,
              divisions: 49,
              onChanged: (value) {
                setState(() {
                  _radiusKm = value;
                });
                _filterByLocation();
              },
            ),

            const SizedBox(height: 8),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _getUserLocationAndFilter,
                icon: const Icon(Icons.my_location),
                label: Text(
                  _userPosition == null
                      ? 'Utiliser ma position'
                      : 'Position détectée',
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _userPosition == null
                      ? Colors.blue
                      : Colors.green,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _getUserLocationAndFilter() async {
    setState(() {
      _isLoading = true;
    });

    final position = await LocationService.instance.getCurrentLocation();

    setState(() {
      _userPosition = position;
      _isLoading = false;
    });

    if (position != null) {
      _filterByLocation();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Impossible d\'obtenir votre position')),
      );
    }
  }

  void _filterByLocation() {
    if (_userPosition == null) return;

    // TODO: Implémenter le filtrage par distance réelle
    // Pour l'instant, retourner tous les professionnels
    widget.onFiltered(widget.professionals);
  }
}
