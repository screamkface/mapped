import 'package:url_launcher/url_launcher.dart';

import '../models/destination.dart';

class NavigationException implements Exception {
  const NavigationException(this.message);

  final String message;

  @override
  String toString() => message;
}

class NavigationService {
  Future<void> openInGoogleMaps(Destination destination) async {
    final target = destination.hasCoordinates
        ? '${destination.latitude},${destination.longitude}'
        : destination.fullAddress;

    if (target.trim().isEmpty) {
      throw const NavigationException(
        'Inserisci coordinate o indirizzo prima di avviare la navigazione.',
      );
    }

    final uri = Uri.https('www.google.com', '/maps/dir/', <String, String>{
      'api': '1',
      'destination': target,
      'travelmode': 'driving',
    });

    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);

    if (!launched) {
      throw const NavigationException(
        'Impossibile aprire Google Maps sul dispositivo.',
      );
    }
  }
}
