import 'package:flutter/widgets.dart';

/// The kinds of writing the type scale has sizes for: Latin-like,
/// dense (Chinese, Japanese, Korean) and tall (Arabic, Hindi, Thai).
enum TextScript {
  /// Latin, Greek, Cyrillic and the like.
  englishLike,

  /// Chinese, Japanese and Korean.
  dense,

  /// Scripts with tall glyphs: Arabic, Farsi, Hindi, Thai, Bengali, Urdu.
  tall,
}

/// The sizes and fonts the 15 text styles of a theme have when the
/// properties set none: the Material 3 type scale, as a table.
///
/// The names of the text styles (`displayLarge` ... `labelSmall`) are
/// Material 3's, and so are these numbers, so a theme reads the same in an
/// app of any design. Nothing here needs a design library: an app without
/// one has the same styles a `MaterialApp` gives.
///
/// Apps read finished styles with `SpringThemeData.textStyle` and
/// `SpringThemeData.localizedTextStyle`, not this table.
abstract final class SpringTypeScale {
  /// The script of [locale]'s language; Latin-like when [locale] is null
  /// or its language is not one of the dense or tall ones.
  static TextScript scriptOf(Locale? locale) => switch (locale?.languageCode) {
    'ja' || 'zh' || 'ko' => TextScript.dense,
    'ar' || 'fa' || 'hi' || 'th' || 'bn' || 'ur' => TextScript.tall,
    _ => TextScript.englishLike,
  };

  /// The size, weight, line height and letter spacing of text style
  /// [style] (canonical name, `titlelarge`) for [script]; `null` for
  /// another name.
  static TextStyle? geometry(String style, TextScript script) =>
      switch (script) {
        TextScript.englishLike => _englishLike,
        TextScript.dense => _dense,
        TextScript.tall => _tall,
      }[style];

  /// The font family text style [style] (canonical name) has on
  /// [platform] when the theme names none, as Flutter's Material themes
  /// choose it: Roboto on Android, the system fonts of Apple's platforms,
  /// Segoe UI on Windows.
  static String fontFamily(TargetPlatform platform, String style) =>
      switch (platform) {
        TargetPlatform.android || TargetPlatform.fuchsia => 'Roboto',
        TargetPlatform.linux => 'Roboto',
        TargetPlatform.windows => 'Segoe UI',
        TargetPlatform.macOS => '.AppleSystemUIFont',
        TargetPlatform.iOS =>
          _cupertinoDisplay.contains(style)
              ? 'CupertinoSystemDisplay'
              : 'CupertinoSystemText',
      };

  /// The fallback families of [platform] when the theme names none;
  /// `null` where Flutter has none.
  static List<String>? fontFamilyFallback(TargetPlatform platform) =>
      platform == TargetPlatform.linux ? _linuxFallback : null;

  static const _linuxFallback = [
    'Ubuntu',
    'Adwaita Sans',
    'Cantarell',
    'DejaVu Sans',
    'Liberation Sans',
    'Arial',
  ];

  static const _cupertinoDisplay = {
    'displaylarge', 'displaymedium', 'displaysmall', //
    'headlinelarge', 'headlinemedium', 'headlinesmall', //
    'titlelarge',
  };

