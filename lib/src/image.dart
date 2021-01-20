import 'dart:math';
import 'dart:typed_data';

import 'color.dart';
import 'exif_data.dart';
import 'icc_profile_data.dart';
import 'util/interpolation.dart';

enum Format { argb, abgr, rgba, bgra, rgb, bgr, luminance }

enum Channels { rgb, rgba }

enum BlendMode {
  /// No alpha blending should be done when drawing this frame (replace
  /// pixels in canvas).
  source,

  /// Alpha blending should be used when drawing this frame (composited over
  /// the current canvas image).
  over
}

enum DisposeMode {
  /// When drawing a frame, the canvas should be left as it is.
  none,

  /// When drawing a frame, the canvas should be cleared first.
  clear,

  /// When drawing this frame, the canvas should be reverted to how it was
  /// before drawing it.
  previous
}

/// An image buffer where pixels are encoded into 32-bit unsigned ints (Uint32).
///
/// Pixels are stored in 32-bit unsigned integers in #AARRGGBB format.
/// This is to be consistent with the Flutter image data. You can use
/// [getBytes] to access the pixel data at the byte (channel) level, optionally
/// providing the format to get the image data as. You can use the various color
/// functions, such as [getRed], [getGreen], [getBlue], and [getAlpha] to access
/// the individual channels of a given pixel color.
///
/// If this image is a frame of an animation as decoded by the [decodeFrame]
/// method of [Decoder], then the [xOffset], [yOffset], [width] and [height]
/// determine the area of the canvas this image should be drawn into,
/// as some frames of an animation only modify part of the canvas (recording
/// the part of the frame that actually changes). The [decodeAnimation] method
/// will always return the fully composed animation, so these coordinate
/// properties are not used.
class Image {
  /// Width of the image.
  final int width;

  /// Height of the image.
  final int height;

  /// The channels used by this image, indicating whether the alpha channel
  /// is used or not. All images have an implicit alpha channel due to the
  /// image data being stored in a Uint32, but some images, such as those
  /// decoded from a Jpeg, don't use the alpha channel. This allows
  /// image encoders that support both rgb and rgba formats, to know which
  /// one it should use.
  Channels channels;

  /// x position at which to render the frame. This is used for frames
  /// in an animation, such as from an animated GIF.
  int xOffset = 0;

  /// y position at which to render the frame. This is used for frames
  /// in an animation, such as from an animated GIF.
  int yOffset = 0;

  /// How long this frame should be displayed, in milliseconds.
  /// A duration of 0 indicates no delay and the next frame will be drawn
  /// as quickly as it can.
  int duration = 0;

  /// Defines what should be done to the canvas when drawing this frame
  /// in an animation.
  DisposeMode disposeMethod = DisposeMode.clear;

  /// Defines the blending method (alpha compositing) to use when drawing this
  /// frame in an animation.
  BlendMode blendMethod = BlendMode.over;

  /// Pixels are encoded into 4-byte Uint32 integers in #AABBGGRR channel order.
  final Uint32List data;

  /// EXIF data decoded from an image file.
  ExifData exif;

  /// ICC color profile read from an image file.
  ICCProfileData? iccProfile;

  /// Create an image with the given dimensions and format.
  Image(this.width, this.height,
      {this.channels = Channels.rgba, ExifData? exif, ICCProfileData? iccp})
      : data = Uint32List(width * height),
        exif = ExifData.from(exif),
        iccProfile = iccp;

  Image.rgb(this.width, this.height, {ExifData? exif, ICCProfileData? iccp})
      : channels = Channels.rgb,
        data = Uint32List(width * height),
        exif = ExifData.from(exif),
        iccProfile = iccp;

  /// Create a copy of the image [other].
  Image.from(Image other)
      : width = other.width,
        height = other.height,
        xOffset = other.xOffset,
        yOffset = other.yOffset,
        duration = other.duration,
        disposeMethod = other.disposeMethod,
        blendMethod = other.blendMethod,
        channels = other.channels,
        data = other.data.sublist(0),
        exif = ExifData.from(other.exif),
        iccProfile = other.iccProfile;

