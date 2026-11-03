import 'dart:async';

import 'package:PiliPlus/utils/accounts/account.dart';

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  // Without the network in tests, the anonymous account falls back to a
  // buvid of its own and activates it, a request whose failure shows a toast
  // with no SmartDialog to show it. Tests of the account turn it back on.
  AnonymousAccount.activateBuvid = (_) async {};
  // No web views either.
  AnonymousAccount.syncWebCookie = (_) {};
  await testMain();
}
