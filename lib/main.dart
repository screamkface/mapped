import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'controllers/destination_controller.dart';
import 'screens/app_shell.dart';
import 'services/destination_storage_service.dart';
import 'services/destination_photo_service.dart';
import 'services/drive_sync_service.dart';
import 'services/geocoding_service.dart';
import 'services/import_service.dart';
import 'services/navigation_service.dart';
import 'services/platform_config_service.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final preferences = await SharedPreferences.getInstance();
  final controller = DestinationController(
    storageService: DestinationStorageService(preferences),
    photoService: DestinationPhotoService(),
    driveSyncService: DriveSyncService(
      preferences,
      platformConfigService: PlatformConfigService(),
    ),
    importService: ImportService(),
    navigationService: NavigationService(),
    geocodingService: GeocodingService(preferences),
  );
  await controller.initialize();

  runApp(MyApp(controller: controller));
}

class MyApp extends StatelessWidget {
  const MyApp({super.key, required this.controller});

  final DestinationController controller;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<DestinationController>.value(
      value: controller,
      child: MaterialApp(
        title: 'Mapped',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        home: const AppShell(),
      ),
    );
  }
}