  /// Create an image from raw data in [bytes].
  ///
  /// [format] defines the order of color channels in [bytes].
  /// An HTML canvas element stores colors in Format.rgba format; a Flutter
  /// Image object stores colors in Format.rgba format.
  /// The length of [bytes] should be (width * height) * format-byte-count,
  /// where format-byte-count is 1, 3, or 4 depending on the number of
  /// channels in the format (luminance, rgb, rgba, etc).
  ///
  /// The native format of an image is Format.rgba. If another format
  /// is specified, the input data will be converted to rgba to store
  /// in the Image.
  ///
  /// For example, given an Html Canvas, you could create an image:
  /// var bytes = canvas.getContext('2d').getImageData(0, 0,
  ///   canvas.width, canvas.height).data;
  /// var image = Image.fromBytes(canvas.width, canvas.height, bytes,
  ///                             format: Format.rgba);
  Image.fromBytes(int width, int height, List<int> bytes,
      {ExifData? exif,
      ICCProfileData? iccp,
      Format format = Format.rgba,
      this.channels = Channels.rgba})
      : width = width,
        height = height,
        data = _convertData(width, height, bytes, format),
        exif = ExifData.from(exif),
        iccProfile = iccp;

  /// Clone this image.
  Image clone() => Image.from(this);

  /// The number of channels used by this Image. While all images
  /// are stored internally with 4 bytes, some images, such as those
  /// loaded from a Jpeg, don't use the 4th (alpha) channel.
  int get numberOfChannels => channels == Channels.rgba ? 4 : 3;

  /// Get the bytes from the image. You can use this to access the
  /// color channels directly, or to pass it to something like an
  /// Html canvas context.
  ///
  /// Specifying the [format] will convert the image data to the specified
  /// format. Images are stored internally in Format.rgba format; any
  /// other format will require a conversion.
  ///
  /// For example, given an Html Canvas, you could draw this image into the
  /// canvas:
  /// Html.ImageData d = context2D.createImageData(image.width, image.height);
  /// d.data.setRange(0, image.length, image.getBytes(format: Format.rgba));
  /// context2D.putImageData(data, 0, 0);
  Uint8List getBytes({Format format = Format.rgba}) {
    var rgba = Uint8List.view(data.buffer);
    switch (format) {
      case Format.rgba:
        return rgba;
      case Format.bgra:
        var bytes = Uint8List(width * height * 4);
        for (var i = 0, len = bytes.length; i < len; i += 4) {
          bytes[i + 0] = rgba[i + 2];
          bytes[i + 1] = rgba[i + 1];
          bytes[i + 2] = rgba[i + 0];
          bytes[i + 3] = rgba[i + 3];
        }
        return bytes;
      case Format.abgr:
        var bytes = Uint8List(width * height * 4);
        for (var i = 0, len = bytes.length; i < len; i += 4) {
          bytes[i + 0] = rgba[i + 3];
          bytes[i + 1] = rgba[i + 2];
          bytes[i + 2] = rgba[i + 1];
          bytes[i + 3] = rgba[i + 0];
        }
        return bytes;
      case Format.argb:
        var bytes = Uint8List(width * height * 4);
        for (var i = 0, len = bytes.length; i < len; i += 4) {
          bytes[i + 0] = rgba[i + 3];
          bytes[i + 1] = rgba[i + 0];
          bytes[i + 2] = rgba[i + 1];
          bytes[i + 3] = rgba[i + 2];
        }
        return bytes;
      case Format.rgb:
        var bytes = Uint8List(width * height * 3);
        for (var i = 0, j = 0, len = bytes.length; j < len; i += 4, j += 3) {
          bytes[j + 0] = rgba[i + 0];
          bytes[j + 1] = rgba[i + 1];
          bytes[j + 2] = rgba[i + 2];
        }
        return bytes;
      case Format.bgr:
        var bytes = Uint8List(width * height * 3);
        for (var i = 0, j = 0, len = bytes.length; j < len; i += 4, j += 3) {
          bytes[j + 0] = rgba[i + 2];
          bytes[j + 1] = rgba[i + 1];
          bytes[j + 2] = rgba[i + 0];
        }
        return bytes;
      case Format.luminance:
        var bytes = Uint8List(width * height);
        for (var i = 0, len = length; i < len; ++i) {
          bytes[i] = getLuminance(data[i]);
        }
        return bytes;
    }
  }

