import 'package:flutter/material.dart';

/// Colours with no natural [ColorScheme] role: bubble fills, the secret
/// takeover, the illustration palette, and the third tier of ink.
///
/// Read through `Theme.of(context).extension<ThemeColors>()!` — never from
/// `AppColors`, which exists only to feed this and the [ColorScheme].
@immutable
class ThemeColors extends ThemeExtension<ThemeColors> {
  const ThemeColors({
    required this.inkFaint,
    required this.disabled,
    required this.sageDisabled,
    required this.tile,
    required this.feedBackground,
    required this.bubbleMine,
    required this.bubbleTheirs,
    required this.onBubbleMineFaint,
    required this.photoPlaceholder,
    required this.secretCard,
    required this.secretScrim,
    required this.secretPaper,
    required this.onSecretPaper,
    required this.onScrim,
    required this.onScrimFaint,
    required this.dangerInk,
    required this.paper,
    required this.paperHighlight,
    required this.paperShade,
    required this.pollen,
    required this.pollenCentre,
    required this.blush,
    required this.blushDeep,
    required this.blushPale,
    required this.leaf,
    required this.leafDeep,
    required this.leafPale,
  });

  /// Third tier of ink, below `onSurfaceVariant`.
  final Color inkFaint;

  final Color disabled;
  final Color sageDisabled;
  final Color tile;

  // Feed surfaces.
  final Color feedBackground;
  final Color bubbleMine;
  final Color bubbleTheirs;
  final Color onBubbleMineFaint;
  final Color photoPlaceholder;
  final Color secretCard;

  // Secret takeover.
  final Color secretScrim;
  final Color secretPaper;

  /// Ink on [secretPaper], which stays cream in both modes.
  final Color onSecretPaper;
  final Color onScrim;
  final Color onScrimFaint;

  /// Text tone for destructive rows, distinct from the `error` fill.
  final Color dangerInk;

  // Illustration palette — the painted hero, not UI chrome.
  final Color paper;
  final Color paperHighlight;
  final Color paperShade;
  final Color pollen;
  final Color pollenCentre;
  final Color blush;
  final Color blushDeep;
  final Color blushPale;
  final Color leaf;
  final Color leafDeep;
  final Color leafPale;

  @override
  ThemeColors copyWith({
    Color? inkFaint,
    Color? disabled,
    Color? sageDisabled,
    Color? tile,
    Color? feedBackground,
    Color? bubbleMine,
    Color? bubbleTheirs,
    Color? onBubbleMineFaint,
    Color? photoPlaceholder,
    Color? secretCard,
    Color? secretScrim,
    Color? secretPaper,
    Color? onSecretPaper,
    Color? onScrim,
    Color? onScrimFaint,
    Color? dangerInk,
    Color? paper,
    Color? paperHighlight,
    Color? paperShade,
    Color? pollen,
    Color? pollenCentre,
    Color? blush,
    Color? blushDeep,
    Color? blushPale,
    Color? leaf,
    Color? leafDeep,
    Color? leafPale,
  }) {
    return ThemeColors(
      inkFaint: inkFaint ?? this.inkFaint,
      disabled: disabled ?? this.disabled,
      sageDisabled: sageDisabled ?? this.sageDisabled,
      tile: tile ?? this.tile,
      feedBackground: feedBackground ?? this.feedBackground,
      bubbleMine: bubbleMine ?? this.bubbleMine,
      bubbleTheirs: bubbleTheirs ?? this.bubbleTheirs,
      onBubbleMineFaint: onBubbleMineFaint ?? this.onBubbleMineFaint,
      photoPlaceholder: photoPlaceholder ?? this.photoPlaceholder,
      secretCard: secretCard ?? this.secretCard,
      secretScrim: secretScrim ?? this.secretScrim,
      secretPaper: secretPaper ?? this.secretPaper,
      onSecretPaper: onSecretPaper ?? this.onSecretPaper,
      onScrim: onScrim ?? this.onScrim,
      onScrimFaint: onScrimFaint ?? this.onScrimFaint,
      dangerInk: dangerInk ?? this.dangerInk,
      paper: paper ?? this.paper,
      paperHighlight: paperHighlight ?? this.paperHighlight,
      paperShade: paperShade ?? this.paperShade,
      pollen: pollen ?? this.pollen,
      pollenCentre: pollenCentre ?? this.pollenCentre,
      blush: blush ?? this.blush,
      blushDeep: blushDeep ?? this.blushDeep,
      blushPale: blushPale ?? this.blushPale,
      leaf: leaf ?? this.leaf,
      leafDeep: leafDeep ?? this.leafDeep,
      leafPale: leafPale ?? this.leafPale,
    );
  }

  @override
  ThemeColors lerp(ThemeExtension<ThemeColors>? other, double t) {
    if (other is! ThemeColors) return this;
    return ThemeColors(
      inkFaint: Color.lerp(inkFaint, other.inkFaint, t)!,
      disabled: Color.lerp(disabled, other.disabled, t)!,
      sageDisabled: Color.lerp(sageDisabled, other.sageDisabled, t)!,
      tile: Color.lerp(tile, other.tile, t)!,
      feedBackground: Color.lerp(feedBackground, other.feedBackground, t)!,
      bubbleMine: Color.lerp(bubbleMine, other.bubbleMine, t)!,
      bubbleTheirs: Color.lerp(bubbleTheirs, other.bubbleTheirs, t)!,
      onBubbleMineFaint: Color.lerp(
        onBubbleMineFaint,
        other.onBubbleMineFaint,
        t,
      )!,
      photoPlaceholder: Color.lerp(
        photoPlaceholder,
        other.photoPlaceholder,
        t,
      )!,
      secretCard: Color.lerp(secretCard, other.secretCard, t)!,
      secretScrim: Color.lerp(secretScrim, other.secretScrim, t)!,
      secretPaper: Color.lerp(secretPaper, other.secretPaper, t)!,
      onSecretPaper: Color.lerp(onSecretPaper, other.onSecretPaper, t)!,
      onScrim: Color.lerp(onScrim, other.onScrim, t)!,
      onScrimFaint: Color.lerp(onScrimFaint, other.onScrimFaint, t)!,
      dangerInk: Color.lerp(dangerInk, other.dangerInk, t)!,
      paper: Color.lerp(paper, other.paper, t)!,
      paperHighlight: Color.lerp(paperHighlight, other.paperHighlight, t)!,
      paperShade: Color.lerp(paperShade, other.paperShade, t)!,
      pollen: Color.lerp(pollen, other.pollen, t)!,
      pollenCentre: Color.lerp(pollenCentre, other.pollenCentre, t)!,
      blush: Color.lerp(blush, other.blush, t)!,
      blushDeep: Color.lerp(blushDeep, other.blushDeep, t)!,
      blushPale: Color.lerp(blushPale, other.blushPale, t)!,
      leaf: Color.lerp(leaf, other.leaf, t)!,
      leafDeep: Color.lerp(leafDeep, other.leafDeep, t)!,
      leafPale: Color.lerp(leafPale, other.leafPale, t)!,
    );
  }
}

/// Convenience accessor for the palette that has no `ColorScheme` home.
extension ThemeColorsX on BuildContext {
  ThemeColors get palette => Theme.of(this).extension<ThemeColors>()!;
}
