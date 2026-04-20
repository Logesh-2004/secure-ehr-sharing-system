
import 'package:flutter/services.dart';

class DocumentLauncherService {
  const DocumentLauncherService();

  static const MethodChannel _channel = MethodChannel(
    'secureehr/clinician_documents',
  );

  Future<void> openDocumentBytes({
    required Uint8List bytes,
    required String fileName,
  }) {
    return _channel.invokeMethod<void>('openDocumentBytes', {
      'bytes': bytes,
      'fileName': fileName,
    });
  }

  Future<void> openExternalUrl(String url) {
    return _channel.invokeMethod<void>('openExternalUrl', {'url': url});
  }
}
