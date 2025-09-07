import 'package:url_launcher/url_launcher.dart';

class MapsService {
  static MapsService? _instance;

  MapsService._internal();

  static MapsService get instance {
    _instance ??= MapsService._internal();
    return _instance!;
  }

  /// Ouvrir Google Maps avec une adresse
  Future<bool> openGoogleMaps(String address) async {
    try {
      // Encoder l'adresse pour l'URL
      final encodedAddress = Uri.encodeComponent(address);

      // URL pour Google Maps
      final googleMapsUrl =
          'https://www.google.com/maps/search/?api=1&query=$encodedAddress';

      final uri = Uri.parse(googleMapsUrl);

      if (await canLaunchUrl(uri)) {
        return await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        return false;
      }
    } catch (e) {
      return false;
    }
  }

  /// Ouvrir Google Maps avec des coordonnées lat/lng
  Future<bool> openGoogleMapsWithCoordinates(
    double latitude,
    double longitude,
  ) async {
    try {
      final googleMapsUrl =
          'https://www.google.com/maps/search/?api=1&query=$latitude,$longitude';

      final uri = Uri.parse(googleMapsUrl);

      if (await canLaunchUrl(uri)) {
        return await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        return false;
      }
    } catch (e) {
      return false;
    }
  }

  /// Ouvrir l'application Maps native (iOS) ou Google Maps (Android)
  Future<bool> openNativeMaps(String address) async {
    try {
      final encodedAddress = Uri.encodeComponent(address);

      // Pour iOS: utiliser l'app Maps native
      final iosMapsUrl = 'maps://?q=$encodedAddress';
      final iosUri = Uri.parse(iosMapsUrl);

      // Pour Android: utiliser Google Maps
      final androidMapsUrl = 'geo:0,0?q=$encodedAddress';
      final androidUri = Uri.parse(androidMapsUrl);

      // Essayer d'abord l'app native iOS
      if (await canLaunchUrl(iosUri)) {
        return await launchUrl(iosUri, mode: LaunchMode.externalApplication);
      }
      // Sinon essayer l'app Android
      else if (await canLaunchUrl(androidUri)) {
        return await launchUrl(
          androidUri,
          mode: LaunchMode.externalApplication,
        );
      }
      // Fallback: utiliser le navigateur web
      else {
        return await openGoogleMaps(address);
      }
    } catch (e) {
      // Fallback: utiliser le navigateur web
      return await openGoogleMaps(address);
    }
  }
}
