import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../controllers/destination_controller.dart';
import '../models/destination.dart';
import '../services/geocoding_service.dart';
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
  late final TextEditingController _categoryController;
  late final TextEditingController _tagsController;

  late DestinationStatus _status;
  late List<String> _attachmentPaths;
  late DateTime? _dueDate;
  late final List<_ChecklistDraft> _checklistDrafts;
  late final List<_CustomFieldDraft> _customFieldDrafts;

  bool _isCapturingPhoto = false;
  bool _isPickingFromGallery = false;
  bool _isSearchingAddress = false;
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
    _categoryController = TextEditingController(
      text: destination?.category ?? '',
    );
    _tagsController = TextEditingController(
      text: destination?.tags.join(', ') ?? '',
    );
    _status = destination?.status ?? DestinationStatus.pending;
    _attachmentPaths = <String>[...(destination?.attachmentPaths ?? const <String>[])];
    _dueDate = destination?.dueDate;
    _checklistDrafts = (destination?.checklistItems ?? const <ChecklistItem>[])
        .map((item) => _ChecklistDraft.fromItem(item))
        .toList(growable: true);
    _customFieldDrafts = (destination?.sortedCustomFields ?? const <MapEntry<String, String>>[])
        .map((entry) => _CustomFieldDraft(key: entry.key, value: entry.value))
        .toList(growable: true);
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
    _categoryController.dispose();
    _tagsController.dispose();

    for (final draft in _checklistDrafts) {
      draft.dispose();
    }
    for (final draft in _customFieldDrafts) {
      draft.dispose();
    }

    if (!_submitted) {
      final initialAttachments = widget.initialDestination?.attachmentPaths ?? const <String>[];
      final temporaryAttachments = _attachmentPaths
          .where((path) => !initialAttachments.contains(path))
          .toList(growable: false);
      unawaited(_photoService.deletePhotos(temporaryAttachments));
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
        heightFactor: 0.95,
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
                        _SectionTitle(title: 'Destinazione'),
                        TextFormField(
                          controller: _nameController,
                          decoration: const InputDecoration(labelText: 'Nome'),
                          validator: (value) {
                            if ((value ?? '').trim().isEmpty) {
                              return 'Il nome è obbligatorio.';
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
                        ),
                        const SizedBox(height: 12),
                        if (useStackedFields) ...<Widget>[
                          TextFormField(
                            controller: _cityController,
                            decoration: const InputDecoration(labelText: 'Città'),
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _postalCodeController,
                            decoration: const InputDecoration(labelText: 'CAP'),
                          ),
                        ] else
                          Row(
                            children: <Widget>[
                              Expanded(
                                child: TextFormField(
                                  controller: _cityController,
                                  decoration: const InputDecoration(
                                    labelText: 'Città',
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
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _categoryController,
                          decoration: const InputDecoration(
                            labelText: 'Categoria / tipo lavoro',
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _tagsController,
                          decoration: const InputDecoration(
                            labelText: 'Tag',
                            hintText: 'Es. urgente, sopralluogo, impianti',
                          ),
                        ),
                        const SizedBox(height: 16),
                        _SectionTitle(title: 'Coordinate e mappa'),
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
                                ),
                              ),
                            ],
                          ),
                        const SizedBox(height: 8),
                        Text(
                          'Se lasci vuote le coordinate, l’app prova a ricavarle automaticamente dall’indirizzo.',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: <Widget>[
                            OutlinedButton.icon(
                              onPressed: _isSearchingAddress
                                  ? null
                                  : _searchAddressCandidates,
                              icon: _isSearchingAddress
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2.2,
                                      ),
                                    )
                                  : const Icon(Icons.search_outlined),
                              label: const Text('Trova indirizzo'),
                            ),
                            if (_latitudeController.text.trim().isNotEmpty &&
                                _longitudeController.text.trim().isNotEmpty)
                              TextButton.icon(
                                onPressed: () {
                                  setState(() {
                                    _latitudeController.clear();
                                    _longitudeController.clear();
                                  });
                                },
                                icon: const Icon(Icons.clear_outlined),
                                label: const Text('Pulisci coordinate'),
                              ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        _SectionTitle(title: 'Stato e scadenza'),
                        DropdownButtonFormField<DestinationStatus>(
                          initialValue: _status,
                          items: DestinationStatus.values
                              .map(
                                (status) => DropdownMenuItem<DestinationStatus>(
                                  value: status,
                                  child: Text(status.label),
                                ),
                              )
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
                        _DueDateField(
                          dueDate: _dueDate,
                          onPickDate: _pickDueDate,
                          onClearDate: _dueDate == null
                              ? null
                              : () {
                                  setState(() {
                                    _dueDate = null;
                                  });
                                },
                        ),
                        const SizedBox(height: 16),
                        _SectionTitle(title: 'Allegati'),
                        _AttachmentSection(
                          attachmentPaths: _attachmentPaths,
                          isBusy: _isCapturingPhoto || _isPickingFromGallery,
                          onCapture: _capturePhoto,
                          onPickFromGallery: _pickFromGallery,
                          onPickMultipleFromGallery: _pickMultipleFromGallery,
                          onRemove: _removeAttachment,
                        ),
                        const SizedBox(height: 16),
                        _SectionTitle(title: 'Checklist'),
                        ..._buildChecklistWidgets(),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton.icon(
                            onPressed: _addChecklistItem,
                            icon: const Icon(Icons.add_task_outlined),
                            label: const Text('Aggiungi voce checklist'),
                          ),
                        ),
                        const SizedBox(height: 16),
                        _SectionTitle(title: 'Campi personalizzati'),
                        ..._buildCustomFieldWidgets(),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton.icon(
                            onPressed: _addCustomField,
                            icon: const Icon(Icons.add_circle_outline),
                            label: const Text('Aggiungi campo personalizzato'),
                          ),
                        ),
                        const SizedBox(height: 16),
                        _SectionTitle(title: 'Note'),
                        TextFormField(
                          controller: _notesController,
                          decoration: const InputDecoration(labelText: 'Note'),
                          maxLines: 4,
                          minLines: 3,
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

  List<Widget> _buildChecklistWidgets() {
    if (_checklistDrafts.isEmpty) {
      return <Widget>[
        Text(
          'Nessuna voce checklist. Puoi aggiungerne quante vuoi.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 8),
      ];
    }

    return _checklistDrafts
        .asMap()
        .entries
        .map((entry) {
          final draft = entry.value;
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: <Widget>[
                Checkbox(
                  value: draft.isDone,
                  onChanged: (value) {
                    setState(() {
                      draft.isDone = value ?? false;
                    });
                  },
                ),
                Expanded(
                  child: TextFormField(
                    controller: draft.controller,
                    decoration: InputDecoration(
                      labelText: 'Voce ${entry.key + 1}',
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => _removeChecklistItem(entry.key),
                  icon: const Icon(Icons.delete_outline),
                ),
              ],
            ),
          );
        })
        .toList(growable: false);
  }

  List<Widget> _buildCustomFieldWidgets() {
    if (_customFieldDrafts.isEmpty) {
      return <Widget>[
        Text(
          'I campi custom compaiono anche in tabella, export e dettaglio.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 8),
      ];
    }

    return _customFieldDrafts
        .asMap()
        .entries
        .map((entry) {
          final draft = entry.value;
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: TextFormField(
                    controller: draft.keyController,
                    decoration: InputDecoration(
                      labelText: 'Campo ${entry.key + 1}',
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextFormField(
                    controller: draft.valueController,
                    decoration: const InputDecoration(labelText: 'Valore'),
                  ),
                ),
                IconButton(
                  onPressed: () => _removeCustomField(entry.key),
                  icon: const Icon(Icons.delete_outline),
                ),
              ],
            ),
          );
        })
        .toList(growable: false);
  }

  Future<void> _capturePhoto() async {
    await _runAttachmentAction(() async {
      final capturedPhotoPath = await _photoService.capturePhoto();
      if (!mounted || capturedPhotoPath == null) {
        return;
      }

      setState(() {
        _attachmentPaths = <String>[..._attachmentPaths, capturedPhotoPath];
      });
    }, isCamera: true);
  }

  Future<void> _pickFromGallery() async {
    await _runAttachmentAction(() async {
      final selectedPhotoPath = await _photoService.pickPhotoFromGallery();
      if (!mounted || selectedPhotoPath == null) {
        return;
      }

      setState(() {
        _attachmentPaths = <String>[..._attachmentPaths, selectedPhotoPath];
      });
    });
  }

  Future<void> _pickMultipleFromGallery() async {
    await _runAttachmentAction(() async {
      final selectedPhotoPaths = await _photoService.pickMultiplePhotosFromGallery();
      if (!mounted || selectedPhotoPaths.isEmpty) {
        return;
      }

      setState(() {
        _attachmentPaths = <String>[..._attachmentPaths, ...selectedPhotoPaths];
      });
    });
  }

  Future<void> _runAttachmentAction(
    Future<void> Function() action, {
    bool isCamera = false,
  }) async {
    FocusScope.of(context).unfocus();
    setState(() {
      if (isCamera) {
        _isCapturingPhoto = true;
      } else {
        _isPickingFromGallery = true;
      }
    });

    try {
      await action();
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gestione allegati non riuscita: $error')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isCapturingPhoto = false;
          _isPickingFromGallery = false;
        });
      }
    }
  }

  Future<void> _removeAttachment(String attachmentPath) async {
    final initialAttachments =
        widget.initialDestination?.attachmentPaths ?? const <String>[];
    if (!initialAttachments.contains(attachmentPath)) {
      await _photoService.deletePhoto(attachmentPath);
    }

    if (!mounted) {
      return;
    }

    setState(() {
      _attachmentPaths = _attachmentPaths
          .where((path) => path != attachmentPath)
          .toList(growable: false);
    });
  }

  Future<void> _pickDueDate() async {
    final now = DateTime.now();
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: _dueDate ?? now,
      firstDate: DateTime(now.year - 2),
      lastDate: DateTime(now.year + 10),
    );

    if (pickedDate == null) {
      return;
    }

    setState(() {
      _dueDate = DateTime(pickedDate.year, pickedDate.month, pickedDate.day);
    });
  }

  void _addChecklistItem() {
    setState(() {
      _checklistDrafts.add(_ChecklistDraft(label: '', isDone: false));
    });
  }

  void _removeChecklistItem(int index) {
    final removed = _checklistDrafts.removeAt(index);
    removed.dispose();
    setState(() {});
  }

  void _addCustomField() {
    setState(() {
      _customFieldDrafts.add(_CustomFieldDraft(key: '', value: ''));
    });
  }

  void _removeCustomField(int index) {
    final removed = _customFieldDrafts.removeAt(index);
    removed.dispose();
    setState(() {});
  }

  Future<void> _searchAddressCandidates() async {
    FocusScope.of(context).unfocus();
    final address = _buildAddressForSearch();
    if (address.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Inserisci almeno indirizzo o città prima di cercare.'),
        ),
      );
      return;
    }

    setState(() {
      _isSearchingAddress = true;
    });

    try {
      final candidates = await context
          .read<DestinationController>()
          .searchGeocodingCandidates(address);
      if (!mounted) {
        return;
      }

      if (candidates.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Nessun candidato trovato per questo indirizzo.'),
          ),
        );
        return;
      }

      final selected = await showModalBottomSheet<GeocodingCandidate>(
        context: context,
        showDragHandle: true,
        builder: (context) {
          return SafeArea(
            child: ListView.separated(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              itemBuilder: (_, index) {
                final candidate = candidates[index];
                return ListTile(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  title: Text(candidate.label),
                  subtitle: Text(
                    '${candidate.latitude.toStringAsFixed(5)}, ${candidate.longitude.toStringAsFixed(5)}',
                  ),
                  onTap: () => Navigator.of(context).pop(candidate),
                );
              },
              separatorBuilder: (_, _) => const SizedBox(height: 6),
              itemCount: candidates.length,
            ),
          );
        },
      );

      if (selected == null || !mounted) {
        return;
      }

      setState(() {
        _latitudeController.text = selected.latitude.toStringAsFixed(6);
        _longitudeController.text = selected.longitude.toStringAsFixed(6);
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ricerca indirizzo non riuscita: $error')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSearchingAddress = false;
        });
      }
    }
  }

  String _buildAddressForSearch() {
    return <String>[
      _addressController.text.trim(),
      _postalCodeController.text.trim(),
      _cityController.text.trim(),
    ].where((value) => value.isNotEmpty).join(', ');
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) {
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
        attachmentPaths: _attachmentPaths,
        latitude: _parseCoordinate(_latitudeController.text),
        longitude: _parseCoordinate(_longitudeController.text),
        status: _status,
        category: _categoryController.text.trim(),
        tags: _parseTags(_tagsController.text),
        dueDate: _dueDate,
        checklistItems: _checklistDrafts
            .map((draft) => draft.toItem())
            .where((item) => item.label.isNotEmpty)
            .toList(growable: false),
        customFields: Map<String, String>.fromEntries(
          _customFieldDrafts
              .map((draft) => draft.toEntry())
              .where((entry) => entry != null)
              .whereType<MapEntry<String, String>>(),
        ),
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

  List<String> _parseTags(String rawValue) {
    return rawValue
        .split(RegExp(r'[;,|]'))
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toSet()
        .toList(growable: false);
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(
        title,
        style: Theme.of(
          context,
        ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _DueDateField extends StatelessWidget {
  const _DueDateField({
    required this.dueDate,
    required this.onPickDate,
    this.onClearDate,
  });

  final DateTime? dueDate;
  final Future<void> Function() onPickDate;
  final VoidCallback? onClearDate;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onPickDate,
      child: InputDecorator(
        decoration: const InputDecoration(labelText: 'Scadenza'),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Text(
                dueDate == null
                    ? 'Nessuna scadenza'
                    : '${dueDate!.day.toString().padLeft(2, '0')}/${dueDate!.month.toString().padLeft(2, '0')}/${dueDate!.year}',
              ),
            ),
            if (dueDate != null && onClearDate != null)
              IconButton(
                onPressed: onClearDate,
                icon: const Icon(Icons.clear_outlined),
              ),
            const Icon(Icons.calendar_today_outlined, size: 18),
          ],
        ),
      ),
    );
  }
}

