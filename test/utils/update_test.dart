import 'dart:convert';

import 'package:PiliPlus/http/loading_state.dart';
import 'package:PiliPlus/http/update.dart';
import 'package:PiliPlus/models_new/update/manifest.dart';
import 'package:PiliPlus/utils/update.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

String _sha(List<int> bytes) => sha256.convert(bytes).toString();

Map<String, Object?> _asset(String name, {String? abi, String? format}) => {
  'name': name,
  'size': 3,
  'sha256': _sha([1, 2, 3]),
  'abi': ?abi,
  'format': ?format,
};

UpdateManifest _manifest(List<Map<String, Object?>> assets) =>
    UpdateManifest.fromJson({
      'tag': '2.2.0+6120',
      'versionCode': 6120,
      'body': 'note',
      'assets': assets,
    });

void main() {
  group('UpdateManifest.fromJson', () {
    test('reads what release_manifest.ps1 writes', () {
      final m = UpdateManifest.fromJson(
        jsonDecode('''{
          "tag": "2.2.0+6120",
          "versionCode": 6120,
          "body": "## 更新\\n- 修复",
          "assets": [{
            "name": "PiliPlus_android_2.2.0-abc+6120_arm64-v8a.apk",
            "size": 1000,
            "sha256": "32F4694AEF7404B673E57CC38F41C11B532ACE2DDDD87ACE2FDB8A35A61D10FE",
            "abi": "arm64-v8a"
          }]
        }'''),
      );
      expect(m.tag, '2.2.0+6120');
      expect(m.versionCode, 6120);
      expect(m.body, '## 更新\n- 修复');
      final a = m.assets.single;
      expect(a.size, 1000);
      expect(a.abi, 'arm64-v8a');
      expect(a.format, isNull);
      // stored lower case, as the downloader compares it
      expect(
        a.sha256,
        '32f4694aef7404b673e57cc38f41c11b532ace2dddd87ace2fdb8a35a61d10fe',
      );
    });

    test('rejects a manifest missing what the app relies on', () {
      final good = {
        'tag': '2.2.0+6120',
        'versionCode': 6120,
        'assets': [_asset('a.apk', abi: 'x86_64')],
      };
      expect(UpdateManifest.fromJson(good).body, '');
      for (final bad in [
        null,
        'text',
        {...good, 'tag': ''},
        {...good, 'versionCode': '6120'},
        {...good, 'assets': null},
        {
          ...good,
          'assets': [
            {..._asset('a.apk'), 'sha256': 'abc'},
          ],
        },
        {
          ...good,
          'assets': [
            {..._asset('a.apk'), 'size': 0},
          ],
        },
        {
          ...good,
          'assets': [_asset('../a.apk')],
        },
      ]) {
        expect(
          () => UpdateManifest.fromJson(bad),
          throwsFormatException,
          reason: '$bad',
        );
      }
    });
  });

  group('UpdateHttp.parseResponse', () {
    String message(LoadingState res) => (res as Error).errMsg!;

    test('parses the manifest', () {
      final res = UpdateHttp.parseResponse(
        200,
        jsonEncode({'tag': 't', 'versionCode': 1, 'assets': []}),
      );
      expect(res.data.tag, 't');
    });

    test('says what failed', () {
      expect(
        UpdateHttp.parseResponse(404, null),
        const Error('新版本的安装包还在上传，请稍后再试', code: 404),
      );
      expect(message(UpdateHttp.parseResponse(403, null)), contains('访问频率'));
      expect(message(UpdateHttp.parseResponse(429, null)), contains('访问频率'));
      expect(
        message(UpdateHttp.parseResponse(-1, {'message': '连接错误，请检查网络设置'})),
        '检查更新失败，无法连接 GitHub：连接错误，请检查网络设置',
      );
      expect(
        message(UpdateHttp.parseResponse(502, null)),
        contains('HTTP 502'),
      );
      expect(
        message(UpdateHttp.parseResponse(200, '<html>')),
        contains('格式有误'),
      );
      expect(
        message(UpdateHttp.parseResponse(200, '{"tag": "t"}')),
        contains('格式有误'),
      );
    });
  });

  test('Update.hasUpdate compares the build number', () {
    final m = _manifest([]);
    expect(Update.hasUpdate(m, versionCode: 6119), isTrue);
    expect(Update.hasUpdate(m, versionCode: 6120), isFalse);
    expect(Update.hasUpdate(m, versionCode: 6121), isFalse);
  });

  group('Update.formatButtons', () {
    List<String> labels(UpdateManifest m, String os) => [
      for (final w in Update.formatButtons(
        m,
        (text, {ext}) => Text(text),
        os: os,
      ))
        (w as Text).data!,
    ];

    test('offers only the formats in the manifest', () {
      expect(
        labels(
          _manifest([_asset('w.zip', format: 'zip')]),
          'windows',
        ),
        ['zip'],
      );
      expect(
        labels(
          _manifest([
            _asset('l.AppImage', format: 'AppImage'),
            _asset('l.tar.gz', format: 'tar.gz'),
          ]),
          'linux',
        ),
        ['targz', 'AppImage'],
      );
    });

    test('offers Github when no format matches', () {
      expect(labels(_manifest([]), 'linux'), ['Github']);
      expect(labels(_manifest([_asset('m.dmg', format: 'dmg')]), 'macos'), [
        'Github',
      ]);
    });
  });

  group('Update.pickApk', () {
    final assets = _manifest([
      _asset('p_arm64-v8a.apk', abi: 'arm64-v8a'),
      _asset('p_armeabi-v7a.apk', abi: 'armeabi-v7a'),
      _asset('p_x86_64.apk', abi: 'x86_64'),
    ]).assets;
    String? pick(List<String> abis) => Update.pickApk(assets, abis)?.abi;

    test("follows the device's ABI order", () {
      expect(pick(['arm64-v8a', 'armeabi-v7a', 'armeabi']), 'arm64-v8a');
      expect(pick(['armeabi-v7a', 'armeabi']), 'armeabi-v7a');
      // an x86_64 emulator that also translates arm
      expect(pick(['x86_64', 'x86', 'arm64-v8a']), 'x86_64');
    });

    test('finds nothing for an ABI without a package', () {
      expect(pick(['x86']), isNull);
      expect(pick([]), isNull);
    });
  });

  test('UpdateHttp.assetUrl points at the release of the manifest', () {
    final m = _manifest([_asset('PiliPlus_android_2.2.0-abc+6120_x86_64.apk')]);
    expect(
      UpdateHttp.assetUrl(m, m.assets.single),
      'https://github.com/PYH0809/PiliPlus/releases/download/2.2.0%2B6120/'
      'PiliPlus_android_2.2.0-abc%2B6120_x86_64.apk',
    );
  });
}
