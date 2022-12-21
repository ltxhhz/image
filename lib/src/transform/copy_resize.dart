import 'dart:typed_data';

import '../image/image.dart';
import '../util/image_exception.dart';
import '../util/interpolation.dart';
import 'bake_orientation.dart';

/// Returns a resized copy of the [src] Image.
/// If [height] isn't specified, then it will be determined by the aspect
/// ratio of [src] and [width].
/// If [width] isn't specified, then it will be determined by the aspect ratio
/// of [src] and [height].
Image copyResize(Image src,
    { int? width, int? height,
    Interpolation interpolation = Interpolation.nearest }) {
  if (width == null && height == null) {
    throw ImageException('Invalid size');
  }

  src = bakeOrientation(src);

  // this block sets [width] and [height] if null or negative.
  if (height == null || height <= 0) {
    height = (width! * (src.height / src.width)).toInt();
  }

  if (width == null || width <= 0) {
    width = (height * (src.width / src.height)).toInt();
  }

  if (width == src.width && height == src.height) {
    return src.clone();
  }

  final dst = Image(width, height,
      numChannels: src.numChannels, format: src.format,
      palette: src.palette, exif: src.exif, iccp: src.iccProfile);

  final dy = src.height / height;
  final dx = src.width / width;

  if (interpolation == Interpolation.average) {
    for (var y = 0; y < height; ++y) {
      final y1 = (y * dy).toInt();
      var y2 = ((y + 1) * dy).toInt();
      if (y2 == y1) {
        y2++;
      }

      for (var x = 0; x < width; ++x) {
        final x1 = (x * dx).toInt();
        var x2 = ((x + 1) * dx).toInt();
        if (x2 == x1) {
          x2++;
        }

        num r = 0;
        num g = 0;
        num b = 0;
        num a = 0;
        var np = 0;
        for (var sy = y1; sy < y2; ++sy) {
          for (var sx = x1; sx < x2; ++sx, ++np) {
            final s = src.getPixel(sx, sy);
            r += s.r;
            g += s.g;
            b += s.b;
            a += s.a;
          }
        }
        dst.setPixel(x, y, dst.getColor(r / np, g / np, b / np, a / np));
      }
    }
  } else if (interpolation == Interpolation.nearest) {
    final scaleX = Int32List(width);
    for (var x = 0; x < width; ++x) {
      scaleX[x] = (x * dx).toInt();
    }
    for (var y = 0; y < height; ++y) {
      final y2 = (y * dy).toInt();
      for (var x = 0; x < width; ++x) {
        dst.setPixel(x, y, src.getPixel(scaleX[x], y2));
      }
    }
  } else {
    // Copy the pixels from this image to the new image.
    for (var y = 0; y < height; ++y) {
      final y2 = y * dy;
      for (var x = 0; x < width; ++x) {
        final x2 = x * dx;
        dst.setPixel(x, y, src.getPixelInterpolate(x2, y2, interpolation));
      }
    }
  }

  return dst;
}
