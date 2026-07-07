// dart run tool/fix_icon.dart
import 'dart:io';
import 'package:image/image.dart' as img;

void main() async {
  final input = File('assets/icon.png');
  final output = File('assets/icon_white_bg.png');

  final image = img.decodeImage(await input.readAsBytes())!;

  for (int y = 0; y < image.height; y++) {
    for (int x = 0; x < image.width; x++) {
      final c = image.getPixel(x, y);
      if (c.a < 255) {
        final r = (255 * (255 - c.a) + c.r * c.a) ~/ 255;
        final g = (255 * (255 - c.a) + c.g * c.a) ~/ 255;
        final b = (255 * (255 - c.a) + c.b * c.a) ~/ 255;
        image.setPixelRgba(x, y, r, g, b, 255);
      }
    }
  }

  await output.writeAsBytes(img.encodePng(image));
  print('✅ White-background icon created');
}
