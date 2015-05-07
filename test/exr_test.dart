part of image_test;

void defineExrTests() {
  List<int> bytes = new Io.File('test/res/exr/grid.exr').readAsBytesSync();

  ExrDecoder dec = new ExrDecoder();
  dec.startDecode(bytes);
  Image img = dec.decodeFrame(0);

  List<int> png = new PngEncoder().encodeImage(img);
  new Io.File('test/out/exr/grid.png')
        ..createSync(recursive: true)
        ..writeAsBytesSync(png);
}
