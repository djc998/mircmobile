import 'dart:async';

import 'package:irc_client/features/safety/application/safety_controller.dart';

/// Runs before every test file: tests start with the terms agreed, so they
/// open on the welcome screen. `test/features/safety` covers the terms.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  debugTermsAgreedByDefault = true;
  await testMain();
}
