// tool/generate_icons.dart
//
// Generates the Leak Radar launcher icons using the pure-Dart `image` package.
// Produces two PNGs in assets/icon/:
//   • leak_radar_icon.png     — full icon with dark rounded-square background
//   • leak_radar_foreground.png — radar glyph on transparent background
//
// Run: dart run tool/generate_icons.dart
import 'dart:io';
import 'dart:math' as math;

import 'package:image/image.dart' as img;

// Brand colours
const int _kBgR = 0x0A, _kBgG = 0x0D, _kBgB = 0x0E;
const int _kAccR = 0x2F, _kAccG = 0xE3, _kAccB = 0x9B;

const int _kSize = 1024;
const int _kCornerRadius = 180;

/// Creates a pixel colour from RGBA components.
img.ColorRgba8 _rgba(int r, int g, int b, int a) => img.ColorRgba8(r, g, b, a);

/// Draws a filled circle at [cx], [cy] with [radius].
void _fillCircle(img.Image image, int cx, int cy, int radius, img.Color color) {
  final int r2 = radius * radius;
  for (int dy = -radius; dy <= radius; dy++) {
    for (int dx = -radius; dx <= radius; dx++) {
      if (dx * dx + dy * dy <= r2) {
        final int px = cx + dx;
        final int py = cy + dy;
        if (px >= 0 && px < image.width && py >= 0 && py < image.height) {
          image.setPixel(px, py, color);
        }
      }
    }
  }
}

/// Draws a ring (annulus) by filling the outer disc then inner disc in [fill].
/// [strokeColor] is the ring colour; [holeColor] is what fills the hole.
void _drawRing(
  img.Image image,
  int cx,
  int cy,
  int outerRadius,
  int strokeWidth,
  img.Color strokeColor,
  img.Color holeColor,
) {
  _fillCircle(image, cx, cy, outerRadius, strokeColor);
  _fillCircle(image, cx, cy, outerRadius - strokeWidth, holeColor);
}

/// Draws the rounded-square background with radius [r].
void _fillRoundedRect(img.Image image, img.Color color, int r) {
  final int w = image.width;
  final int h = image.height;

  // Fill the interior rectangles (horizontal and vertical bands)
  for (int y = r; y < h - r; y++) {
    for (int x = 0; x < w; x++) {
      image.setPixel(x, y, color);
    }
  }
  for (int y = 0; y < r; y++) {
    for (int x = r; x < w - r; x++) {
      image.setPixel(x, y, color);
    }
  }
  for (int y = h - r; y < h; y++) {
    for (int x = r; x < w - r; x++) {
      image.setPixel(x, y, color);
    }
  }

  // Fill four corners
  final int r2 = r * r;
  for (int dy = 0; dy < r; dy++) {
    for (int dx = 0; dx < r; dx++) {
      // Distance from corner arc centre
      final int d2 = (r - 1 - dx) * (r - 1 - dx) + (r - 1 - dy) * (r - 1 - dy);
      if (d2 <= r2) {
        image.setPixel(dx, dy, color); // top-left
        image.setPixel(w - 1 - dx, dy, color); // top-right
        image.setPixel(dx, h - 1 - dy, color); // bottom-left
        image.setPixel(w - 1 - dx, h - 1 - dy, color); // bottom-right
      }
    }
  }
}

/// Draws the sweep wedge (semi-transparent bright green arc).
void _drawSweep(img.Image image, int cx, int cy, int maxRadius, img.Color bg) {
  // Sweep from 0 (3 o'clock) going 60 degrees clockwise
  const double sweepStart = -math.pi / 6; // 330 deg (11 o'clock)
  const double sweepEnd = math.pi / 6; // 30 deg (1 o'clock)

  for (int y = 0; y < image.height; y++) {
    for (int x = 0; x < image.width; x++) {
      final int dx = x - cx;
      final int dy = y - cy;
      final double dist = math.sqrt(dx * dx + dy * dy);
      if (dist > maxRadius) continue;

      double angle = math.atan2(dy, dx);
      // Normalise angle into sweep window
      bool inSweep = angle >= sweepStart && angle <= sweepEnd;
      if (!inSweep) continue;

      // Gradient: full opacity at the sweep line (angle = 0) fading outward
      final double t = 1.0 - ((angle - sweepStart) / (sweepEnd - sweepStart));
      final double distFade = 1.0 - (dist / maxRadius) * 0.3;
      final int alpha = (255 * t * distFade * 0.35).round().clamp(0, 255);

      if (alpha < 2) continue;

      // Blend accent colour over existing pixel
      final img.Pixel px = image.getPixel(x, y);
      final double a = alpha / 255.0;
      final int nr = (px.r * (1 - a) + _kAccR * a).round().clamp(0, 255);
      final int ng = (px.g * (1 - a) + _kAccG * a).round().clamp(0, 255);
      final int nb = (px.b * (1 - a) + _kAccB * a).round().clamp(0, 255);
      image.setPixel(x, y, _rgba(nr, ng, nb, px.a.toInt()));
    }
  }
}