  /// Set all of the pixels of the image to the given [color].
  Image fill(int color) {
    data.fillRange(0, data.length, color);
    return this;
  }

  /// Add the colors of [other] to the pixels of this image.
  Image operator +(Image other) {
    var h = min(height, other.height);
    var w = min(width, other.width);
    for (var y = 0; y < h; ++y) {
      for (var x = 0; x < w; ++x) {
        var c1 = getPixel(x, y);
        var r1 = getRed(c1);
        var g1 = getGreen(c1);
        var b1 = getBlue(c1);
        var a1 = getAlpha(c1);

        var c2 = other.getPixel(x, y);
        var r2 = getRed(c2);
        var g2 = getGreen(c2);
        var b2 = getBlue(c2);
        var a2 = getAlpha(c2);

        setPixel(x, y, getColor(r1 + r2, g1 + g2, b1 + b2, a1 + a2));
      }
    }
    return this;
  }

  /// Subtract the colors of [other] from the pixels of this image.
  Image operator -(Image other) {
    var h = min(height, other.height);
    var w = min(width, other.width);
    for (var y = 0; y < h; ++y) {
      for (var x = 0; x < w; ++x) {
        var c1 = getPixel(x, y);
        var r1 = getRed(c1);
        var g1 = getGreen(c1);
        var b1 = getBlue(c1);
        var a1 = getAlpha(c1);

        var c2 = other.getPixel(x, y);
        var r2 = getRed(c2);
        var g2 = getGreen(c2);
        var b2 = getBlue(c2);
        var a2 = getAlpha(c2);

        setPixel(x, y, getColor(r1 - r2, g1 - g2, b1 - b2, a1 - a2));
      }
    }
    return this;
  }

  /// Multiply the colors of [other] with the pixels of this image.
  Image operator *(Image other) {
    var h = min(height, other.height);
    var w = min(width, other.width);
    for (var y = 0; y < h; ++y) {
      for (var x = 0; x < w; ++x) {
        var c1 = getPixel(x, y);
        var r1 = getRed(c1);
        var g1 = getGreen(c1);
        var b1 = getBlue(c1);
        var a1 = getAlpha(c1);

        var c2 = other.getPixel(x, y);
        var r2 = getRed(c2);
        var g2 = getGreen(c2);
        var b2 = getBlue(c2);
        var a2 = getAlpha(c2);

        setPixel(x, y, getColor(r1 * r2, g1 * g2, b1 * b2, a1 * a2));
      }
    }
    return this;
  }

  /// OR the colors of [other] to the pixels of this image.
  Image operator |(Image other) {
    var h = min(height, other.height);
    var w = min(width, other.width);
    for (var y = 0; y < h; ++y) {
      for (var x = 0; x < w; ++x) {
        var c1 = getPixel(x, y);
        var r1 = getRed(c1);
        var g1 = getGreen(c1);
        var b1 = getBlue(c1);
        var a1 = getAlpha(c1);

        var c2 = other.getPixel(x, y);
        var r2 = getRed(c2);
        var g2 = getGreen(c2);
        var b2 = getBlue(c2);
        var a2 = getAlpha(c2);

        setPixel(x, y, getColor(r1 | r2, g1 | g2, b1 | b2, a1 | a2));
      }
    }
    return this;
  }

  /// AND the colors of [other] with the pixels of this image.
  Image operator &(Image other) {
    var h = min(height, other.height);
    var w = min(width, other.width);
    for (var y = 0; y < h; ++y) {
      for (var x = 0; x < w; ++x) {
        var c1 = getPixel(x, y);
        var r1 = getRed(c1);
        var g1 = getGreen(c1);
        var b1 = getBlue(c1);
        var a1 = getAlpha(c1);

        var c2 = other.getPixel(x, y);
        var r2 = getRed(c2);
        var g2 = getGreen(c2);
        var b2 = getBlue(c2);
        var a2 = getAlpha(c2);

        setPixel(x, y, getColor(r1 & r2, g1 & g2, b1 & b2, a1 & a2));
      }
    }
    return this;
  }

