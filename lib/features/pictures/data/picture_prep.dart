/// Gets a photo ready to share: upright, at most 2048 px, JPEG, and with
/// all metadata (including GPS location) removed.
library;

import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

const maxPictureSide = 2048;

/// Runs [preparePictureSync] off the UI thread.
Future<Uint8List> preparePicture(Uint8List bytes) =>
    Isolate.run(() => preparePictureSync(bytes));

/// Decodes [bytes], applies the camera's rotation, shrinks it and
/// re-encodes it as JPEG without EXIF/GPS. Throws [FormatException] when
/// the file isn't a picture.
Uint8List preparePictureSync(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) {
    throw const FormatException("That file isn't a picture the app can read.");
  }
  var picture = img.bakeOrientation(decoded);
  final longest = math.max(picture.width, picture.height);
  if (longest > maxPictureSide) {
    picture = img.copyResize(
      picture,
      width: picture.width >= picture.height ? maxPictureSide : null,
      height: picture.height > picture.width ? maxPictureSide : null,
      interpolation: img.Interpolation.average,
    );
  }
  // Drop everything but the pixels: EXIF (GPS, camera, time) and ICC/text.
  picture
    ..exif = img.ExifData()
    ..iccProfile = null
    ..textData = null;
  return img.encodeJpg(picture, quality: 85);
}
