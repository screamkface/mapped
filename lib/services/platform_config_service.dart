import 'package:flutter/services.dart';

class PlatformConfigService {
  static const MethodChannel _channel = MethodChannel(
    'mapped_app/platform_config',
  );

  Future<String> getGoogleDriveServerClientId() async {
    try {
      final value = await _channel.invokeMethod<String>(
        'getGoogleDriveServerClientId',
      );
      return value?.trim() ?? '';
    } on MissingPluginException {
      return '';
    } on PlatformException {
      return '';
    }
  }
}