class _AttachmentSection extends StatelessWidget {
  const _AttachmentSection({
    required this.attachmentPaths,
    required this.isBusy,
    required this.onCapture,
    required this.onPickFromGallery,
    required this.onPickMultipleFromGallery,
    required this.onRemove,
  });

  final List<String> attachmentPaths;
  final bool isBusy;
  final Future<void> Function() onCapture;
  final Future<void> Function() onPickFromGallery;
  final Future<void> Function() onPickMultipleFromGallery;
  final Future<void> Function(String attachmentPath) onRemove;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (attachmentPaths.isNotEmpty)
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: attachmentPaths
                .map(
                  (path) => Stack(
                    children: <Widget>[
                      ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: Image.file(
                          File(path),
                          width: 92,
                          height: 92,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(
                            width: 92,
                            height: 92,
                            color: Theme.of(context)
                                .colorScheme
                                .surfaceContainerHighest,
                            alignment: Alignment.center,
                            child: const Icon(Icons.broken_image_outlined),
                          ),
                        ),
                      ),
                      Positioned(
                        top: 4,
                        right: 4,
                        child: InkWell(
                          onTap: () => onRemove(path),
                          child: Container(
                            decoration: const BoxDecoration(
                              color: Colors.black54,
                              shape: BoxShape.circle,
                            ),
                            padding: const EdgeInsets.all(4),
                            child: const Icon(
                              Icons.close,
                              size: 14,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                )
                .toList(growable: false),
          )
        else
          Text(
            'Nessun allegato aggiunto.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: <Widget>[
            FilledButton.tonalIcon(
              onPressed: isBusy ? null : onCapture,
              icon: const Icon(Icons.photo_camera_outlined),
              label: const Text('Scatta foto'),
            ),
            OutlinedButton.icon(
              onPressed: isBusy ? null : onPickFromGallery,
              icon: const Icon(Icons.photo_library_outlined),
              label: const Text('Galleria'),
            ),
            OutlinedButton.icon(
              onPressed: isBusy ? null : onPickMultipleFromGallery,
              icon: const Icon(Icons.collections_outlined),
              label: const Text('Più immagini'),
            ),
          ],
        ),
      ],
    );
  }
}

class _ChecklistDraft {
  _ChecklistDraft({required String label, required this.isDone})
    : controller = TextEditingController(text: label);

  factory _ChecklistDraft.fromItem(ChecklistItem item) {
    return _ChecklistDraft(label: item.label, isDone: item.isDone);
  }

  final TextEditingController controller;
  bool isDone;

  ChecklistItem toItem() {
    return ChecklistItem(label: controller.text.trim(), isDone: isDone);
  }

  void dispose() {
    controller.dispose();
  }
}

class _CustomFieldDraft {
  _CustomFieldDraft({required String key, required String value})
    : keyController = TextEditingController(text: key),
      valueController = TextEditingController(text: value);

  final TextEditingController keyController;
  final TextEditingController valueController;

  MapEntry<String, String>? toEntry() {
    final key = keyController.text.trim();
    final value = valueController.text.trim();
    if (key.isEmpty || value.isEmpty) {
      return null;
    }
    return MapEntry<String, String>(key, value);
  }

  void dispose() {
    keyController.dispose();
    valueController.dispose();
  }
}
