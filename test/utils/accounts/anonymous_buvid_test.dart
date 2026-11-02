import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:PiliPlus/http/init.dart';
import 'package:PiliPlus/models/common/account_type.dart';
import 'package:PiliPlus/utils/accounts.dart';
import 'package:PiliPlus/utils/accounts/account.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';

/// Answers /x/frontend/finger/spi with `b3-n`, n counting the requests.
class _SpiAdapter implements HttpClientAdapter {
  int requests = 0;

  /// Holds the answers back until it completes.
  Completer<void>? hold;

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
    final n = requests;
    await hold?.future;
    return ResponseBody.fromString(
      jsonEncode({
        'code': 0,
        'data': {'b_3': 'b3-$n', 'b_4': 'b4-$n'},
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
  // What each sync to the web views had: the account and its buvid3.
  final synced = <(Account, String?)>[];

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('piliplus-anonymous-test-');
    Hive.init(tempDir.path);
    GStorage.regAdapter();
    GStorage.setting = await Hive.openBox('setting');
    GStorage.localCache = await Hive.openBox('localCache');
    Request();
    Request.dio.httpClientAdapter = adapter;
    AnonymousAccount.syncWebCookie = (account) => synced.add((
      account,
      _cookie(account.cookieJar, 'buvid3'),
    ));
  });

  setUp(() {
    synced.clear();
    adapter.hold = null;
  });

  void logIn() {
    final main = Accounts.accountMode[AccountType.main.index];
    Accounts.accountMode[AccountType.main.index] = LoginAccount(
      BiliCookieJar.fromJson({'DedeUserID': '123', 'bili_jct': 'csrf'}),
      null,
      null,
    );
    addTearDown(() => Accounts.accountMode[AccountType.main.index] = main);
  }

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
    await pumpEventQueue();

    expect(adapter.requests, 2);
    expect(_cookie(account.cookieJar, 'buvid3'), 'b3-2');
    expect(_cookie(account.cookieJar, 'buvid4'), 'b4-2');
  });

  test('fetched, the anonymous cookies reach the web views while no one is '
      'logged in, and only then', () async {
    final account = AnonymousAccount();
    await account.delete();
    await pumpEventQueue();
    expect(Accounts.main, same(account));
    expect(synced, hasLength(1));
    expect(synced.single.$1, same(account));
    expect(synced.single.$2, startsWith('b3-'));

    logIn();
    synced.clear();
    await account.delete();
    await pumpEventQueue();
    expect(synced, isEmpty);
  });

  test(
    'a login waits on clearing the anonymous cookies, not on the server',
    () async {
      final account = AnonymousAccount();
      await pumpEventQueue();
      final requests = adapter.requests;
      adapter.hold = Completer();
      var cleared = false;
      account.delete().then((_) => cleared = true);
      await pumpEventQueue();

      // Cleared while the server is yet to answer, with a buvid3 meanwhile.
      expect(cleared, isTrue);
      expect(adapter.requests, requests + 1);
      expect(_cookie(account.cookieJar, 'buvid3'), isNotNull);

      adapter.hold!.complete();
      await pumpEventQueue();
      expect(_cookie(account.cookieJar, 'buvid3'), 'b3-${requests + 1}');
    },
  );
}
