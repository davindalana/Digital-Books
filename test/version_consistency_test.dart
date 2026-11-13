import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:digital_books/core/constants/app_info.dart';

void main() {
  group('Version Consistency Regression Guard', () {
    late String pubspecVersion;

    setUpAll(() {
      final pubspecFile = File('pubspec.yaml');
      expect(
        pubspecFile.existsSync(),
        isTrue,
        reason: 'pubspec.yaml must exist at repository root',
      );

      final pubspecLines = pubspecFile.readAsLinesSync();
      final versionLine = pubspecLines.firstWhere(
        (line) => line.trim().startsWith('version:'),
        orElse: () => '',
      );

      expect(
        versionLine,
        isNotEmpty,
        reason: 'version field must be declared in pubspec.yaml',
      );

      pubspecVersion = versionLine.split(':').last.trim();
    });

    test('AppInfo.technicalVersion matches pubspec.yaml version exactly', () {
      expect(
        AppInfo.technicalVersion,
        equals(pubspecVersion),
        reason:
            'AppInfo.technicalVersion must be identical to pubspec.yaml version ($pubspecVersion). '
            'If you bumped the version in pubspec.yaml, update AppInfo.technicalVersion accordingly.',
      );
    });

    test('AppInfo.displayVersion adheres to human-readable format', () {
      // pubspec format: 1.1.0-alpha.8+9 -> display format: 1.1.0-alpha.8 (build 9)
      final parts = pubspecVersion.split('+');
      final semver = parts.first;
      final buildNumber = parts.length > 1 ? parts[1] : null;

      final expectedDisplay = buildNumber != null
          ? '$semver (build $buildNumber)'
          : semver;

      expect(
        AppInfo.displayVersion,
        equals(expectedDisplay),
        reason:
            'AppInfo.displayVersion must match "$expectedDisplay". '
            'If pubspec.yaml version was changed, update AppInfo.displayVersion.',
      );
    });

    test('README.md header title matches pubspec.yaml version', () {
      final readmeFile = File('README.md');
      expect(readmeFile.existsSync(), isTrue);

      final firstLine = readmeFile.readAsLinesSync().first;
      expect(
        firstLine,
        contains('Version ${AppInfo.technicalVersion}'),
        reason:
            'README.md title header must declare "Version ${AppInfo.technicalVersion}". '
            'Currently: "$firstLine"',
      );
    });

    test(
      'docs/BACKUP_AND_RESTORE.md header title matches AppInfo.displayVersion',
      () {
        final docFile = File('docs/BACKUP_AND_RESTORE.md');
        expect(docFile.existsSync(), isTrue);

        final firstLine = docFile.readAsLinesSync().first;
        expect(
          firstLine,
          contains('Digital Books v${AppInfo.displayVersion}'),
          reason:
              'docs/BACKUP_AND_RESTORE.md header must declare "Digital Books v${AppInfo.displayVersion}". '
              'Currently: "$firstLine"',
        );
      },
    );
  });
}
