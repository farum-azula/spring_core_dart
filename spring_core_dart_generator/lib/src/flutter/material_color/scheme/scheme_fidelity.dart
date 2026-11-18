// Ported from material_color_utilities 0.13.0 (https://github.com/material-foundation/material-color-utilities),
// Copyright 2021-2023 Google LLC, Apache License 2.0 (see NOTICE). Changed: lives in this package, no
// third-party imports; only what the page loader needs.
// ignore_for_file: type=lint

// Copyright 2022 Google LLC
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//      http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

library;

import 'dart:math' as math;

import '../dislike/dislike_analyzer.dart';
import '../dynamiccolor/dynamic_scheme.dart';
import '../dynamiccolor/variant.dart';
import '../palettes/tonal_palette.dart';
import '../temperature/temperature_cache.dart';

/// A scheme that places the source color in [Scheme.primaryContainer].
///
/// Primary Container is the source color, adjusted for color relativity.
/// It maintains constant appearance in light mode and dark mode.
/// This adds ~5 tone in light mode, and subtracts ~5 tone in dark mode.
///
/// Tertiary Container is the complement to the source color, using
/// [TemperatureCache]. It also maintains constant appearance.
class SchemeFidelity extends DynamicScheme {
  SchemeFidelity({
    required super.sourceColorHct,
    required super.isDark,
    required super.contrastLevel,
  }) : super(
         variant: Variant.fidelity,
         primaryPalette: TonalPalette.of(
           sourceColorHct.hue,
           sourceColorHct.chroma,
         ),
         secondaryPalette: TonalPalette.of(
           sourceColorHct.hue,
           math.max(sourceColorHct.chroma - 32.0, sourceColorHct.chroma * 0.5),
         ),
         tertiaryPalette: TonalPalette.fromHct(
           DislikeAnalyzer.fixIfDisliked(
             TemperatureCache(sourceColorHct).complement,
           ),
         ),
         neutralPalette: TonalPalette.of(
           sourceColorHct.hue,
           sourceColorHct.chroma / 8.0,
         ),
         neutralVariantPalette: TonalPalette.of(
           sourceColorHct.hue,
           (sourceColorHct.chroma / 8.0) + 4.0,
         ),
       );
}
