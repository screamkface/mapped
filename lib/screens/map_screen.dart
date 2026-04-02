import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';

import '../controllers/destination_controller.dart';
import '../models/destination.dart';

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

class _MapScreenState extends State<MapScreen> {
  GoogleMapController? _mapController;
  String _lastBoundsSignature = '';

  @override
  void dispose() {
    _mapController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<DestinationController>();
    final destinations = controller.mappableDestinations;
    final selected = controller.selectedDestination;

    if (destinations.isEmpty) {
      return _NoMarkersState(missingCount: controller.missingCoordinatesCount);
    }

    _scheduleBoundsUpdate(destinations);

    return Stack(
      children: <Widget>[
        ClipRRect(
          borderRadius: BorderRadius.circular(28),
          child: GoogleMap(
            initialCameraPosition: CameraPosition(
              target: _initialTarget(destinations),
              zoom: destinations.length == 1 ? 12 : 5.2,
            ),
            markers: destinations.map(_buildMarker).toSet(),
            myLocationButtonEnabled: false,
            mapToolbarEnabled: false,
            onMapCreated: (mapController) {
              _mapController = mapController;
              _fitBounds(destinations);
            },
            onTap: (_) => controller.selectDestination(null),
          ),
        ),
        if (controller.missingCoordinatesCount > 0)
          Positioned(
            top: 16,
            left: 16,
            right: 16,
            child: _Banner(
              text:
                  '${controller.missingCoordinatesCount} record senza coordinate non sono mostrati sulla mappa.',
            ),
          ),
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
          ),
      ],
    );
  }

  Marker _buildMarker(Destination destination) {
    final isSelected =
        destination.id ==
        context.read<DestinationController>().selectedDestinationId;

    return Marker(
      markerId: MarkerId(destination.id),
      position: LatLng(destination.latitude!, destination.longitude!),
      icon: BitmapDescriptor.defaultMarkerWithHue(
        isSelected
            ? BitmapDescriptor.hueAzure
            : destination.status == DestinationStatus.completed
            ? BitmapDescriptor.hueGreen
            : BitmapDescriptor.hueRed,
      ),
      onTap: () {
        context.read<DestinationController>().selectDestination(destination.id);
      },
      infoWindow: InfoWindow(title: destination.displayName),
    );
  }

  LatLng _initialTarget(List<Destination> destinations) {
    final first = destinations.first;
    return LatLng(first.latitude!, first.longitude!);
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
  const _NoMarkersState({required this.missingCount});

  final int missingCount;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(
                Icons.pin_drop_outlined,
                size: 44,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 12),
              Text(
                'Nessun marker disponibile',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(
                missingCount > 0
                    ? 'I record presenti non hanno coordinate valide. Rimangono comunque disponibili in tabella e nel dettaglio.'
                    : 'Importa o crea destinazioni con latitudine e longitudine per visualizzarle sulla mappa.',
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
