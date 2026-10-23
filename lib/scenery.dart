import 'dart:math';
import 'dart:ui';

import 'package:flame/components.dart';

enum Weather {
  sunny('晴れ', 30, 0xffb9edff, 0xffeefbff),
  cloudy('曇り', 20, 0xffaebdce, 0xffe3edf2),
  rain('雨', 14, 0xff758ca7, 0xffc5d9e7),
  thunder('雷', 3, 0xff344460, 0xff8ca2b5),
  snow('雪', 8, 0xffb6cede, 0xfff4fbff),
  blossom('桜', 5, 0xffffd9e8, 0xfffff3eb),
  sunset('夕方', 12, 0xffb786bf, 0xffffd19c),
  night('夜', 8, 0xff182640, 0xff526685);

  const Weather(this.label, this.weight, this.top, this.bottom);
  final String label;
  final int weight;
  final int top;
  final int bottom;
  bool get rare => weight <= 5;
}

T weightedPick<T>(Random random, List<T> values, int Function(T) weight) {
  final total = values.fold<int>(0, (sum, v) => sum + weight(v));
  var choice = random.nextInt(total);
  for (final value in values) {
    choice -= weight(value);
    if (choice < 0) return value;
  }
  return values.last;
}

Weather randomWeather(Random random) =>
    weightedPick(random, Weather.values, (v) => v.weight);

/// Paint to the current canvas every frame. A rectangle sized at onLoad would
/// retain the old width after ad ownership, rotation or a viewport resize.
class Landscape extends Component {
  Landscape({required this.canvasSize, required this.weather})
    : super(priority: -100);
  final Vector2 Function() canvasSize;
  final Weather Function() weather;
  double elapsed = 0;

  @override
  void update(double dt) {
    elapsed += dt;
  }

  @override
  void render(Canvas canvas) {
    final size = canvasSize();
    final scene = weather();
    final bounds = Rect.fromLTWH(0, 0, size.x, size.y);
    canvas.drawRect(
      bounds,
      Paint()
        ..shader = Gradient.linear(Offset.zero, const Offset(0, 400), [
          Color(scene.top),
          Color(scene.bottom),
        ]),
    );
    if (scene == Weather.night) {
      for (var i = 0; i < 35; i++) {
        canvas.drawCircle(
          Offset((i * 173.7) % size.x, 20 + (i * 43.9) % 240),
          1.3 + (i % 3) * 0.4,
          Paint()..color = const Color(0xfff8f1c8),
        );
      }
      canvas.drawCircle(
        Offset(size.x - 110, 65),
        27,
        Paint()..color = const Color(0xfffff0c0),
      );
      canvas.drawCircle(
        Offset(size.x - 98, 57),
        23,
        Paint()..color = Color(scene.top),
      );
    } else if (scene == Weather.sunny ||
        scene == Weather.sunset ||
        scene == Weather.blossom) {
      canvas.drawCircle(
        Offset(size.x - 100, scene == Weather.sunset ? 280 : 65),
        34,
        Paint()
          ..color = Color(scene == Weather.sunset ? 0xffffaf69 : 0xffffdf76),
      );
    }
    // Distant hills stop at the ground line, keeping obstacles readable.
    final hills = Path()..moveTo(0, 400);
    for (double x = 0; x <= size.x + 40; x += 40) {
      hills.lineTo(x, 340 + sin(x / 170) * 28);
    }
    hills
      ..lineTo(size.x + 40, 400)
      ..close();
    canvas.drawPath(
      hills,
      Paint()..color = Color(scene == Weather.night ? 0xff455d64 : 0xff96c6a0),
    );
    canvas.drawRect(
      Rect.fromLTWH(0, 400, size.x, max(0, size.y - 400)),
      Paint()..color = Color(scene == Weather.snow ? 0xffd6e8dc : 0xff8ac95c),
    );
    canvas.drawRect(
      Rect.fromLTWH(0, 400, size.x, 8),
      Paint()..color = Color(scene == Weather.snow ? 0xfff5fbff : 0xff4d963d),
    );
    for (double x = -40; x < size.x; x += 48) {
      final offset = (elapsed * 32) % 48;
      canvas.drawLine(
        Offset(x - offset, 445),
        Offset(x + 12 - offset, 445),
        Paint()
          ..color = const Color(0x33649445)
          ..strokeWidth = 3,
      );
    }
    if (scene == Weather.thunder && elapsed % 11 > 9.8 && elapsed % 11 < 10.1) {
      final x = size.x * 0.74;
      canvas.drawPath(
        Path()
          ..moveTo(x, 18)
          ..lineTo(x - 20, 65)
          ..lineTo(x + 3, 60)
          ..lineTo(x - 15, 110),
        Paint()
          ..color = const Color(0xfff8df89)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3,
      );
    }
    if (scene == Weather.rain ||
        scene == Weather.thunder ||
        scene == Weather.snow ||
        scene == Weather.blossom) {
      final rain = scene == Weather.rain || scene == Weather.thunder;
      for (var i = 0; i < 55; i++) {
        final x =
            ((i * 137.1 + elapsed * (rain ? -45 : 18)) % (size.x + 40)) - 20;
        final y = (i * 53.3 + elapsed * (rain ? 230 : 32)) % 397;
        final paint = Paint()
          ..color = rain
              ? const Color(0x8877bddb)
              : scene == Weather.snow
              ? const Color(0xddffffff)
              : const Color(0xddf698bd);
        if (rain) {
          canvas.drawLine(
            Offset(x, y),
            Offset(x - 4, y + 12),
            paint..strokeWidth = 1.2,
          );
        } else {
          canvas.drawOval(
            Rect.fromCenter(
              center: Offset(x + sin(y / 28) * 10, y),
              width: scene == Weather.snow ? 4 : 7,
              height: 4,
            ),
            paint,
          );
        }
      }
    }
  }
}
