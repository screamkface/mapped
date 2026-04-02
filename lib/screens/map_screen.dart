import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';

import '../controllers/destination_controller.dart';
import '../models/destination.dart';
import '../services/device_location_service.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({
    super.key,
    required this.onOpenDetail,
    required this.onNavigate,
  });

  final Future<void> Function(String destinationId) onOpenDetail;
  final Future<void> Function(Destination destination) onNavigate;

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> with WidgetsBindingObserver {
  static const LatLng _fallbackTarget = LatLng(41.8719, 12.5674);

  final DeviceLocationService _deviceLocationService = DeviceLocationService();

  GoogleMapController? _mapController;
  String _lastBoundsSignature = '';
  DeviceLocationStatus _locationStatus = DeviceLocationStatus.unknown;
  LatLng? _currentLocation;
  String? _locationMessage;
  bool _isResolvingLocation = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_refreshCurrentLocation());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _mapController?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_refreshCurrentLocation());
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<DestinationController>();
    final destinations = controller.mappableDestinations;
    final selected = controller.selectedDestination;

    if (destinations.isNotEmpty) {
      _scheduleBoundsUpdate(destinations);
    }

    return Stack(
      children: <Widget>[
        ClipRRect(
          borderRadius: BorderRadius.circular(28),
          child: GoogleMap(
            initialCameraPosition: CameraPosition(
              target: _initialTarget(destinations),
              zoom: _initialZoom(destinations),
            ),
            markers: destinations.map(_buildMarker).toSet(),
            myLocationEnabled: _locationStatus == DeviceLocationStatus.available,
            myLocationButtonEnabled:
                _locationStatus == DeviceLocationStatus.available,
            mapToolbarEnabled: false,
            onMapCreated: (mapController) {
              _mapController = mapController;
              if (destinations.isNotEmpty) {
                _fitBounds(destinations);
                return;
              }
              unawaited(_centerOnCurrentLocation());
            },
            onTap: (_) => controller.selectDestination(null),
          ),
        ),
        ..._buildTopBanners(controller),
        if (selected != null && selected.hasCoordinates)
          Positioned(
            left: 16,
            right: 16,
            bottom: 16,
            child: _SelectedDestinationCard(
              destination: selected,
              onOpenDetail: () => widget.onOpenDetail(selected.id),
              onNavigate: () => widget.onNavigate(selected),
            ),
          )
        else if (destinations.isEmpty)
          Positioned(
            left: 16,
            right: 16,
            bottom: 16,
            child: _NoMarkersState(
              missingCount: controller.missingCoordinatesCount,
              hasCurrentLocation:
                  _locationStatus == DeviceLocationStatus.available,
            ),
          ),
      ],
    );
  }

  List<Widget> _buildTopBanners(DestinationController controller) {
    final banners = <Widget>[
      if (controller.missingCoordinatesCount > 0)
        _Banner(
          text:
              '${controller.missingCoordinatesCount} record senza coordinate non sono mostrati sulla mappa.',
        ),
      if (_buildLocationBanner() case final locationBanner?) locationBanner,
    ];

    if (banners.isEmpty) {
      return const <Widget>[];
    }

    return <Widget>[
      Positioned(
        top: 16,
        left: 16,
        right: 16,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: banners
              .expand((banner) => <Widget>[banner, const SizedBox(height: 10)])
              .toList(growable: true)
            ..removeLast(),
        ),
      ),
    ];
  }

  Widget? _buildLocationBanner() {
    if (_isResolvingLocation && _currentLocation == null) {
      return const _StatusBanner(
        icon: Icons.my_location_outlined,
        text: 'Recupero posizione attuale in corso...',
        isLoading: true,
      );
    }

    switch (_locationStatus) {
      case DeviceLocationStatus.unknown:
      case DeviceLocationStatus.available:
        return null;
      case DeviceLocationStatus.servicesDisabled:
        return _StatusBanner(
          icon: Icons.location_disabled_outlined,
          text:
              _locationMessage ??
              'Attiva la posizione del dispositivo per vedere il tuo punto attuale.',
          actionLabel: 'Impostazioni',
          onAction: _openLocationSettings,
        );
      case DeviceLocationStatus.denied:
        return _StatusBanner(
          icon: Icons.location_searching_outlined,
          text:
              _locationMessage ??
              'Consenti l’accesso alla posizione per vedere il tuo punto attuale.',
          actionLabel: 'Consenti',
          onAction: () => _refreshCurrentLocation(recenterMap: true),
        );
      case DeviceLocationStatus.deniedForever:
        return _StatusBanner(
          icon: Icons.lock_outline,
          text:
              _locationMessage ??
              'Il permesso posizione è bloccato. Riattivalo nelle impostazioni dell’app.',
          actionLabel: 'Apri app',
          onAction: _openAppSettings,
        );
      case DeviceLocationStatus.error:
        return _StatusBanner(
          icon: Icons.gps_off_outlined,
          text:
              _locationMessage ??
              'Posizione attuale non disponibile. Riprova tra poco.',
          actionLabel: 'Riprova',
          onAction: () => _refreshCurrentLocation(recenterMap: true),
        );
    }
  }

  Marker _buildMarker(Destination destination) {
    final controller = context.read<DestinationController>();
    final isSelected =
        destination.id == controller.selectedDestinationId;

    return Marker(
      markerId: MarkerId(destination.id),
      position: LatLng(destination.latitude!, destination.longitude!),
      icon: BitmapDescriptor.defaultMarkerWithHue(
        isSelected
            ? BitmapDescriptor.hueAzure
            : controller.markerHueFor(destination),
      ),
      onTap: () {
        controller.selectDestination(destination.id);
      },
      infoWindow: InfoWindow(title: destination.displayName),
    );
  }

  LatLng _initialTarget(List<Destination> destinations) {
    if (destinations.isNotEmpty) {
      final first = destinations.first;
      return LatLng(first.latitude!, first.longitude!);
    }

    return _currentLocation ?? _fallbackTarget;
  }

  double _initialZoom(List<Destination> destinations) {
    if (destinations.isEmpty) {
      return _currentLocation == null ? 5.8 : 14;
    }
    return destinations.length == 1 ? 12 : 5.2;
  }

  void _scheduleBoundsUpdate(List<Destination> destinations) {
    final signature = destinations
        .map(
          (destination) =>
              '${destination.id}:${destination.latitude}:${destination.longitude}',
        )
        .join('|');

    if (_lastBoundsSignature == signature) {
      return;
    }

    _lastBoundsSignature = signature;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _fitBounds(destinations);
    });
  }

  Future<void> _fitBounds(List<Destination> destinations) async {
    final controller = _mapController;
    if (controller == null || destinations.isEmpty) {
      return;
    }

    if (destinations.length == 1) {
      final destination = destinations.first;
      await controller.animateCamera(
        CameraUpdate.newLatLngZoom(
          LatLng(destination.latitude!, destination.longitude!),
          13,
        ),
      );
      return;
    }

    final latitudes = destinations.map((destination) => destination.latitude!);
    final longitudes = destinations.map(
      (destination) => destination.longitude!,
    );

    final bounds = LatLngBounds(
      southwest: LatLng(
        latitudes.reduce((value, element) => value < element ? value : element),
        longitudes.reduce(
          (value, element) => value < element ? value : element,
        ),
      ),
      northeast: LatLng(
        latitudes.reduce((value, element) => value > element ? value : element),
        longitudes.reduce(
          (value, element) => value > element ? value : element,
        ),
      ),
    );

    unawaited(
      Future<void>.delayed(const Duration(milliseconds: 250), () async {
        if (!mounted || _mapController == null) {
          return;
        }
        await _mapController!.animateCamera(
          CameraUpdate.newLatLngBounds(bounds, 56),
        );
      }),
    );
  }

  Future<void> _refreshCurrentLocation({bool recenterMap = false}) async {
    if (_isResolvingLocation) {
      return;
    }

    setState(() {
      _isResolvingLocation = true;
    });

    final result = await _deviceLocationService.resolveCurrentPosition();
    if (!mounted) {
      return;
    }

    LatLng? currentLocation;
    final position = result.position;
    if (position != null) {
      currentLocation = LatLng(position.latitude, position.longitude);
    }

    setState(() {
      _isResolvingLocation = false;
      _locationStatus = result.status;
      _locationMessage = result.message;
      _currentLocation = currentLocation ?? _currentLocation;
    });

    if (result.status == DeviceLocationStatus.available &&
        _currentLocation != null &&
        (recenterMap ||
            context.read<DestinationController>().mappableDestinations.isEmpty)) {
      await _centerOnCurrentLocation();
    }
  }

  Future<void> _centerOnCurrentLocation() async {
    final currentLocation = _currentLocation;
    final mapController = _mapController;
    if (currentLocation == null || mapController == null) {
      return;
    }

    await mapController.animateCamera(
      CameraUpdate.newLatLngZoom(currentLocation, 15),
    );
  }

  Future<void> _openAppSettings() async {
    await _deviceLocationService.openAppSettings();
  }

  Future<void> _openLocationSettings() async {
    await _deviceLocationService.openLocationSettings();
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFFFF3DD),
      elevation: 1,
      borderRadius: BorderRadius.circular(18),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: <Widget>[
            const Icon(Icons.info_outline),
            const SizedBox(width: 10),
            Expanded(child: Text(text)),
          ],
        ),
      ),
    );
  }
}

