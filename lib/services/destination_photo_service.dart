import 'dart:io';

import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

class DestinationPhotoService {
  DestinationPhotoService({ImagePicker? imagePicker})
    : _imagePicker = imagePicker ?? ImagePicker();

  final ImagePicker _imagePicker;

  Future<String?> capturePhoto() async {
    final captured = await _imagePicker.pickImage(
      source: ImageSource.camera,
      imageQuality: 88,
      maxWidth: 1800,
    );

    if (captured == null) {
      return null;
    }

    return _persistImage(File(captured.path));
  }

  Future<String?> pickPhotoFromGallery() async {
    final selected = await _imagePicker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 88,
      maxWidth: 1800,
    );

    if (selected == null) {
      return null;
    }

    return _persistImage(File(selected.path));
  }

  Future<List<String>> pickMultiplePhotosFromGallery() async {
    final selected = await _imagePicker.pickMultiImage(
      imageQuality: 88,
      maxWidth: 1800,
    );

    final paths = <String>[];
    for (final image in selected) {
      paths.add(await _persistImage(File(image.path)));
    }
    return paths;
  }

  Future<void> deletePhoto(String? photoPath) async {
    if (photoPath == null || photoPath.trim().isEmpty) {
      return;
    }

    final file = File(photoPath);
    if (await file.exists()) {
      await file.delete();
    }
  }

  Future<void> deletePhotos(List<String> photoPaths) async {
    for (final photoPath in photoPaths) {
      await deletePhoto(photoPath);
    }
  }

  Future<String> _persistImage(File sourceFile) async {
    final documentsDirectory = await getApplicationDocumentsDirectory();
    final photosDirectory = Directory(
      '${documentsDirectory.path}/destination_photos',
    );

    if (!await photosDirectory.exists()) {
      await photosDirectory.create(recursive: true);
    }

    final extension = _extractExtension(sourceFile.path);
    final timestamp = DateTime.now().microsecondsSinceEpoch;
    final destinationFile = File(
      '${photosDirectory.path}/photo_$timestamp$extension',
    );

    await sourceFile.copy(destinationFile.path);
    return destinationFile.path;
  }

  String _extractExtension(String path) {
    final lastDot = path.lastIndexOf('.');
    if (lastDot == -1 || lastDot == path.length - 1) {
      return '.jpg';
    }
    return path.substring(lastDot);
  }
}
