import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'tandem_colors.dart';
import 'tandem_glyphs.dart';

/// Palette for the "Tandem" private-space look: warm paper background,
/// deep olive-charcoal ink and soft sage / blush accents.
///
/// This is the source of truth for raw colour values only. Widgets never read
/// it — they go through `Theme.of(context)`, which these constants feed.
abstract final class AppColors {
  // ---------------------------------------------------------------- light --
  static const background = Color(0xFFFAF7F0);
  static const paper = Color(0xFFFBF6EA);

  /// Lit centre and shaded rim of the hero's painted-paper wash.
  static const paperHighlight = Color(0xFFFFFDF6);
  static const paperShade = Color(0xFFF3ECDC);

  /// Soft centre disc a bloom's stamen dots sit on.
  static const pollenCentre = Color(0xFFF6E7B8);

  static const ink = Color(0xFF2F352C);
  static const inkSoft = Color(0xFF6B6F66);
  static const inkFaint = Color(0xFF9A9C93);

  static const sage = Color(0xFFDCE5DC);
  static const sageInk = Color(0xFF3F4A40);

  static const border = Color(0xFFE2DED2);

  static const card = Color(0xFFFFFFFF);
  static const tile = Color(0xFFDFE7DF);
  static const field = Color(0xFFF8F6F0);
  static const disabled = Color(0xFFC9C9C9);

  // Feed surfaces.
  static const feedBackground = Color(0xFFF6F3EC);
  static const bubbleMine = Color(0xFF4B5B45);
  static const bubbleTheirs = Color(0xFFFFFFFF);

  /// Secondary text sitting on top of an outgoing bubble.
  static const onBubbleMineFaint = Color(0xFFCBD5C5);
  static const photoPlaceholder = Color(0xFFE0D6C8);
  static const secretCard = Color(0xFFF1E9DD);
  static const chip = Color(0xFFF4F2EC);
  static const sageDisabled = Color(0xFFB7C1B1);

  // Secret takeover.
  static const secretScrim = Color(0xFF3D4A38);
  static const secretPaper = Color(0xFFFBF4E9);
  static const onScrim = Color(0xFFE6E9E2);
  static const onScrimFaint = Color(0xFF9FA898);

  // Destructive actions.
  static const danger = Color(0xFFC08A8A);
  static const dangerInk = Color(0xFFB87F7F);

  // Illustration palette, shared by both modes — the hero is a painting, not
  // chrome, so it keeps its own light ground in the dark theme.
  static const blush = Color(0xFFF2C0C4);
  static const blushDeep = Color(0xFFE79AA4);
  static const blushPale = Color(0xFFF9DCDC);
  static const leaf = Color(0xFFA3BC9B);
  static const leafDeep = Color(0xFF87A47E);
  static const leafPale = Color(0xFFC6D5BB);
  static const pollen = Color(0xFFC9A227);

  // ----------------------------------------------------------------- dark --
  static const darkBackground = Color(0xFF14170F);
  static const darkFeedBackground = Color(0xFF101309);

  static const darkInk = Color(0xFFECEAE0);
  static const darkInkSoft = Color(0xFFA9AFA2);
  static const darkInkFaint = Color(0xFF7C8377);

  static const darkSage = Color(0xFF2E3A2C);
  static const darkSageInk = Color(0xFFC7D6C2);

  static const darkBorder = Color(0xFF2E332A);
  static const darkCard = Color(0xFF1C2118);
  static const darkTile = Color(0xFF2B3529);
  static const darkField = Color(0xFF23281E);
  static const darkChip = Color(0xFF23281E);
  static const darkDisabled = Color(0xFF3E443A);
  static const darkSageDisabled = Color(0xFF44513F);

  static const darkBubbleMine = Color(0xFF55684E);
  static const darkBubbleTheirs = Color(0xFF22271D);
  static const darkOnBubbleMineFaint = Color(0xFFBECBB8);
  static const darkPhotoPlaceholder = Color(0xFF3A362E);
  static const darkSecretCard = Color(0xFF262117);

  static const darkSecretScrim = Color(0xFF0E120B);
  static const darkDanger = Color(0xFFC9908F);
  static const darkDangerInk = Color(0xFFD09B9A);
}