class _StatusBanner extends StatelessWidget {
  const _StatusBanner({
    required this.icon,
    required this.text,
    this.actionLabel,
    this.onAction,
    this.isLoading = false,
  });

  final IconData icon;
  final String text;
  final String? actionLabel;
  final VoidCallback? onAction;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFE8F4F0),
      elevation: 1,
      borderRadius: BorderRadius.circular(18),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: <Widget>[
            Icon(icon),
            const SizedBox(width: 10),
            Expanded(child: Text(text)),
            if (isLoading)
              const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2.2),
              )
            else if (actionLabel != null && onAction != null)
              TextButton(
                onPressed: onAction,
                child: Text(actionLabel!),
              ),
          ],
        ),
      ),
    );
  }
}

class _SelectedDestinationCard extends StatelessWidget {
  const _SelectedDestinationCard({
    required this.destination,
    required this.onOpenDetail,
    required this.onNavigate,
  });

  final Destination destination;
  final VoidCallback onOpenDetail;
  final VoidCallback onNavigate;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: onOpenDetail,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                destination.displayName,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 6),
              Text(
                destination.fullAddress.isNotEmpty
                    ? destination.fullAddress
                    : 'Indirizzo non disponibile',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: <Widget>[
                  OutlinedButton(
                    onPressed: onOpenDetail,
                    child: const Text('Dettagli'),
                  ),
                  FilledButton.icon(
                    onPressed: onNavigate,
                    icon: const Icon(Icons.navigation_outlined),
                    label: const Text('Naviga'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NoMarkersState extends StatelessWidget {
  const _NoMarkersState({
    required this.missingCount,
    required this.hasCurrentLocation,
  });

  final int missingCount;
  final bool hasCurrentLocation;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              hasCurrentLocation
                  ? Icons.my_location_outlined
                  : Icons.pin_drop_outlined,
              size: 44,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 12),
            Text(
              hasCurrentLocation
                  ? 'Posizione attuale visibile'
                  : 'Nessun marker disponibile',
              style: Theme.of(context).textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              hasCurrentLocation
                  ? 'La mappa mostra già il tuo punto attuale. Aggiungi o importa destinazioni con coordinate per vedere anche i marker dei siti.'
                  : missingCount > 0
                  ? 'I record presenti non hanno coordinate valide. Rimangono comunque disponibili in tabella e nel dettaglio.'
                  : 'Importa o crea destinazioni con latitudine e longitudine per visualizzarle sulla mappa.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