  static const _englishLike = <String, TextStyle>{
    'displaylarge': TextStyle(
      inherit: false,
      fontSize: 57.0,
      fontWeight: FontWeight.w400,
      letterSpacing: -0.25,
      height: 1.12,
      textBaseline: TextBaseline.alphabetic,
      leadingDistribution: TextLeadingDistribution.even,
    ),
    'displaymedium': TextStyle(
      inherit: false,
      fontSize: 45.0,
      fontWeight: FontWeight.w400,
      letterSpacing: 0.0,
      height: 1.16,
      textBaseline: TextBaseline.alphabetic,
      leadingDistribution: TextLeadingDistribution.even,
    ),
    'displaysmall': TextStyle(
      inherit: false,
      fontSize: 36.0,
      fontWeight: FontWeight.w400,
      letterSpacing: 0.0,
      height: 1.22,
      textBaseline: TextBaseline.alphabetic,
      leadingDistribution: TextLeadingDistribution.even,
    ),
    'headlinelarge': TextStyle(
      inherit: false,
      fontSize: 32.0,
      fontWeight: FontWeight.w400,
      letterSpacing: 0.0,
      height: 1.25,
      textBaseline: TextBaseline.alphabetic,
      leadingDistribution: TextLeadingDistribution.even,
    ),
    'headlinemedium': TextStyle(
      inherit: false,
      fontSize: 28.0,
      fontWeight: FontWeight.w400,
      letterSpacing: 0.0,
      height: 1.29,
      textBaseline: TextBaseline.alphabetic,
      leadingDistribution: TextLeadingDistribution.even,
    ),
    'headlinesmall': TextStyle(
      inherit: false,
      fontSize: 24.0,
      fontWeight: FontWeight.w400,
      letterSpacing: 0.0,
      height: 1.33,
      textBaseline: TextBaseline.alphabetic,
      leadingDistribution: TextLeadingDistribution.even,
    ),
    'titlelarge': TextStyle(
      inherit: false,
      fontSize: 22.0,
      fontWeight: FontWeight.w400,
      letterSpacing: 0.0,
      height: 1.27,
      textBaseline: TextBaseline.alphabetic,
      leadingDistribution: TextLeadingDistribution.even,
    ),
    'titlemedium': TextStyle(
      inherit: false,
      fontSize: 16.0,
      fontWeight: FontWeight.w500,
      letterSpacing: 0.15,
      height: 1.5,
      textBaseline: TextBaseline.alphabetic,
      leadingDistribution: TextLeadingDistribution.even,
    ),
    'titlesmall': TextStyle(
      inherit: false,
      fontSize: 14.0,
      fontWeight: FontWeight.w500,
      letterSpacing: 0.1,
      height: 1.43,
      textBaseline: TextBaseline.alphabetic,
      leadingDistribution: TextLeadingDistribution.even,
    ),
    'bodylarge': TextStyle(
      inherit: false,
      fontSize: 16.0,
      fontWeight: FontWeight.w400,
      letterSpacing: 0.5,
      height: 1.5,
      textBaseline: TextBaseline.alphabetic,
      leadingDistribution: TextLeadingDistribution.even,
    ),
    'bodymedium': TextStyle(
      inherit: false,
      fontSize: 14.0,
      fontWeight: FontWeight.w400,
      letterSpacing: 0.25,
      height: 1.43,
      textBaseline: TextBaseline.alphabetic,
      leadingDistribution: TextLeadingDistribution.even,
    ),
    'bodysmall': TextStyle(
      inherit: false,
      fontSize: 12.0,
      fontWeight: FontWeight.w400,
      letterSpacing: 0.4,
      height: 1.33,
      textBaseline: TextBaseline.alphabetic,
      leadingDistribution: TextLeadingDistribution.even,
    ),
    'labellarge': TextStyle(
      inherit: false,
      fontSize: 14.0,
      fontWeight: FontWeight.w500,
      letterSpacing: 0.1,
      height: 1.43,
      textBaseline: TextBaseline.alphabetic,
      leadingDistribution: TextLeadingDistribution.even,
    ),
    'labelmedium': TextStyle(
      inherit: false,
      fontSize: 12.0,
      fontWeight: FontWeight.w500,
      letterSpacing: 0.5,
      height: 1.33,
      textBaseline: TextBaseline.alphabetic,
      leadingDistribution: TextLeadingDistribution.even,
    ),
    'labelsmall': TextStyle(
      inherit: false,
      fontSize: 11.0,
      fontWeight: FontWeight.w500,
      letterSpacing: 0.5,
      height: 1.45,
      textBaseline: TextBaseline.alphabetic,
      leadingDistribution: TextLeadingDistribution.even,
    ),
  };
  static const _dense = <String, TextStyle>{
    'displaylarge': TextStyle(
      inherit: false,
      fontSize: 57.0,
      fontWeight: FontWeight.w400,
      letterSpacing: -0.25,
      height: 1.12,
      textBaseline: TextBaseline.ideographic,
      leadingDistribution: TextLeadingDistribution.even,
    ),
    'displaymedium': TextStyle(
      inherit: false,
      fontSize: 45.0,
      fontWeight: FontWeight.w400,
      letterSpacing: 0.0,
      height: 1.16,
      textBaseline: TextBaseline.ideographic,
      leadingDistribution: TextLeadingDistribution.even,
    ),
    'displaysmall': TextStyle(
      inherit: false,
      fontSize: 36.0,
      fontWeight: FontWeight.w400,
      letterSpacing: 0.0,
      height: 1.22,
      textBaseline: TextBaseline.ideographic,
      leadingDistribution: TextLeadingDistribution.even,
    ),
    'headlinelarge': TextStyle(
      inherit: false,
      fontSize: 32.0,
      fontWeight: FontWeight.w400,
      letterSpacing: 0.0,
      height: 1.25,
      textBaseline: TextBaseline.ideographic,
      leadingDistribution: TextLeadingDistribution.even,
    ),
    'headlinemedium': TextStyle(
      inherit: false,
      fontSize: 28.0,
      fontWeight: FontWeight.w400,
      letterSpacing: 0.0,
      height: 1.29,
      textBaseline: TextBaseline.ideographic,
      leadingDistribution: TextLeadingDistribution.even,
    ),
    'headlinesmall': TextStyle(
      inherit: false,
      fontSize: 24.0,
      fontWeight: FontWeight.w400,
      letterSpacing: 0.0,
      height: 1.33,
      textBaseline: TextBaseline.ideographic,
      leadingDistribution: TextLeadingDistribution.even,
    ),
    'titlelarge': TextStyle(
      inherit: false,
      fontSize: 22.0,
      fontWeight: FontWeight.w400,
      letterSpacing: 0.0,
      height: 1.27,
      textBaseline: TextBaseline.ideographic,
      leadingDistribution: TextLeadingDistribution.even,
    ),
    'titlemedium': TextStyle(
      inherit: false,
      fontSize: 16.0,
      fontWeight: FontWeight.w500,
      letterSpacing: 0.15,
      height: 1.5,
      textBaseline: TextBaseline.ideographic,
      leadingDistribution: TextLeadingDistribution.even,
    ),
    'titlesmall': TextStyle(
      inherit: false,
      fontSize: 14.0,
      fontWeight: FontWeight.w500,
      letterSpacing: 0.1,
      height: 1.43,
      textBaseline: TextBaseline.ideographic,
      leadingDistribution: TextLeadingDistribution.even,
    ),
    'bodylarge': TextStyle(
      inherit: false,
      fontSize: 16.0,
      fontWeight: FontWeight.w400,
      letterSpacing: 0.5,
      height: 1.5,
      textBaseline: TextBaseline.ideographic,
      leadingDistribution: TextLeadingDistribution.even,
    ),
    'bodymedium': TextStyle(
      inherit: false,
      fontSize: 14.0,
      fontWeight: FontWeight.w400,
      letterSpacing: 0.25,
      height: 1.43,
      textBaseline: TextBaseline.ideographic,
      leadingDistribution: TextLeadingDistribution.even,
    ),
    'bodysmall': TextStyle(
      inherit: false,
      fontSize: 12.0,
      fontWeight: FontWeight.w400,
      letterSpacing: 0.4,
      height: 1.33,
      textBaseline: TextBaseline.ideographic,
      leadingDistribution: TextLeadingDistribution.even,
    ),
    'labellarge': TextStyle(
      inherit: false,
      fontSize: 14.0,
      fontWeight: FontWeight.w500,
      letterSpacing: 0.1,
      height: 1.43,
      textBaseline: TextBaseline.ideographic,
      leadingDistribution: TextLeadingDistribution.even,
    ),
    'labelmedium': TextStyle(
      inherit: false,
      fontSize: 12.0,
      fontWeight: FontWeight.w500,
      letterSpacing: 0.5,
      height: 1.33,
      textBaseline: TextBaseline.ideographic,
      leadingDistribution: TextLeadingDistribution.even,
    ),
    'labelsmall': TextStyle(
      inherit: false,
      fontSize: 11.0,
      fontWeight: FontWeight.w500,
      letterSpacing: 0.5,
      height: 1.45,
      textBaseline: TextBaseline.ideographic,
      leadingDistribution: TextLeadingDistribution.even,
    ),
  };
  static const _tall = <String, TextStyle>{
    'displaylarge': TextStyle(
      inherit: false,
      fontSize: 57.0,
      fontWeight: FontWeight.w400,
      letterSpacing: -0.25,
      height: 1.12,
      textBaseline: TextBaseline.alphabetic,
      leadingDistribution: TextLeadingDistribution.even,
    ),
    'displaymedium': TextStyle(
      inherit: false,
      fontSize: 45.0,
      fontWeight: FontWeight.w400,
      letterSpacing: 0.0,
      height: 1.16,
      textBaseline: TextBaseline.alphabetic,
      leadingDistribution: TextLeadingDistribution.even,
    ),
    'displaysmall': TextStyle(
      inherit: false,
      fontSize: 36.0,
      fontWeight: FontWeight.w400,
      letterSpacing: 0.0,
      height: 1.22,
      textBaseline: TextBaseline.alphabetic,
      leadingDistribution: TextLeadingDistribution.even,
    ),
    'headlinelarge': TextStyle(
      inherit: false,
      fontSize: 32.0,
      fontWeight: FontWeight.w400,
      letterSpacing: 0.0,
      height: 1.25,
      textBaseline: TextBaseline.alphabetic,
      leadingDistribution: TextLeadingDistribution.even,
    ),
    'headlinemedium': TextStyle(
      inherit: false,
      fontSize: 28.0,
      fontWeight: FontWeight.w400,
      letterSpacing: 0.0,
      height: 1.29,
      textBaseline: TextBaseline.alphabetic,
      leadingDistribution: TextLeadingDistribution.even,
    ),
    'headlinesmall': TextStyle(
      inherit: false,
      fontSize: 24.0,
      fontWeight: FontWeight.w400,
      letterSpacing: 0.0,
      height: 1.33,
      textBaseline: TextBaseline.alphabetic,
      leadingDistribution: TextLeadingDistribution.even,
    ),
    'titlelarge': TextStyle(
      inherit: false,
      fontSize: 22.0,
      fontWeight: FontWeight.w400,
      letterSpacing: 0.0,
      height: 1.27,
      textBaseline: TextBaseline.alphabetic,
      leadingDistribution: TextLeadingDistribution.even,
    ),
    'titlemedium': TextStyle(
      inherit: false,
      fontSize: 16.0,
      fontWeight: FontWeight.w500,
      letterSpacing: 0.15,
      height: 1.5,
      textBaseline: TextBaseline.alphabetic,
      leadingDistribution: TextLeadingDistribution.even,
    ),
    'titlesmall': TextStyle(
      inherit: false,
      fontSize: 14.0,
      fontWeight: FontWeight.w500,
      letterSpacing: 0.1,
      height: 1.43,
      textBaseline: TextBaseline.alphabetic,
      leadingDistribution: TextLeadingDistribution.even,
    ),
    'bodylarge': TextStyle(
      inherit: false,
      fontSize: 16.0,
      fontWeight: FontWeight.w400,
      letterSpacing: 0.5,
      height: 1.5,
      textBaseline: TextBaseline.alphabetic,
      leadingDistribution: TextLeadingDistribution.even,
    ),
    'bodymedium': TextStyle(
      inherit: false,
      fontSize: 14.0,
      fontWeight: FontWeight.w400,
      letterSpacing: 0.25,
      height: 1.43,
      textBaseline: TextBaseline.alphabetic,
      leadingDistribution: TextLeadingDistribution.even,
    ),
    'bodysmall': TextStyle(
      inherit: false,
      fontSize: 12.0,
      fontWeight: FontWeight.w400,
      letterSpacing: 0.4,
      height: 1.33,
      textBaseline: TextBaseline.alphabetic,
      leadingDistribution: TextLeadingDistribution.even,
    ),
    'labellarge': TextStyle(
      inherit: false,
      fontSize: 14.0,
      fontWeight: FontWeight.w500,
      letterSpacing: 0.1,
      height: 1.43,
      textBaseline: TextBaseline.alphabetic,
      leadingDistribution: TextLeadingDistribution.even,
    ),
    'labelmedium': TextStyle(
      inherit: false,
      fontSize: 12.0,
      fontWeight: FontWeight.w500,
      letterSpacing: 0.5,
      height: 1.33,
      textBaseline: TextBaseline.alphabetic,
      leadingDistribution: TextLeadingDistribution.even,
    ),
    'labelsmall': TextStyle(
      inherit: false,
      fontSize: 11.0,
      fontWeight: FontWeight.w500,
      letterSpacing: 0.5,
      height: 1.45,
      textBaseline: TextBaseline.alphabetic,
      leadingDistribution: TextLeadingDistribution.even,
    ),
  };
}
