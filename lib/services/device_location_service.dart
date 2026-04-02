import 'dart:async';

import 'package:geolocator/geolocator.dart';

enum DeviceLocationStatus {
  unknown,
  available,
  servicesDisabled,
  denied,
  deniedForever,
  error,
}

class DeviceLocationResult {
  const DeviceLocationResult({
    required this.status,
    this.position,
    this.message,
  });

  final DeviceLocationStatus status;
  final Position? position;
  final String? message;

  bool get hasPosition => position != null;
}

class DeviceLocationService {
  Future<DeviceLocationResult> resolveCurrentPosition() async {
    try {
      final servicesEnabled = await Geolocator.isLocationServiceEnabled();
      if (!servicesEnabled) {
        return const DeviceLocationResult(
          status: DeviceLocationStatus.servicesDisabled,
          message: 'Attiva il GPS del dispositivo per vedere la tua posizione attuale.',
        );
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied) {
        return const DeviceLocationResult(
          status: DeviceLocationStatus.denied,
          message: 'Consenti l’accesso alla posizione per mostrare il tuo punto attuale sulla mappa.',
        );
      }

      if (permission == LocationPermission.deniedForever) {
        return const DeviceLocationResult(
          status: DeviceLocationStatus.deniedForever,
          message: 'Il permesso posizione è bloccato in modo permanente. Riattivalo dalle impostazioni dell’app.',
        );
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 12),
        ),
      );

      return DeviceLocationResult(
        status: DeviceLocationStatus.available,
        position: position,
      );
    } on TimeoutException {
      final fallbackPosition = await Geolocator.getLastKnownPosition();
      if (fallbackPosition != null) {
        return DeviceLocationResult(
          status: DeviceLocationStatus.available,
          position: fallbackPosition,
          message: 'Usata l’ultima posizione nota del dispositivo.',
        );
      }

      return const DeviceLocationResult(
        status: DeviceLocationStatus.error,
        message: 'Posizione attuale non disponibile in tempo utile. Riprova tra poco.',
      );
    } catch (error) {
      return DeviceLocationResult(
        status: DeviceLocationStatus.error,
        message: 'Posizione attuale non disponibile: $error',
      );
    }
  }

  Future<void> openAppSettings() async {
    await Geolocator.openAppSettings();
  }

  Future<void> openLocationSettings() async {
    await Geolocator.openLocationSettings();
  }
}
