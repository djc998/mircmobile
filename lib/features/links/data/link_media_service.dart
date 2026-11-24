/// Downloads the images people link to in chat, for the preview under the
/// message.
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

/// Why a linked image couldn't be shown, in words for the chat.
class LinkMediaException implements Exception {
  const LinkMediaException(this.message);

  final String message;

  @override
  String toString() => message;
}

class LinkMediaService {
  LinkMediaService({http.Client? client}) : _http = client ?? http.Client();

  /// Bigger images aren't downloaded.
  static const int maxBytes = 15 * 1024 * 1024;

  /// How many images are kept so scrolling back doesn't load them again.
  static const _cacheSize = 30;

  final http.Client _http;
  final Map<Uri, Uint8List> _cache = {};
  final Map<Uri, Future<Uint8List>> _loading = {};

  /// The image at [uri] if it was loaded already.
  Uint8List? cached(Uri uri) => _cache[uri];

  /// Downloads the image at [uri]. Only https links, only real images (by
  /// the type the server says), and at most [maxBytes].
  Future<Uint8List> fetchImage(Uri uri) {
    final done = _cache[uri];
    if (done != null) return Future.value(done);
    return _loading[uri] ??= _fetchOnce(uri);
  }

  Future<Uint8List> _fetchOnce(Uri uri) async {
    try {
      return await _fetch(uri);
    } finally {
      unawaited(_loading.remove(uri));
    }
  }

  Future<Uint8List> _fetch(Uri uri) async {
    if (uri.scheme != 'https') {
      throw const LinkMediaException('Only secure (https) links are shown.');
    }
    final http.StreamedResponse response;
    try {
      final request = http.Request('GET', uri)
        ..headers['Accept'] = 'image/*'
        ..maxRedirects = 5;
      response = await _http.send(request).timeout(const Duration(seconds: 20));
    } on TimeoutException {
      throw const LinkMediaException('The image took too long to load.');
    } on Object {
      throw const LinkMediaException("Couldn't reach the website.");
    }
    if (response.statusCode != 200) {
      unawaited(response.stream.drain<void>().catchError((_) {}));
      throw LinkMediaException(
        "Couldn't load the image (error ${response.statusCode}).",
      );
    }
    final type = response.headers['content-type']?.toLowerCase() ?? '';
    if (!type.startsWith('image/')) {
      unawaited(response.stream.drain<void>().catchError((_) {}));
      throw const LinkMediaException("That link isn't an image.");
    }
    final length = response.contentLength;
    if (length != null && length > maxBytes) {
      unawaited(response.stream.drain<void>().catchError((_) {}));
      throw const LinkMediaException('The image is too big to preview.');
    }
    final bytes = BytesBuilder(copy: false);
    try {
      await for (final chunk in response.stream.timeout(
        const Duration(seconds: 20),
      )) {
        bytes.add(chunk);
        if (bytes.length > maxBytes) {
          throw const LinkMediaException('The image is too big to preview.');
        }
      }
    } on LinkMediaException {
      rethrow;
    } on Object {
      throw const LinkMediaException('The image stopped loading.');
    }
    final image = bytes.takeBytes();
    _cache[uri] = image;
    while (_cache.length > _cacheSize) {
      _cache.remove(_cache.keys.first);
    }
    return image;
  }
}

final linkMediaServiceProvider = Provider<LinkMediaService>(
  (ref) => LinkMediaService(),
);