  /// Modula the colors of [other] with the pixels of this image.
  Image operator %(Image other) {
    var h = min(height, other.height);
    var w = min(width, other.width);
    for (var y = 0; y < h; ++y) {
      for (var x = 0; x < w; ++x) {
        var c1 = getPixel(x, y);
        var r1 = getRed(c1);
        var g1 = getGreen(c1);
        var b1 = getBlue(c1);
        var a1 = getAlpha(c1);

        var c2 = other.getPixel(x, y);
        var r2 = getRed(c2);
        var g2 = getGreen(c2);
        var b2 = getBlue(c2);
        var a2 = getAlpha(c2);

        setPixel(x, y, getColor(r1 % r2, g1 % g2, b1 % b2, a1 % a2));
      }
    }
    return this;
  }

  /// The size of the image buffer.
  int get length => data.length;

  /// Get a pixel from the buffer. No range checking is done.
  int operator [](int index) => data[index];

  /// Set a pixel in the buffer. No range checking is done.
  void operator []=(int index, int color) {
    data[index] = color;
  }

  /// Get the buffer index for the [x], [y] pixel coordinates.
  /// No range checking is done.
  int index(int x, int y) => y * width + x;

  /// Is the given [x], [y] pixel coordinates within the resolution of the image.
  bool boundsSafe(int x, int y) => x >= 0 && x < width && y >= 0 && y < height;

  /// Get the pixel from the given [x], [y] coordinate. Color is encoded in a
  /// Uint32 as #AABBGGRR. No range checking is done.
  int getPixel(int x, int y) => data[y * width + x];

  /// Get the pixel from the given [x], [y] coordinate. Color is encoded in a
  /// Uint32 as #AABBGGRR. If the pixel coordinates are out of bounds, 0 is
  /// returned.
  int getPixelSafe(int x, int y) => boundsSafe(x, y) ? data[y * width + x] : 0;

  /// Get the pixel using the given [interpolation] type for non-integer pixel
  /// coordinates.
  int getPixelInterpolate(num fx, num fy,
      [Interpolation interpolation = Interpolation.linear]) {
    if (interpolation == Interpolation.cubic) {
      return getPixelCubic(fx, fy);
    } else if (interpolation == Interpolation.linear) {
      return getPixelLinear(fx, fy);
    }
    return getPixelSafe(fx.toInt(), fy.toInt());
  }

  /// Get the pixel using linear interpolation for non-integer pixel
  /// coordinates.
  int getPixelLinear(num fx, num fy) {
    var x = fx.toInt() - (fx >= 0 ? 0 : 1);
    var nx = x + 1;
    var y = fy.toInt() - (fy >= 0 ? 0 : 1);
    var ny = y + 1;
    var dx = fx - x;
    var dy = fy - y;

    int _linear(int Icc, int Inc, int Icn, int Inn) {
      return (Icc +
              dx * (Inc - Icc + dy * (Icc + Inn - Icn - Inc)) +
              dy * (Icn - Icc))
          .toInt();
    }

    var Icc = getPixelSafe(x, y);
    var Inc = getPixelSafe(nx, y);
    var Icn = getPixelSafe(x, ny);
    var Inn = getPixelSafe(nx, ny);

    return getColor(
        _linear(getRed(Icc), getRed(Inc), getRed(Icn), getRed(Inn)),
        _linear(getGreen(Icc), getGreen(Inc), getGreen(Icn), getGreen(Inn)),
        _linear(getBlue(Icc), getBlue(Inc), getBlue(Icn), getBlue(Inn)),
        _linear(getAlpha(Icc), getAlpha(Inc), getAlpha(Icn), getAlpha(Inn)));
  }

