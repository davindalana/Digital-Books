/// Central application information and versioning metadata.
///
/// Single source of truth for in-app version presentation, aligned directly
/// with `pubspec.yaml`.
class AppInfo {
  const AppInfo._();

  /// Human-readable display version shown in the user interface (e.g. About, Settings).
  static const String displayVersion = '1.1.0-alpha.8 (build 9)';

  /// Technical version string matching `version` in `pubspec.yaml`.
  static const String technicalVersion = '1.1.0-alpha.8+9';

  /// Application name.
  static const String appName = 'Digital Books';
}