abstract final class AppTheme {
  /// Every size below is the exact value it replaced in the widget files, so
  /// light mode renders identically to the pre-theme build. Dark mode reuses
  /// this same ramp — it differs in colour only, never in metrics.
  ///
  /// Slots that Material components read are left at their framework defaults
  /// so component sizing does not shift:
  ///   bodyLarge 16 · bodyMedium 14 (bare `Text`) · bodySmall 12 ·
  ///   labelLarge 14 (`TextButton`)
  ///
  /// The remaining slots carry the app ramp, largest to smallest:
  ///   displayLarge   38   big-emoji message (content, so it scales)
  ///   displayMedium  21   code characters
  ///   displaySmall   18   typed confirmation (mono)
  ///   headlineLarge  17   primary body, message text, button labels
  ///   headlineMedium 16.5 secondary body
  ///   headlineSmall  15.5
  ///   titleLarge     15
  ///   titleMedium    14.5
  ///   titleSmall     13.5
  ///   labelMedium    13
  ///   labelSmall     12.5 letterspaced caps
  ///
  /// One slot per *size*; weight variants use `copyWith` at the call site.
  /// The inline styles these replace were merged onto `DefaultTextStyle`, which
  /// `Material` seeds from `bodyMedium` — so each of them silently inherited
  /// Material's `height: 1.43` and `letterSpacing: 0.25`. Every entry carries
  /// those same metrics, otherwise every line reflows tighter than before.
  static const _inheritedHeight = 1.43;
  static const _inheritedLetterSpacing = 0.25;

  static TextTheme _textTheme(Color ink) {
    TextStyle style(
      double size, {
      FontWeight weight = FontWeight.w400,
      double? letterSpacing,
      String? family,
    }) {
      // Weight is applied *after* the family is resolved, not passed into
      // google_fonts. google_fonts encodes the weight in the family name, so
      // asking it for w700 would bind the Bold file — while the inline styles
      // this replaces asked for w700 on the regular family and got a
      // synthesised weight. Binding the real file changes the rendering.
      // See the follow-up note: the bundled SemiBold/Bold files are currently
      // unused for this reason.
      return GoogleFonts.plusJakartaSans(
        fontSize: size,
        color: ink,
        height: _inheritedHeight,
        letterSpacing: letterSpacing ?? _inheritedLetterSpacing,
      ).copyWith(fontWeight: weight, fontFamily: family);
    }

    return TextTheme(
      displayLarge: style(38),
      displayMedium: style(21, weight: FontWeight.w700),
      displaySmall: style(18, letterSpacing: 3, family: 'Menlo'),
      headlineLarge: style(17),
      headlineMedium: style(16.5),
      headlineSmall: style(15.5),
      titleLarge: style(15),
      titleMedium: style(14.5),
      titleSmall: style(13.5),
      bodyLarge: style(16),
      bodyMedium: style(14),
      bodySmall: style(12),
      labelLarge: style(14),
      labelMedium: style(13),
      labelSmall: style(12.5, weight: FontWeight.w600, letterSpacing: 1.6),
    );
  }

  static const _glyphs = TandemGlyphs(
    heart: 19,
    streakFlame: 14,
    chipLock: 15,
    sentLock: 17,
    favouriteSlot: 20,
    sealBadge: 24,
    openedSeal: 24,
    moodTile: 24,
    traySlot: 25,
    revealSeal: 26,
    pickerTile: 30,
  );

  static ThemeData light() {
    const scheme = ColorScheme(
      brightness: Brightness.light,
      primary: AppColors.ink,
      onPrimary: Colors.white,
      secondary: AppColors.sage,
      onSecondary: AppColors.sageInk,
      secondaryContainer: AppColors.sage,
      onSecondaryContainer: AppColors.sageInk,
      tertiary: AppColors.leafDeep,
      onTertiary: Colors.white,
      surface: AppColors.background,
      onSurface: AppColors.ink,
      onSurfaceVariant: AppColors.inkSoft,
      surfaceContainerLowest: AppColors.card,
      surfaceContainerLow: AppColors.chip,
      surfaceContainer: AppColors.chip,
      surfaceContainerHigh: AppColors.field,
      surfaceContainerHighest: AppColors.field,
      outline: AppColors.border,
      outlineVariant: AppColors.field,
      error: AppColors.danger,
      onError: Colors.white,
      errorContainer: AppColors.danger,
      onErrorContainer: AppColors.dangerInk,
    );

    return _build(
      scheme: scheme,
      scaffold: AppColors.background,
      extensions: const [
        TandemColors(
          inkFaint: AppColors.inkFaint,
          disabled: AppColors.disabled,
          sageDisabled: AppColors.sageDisabled,
          tile: AppColors.tile,
          feedBackground: AppColors.feedBackground,
          bubbleMine: AppColors.bubbleMine,
          bubbleTheirs: AppColors.bubbleTheirs,
          onBubbleMineFaint: AppColors.onBubbleMineFaint,
          photoPlaceholder: AppColors.photoPlaceholder,
          secretCard: AppColors.secretCard,
          secretScrim: AppColors.secretScrim,
          secretPaper: AppColors.secretPaper,
          onSecretPaper: AppColors.ink,
          onScrim: AppColors.onScrim,
          onScrimFaint: AppColors.onScrimFaint,
          dangerInk: AppColors.dangerInk,
          paper: AppColors.paper,
          paperHighlight: AppColors.paperHighlight,
          paperShade: AppColors.paperShade,
          pollen: AppColors.pollen,
          pollenCentre: AppColors.pollenCentre,
          blush: AppColors.blush,
          blushDeep: AppColors.blushDeep,
          blushPale: AppColors.blushPale,
          leaf: AppColors.leaf,
          leafDeep: AppColors.leafDeep,
          leafPale: AppColors.leafPale,
        ),
        _glyphs,
      ],
    );
  }

