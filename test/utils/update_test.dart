import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:PiliPlus/http/loading_state.dart';
import 'package:PiliPlus/http/update.dart';
import 'package:PiliPlus/models_new/update/manifest.dart';
import 'package:PiliPlus/utils/update.dart';
import 'package:PiliPlus/utils/update_download.dart';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
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

  test('downloads go through gh-proxy, then ghfast, then GitHub', () {
    const url = 'https://github.com/PYH0809/PiliPlus/releases/download/t/a.apk';
    final sources = UpdateDownloader.sources(url);
    expect(sources, [
      'https://gh-proxy.com/$url',
      'https://ghfast.top/$url',
      url,
    ]);
    expect(sources.map(UpdateDownloader.sourceName), [
      'gh-proxy.com',
      'ghfast.top',
      'GitHub',
    ]);
  });

  group('UpdateDownloader.run', () {
    late Directory dir;
    final good = [1, 2, 3];
    final m = _manifest([_asset('p.apk', abi: 'arm64-v8a')]);

    setUp(() => dir = Directory.systemTemp.createTempSync('update_test'));
    tearDown(() => dir.deleteSync(recursive: true));

    UpdateDownloader downloader(
      FutureOr<List<int>> Function(String url, CancelToken token) serve,
    ) => UpdateDownloader(
      manifest: m,
      asset: m.assets.single,
      dir: dir.path,
      mirrors: const ['https://a/', 'https://b/', ''],
      fetch: (url, path, {required cancelToken, required onProgress}) async {
        final bytes = await serve(url, cancelToken);
        File(path).writeAsBytesSync(bytes);
        onProgress(bytes.length);
      },
    );

    test('falls back on an error and on a hash mismatch', () async {
      final tried = <String>[];
      final sources = <String>[];
      final file = await downloader((url, _) {
        tried.add(url);
        if (url.startsWith('https://a/')) {
          throw DioException.connectionTimeout(
            timeout: Duration.zero,
            requestOptions: RequestOptions(),
          );
        }
        // the mirror hands back something else
        if (url.startsWith('https://b/')) return [9, 9, 9];
        return good;
      }).run(onSource: sources.add);
      expect(tried, hasLength(3));
      expect(sources, ['a', 'b', 'GitHub']);
      expect(file!.path, '${dir.path}/p.apk');
      expect(file.readAsBytesSync(), good);
      // nothing left half-written
      expect(dir.listSync().map((i) => i.path), [file.path]);
    });

    test(
      'stops a source as soon as it sends more than the manifest says',
      () async {
        var sent = 0;
        final d = UpdateDownloader(
          manifest: m,
          asset: m.assets.single,
          dir: dir.path,
          mirrors: const [''],
          fetch: (url, path, {required cancelToken, required onProgress}) {
            // an endless body, a byte at a time, as dio reports it
            while (true) {
              onProgress(++sent);
              if (cancelToken.isCancelled) {
                throw DioException.requestCancelled(
                  requestOptions: RequestOptions(),
                  reason: null,
                );
              }
              if (sent > 1000) fail('the download was not stopped');
            }
          },
        );
        await expectLater(
          d.run(),
          throwsA(
            isA<UpdateDownloadException>().having(
              (e) => e.failures,
              'failures',
              ['GitHub：文件比清单里的大'],
            ),
          ),
        );
        // the manifest says 3 bytes
        expect(sent, 4);
      },
    );

    test('a restart writes its own temporary file', () async {
      // the first run is cancelled while it still holds its file, and a new
      // one starts at once: the old run's cleanup must not touch the new file
      final paths = <String>[];
      late UpdateDownloader first;
      UpdateDownloader start() => UpdateDownloader(
        manifest: m,
        asset: m.assets.single,
        dir: dir.path,
        mirrors: const [''],
        fetch: (url, path, {required cancelToken, required onProgress}) async {
          paths.add(path);
          File(path).writeAsBytesSync(good);
          if (paths.length == 1) {
            first.cancel();
            // the restart runs while the first still has its file
            expect(await start().run(), isNotNull);
          }
        },
      );
      first = start();
      expect(await first.run(), isNull);
      expect(paths, hasLength(2));
      expect(paths.first, isNot(paths.last));
      expect(File('${dir.path}/p.apk').readAsBytesSync(), good);
    });

    test('a run cancelled while checking the cache leaves it alone', () async {
      final cached = File('${dir.path}/p.apk')..writeAsBytesSync([7, 7, 7]);
      final d = downloader((url, _) => fail('should not download'));
      final run = d.run();
      d.cancel();
      expect(await run, isNull);
      expect(cached.readAsBytesSync(), [7, 7, 7]);
    });

    test('reports every source when all fail', () async {
      await expectLater(
        downloader((url, _) => [0]).run(),
        throwsA(
          isA<UpdateDownloadException>().having(
            (e) => e.failures,
            'failures',
            ['a：文件校验不通过', 'b：文件校验不通过', 'GitHub：文件校验不通过'],
          ),
        ),
      );
      expect(dir.listSync(), isEmpty);
    });

    test('reuses a verified package and drops older ones', () async {
      File('${dir.path}/p.apk').writeAsBytesSync(good);
      File('${dir.path}/old.apk').writeAsBytesSync(good);
      var fetched = 0;
      final file = await downloader((url, _) {
        fetched++;
        return good;
      }).run();
      expect(fetched, 0);
      expect(file!.readAsBytesSync(), good);

      // another download's recent temporary file stays, an old one goes
      final recent = File('${dir.path}/p.apk.1.part')..writeAsBytesSync(good);
      final old = File('${dir.path}/p.apk.0.part')
        ..writeAsBytesSync(good)
        ..setLastModifiedSync(DateTime.now().subtract(const Duration(days: 1)));
      File('${dir.path}/p.apk').writeAsBytesSync([7, 7, 7]);
      await downloader((url, _) => good).run();
      expect(recent.existsSync(), isTrue);
      expect(old.existsSync(), isFalse);
      recent.deleteSync();

      // a stale file of the same name is downloaded again, after it is
      // deleted to make room
      File('${dir.path}/p.apk').writeAsBytesSync([7, 7, 7]);
      await downloader((url, _) {
        fetched++;
        expect(File('${dir.path}/p.apk').existsSync(), isFalse);
        return good;
      }).run();
      expect(fetched, 1);
      expect(dir.listSync().map((i) => i.path), ['${dir.path}/p.apk']);
    });

    test('turns a cache error into a download error', () async {
      // the download directory is a file: nothing can be written under it
      final blocked = File('${dir.path}/blocked')..writeAsStringSync('');
      final d = UpdateDownloader(
        manifest: m,
        asset: m.assets.single,
        dir: '${blocked.path}/update',
        mirrors: const [''],
        fetch: (url, path, {required cancelToken, required onProgress}) async {
          File(path).writeAsBytesSync(good);
        },
      );
      await expectLater(
        d.run(),
        throwsA(
          isA<UpdateDownloadException>().having(
            (e) => e.failures.single,
            'failure',
            startsWith('缓存目录读写出错'),
          ),
        ),
      );

      // the cache cleared while downloading
      await expectLater(
        downloader((url, _) {
          dir.deleteSync(recursive: true);
          throw const FileSystemException('gone');
        }).run(),
        throwsA(isA<UpdateDownloadException>()),
      );
      dir.createSync();
    });

    Future<List<int>> hang(CancelToken token) async {
      await token.whenCancel;
      throw DioException.requestCancelled(
        requestOptions: RequestOptions(),
        reason: null,
      );
    }

    test('skip moves on to the next source', () async {
      final started = StreamController<String>();
      final d = downloader((url, token) {
        started.add(url);
        return url.startsWith('https://a/') ? hang(token) : good;
      });
      started.stream.first.then((_) => d.skip());
      final file = await d.run();
      expect(file!.readAsBytesSync(), good);
      await started.close();
    });

    test('skip during the hash check still moves on', () async {
      late UpdateDownloader d;
      final tried = <String>[];
      d = downloader((url, _) {
        tried.add(url);
        // the download is done; the skip lands while the file is checked
        if (url.startsWith('https://a/')) Future.microtask(d.skip);
        return good;
      });
      final file = await d.run();
      expect(tried, hasLength(2));
      expect(file!.readAsBytesSync(), good);
    });

    test('cancel stops without an error', () async {
      final tried = <String>[];
      late UpdateDownloader d;
      d = downloader((url, token) {
        tried.add(url);
        Future.microtask(d.cancel);
        return hang(token);
      });
      expect(await d.run(), isNull);
      expect(tried, hasLength(1));
      expect(dir.listSync(), isEmpty);
    });
  });
}
