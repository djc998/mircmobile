/// A folder for files on their way somewhere: downloads being saved, files
/// being sent directly.
library;

import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// `<app temporary folder>/<name>`, created if needed. Falls back to the
/// system's temporary folder where the app has none (tests).
Future<Directory> tempFolder(String name) async {
  Directory base;
  try {
    base = await getTemporaryDirectory();
  } on Object {
    base = Directory.systemTemp;
  }
  return await Directory('${base.path}/$name').create(recursive: true);
}