  static ThemeData dark() {
    const scheme = ColorScheme(
      brightness: Brightness.dark,
      primary: AppColors.darkSage,
      onPrimary: AppColors.darkInk,
      secondary: AppColors.darkSage,
      onSecondary: AppColors.darkSageInk,
      secondaryContainer: AppColors.darkSage,
      onSecondaryContainer: AppColors.darkSageInk,
      tertiary: AppColors.leafDeep,
      onTertiary: AppColors.darkInk,
      surface: AppColors.darkBackground,
      onSurface: AppColors.darkInk,
      onSurfaceVariant: AppColors.darkInkSoft,
      surfaceContainerLowest: AppColors.darkCard,
      surfaceContainerLow: AppColors.darkChip,
      surfaceContainer: AppColors.darkChip,
      surfaceContainerHigh: AppColors.darkField,
      surfaceContainerHighest: AppColors.darkField,
      outline: AppColors.darkBorder,
      outlineVariant: AppColors.darkBorder,
      error: AppColors.darkDanger,
      onError: AppColors.darkBackground,
      errorContainer: AppColors.darkDanger,
      onErrorContainer: AppColors.darkDangerInk,
    );

    return _build(
      scheme: scheme,
      scaffold: AppColors.darkBackground,
      extensions: const [
        TandemColors(
          inkFaint: AppColors.darkInkFaint,
          disabled: AppColors.darkDisabled,
          sageDisabled: AppColors.darkSageDisabled,
          tile: AppColors.darkTile,
          feedBackground: AppColors.darkFeedBackground,
          bubbleMine: AppColors.darkBubbleMine,
          bubbleTheirs: AppColors.darkBubbleTheirs,
          onBubbleMineFaint: AppColors.darkOnBubbleMineFaint,
          photoPlaceholder: AppColors.darkPhotoPlaceholder,
          secretCard: AppColors.darkSecretCard,
          secretScrim: AppColors.darkSecretScrim,
          // The torn card is paper; it stays paper in the dark.
          secretPaper: AppColors.secretPaper,
          onSecretPaper: AppColors.ink,
          onScrim: AppColors.onScrim,
          onScrimFaint: AppColors.onScrimFaint,
          dangerInk: AppColors.darkDangerInk,
          paper: AppColors.paper,
          paperHighlight: AppColors.paperHighlight,
          paperShade: AppColors.paperShade,
          pollen: AppColors.pollen,
          pollenCentre: AppColors.pollenCentre,
          blush: AppColors.blush,
          blushDeep: AppColors.blushDeep,
          blushPale: AppColors.blushPale,
          leaf: AppColors.leaf,
          leafDeep: AppColors.leafDeep,
          leafPale: AppColors.leafPale,
        ),
        _glyphs,
      ],
    );
  }

  static ThemeData _build({
    required ColorScheme scheme,
    required Color scaffold,
    required List<ThemeExtension<dynamic>> extensions,
  }) {
    return ThemeData(
      useMaterial3: true,
      brightness: scheme.brightness,
      scaffoldBackgroundColor: scaffold,
      colorScheme: scheme,
      textTheme: _textTheme(scheme.onSurface),
      splashFactory: InkSparkle.splashFactory,
      extensions: extensions,
    );
  }

  /// Emphasis for button labels — binds the real Bold face.
  ///
  /// google_fonts encodes weight in the family name, so `copyWith(fontWeight:)`
  /// alone cannot change the face and the weight is silently dropped. Before
  /// the theme existed, button labels resolved to M3's `labelLarge` (w500) with
  /// the platform emboldening on top; this binds the bundled Bold file instead,
  /// which is correct but renders slightly tighter than that did.
  static TextStyle bold(TextStyle base) => base.copyWith(
    fontFamily: GoogleFonts.plusJakartaSans(
      fontWeight: FontWeight.w700,
    ).fontFamily,
    fontWeight: FontWeight.w700,
  );

  /// High-contrast serif used for the wordmark and other display moments.
  /// Colour comes from the caller's context so it follows the scheme.
  static TextStyle wordmark(BuildContext context, double size) =>
      GoogleFonts.fraunces(
        fontSize: size,
        fontWeight: FontWeight.w400,
        color: Theme.of(context).colorScheme.onSurface,
        height: 1.0,
        letterSpacing: -0.5,
      );
}
