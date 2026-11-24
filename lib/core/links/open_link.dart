/// Opens a web link from a message in the browser.
library;

import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

/// Opens [uri] in the default browser (or the app that handles it).
/// Returns false if nothing could open it.
typedef LinkOpener = Future<bool> Function(Uri uri);

Future<bool> _launch(Uri uri) async {
  if (uri.scheme != 'https' && uri.scheme != 'http') return false;
  try {
    return await launchUrl(uri, mode: LaunchMode.externalApplication);
  } on Object {
    return false;
  }
}

/// How links are opened; tests replace it to see what was opened.
@visibleForTesting
LinkOpener linkOpener = _launch;

/// Opens [uri] in the browser.
Future<bool> openLink(Uri uri) => linkOpener(uri);
