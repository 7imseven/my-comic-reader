// dart run tool/fix_icon.dart
import 'dart:io';
import 'package:image/image.dart' as img;

void main() async {
  final input = File('assets/icon.png');
  final output = File('assets/icon_white_bg.png');

  final src = img.decodeImage(await input.readAsBytes())!;
  final srcW = src.width;
  final srcH = src.height;

  // Add 25% padding around the icon, keep it centered
  final padRatio = 0.25;
  final newW = (srcW / (1 - padRatio * 2)).round();
  final newH = (srcH / (1 - padRatio * 2)).round();
  final canvas = img.Image(width: newW, height: newH, numChannels: 4);
  final ox = (newW - srcW) ~/ 2;
  final oy = (newH - srcH) ~/ 2;

  // Fill canvas with white
  for (int y = 0; y < newH; y++) {
    for (int x = 0; x < newW; x++) {
      canvas.setPixelRgba(x, y, 255, 255, 255, 255);
    }
  }

  // Composite source onto center of canvas (pre-multiply alpha onto white)
  for (int y = 0; y < srcH; y++) {
    for (int x = 0; x < srcW; x++) {
      final c = src.getPixel(x, y);
      final a = c.a / 255.0;
      final dx = ox + x;
      final dy = oy + y;
      final r = (255 * (1 - a) + c.r * a).round().clamp(0, 255);
      final g = (255 * (1 - a) + c.g * a).round().clamp(0, 255);
      final b = (255 * (1 - a) + c.b * a).round().clamp(0, 255);
      canvas.setPixelRgba(dx, dy, r, g, b, 255);
    }
  }

  await output.writeAsBytes(img.encodePng(canvas));
  print('✅ Icon padded and centered: ${output.path}');

  // Run flutter_launcher_icons
  final result = await Process.run('dart', ['run', 'flutter_launcher_icons']);
  print(result.stdout);
  if (result.exitCode != 0) print(result.stderr);
}