/// Draws the full radar glyph onto [image] at [cx],[cy].
/// [bgColor] is used as the hole fill for rings (transparent on foreground).
void _drawGlyph(img.Image image, int cx, int cy, img.Color bgColor) {
  final int outermost = (cx * 0.72).round();

  // 4 concentric rings — opacities 0.28, 0.18, 0.12, 0.08 (outside to inside)
  final List<double> opacities = [0.28, 0.18, 0.12, 0.08];
  final double spacing = outermost / 4.0;

  for (int i = 0; i < 4; i++) {
    final int r = (outermost - i * spacing).round();
    final int stroke = (spacing * 0.18).round().clamp(3, 24);
    final int alpha = (255 * opacities[i]).round();
    final img.Color ringColor = _rgba(_kAccR, _kAccG, _kAccB, alpha);
    _drawRing(image, cx, cy, r, stroke, ringColor, bgColor);
  }

  // Sweep wedge
  _drawSweep(image, cx, cy, outermost, bgColor);

  // Sweep line (a thin bright line at angle 0)
  final int lineLen = outermost;
  for (int d = 0; d < lineLen; d++) {
    final int x = cx + d;
    final int y = cy;
    if (x >= 0 && x < image.width) {
      // Semi-transparent accent
      final int alpha = (255 * 0.7 * (1.0 - d / lineLen)).round();
      final img.Pixel px = image.getPixel(x, y);
      final double a = alpha / 255.0;
      final int nr = (px.r * (1 - a) + _kAccR * a).round().clamp(0, 255);
      final int ng = (px.g * (1 - a) + _kAccG * a).round().clamp(0, 255);
      final int nb = (px.b * (1 - a) + _kAccB * a).round().clamp(0, 255);
      final int na = (px.a.toInt() == 0 && alpha > 0) ? alpha : px.a.toInt();
      image.setPixel(x, y, _rgba(nr, ng, nb, na));
    }
  }

  // Center dot — solid accent
  final int dotRadius = (cx * 0.045).round().clamp(6, 28);
  _fillCircle(image, cx, cy, dotRadius, _rgba(_kAccR, _kAccG, _kAccB, 255));
}

/// Generates the full icon (dark rounded-square background + glyph).
img.Image _generateFullIcon() {
  final img.Image image = img.Image(
    width: _kSize,
    height: _kSize,
    numChannels: 4,
  );

  // Start transparent
  img.fill(image, color: _rgba(0, 0, 0, 0));

  // Rounded-square dark background
  final img.Color bgColor = _rgba(_kBgR, _kBgG, _kBgB, 255);
  _fillRoundedRect(image, bgColor, _kCornerRadius);

  // Glyph in centre
  _drawGlyph(image, _kSize ~/ 2, _kSize ~/ 2, bgColor);

  return image;
}

/// Generates the foreground icon (glyph only, transparent bg, inner 64%).
img.Image _generateForeground() {
  final img.Image image = img.Image(
    width: _kSize,
    height: _kSize,
    numChannels: 4,
  );

  // Fully transparent background
  img.fill(image, color: _rgba(0, 0, 0, 0));

  // Glyph centred inside inner 64% (18% padding each side)
  // We scale by drawing into a sub-image and compositing
  final int padding = (_kSize * 0.18).round();
  final int innerSize = _kSize - 2 * padding;

  // Draw a smaller version of the glyph onto a temp image
  final img.Image glyph = img.Image(
    width: innerSize,
    height: innerSize,
    numChannels: 4,
  );
  img.fill(glyph, color: _rgba(0, 0, 0, 0));

  final int gc = innerSize ~/ 2;
  _drawGlyph(glyph, gc, gc, _rgba(0, 0, 0, 0));

  // Composite glyph onto full canvas at (padding, padding)
  img.compositeImage(image, glyph, dstX: padding, dstY: padding);

  return image;
}

void main() {
  const String outDir = 'assets/icon';
  Directory(outDir).createSync(recursive: true);

  stdout.writeln('Generating full icon...');
  final img.Image fullIcon = _generateFullIcon();
  final List<int> fullPng = img.encodePng(fullIcon);
  File('$outDir/leak_radar_icon.png').writeAsBytesSync(fullPng);
  stdout.writeln(
    '  Written: $outDir/leak_radar_icon.png (${fullPng.length} bytes)',
  );

  stdout.writeln('Generating foreground icon...');
  final img.Image fg = _generateForeground();
  final List<int> fgPng = img.encodePng(fg);
  File('$outDir/leak_radar_foreground.png').writeAsBytesSync(fgPng);
  stdout.writeln(
    '  Written: $outDir/leak_radar_foreground.png (${fgPng.length} bytes)',
  );

  stdout.writeln('Done.');
}