  /// Get the pixel using cubic interpolation for non-integer pixel
  /// coordinates.
  int getPixelCubic(num fx, num fy) {
    var x = fx.toInt() - (fx >= 0.0 ? 0 : 1);
    var px = x - 1;
    var nx = x + 1;
    var ax = x + 2;
    var y = fy.toInt() - (fy >= 0.0 ? 0 : 1);
    var py = y - 1;
    var ny = y + 1;
    var ay = y + 2;

    var dx = fx - x;
    var dy = fy - y;

    num _cubic(num dx, num Ipp, num Icp, num Inp, num Iap) =>
        Icp +
        0.5 *
            (dx * (-Ipp + Inp) +
                dx * dx * (2 * Ipp - 5 * Icp + 4 * Inp - Iap) +
                dx * dx * dx * (-Ipp + 3 * Icp - 3 * Inp + Iap));

    var Ipp = getPixelSafe(px, py);
    var Icp = getPixelSafe(x, py);
    var Inp = getPixelSafe(nx, py);
    var Iap = getPixelSafe(ax, py);
    var Ip0 = _cubic(dx, getRed(Ipp), getRed(Icp), getRed(Inp), getRed(Iap));
    var Ip1 =
        _cubic(dx, getGreen(Ipp), getGreen(Icp), getGreen(Inp), getGreen(Iap));
    var Ip2 =
        _cubic(dx, getBlue(Ipp), getBlue(Icp), getBlue(Inp), getBlue(Iap));
    var Ip3 =
        _cubic(dx, getAlpha(Ipp), getAlpha(Icp), getAlpha(Inp), getAlpha(Iap));

    var Ipc = getPixelSafe(px, y);
    var Icc = getPixelSafe(x, y);
    var Inc = getPixelSafe(nx, y);
    var Iac = getPixelSafe(ax, y);
    var Ic0 = _cubic(dx, getRed(Ipc), getRed(Icc), getRed(Inc), getRed(Iac));
    var Ic1 =
        _cubic(dx, getGreen(Ipc), getGreen(Icc), getGreen(Inc), getGreen(Iac));
    var Ic2 =
        _cubic(dx, getBlue(Ipc), getBlue(Icc), getBlue(Inc), getBlue(Iac));
    var Ic3 =
        _cubic(dx, getAlpha(Ipc), getAlpha(Icc), getAlpha(Inc), getAlpha(Iac));

    var Ipn = getPixelSafe(px, ny);
    var Icn = getPixelSafe(x, ny);
    var Inn = getPixelSafe(nx, ny);
    var Ian = getPixelSafe(ax, ny);
    var In0 = _cubic(dx, getRed(Ipn), getRed(Icn), getRed(Inn), getRed(Ian));
    var In1 =
        _cubic(dx, getGreen(Ipn), getGreen(Icn), getGreen(Inn), getGreen(Ian));
    var In2 =
        _cubic(dx, getBlue(Ipn), getBlue(Icn), getBlue(Inn), getBlue(Ian));
    var In3 =
        _cubic(dx, getAlpha(Ipn), getAlpha(Icn), getAlpha(Inn), getAlpha(Ian));

    var Ipa = getPixelSafe(px, ay);
    var Ica = getPixelSafe(x, ay);
    var Ina = getPixelSafe(nx, ay);
    var Iaa = getPixelSafe(ax, ay);
    var Ia0 = _cubic(dx, getRed(Ipa), getRed(Ica), getRed(Ina), getRed(Iaa));
    var Ia1 =
        _cubic(dx, getGreen(Ipa), getGreen(Ica), getGreen(Ina), getGreen(Iaa));
    var Ia2 =
        _cubic(dx, getBlue(Ipa), getBlue(Ica), getBlue(Ina), getBlue(Iaa));
    var Ia3 =
        _cubic(dx, getAlpha(Ipa), getAlpha(Ica), getAlpha(Ina), getAlpha(Iaa));

    var c0 = _cubic(dy, Ip0, Ic0, In0, Ia0);
    var c1 = _cubic(dy, Ip1, Ic1, In1, Ia1);
    var c2 = _cubic(dy, Ip2, Ic2, In2, Ia2);
    var c3 = _cubic(dy, Ip3, Ic3, In3, Ia3);

    return getColor(c0.toInt(), c1.toInt(), c2.toInt(), c3.toInt());
  }

