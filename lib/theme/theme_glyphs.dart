import 'package:flutter/material.dart';

/// Sizes for glyphs that are *chrome* — UI furniture that happens to be
/// rendered as a character rather than an icon asset.
///
/// These are deliberately not in the [TextTheme]: they are not typography, and
/// they must not grow with the user's text scale or they would burst the fixed
/// circles and grid tiles they sit in. Render them with [Glyph], which pins the
/// scale.
///
/// Emoji that carry content — a big-emoji message, a reaction, a mood — stay in
/// the [TextTheme] and scale normally.
@immutable
class ThemeGlyphs extends ThemeExtension<ThemeGlyphs> {
  const ThemeGlyphs({
    required this.heart,
    required this.streakFlame,
    required this.chipLock,
    required this.sentLock,
    required this.favouriteSlot,
    required this.sealBadge,
    required this.openedSeal,
    required this.moodTile,
    required this.traySlot,
    required this.revealSeal,
    required this.pickerTile,
  });

  /// Decorative heart under the sign-in actions.
  final double heart;

  /// Flame in the streak pill.
  final double streakFlame;

  /// Padlock leading the compose "Secret" chip.
  final double chipLock;

  /// Padlock on the outgoing "Secret sent" bubble.
  final double sentLock;

  /// Emoji in a settings favourite slot (fixed 38px circle).
  final double favouriteSlot;

  /// Padlock in the sealed card's circle (fixed 62px).
  final double sealBadge;

  /// Padlock in the "they read it" dialog (fixed 64px).
  final double openedSeal;

  /// Emoji in a mood grid tile.
  final double moodTile;

  /// Emoji in the quick-reaction tray.
  final double traySlot;

  /// Padlock on the full-screen reveal (fixed 68px).
  final double revealSeal;

  /// Emoji in the reaction picker grid.
  final double pickerTile;

  @override
  ThemeGlyphs copyWith({
    double? heart,
    double? streakFlame,
    double? chipLock,
    double? sentLock,
    double? favouriteSlot,
    double? sealBadge,
    double? openedSeal,
    double? moodTile,
    double? traySlot,
    double? revealSeal,
    double? pickerTile,
  }) {
    return ThemeGlyphs(
      heart: heart ?? this.heart,
      streakFlame: streakFlame ?? this.streakFlame,
      chipLock: chipLock ?? this.chipLock,
      sentLock: sentLock ?? this.sentLock,
      favouriteSlot: favouriteSlot ?? this.favouriteSlot,
      sealBadge: sealBadge ?? this.sealBadge,
      openedSeal: openedSeal ?? this.openedSeal,
      moodTile: moodTile ?? this.moodTile,
      traySlot: traySlot ?? this.traySlot,
      revealSeal: revealSeal ?? this.revealSeal,
      pickerTile: pickerTile ?? this.pickerTile,
    );
  }

  @override
  ThemeGlyphs lerp(ThemeExtension<ThemeGlyphs>? other, double t) {
    if (other is! ThemeGlyphs) return this;
    return ThemeGlyphs(
      heart: lerpDouble(heart, other.heart, t),
      streakFlame: lerpDouble(streakFlame, other.streakFlame, t),
      chipLock: lerpDouble(chipLock, other.chipLock, t),
      sentLock: lerpDouble(sentLock, other.sentLock, t),
      favouriteSlot: lerpDouble(favouriteSlot, other.favouriteSlot, t),
      sealBadge: lerpDouble(sealBadge, other.sealBadge, t),
      openedSeal: lerpDouble(openedSeal, other.openedSeal, t),
      moodTile: lerpDouble(moodTile, other.moodTile, t),
      traySlot: lerpDouble(traySlot, other.traySlot, t),
      revealSeal: lerpDouble(revealSeal, other.revealSeal, t),
      pickerTile: lerpDouble(pickerTile, other.pickerTile, t),
    );
  }

  static double lerpDouble(double a, double b, double t) => a + (b - a) * t;
}

extension ThemeGlyphsX on BuildContext {
  ThemeGlyphs get glyphs => Theme.of(this).extension<ThemeGlyphs>()!;
}

/// Renders a chrome glyph at a fixed size, immune to the user's text scale so
/// it cannot outgrow the circle or tile it sits in.
class Glyph extends StatelessWidget {
  const Glyph(this.character, {super.key, required this.size});

  final String character;
  final double size;

  @override
  Widget build(BuildContext context) {
    return MediaQuery(
      data: MediaQuery.of(context).copyWith(textScaler: TextScaler.noScaling),
      child: Text(character, style: TextStyle(fontSize: size)),
    );
  }
}
