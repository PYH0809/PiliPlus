import 'package:PiliPlus/utils/update.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  group('Update.hasUpdate', () {
    test('compares the build number in this repository\'s tags', () {
      final data = {
        'tag_name': '2.2.0+6040',
        // A commit older than the installed build: the time alone says no.
        'created_at': '2026-11-01T00:00:00Z',
      };
      final installed =
          DateTime.utc(2026, 11, 3).millisecondsSinceEpoch ~/ 1000;
      expect(
        Update.hasUpdate(data, versionCode: 6039, buildTime: installed),
        isTrue,
      );
      expect(
        Update.hasUpdate(data, versionCode: 6040, buildTime: 0),
        isFalse,
      );
      expect(
        Update.hasUpdate(data, versionCode: 6041, buildTime: 0),
        isFalse,
      );
    });

    test('compares the time for other tags', () {
      final data = {
        'tag_name': '2.2.0.1',
        'created_at': '2026-11-02T12:10:49Z',
      };
      final created =
          DateTime.utc(2026, 11, 2, 12, 10, 49).millisecondsSinceEpoch ~/ 1000;
      expect(
        Update.hasUpdate(data, versionCode: 99999, buildTime: created - 1),
        isTrue,
      );
      expect(
        Update.hasUpdate(data, versionCode: 1, buildTime: created),
        isFalse,
      );
    });
  });

  group('Update.hasPackage', () {
    final data = {
      'assets': [
        {'name': 'PiliPlus_android_2.2.0-0123456789+6040_arm64-v8a.apk'},
        {'name': 'PiliPlus_linux_2.2.0+6040_amd64.deb'},
      ],
    };

    test('finds the package of a platform that has uploaded', () {
      expect(Update.hasPackage(data, 'android'), isTrue);
      expect(Update.hasPackage(data, 'linux'), isTrue);
    });

    test('says no while a platform has not uploaded yet', () {
      expect(Update.hasPackage(data, 'windows'), isFalse);
      expect(Update.hasPackage(data, 'macos'), isFalse);
      expect(Update.hasPackage(data, 'ios'), isFalse);
      expect(Update.hasPackage({'assets': []}, 'android'), isFalse);
    });

    test('matches the format when one is asked for', () {
      expect(Update.hasPackage(data, 'linux', ext: 'deb'), isTrue);
      expect(Update.hasPackage(data, 'linux', ext: 'rpm'), isFalse);
      expect(Update.hasPackage(data, 'linux', ext: 'tar.gz'), isFalse);
    });
  });

  group('Update.formatButtons', () {
    List<String> labels(Map data, String os) => [
      for (final w in Update.formatButtons(
        data,
        (text, {ext}) => Text(text),
        os: os,
      ))
        (w as Text).data!,
    ];
    Map withFiles(List<String> names) => {
      'assets': [
        for (final n in names) {'name': n},
      ],
    };

    test('offers only the formats that are uploaded', () {
      expect(
        labels(
          withFiles(['PiliPlus_windows_2.2.0+6040_x64_portable.zip']),
          'windows',
        ),
        ['zip'],
      );
      expect(
        labels(
          withFiles(['PiliPlus_linux_2.2.0+6040_amd64.AppImage']),
          'linux',
        ),
        ['AppImage'],
      );
    });

    test('offers the release page when no format matches', () {
      expect(labels(withFiles([]), 'linux'), ['Github']);
      expect(labels(withFiles([]), 'macos'), ['Github']);
    });
  });
}
