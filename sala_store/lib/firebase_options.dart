// Company mobile source: Android/iOS initialize Firebase from native files.
// Both dev and prod native configurations are included; see the root README.
// This handoff does not support Web/Desktop or silently fall back to development.
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform => _nativeOnly();
  static FirebaseOptions get web => _nativeOnly();
  static FirebaseOptions get android => _nativeOnly();

  static FirebaseOptions _nativeOnly() => throw UnsupportedError(
    'This store handoff supports Android/iOS with native Firebase configuration. '
    'Use the documented platform build commands in README_COMPANY_AR.md.',
  );
}
