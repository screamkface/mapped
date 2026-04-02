import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../models/destination.dart';
import '../services/destination_photo_service.dart';

Future<Destination?> showDestinationFormSheet(
  BuildContext context, {
  Destination? initialDestination,
}) {
  return showModalBottomSheet<Destination>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (_) =>
        DestinationFormSheet(initialDestination: initialDestination),
  );
}

class DestinationFormSheet extends StatefulWidget {
  const DestinationFormSheet({super.key, this.initialDestination});

  final Destination? initialDestination;

  @override
  State<DestinationFormSheet> createState() => _DestinationFormSheetState();
}

class _DestinationFormSheetState extends State<DestinationFormSheet> {
  final _formKey = GlobalKey<FormState>();
  final _photoService = DestinationPhotoService();

  late final TextEditingController _nameController;
  late final TextEditingController _addressController;
  late final TextEditingController _cityController;
  late final TextEditingController _postalCodeController;
  late final TextEditingController _notesController;
  late final TextEditingController _phoneController;
  late final TextEditingController _latitudeController;
  late final TextEditingController _longitudeController;

  late DestinationStatus _status;
  String? _photoPath;
  bool _isCapturingPhoto = false;
  bool _submitted = false;

  @override
  void initState() {
    super.initState();
    final destination = widget.initialDestination;
    _nameController = TextEditingController(text: destination?.name ?? '');
    _addressController = TextEditingController(
      text: destination?.address ?? '',
    );
    _cityController = TextEditingController(text: destination?.city ?? '');
    _postalCodeController = TextEditingController(
      text: destination?.postalCode ?? '',
    );
    _notesController = TextEditingController(text: destination?.notes ?? '');
    _phoneController = TextEditingController(text: destination?.phone ?? '');
    _latitudeController = TextEditingController(
      text: destination?.latitude?.toString() ?? '',
    );
    _longitudeController = TextEditingController(
      text: destination?.longitude?.toString() ?? '',
    );
    _status = destination?.status ?? DestinationStatus.pending;
    _photoPath = destination?.photoPath;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _addressController.dispose();
    _cityController.dispose();
    _postalCodeController.dispose();
    _notesController.dispose();
    _phoneController.dispose();
    _latitudeController.dispose();
    _longitudeController.dispose();

    final initialPhotoPath = widget.initialDestination?.photoPath;
    final shouldDeleteTemporaryPhoto =
        !_submitted && _photoPath != null && _photoPath != initialPhotoPath;

    if (shouldDeleteTemporaryPhoto) {
      unawaited(_photoService.deletePhoto(_photoPath));
    }

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.initialDestination != null;
    final useStackedFields = MediaQuery.sizeOf(context).width < 420;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: FractionallySizedBox(
        heightFactor: 0.94,
        child: SafeArea(
          top: false,
          child: Card(
            margin: const EdgeInsets.fromLTRB(12, 12, 12, 12),
            child: Column(
              children: <Widget>[
                const SizedBox(height: 12),
                Container(
                  width: 44,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Theme.of(
                      context,
                    ).colorScheme.outlineVariant.withValues(alpha: 0.9),
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 12, 0),
                  child: Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          isEditing
                              ? 'Modifica destinazione'
                              : 'Nuova destinazione',
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Form(
                    key: _formKey,
                    child: ListView(
                      keyboardDismissBehavior:
                          ScrollViewKeyboardDismissBehavior.onDrag,
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                      children: <Widget>[
                        TextFormField(
                          controller: _nameController,
                          decoration: const InputDecoration(labelText: 'Nome'),
                          scrollPadding: const EdgeInsets.only(bottom: 160),
                          validator: (value) {
                            if ((value ?? '').trim().isEmpty) {
                              return 'Il nome e\' obbligatorio.';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _addressController,
                          decoration: const InputDecoration(
                            labelText: 'Indirizzo',
                          ),
                          scrollPadding: const EdgeInsets.only(bottom: 160),
                        ),
                        const SizedBox(height: 12),
                        if (useStackedFields) ...<Widget>[
                          TextFormField(
                            controller: _cityController,
                            decoration: const InputDecoration(
                              labelText: 'Citta\'',
                            ),
                            scrollPadding: const EdgeInsets.only(bottom: 160),
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _postalCodeController,
                            decoration: const InputDecoration(labelText: 'CAP'),
                            scrollPadding: const EdgeInsets.only(bottom: 160),
                          ),
                        ] else
                          Row(
                            children: <Widget>[
                              Expanded(
                                child: TextFormField(
                                  controller: _cityController,
                                  decoration: const InputDecoration(
                                    labelText: 'Citta\'',
                                  ),
                                  scrollPadding: const EdgeInsets.only(
                                    bottom: 160,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              SizedBox(
                                width: 120,
                                child: TextFormField(
                                  controller: _postalCodeController,
                                  decoration: const InputDecoration(
                                    labelText: 'CAP',
                                  ),
                                  scrollPadding: const EdgeInsets.only(
                                    bottom: 160,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _phoneController,
                          decoration: const InputDecoration(
                            labelText: 'Telefono',
                          ),
                          keyboardType: TextInputType.phone,
                          scrollPadding: const EdgeInsets.only(bottom: 160),
                        ),
                        const SizedBox(height: 16),
                        _PhotoFieldSection(
                          photoPath: _photoPath,
                          isCapturingPhoto: _isCapturingPhoto,
                          onCapture: _capturePhoto,
                          onRemove: _removeSelectedPhoto,
                        ),
                        const SizedBox(height: 16),
                        if (useStackedFields) ...<Widget>[
                          TextFormField(
                            controller: _latitudeController,
                            decoration: const InputDecoration(
                              labelText: 'Latitudine (opzionale)',
                            ),
                            keyboardType: const TextInputType.numberWithOptions(
                              signed: true,
                              decimal: true,
                            ),
                            scrollPadding: const EdgeInsets.only(bottom: 160),
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _longitudeController,
                            decoration: const InputDecoration(
                              labelText: 'Longitudine (opzionale)',
                            ),
                            keyboardType: const TextInputType.numberWithOptions(
                              signed: true,
                              decimal: true,
                            ),
                            scrollPadding: const EdgeInsets.only(bottom: 160),
                          ),
                        ] else
                          Row(
                            children: <Widget>[
                              Expanded(
                                child: TextFormField(
                                  controller: _latitudeController,
                                  decoration: const InputDecoration(
                                    labelText: 'Latitudine (opzionale)',
                                  ),
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                        signed: true,
                                        decimal: true,
                                      ),
                                  scrollPadding: const EdgeInsets.only(
                                    bottom: 160,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: TextFormField(
                                  controller: _longitudeController,
                                  decoration: const InputDecoration(
                                    labelText: 'Longitudine (opzionale)',
                                  ),
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                        signed: true,
                                        decimal: true,
                                      ),
                                  scrollPadding: const EdgeInsets.only(
                                    bottom: 160,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        const SizedBox(height: 8),
                        Text(
                          'Se lasci vuote le coordinate, l\'app prova a ricavarle automaticamente dall\'indirizzo.',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<DestinationStatus>(
                          initialValue: _status,
                          items: DestinationStatus.values
                              .map((status) {
                                return DropdownMenuItem<DestinationStatus>(
                                  value: status,
                                  child: Text(status.label),
                                );
                              })
                              .toList(growable: false),
                          onChanged: (value) {
                            if (value == null) {
                              return;
                            }
                            setState(() {
                              _status = value;
                            });
                          },
                          decoration: const InputDecoration(labelText: 'Stato'),
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _notesController,
                          decoration: const InputDecoration(labelText: 'Note'),
                          maxLines: 4,
                          minLines: 3,
                          scrollPadding: const EdgeInsets.only(bottom: 160),
                        ),
                      ],
                    ),
                  ),
                ),
                SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                    child: useStackedFields
                        ? Column(
                            children: <Widget>[
                              OutlinedButton(
                                onPressed: () => Navigator.of(context).pop(),
                                child: const Text('Annulla'),
                              ),
                              const SizedBox(height: 12),
                              FilledButton.icon(
                                onPressed: _submit,
                                icon: const Icon(Icons.save_outlined),
                                label: const Text('Salva'),
                              ),
                            ],
                          )
                        : Row(
                            children: <Widget>[
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: () => Navigator.of(context).pop(),
                                  child: const Text('Annulla'),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: FilledButton.icon(
                                  onPressed: _submit,
                                  icon: const Icon(Icons.save_outlined),
                                  label: const Text('Salva'),
                                ),
                              ),
                            ],
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _capturePhoto() async {
    FocusScope.of(context).unfocus();
    setState(() {
      _isCapturingPhoto = true;
    });

    try {
      final previousTemporaryPhotoPath = _photoPath;
      final capturedPhotoPath = await _photoService.capturePhoto();
      if (!mounted || capturedPhotoPath == null) {
        return;
      }

      final initialPhotoPath = widget.initialDestination?.photoPath;
      if (previousTemporaryPhotoPath != null &&
          previousTemporaryPhotoPath != initialPhotoPath &&
          previousTemporaryPhotoPath != capturedPhotoPath) {
        await _photoService.deletePhoto(previousTemporaryPhotoPath);
      }

      setState(() {
        _photoPath = capturedPhotoPath;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Acquisizione foto non riuscita: $error')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isCapturingPhoto = false;
        });
      }
    }
  }

  Future<void> _removeSelectedPhoto() async {
    final currentPhotoPath = _photoPath;
    if (currentPhotoPath == null) {
      return;
    }

    final initialPhotoPath = widget.initialDestination?.photoPath;
    if (currentPhotoPath != initialPhotoPath) {
      await _photoService.deletePhoto(currentPhotoPath);
    }

    if (!mounted) {
      return;
    }

    setState(() {
      _photoPath = null;
    });
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final latitude = _parseCoordinate(_latitudeController.text);
    final longitude = _parseCoordinate(_longitudeController.text);

    final hasLatitude = _latitudeController.text.trim().isNotEmpty;
    final hasLongitude = _longitudeController.text.trim().isNotEmpty;
    if (hasLatitude != hasLongitude) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Inserisci entrambe le coordinate oppure nessuna.'),
        ),
      );
      return;
    }

    if ((hasLatitude && latitude == null) ||
        (hasLongitude && longitude == null)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Le coordinate inserite non sono valide.'),
        ),
      );
      return;
    }

    _submitted = true;

    Navigator.of(context).pop(
      Destination(
        id: widget.initialDestination?.id ?? Destination.generateId(),
        name: _nameController.text.trim(),
        address: _addressController.text.trim(),
        city: _cityController.text.trim(),
        postalCode: _postalCodeController.text.trim(),
        notes: _notesController.text.trim(),
        phone: _phoneController.text.trim(),
        photoPath: _photoPath,
        latitude: latitude,
        longitude: longitude,
        status: _status,
        customFields: widget.initialDestination?.customFields,
      ),
    );
  }

  double? _parseCoordinate(String rawValue) {
    final normalized = rawValue.trim().replaceAll(',', '.');
    if (normalized.isEmpty) {
      return null;
    }
    return double.tryParse(normalized);
  }
}

class _PhotoFieldSection extends StatelessWidget {
  const _PhotoFieldSection({
    required this.photoPath,
    required this.isCapturingPhoto,
    required this.onCapture,
    required this.onRemove,
  });

  final String? photoPath;
  final bool isCapturingPhoto;
  final Future<void> Function() onCapture;
  final Future<void> Function() onRemove;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          'Foto',
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 10),
        if (photoPath != null) ...<Widget>[
          ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: AspectRatio(
              aspectRatio: 4 / 3,
              child: Image.file(
                File(photoPath!),
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) {
                  return Container(
                    color: Theme.of(
                      context,
                    ).colorScheme.surfaceContainerHighest,
                    alignment: Alignment.center,
                    child: const Text('Immagine non disponibile'),
                  );
                },
              ),
            ),
          ),
          const SizedBox(height: 10),
        ],
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: <Widget>[
            FilledButton.tonalIcon(
              onPressed: isCapturingPhoto ? null : onCapture,
              icon: Icon(
                photoPath == null
                    ? Icons.photo_camera_outlined
                    : Icons.autorenew_rounded,
              ),
              label: Text(
                isCapturingPhoto
                    ? 'Apertura fotocamera...'
                    : photoPath == null
                    ? 'Scatta foto'
                    : 'Sostituisci foto',
              ),
            ),
            if (photoPath != null)
              OutlinedButton.icon(
                onPressed: onRemove,
                icon: const Icon(Icons.delete_outline),
                label: const Text('Rimuovi'),
              ),
          ],
        ),
      ],
    );
  }
}