  /// Set the pixel at the given [x], [y] coordinate to the [color].
  /// No range checking is done.
  void setPixel(int x, int y, int color) {
    data[y * width + x] = color;
  }

  /// Set the pixel at the given [x], [y] coordinate to the [color].
  /// If the pixel coordinates are out of bounds, nothing is done.
  void setPixelSafe(int x, int y, int color) {
    if (boundsSafe(x, y)) {
      data[y * width + x] = color;
    }
  }

  /// Set the pixel at the given [x], [y] coordinate to the color
  /// [r], [g], [b], [a].
  ///
  /// This simply replaces the existing color, it does not do any alpha
  /// blending. Use [drawPixel] for that. No range checking is done.
  void setPixelRgba(int x, int y, int r, int g, int b, [int a = 0xff]) {
    data[y * width + x] = getColor(r, g, b, a);
  }

  /// Return the average gray value of the image.
  int getWhiteBalance() {
    final len = data.length;
    var r = 0;
    var g = 0;
    var b = 0;
    for (var i = 0; i < len; ++i) {
      r += getRed(data[i]);
      g += getGreen(data[i]);
      b += getBlue(data[i]);
    }

    r ~/= len;
    g ~/= len;
    b ~/= len;

    return (r + g + b) ~/ 3;
  }

  static Uint32List _convertData(
      int width, int height, List<int> bytes, Format format) {
    if (format == Format.rgba) {
      return bytes is Uint32List
          ? bytes.sublist(0)
          : bytes is Uint8List
              ? Uint32List.view(bytes.buffer).sublist(0)
              : Uint32List.view(Uint8List.fromList(bytes).buffer);
    }

    var input = bytes is Uint32List ? Uint8List.view(bytes.buffer) : bytes;

    var data = Uint32List(width * height);
    var rgba = Uint8List.view(data.buffer);

    switch (format) {
      case Format.rgba:
        for (var i = 0, len = input.length; i < len; ++i) {
          rgba[i] = input[i];
        }
        break;
      case Format.bgra:
        for (var i = 0, len = input.length; i < len; i += 4) {
          rgba[i + 0] = input[i + 2];
          rgba[i + 1] = input[i + 1];
          rgba[i + 2] = input[i + 0];
          rgba[i + 3] = input[i + 3];
        }
        break;
      case Format.abgr:
        for (var i = 0, len = input.length; i < len; i += 4) {
          rgba[i + 0] = input[i + 3];
          rgba[i + 1] = input[i + 2];
          rgba[i + 2] = input[i + 1];
          rgba[i + 3] = input[i + 0];
        }
        break;
      case Format.argb:
        for (var i = 0, len = input.length; i < len; i += 4) {
          rgba[i + 0] = input[i + 1];
          rgba[i + 1] = input[i + 2];
          rgba[i + 2] = input[i + 3];
          rgba[i + 3] = input[i + 0];
        }
        break;
      case Format.bgr:
        for (var i = 0, j = 0, len = input.length; j < len; i += 4, j += 3) {
          rgba[i + 0] = input[j + 2];
          rgba[i + 1] = input[j + 1];
          rgba[i + 2] = input[j + 0];
          rgba[i + 3] = 255;
        }
        break;
      case Format.rgb:
        for (var i = 0, j = 0, len = input.length; j < len; i += 4, j += 3) {
          rgba[i + 0] = input[j + 0];
          rgba[i + 1] = input[j + 1];
          rgba[i + 2] = input[j + 2];
          rgba[i + 3] = 255;
        }
        break;
      case Format.luminance:
        for (var i = 0, j = 0, len = input.length; j < len; i += 4, ++j) {
          rgba[i + 0] = input[j];
          rgba[i + 1] = input[j];
          rgba[i + 2] = input[j];
          rgba[i + 3] = 255;
        }
        break;
    }

    return data;
  }
}
