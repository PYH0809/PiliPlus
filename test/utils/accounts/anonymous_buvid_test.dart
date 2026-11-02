import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:PiliPlus/http/init.dart';
import 'package:PiliPlus/utils/accounts/account.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';

/// Answers /x/frontend/finger/spi with b_3-<n>, n counting the requests.
class _SpiAdapter implements HttpClientAdapter {
  int requests = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (options.path != '/x/frontend/finger/spi') {
      return ResponseBody.fromString('', 404);
    }
    requests++;
    return ResponseBody.fromString(
      jsonEncode({
        'code': 0,
        'data': {'b_3': 'b3-$requests', 'b_4': 'b4-$requests'},
      }),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

String? _cookie(DefaultCookieJar jar, String name) =>
    jar.domainCookies['bilibili.com']?['/']?[name]?.cookie.value;

void main() {
  late Directory tempDir;
  final adapter = _SpiAdapter();

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('piliplus-anonymous-test-');
    Hive.init(tempDir.path);
    GStorage.regAdapter();
    GStorage.setting = await Hive.openBox('setting');
    GStorage.localCache = await Hive.openBox('localCache');
    Request();
    Request.dio.httpClientAdapter = adapter;
  });

  tearDownAll(() async {
    await Hive.close();
    await tempDir.delete(recursive: true);
  });

  test('cleared, as on a login, the anonymous cookies come from the server '
      'again', () async {
    final account = AnonymousAccount();
    await pumpEventQueue();
    expect(_cookie(account.cookieJar, 'buvid3'), 'b3-1');

    await account.delete();

    expect(adapter.requests, 2);
    expect(_cookie(account.cookieJar, 'buvid3'), 'b3-2');
    expect(_cookie(account.cookieJar, 'buvid4'), 'b4-2');
  });
}
