/// Uploads, downloads and reports shared pictures on the picture host
/// (`server/picture-host`, a Cloudflare Worker with R2 storage).
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:irc_client/features/pictures/data/picture_crypto.dart';
import 'package:irc_client/features/pictures/data/picture_prep.dart';
import 'package:irc_client/features/pictures/domain/picture_link.dart';

/// The picture host's address, e.g. `https://irc-pictures.example.workers.dev`.
/// Set at build time with `--dart-define=PICTURE_HOST=...`, otherwise
/// [defaultPictureHost] is used.
const pictureHostSetting = String.fromEnvironment('PICTURE_HOST');

/// Filled in once the Worker is deployed. Empty means picture sharing is
/// switched off and the app says so.
const defaultPictureHost = '';

/// Optional shared token the Worker can require (`APP_TOKEN` secret).
const pictureAppToken = String.fromEnvironment('PICTURE_APP_TOKEN');

/// A problem worth showing to the user as is.
class PictureException implements Exception {
  const PictureException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// The picture is gone: expired, or a view-once picture already seen.
class PictureGoneException extends PictureException {
  const PictureGoneException()
    : super('This picture has expired or was already viewed.');
}

class PictureService {
  PictureService({
    required String host,
    http.Client? client,
    this.appToken = pictureAppToken,
    this.prepare = preparePicture,
  }) : host = host.isEmpty ? null : Uri.parse(host),
       _http = client ?? http.Client();

  final Uri? host;
  final String appToken;
  final http.Client _http;

  /// Shrinks and cleans the photo; replaceable in tests.
  final Future<Uint8List> Function(Uint8List bytes) prepare;

  // Recently shown pictures, so scrolling doesn't download them again and
  // a view-once picture can still be seen after its one download.
  final _cache = <PictureLink, Uint8List>{};
  static const _cacheSize = 40;

  bool get isConfigured => host != null;

  Uint8List? cached(PictureLink link) => _cache[link];

  void _remember(PictureLink link, Uint8List bytes) {
    _cache
      ..remove(link)
      ..[link] = bytes;
    while (_cache.length > _cacheSize) {
      _cache.remove(_cache.keys.first);
    }
  }

  /// Prepares, encrypts and uploads [picture]. Returns the link to send.
  Future<PictureLink> upload(
    Uint8List picture, {
    required PictureExpiry expiry,
    bool viewOnce = false,
  }) async {
    final base = host;
    if (base == null) {
      throw const PictureException("Picture sharing isn't set up yet.");
    }
    final Uint8List prepared;
    try {
      prepared = await prepare(picture);
    } on FormatException catch (e) {
      throw PictureException(e.message);
    }
    final (:sealed, :key) = await sealPicture(prepared);
    final http.Response res;
    try {
      res = await _http.post(
        base.resolve('/upload'),
        headers: {
          'content-type': 'application/octet-stream',
          'x-expires-in': '${expiry.duration.inSeconds}',
          if (viewOnce) 'x-view-once': '1',
          if (appToken.isNotEmpty) 'x-app-token': appToken,
        },
        body: sealed,
      );
    } on Object {
      throw const PictureException(
        "Couldn't reach the picture server. Check your connection.",
      );
    }
    if (res.statusCode != 201) {
      throw PictureException(_errorText(res) ?? "Couldn't upload the picture.");
    }
    final body = jsonDecode(res.body) as Map<String, Object?>;
    final link = PictureLink(
      page: Uri.parse(body['url']! as String),
      key: key,
      viewOnce: viewOnce,
    );
    _remember(link, prepared);
    return link;
  }

  /// Downloads and decrypts the picture behind [link].
  Future<Uint8List> download(PictureLink link) async {
    final hit = _cache[link];
    if (hit != null) return hit;
    final http.Response res;
    try {
      res = await _http.get(link.raw);
    } on Object {
      throw const PictureException("Couldn't load the picture.");
    }
    if (res.statusCode == 404) throw const PictureGoneException();
    if (res.statusCode != 200) {
      throw const PictureException("Couldn't load the picture.");
    }
    final Uint8List plain;
    try {
      plain = await openPicture(res.bodyBytes, link.key);
    } on Object {
      throw const PictureException("This picture couldn't be unlocked.");
    }
    _remember(link, plain);
    return plain;
  }

  /// Sends a report about [link] to the server that holds it. The report
  /// includes the full link so the reviewer can see the picture.
  Future<void> report(
    PictureLink link, {
    required String sender,
    required String network,
    required String reason,
  }) async {
    final http.Response res;
    try {
      res = await _http.post(
        link.page.resolve('/report'),
        headers: {'content-type': 'application/json'},
        body: jsonEncode({
          'link': '$link',
          'sender': sender,
          'network': network,
          'reason': reason,
        }),
      );
    } on Object {
      throw const PictureException("Couldn't send the report.");
    }
    if (res.statusCode != 201) {
      throw const PictureException("Couldn't send the report.");
    }
  }

  static String? _errorText(http.Response res) {
    try {
      return (jsonDecode(res.body) as Map<String, Object?>)['error'] as String?;
    } on Object {
      return null;
    }
  }
}

final pictureServiceProvider = Provider<PictureService>(
  (ref) => PictureService(
    host: pictureHostSetting.isNotEmpty
        ? pictureHostSetting
        : defaultPictureHost,
  ),
);
