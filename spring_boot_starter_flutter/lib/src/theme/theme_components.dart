import 'package:flutter/material.dart';
import 'package:spring_boot_starter_flutter/src/theme/theme_reader.dart';
import 'package:spring_boot_starter_flutter/src/theme/theme_values.dart';

/// How a component of `ThemeData` is made from its properties: [apply]
/// reads them with a [ThemeReader], by Flutter's own property names, and
/// returns the theme with the component's theme data set.
///
/// The mapping of a component is its constructor call, one reader per
/// parameter, so the readers' types do the work (colors, shapes, border
/// sides, insets, text styles, enums, ..., and a value per state for
/// what Flutter models as a `WidgetStateProperty`). The valid keys of a
/// component are the ones its [apply] reads, which is also what the
/// reference in `docs/configuration.md` is generated from. Internal to
/// the starter.
final class ThemeComponent {
  /// A component called [name] in kebab case.
  const ThemeComponent(
    this.name,
    this.apply, {
    this.shapeToken,
    this.topShape = false,
    this.base,
  });

  /// The key below `components` (`app-bar`).
  final String name;

  /// Sets the component's theme data in [theme] from [r]; [other] reads
  /// another component (the `button` every button starts from).
  final ThemeData Function(
    ThemeData theme,
    ThemeReader r,
    ThemeReader Function(String component) other,
  )
  apply;

  /// The Material 3 shape token the component's shape follows.
  final String? shapeToken;

  /// Whether the shape rounds the top corners only.
  final bool topShape;

  /// The component this one starts from (`button`): it is themed when that
  /// one is too.
  final String? base;
}

enum _InputStyle { outline, underline, filled }

/// A `ButtonStyle` from the properties of [r]: every property of the
/// class, plus `min-height` and `border-color`.
ButtonStyle buttonStyleOf(ThemeReader r) {
  final minHeight = r.number('minHeight');
  final borderColor = r.color('borderColor');
  return ButtonStyle(
    textStyle: r.stateText('textStyle'),
    backgroundColor: r.stateColor('backgroundColor'),
    foregroundColor: r.stateColor('foregroundColor'),
    overlayColor: r.stateColor('overlayColor'),
    shadowColor: r.stateColor('shadowColor'),
    surfaceTintColor: r.stateColor('surfaceTintColor'),
    elevation: r.stateElevation('elevation'),
    padding: r.stateInsets('padding'),
    minimumSize:
        r.stateSize('minimumSize') ??
        (minHeight == null
            ? null
            : WidgetStatePropertyAll<Size?>(Size(0, minHeight))),
    fixedSize: r.stateSize('fixedSize'),
    maximumSize: r.stateSize('maximumSize'),
    iconColor: r.stateColor('iconColor'),
    iconSize: r.stateNumber('iconSize'),
    iconAlignment: r.choice('iconAlignment', IconAlignment.values),
    side:
        r.stateSide('side') ??
        (borderColor == null
            ? null
            : WidgetStatePropertyAll<BorderSide?>(
                BorderSide(color: borderColor),
              )),
    shape: r.stateShape('shape'),
    mouseCursor: r.stateCursor('mouseCursor'),
    visualDensity: r.density('visualDensity'),
    tapTargetSize: r.choice('tapTargetSize', MaterialTapTargetSize.values),
    animationDuration: r.duration('animationDuration'),
    enableFeedback: r.flag('enableFeedback'),
    alignment: r.alignment('alignment'),
    splashFactory: r.splash('splashFactory'),
  );
}

/// A `MenuStyle` from the properties of [r].
MenuStyle menuStyleOf(ThemeReader r) => MenuStyle(
  backgroundColor: r.stateColor('backgroundColor'),
  shadowColor: r.stateColor('shadowColor'),
  surfaceTintColor: r.stateColor('surfaceTintColor'),
  elevation: r.stateElevation('elevation'),
  padding: r.stateInsets('padding'),
  minimumSize: r.stateSize('minimumSize'),
  fixedSize: r.stateSize('fixedSize'),
  maximumSize: r.stateSize('maximumSize'),
  side: r.stateSide('side'),
  shape: r.stateShape('shape'),
  mouseCursor: r.stateCursor('mouseCursor'),
  visualDensity: r.density('visualDensity'),
  alignment: r.alignment('alignment'),
);

/// An `InputDecorationThemeData` from the properties of [r]: the
/// component's `style`, `shape`, `filled`, `fill-color` and
/// `content-padding`, and the other properties of the class.
InputDecorationThemeData inputDecorationOf(ThemeReader r) {
  final style = r.choice('style', _InputStyle.values);
  final shape = r.shape('shape');
  final radius = shape is RoundedRectangleBorder
      ? shape.borderRadius as BorderRadius
      : shape is StadiumBorder
      ? BorderRadius.circular(999)
      : BorderRadius.circular(r.theme.shape('extrasmall'));
  final border =
      r.inputBorder('border') ??
      switch (style) {
        _InputStyle.outline => OutlineInputBorder(borderRadius: radius),
        _InputStyle.underline || _InputStyle.filled => UnderlineInputBorder(
          borderRadius: style == _InputStyle.filled
              ? BorderRadius.vertical(top: radius.topLeft)
              : BorderRadius.zero,
        ),
        null => shape == null ? null : OutlineInputBorder(borderRadius: radius),
      };
  return InputDecorationThemeData(
    border: border,
    filled: style == _InputStyle.filled || (r.flag('filled') ?? false),
    fillColor: r.color('fillColor'),
    contentPadding: r.insets('contentPadding'),
    labelStyle: r.text('labelStyle'),
    floatingLabelStyle: r.text('floatingLabelStyle'),
    helperStyle: r.text('helperStyle'),
    helperMaxLines: r.count('helperMaxLines'),
    hintStyle: r.text('hintStyle'),
    hintFadeDuration: r.duration('hintFadeDuration'),
    hintMaxLines: r.count('hintMaxLines'),
    errorStyle: r.text('errorStyle'),
    errorMaxLines: r.count('errorMaxLines'),
    floatingLabelBehavior:
        r.choice('floatingLabelBehavior', FloatingLabelBehavior.values) ??
        FloatingLabelBehavior.auto,
    isDense: r.flag('isDense') ?? false,
    isCollapsed: r.flag('isCollapsed') ?? false,
    iconColor: r.color('iconColor'),
    prefixStyle: r.text('prefixStyle'),
    prefixIconColor: r.color('prefixIconColor'),
    prefixIconConstraints: r.constraints('prefixIconConstraints'),
    suffixStyle: r.text('suffixStyle'),
    suffixIconColor: r.color('suffixIconColor'),
    suffixIconConstraints: r.constraints('suffixIconConstraints'),
    counterStyle: r.text('counterStyle'),
    outlineBorder: r.side('outlineBorder'),
    activeIndicatorBorder: r.side('activeIndicatorBorder'),
    focusColor: r.color('focusColor'),
    hoverColor: r.color('hoverColor'),
    errorBorder: r.inputBorder('errorBorder'),
    focusedBorder: r.inputBorder('focusedBorder'),
    focusedErrorBorder: r.inputBorder('focusedErrorBorder'),
    disabledBorder: r.inputBorder('disabledBorder'),
    enabledBorder: r.inputBorder('enabledBorder'),
    alignLabelWithHint: r.flag('alignLabelWithHint') ?? false,
    constraints: r.constraints('constraints'),
    visualDensity: r.density('visualDensity'),
  );
}

/// Every component of `ThemeData` the properties can adjust under
/// `components.*`, by canonical name.
final themeComponents = <String, ThemeComponent>{
  for (final component in _components)
    ThemeValues.canonical(component.name): component,
};

/// The names of [themeComponents], in kebab case, in the order of the
/// reference.
List<String> get themeComponentNames => [
  for (final component in _components) component.name,
];

ThemeData _buttons(
  ThemeData t,
  ThemeReader r,
  ThemeReader Function(String) other,
  ThemeData Function(ThemeData, ButtonStyle) set, {
  bool inherit = true,
}) {
  final own = buttonStyleOf(r);
  if (!inherit) {
    return set(t, own);
  }
  final base = other('button');
  // The kind's own values win over the shared `button` ones.
  return set(t, base.has ? own.merge(buttonStyleOf(base)) : own);
}

// A nested group's value, or `null` when the group has no properties
// (the group is read either way, which lists its keys).
T? _ifSet<T>(ThemeReader group, T Function(ThemeReader) read) {
  final value = read(group);
  return group.has ? value : null;
}

final _components = <ThemeComponent>[
  ThemeComponent(
    'app-bar',
    (t, r, _) => t.copyWith(
      appBarTheme: AppBarTheme(
        backgroundColor: r.color('backgroundColor'),
        foregroundColor: r.color('foregroundColor'),
        elevation: r.elevation('elevation'),
        scrolledUnderElevation: r.elevation('scrolledUnderElevation'),
        shadowColor: r.color('shadowColor'),
        surfaceTintColor: r.color('surfaceTintColor'),
        shape: r.shape('shape'),
        iconTheme: r.icon('iconTheme'),
        actionsIconTheme: r.icon('actionsIconTheme'),
        centerTitle: r.flag('centerTitle'),
        titleSpacing: r.number('titleSpacing'),
        leadingWidth: r.number('leadingWidth'),
        toolbarHeight: r.number('toolbarHeight'),
        toolbarTextStyle: r.text('toolbarTextStyle'),
        titleTextStyle: r.text('titleTextStyle'),
        systemOverlayStyle: r.overlayStyle('systemOverlayStyle'),
        actionsPadding: r.insets('actionsPadding'),
      ),
    ),
  ),
  ThemeComponent(
    'badge',
    (t, r, _) => t.copyWith(
      badgeTheme: BadgeThemeData(
        backgroundColor: r.color('backgroundColor'),
        textColor: r.color('textColor'),
        smallSize: r.number('smallSize'),
        largeSize: r.number('largeSize'),
        textStyle: r.text('textStyle'),
        padding: r.insets('padding'),
        alignment: r.alignment('alignment'),
        offset: r.offset('offset'),
      ),
    ),
  ),
  ThemeComponent(
    'banner',
    (t, r, _) => t.copyWith(
      bannerTheme: MaterialBannerThemeData(
        backgroundColor: r.color('backgroundColor'),
        surfaceTintColor: r.color('surfaceTintColor'),
        shadowColor: r.color('shadowColor'),
        dividerColor: r.color('dividerColor'),
        contentTextStyle: r.text('contentTextStyle'),
        elevation: r.elevation('elevation'),
        padding: r.insets('padding'),
        leadingPadding: r.insets('leadingPadding'),
      ),
    ),
  ),
  ThemeComponent(
    'bottom-app-bar',
    (t, r, _) => t.copyWith(
      bottomAppBarTheme: BottomAppBarThemeData(
        color: r.color('color'),
        elevation: r.elevation('elevation'),
        height: r.number('height'),
        surfaceTintColor: r.color('surfaceTintColor'),
        shadowColor: r.color('shadowColor'),
        padding: r.insets('padding'),
      ),
    ),
  ),
  ThemeComponent(
    'bottom-navigation-bar',
    (t, r, _) => t.copyWith(
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: r.color('backgroundColor'),
        elevation: r.elevation('elevation'),
        selectedIconTheme: r.icon('selectedIconTheme'),
        unselectedIconTheme: r.icon('unselectedIconTheme'),
        selectedItemColor: r.color('selectedItemColor'),
        unselectedItemColor: r.color('unselectedItemColor'),
        selectedLabelStyle: r.text('selectedLabelStyle'),
        unselectedLabelStyle: r.text('unselectedLabelStyle'),
        showSelectedLabels: r.flag('showSelectedLabels'),
        showUnselectedLabels: r.flag('showUnselectedLabels'),
        type: r.choice('type', BottomNavigationBarType.values),
        enableFeedback: r.flag('enableFeedback'),
        landscapeLayout: r.choice(
          'landscapeLayout',
          BottomNavigationBarLandscapeLayout.values,
        ),
        mouseCursor: r.stateCursor('mouseCursor'),
      ),
    ),
  ),
  ThemeComponent(
    'bottom-sheet',
    topShape: true,
    shapeToken: 'extralarge',
    (t, r, _) => t.copyWith(
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: r.color('backgroundColor'),
        surfaceTintColor: r.color('surfaceTintColor'),
        elevation: r.elevation('elevation'),
        modalBackgroundColor: r.color('modalBackgroundColor'),
        modalBarrierColor: r.color('modalBarrierColor'),
        shadowColor: r.color('shadowColor'),
        modalElevation: r.elevation('modalElevation'),
        shape: r.shape('shape'),
        showDragHandle: r.flag('showDragHandle'),
        dragHandleColor: r.color('dragHandleColor'),
        dragHandleSize: r.size('dragHandleSize'),
        clipBehavior: r.choice('clipBehavior', Clip.values),
        constraints: r.constraints('constraints'),
      ),
    ),
  ),
  ThemeComponent(
    'button',
    shapeToken: 'full',
    (t, r, _) {
      // Every button starts from this one: read for its keys here, applied
      // by the four buttons below.
      buttonStyleOf(r);
      return t;
    },
  ),
  ThemeComponent(
    'elevated-button',
    base: 'button',
    (t, r, other) => _buttons(
      t,
      r,
      other,
      (t, s) =>
          t.copyWith(elevatedButtonTheme: ElevatedButtonThemeData(style: s)),
    ),
  ),
  ThemeComponent(
    'filled-button',
    base: 'button',
    (t, r, other) => _buttons(
      t,
      r,
      other,
      (t, s) => t.copyWith(filledButtonTheme: FilledButtonThemeData(style: s)),
    ),
  ),
  ThemeComponent(
    'outlined-button',
    base: 'button',
    (t, r, other) => _buttons(
      t,
      r,
      other,
      (t, s) =>
          t.copyWith(outlinedButtonTheme: OutlinedButtonThemeData(style: s)),
    ),
  ),
  ThemeComponent(
    'text-button',
    base: 'button',
    (t, r, other) => _buttons(
      t,
      r,
      other,
      (t, s) => t.copyWith(textButtonTheme: TextButtonThemeData(style: s)),
    ),
  ),
  ThemeComponent(
    'icon-button',
    (t, r, other) => _buttons(
      t,
      r,
      other,
      (t, s) => t.copyWith(iconButtonTheme: IconButtonThemeData(style: s)),
      inherit: false,
    ),
  ),
  ThemeComponent(
    'segmented-button',
    (t, r, other) => _buttons(
      t,
      r,
      other,
      (t, s) =>
          t.copyWith(segmentedButtonTheme: SegmentedButtonThemeData(style: s)),
      inherit: false,
    ),
  ),
  ThemeComponent(
    'menu-button',
    (t, r, other) => _buttons(
      t,
      r,
      other,
      (t, s) => t.copyWith(menuButtonTheme: MenuButtonThemeData(style: s)),
      inherit: false,
    ),
  ),
  ThemeComponent(
    'toggle-buttons',
    (t, r, _) => t.copyWith(
      toggleButtonsTheme: ToggleButtonsThemeData(
        textStyle: r.text('textStyle'),
        constraints: r.constraints('constraints'),
        color: r.color('color'),
        selectedColor: r.color('selectedColor'),
        disabledColor: r.color('disabledColor'),
        fillColor: r.color('fillColor'),
        focusColor: r.color('focusColor'),
        highlightColor: r.color('highlightColor'),
        splashColor: r.color('splashColor'),
        hoverColor: r.color('hoverColor'),
        borderColor: r.color('borderColor'),
        selectedBorderColor: r.color('selectedBorderColor'),
        disabledBorderColor: r.color('disabledBorderColor'),
        borderWidth: r.number('borderWidth'),
        borderRadius: r.borderRadius('borderRadius'),
      ),
    ),
  ),
  ThemeComponent(
    'floating-action-button',
    shapeToken: 'large',
    (t, r, _) => t.copyWith(
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        foregroundColor: r.color('foregroundColor'),
        backgroundColor: r.color('backgroundColor'),
        focusColor: r.color('focusColor'),
        hoverColor: r.color('hoverColor'),
        splashColor: r.color('splashColor'),
        elevation: r.elevation('elevation'),
        focusElevation: r.elevation('focusElevation'),
        hoverElevation: r.elevation('hoverElevation'),
        disabledElevation: r.elevation('disabledElevation'),
        highlightElevation: r.elevation('highlightElevation'),
        shape: r.shape('shape'),
        enableFeedback: r.flag('enableFeedback'),
        iconSize: r.number('iconSize'),
        sizeConstraints: r.constraints('sizeConstraints'),
        smallSizeConstraints: r.constraints('smallSizeConstraints'),
        largeSizeConstraints: r.constraints('largeSizeConstraints'),
        extendedSizeConstraints: r.constraints('extendedSizeConstraints'),
        extendedIconLabelSpacing: r.number('extendedIconLabelSpacing'),
        extendedPadding: r.insets('extendedPadding'),
        extendedTextStyle: r.text('extendedTextStyle'),
        mouseCursor: r.stateCursor('mouseCursor'),
      ),
    ),
  ),
  ThemeComponent(
    'card',
    shapeToken: 'medium',
    (t, r, _) => t.copyWith(
      cardTheme: CardThemeData(
        clipBehavior: r.choice('clipBehavior', Clip.values),
        color: r.color('color'),
        shadowColor: r.color('shadowColor'),
        surfaceTintColor: r.color('surfaceTintColor'),
        elevation: r.elevation('elevation'),
        margin: r.insets('margin'),
        shape: r.shape('shape'),
      ),
    ),
  ),
  ThemeComponent(
    'carousel-view',
    (t, r, _) => t.copyWith(
      carouselViewTheme: CarouselViewThemeData(
        padding: r.insets('padding'),
        backgroundColor: r.color('backgroundColor'),
        elevation: r.elevation('elevation'),
        shape: r.shape('shape'),
        itemClipBehavior: r.choice('itemClipBehavior', Clip.values),
        overlayColor: r.stateColor('overlayColor'),
      ),
    ),
  ),
  ThemeComponent(
    'checkbox',
    (t, r, _) => t.copyWith(
      checkboxTheme: CheckboxThemeData(
        mouseCursor: r.stateCursor('mouseCursor'),
        fillColor: r.stateColor('fillColor'),
        checkColor: r.stateColor('checkColor'),
        overlayColor: r.stateColor('overlayColor'),
        splashRadius: r.number('splashRadius'),
        materialTapTargetSize: r.choice(
          'materialTapTargetSize',
          MaterialTapTargetSize.values,
        ),
        visualDensity: r.density('visualDensity'),
        shape: r.shape('shape'),
        side: r.side('side'),
      ),
    ),
  ),
  ThemeComponent(
    'chip',
    shapeToken: 'small',
    (t, r, _) => t.copyWith(
      chipTheme: ChipThemeData(
        color: r.stateColor('color'),
        backgroundColor: r.color('backgroundColor'),
        deleteIconColor: r.color('deleteIconColor'),
        disabledColor: r.color('disabledColor'),
        selectedColor: r.color('selectedColor'),
        secondarySelectedColor: r.color('secondarySelectedColor'),
        shadowColor: r.color('shadowColor'),
        surfaceTintColor: r.color('surfaceTintColor'),
        selectedShadowColor: r.color('selectedShadowColor'),
        showCheckmark: r.flag('showCheckmark'),
        checkmarkColor: r.color('checkmarkColor'),
        labelPadding: r.insets('labelPadding'),
        padding: r.insets('padding'),
        side: r.side('side'),
        shape: r.shape('shape'),
        labelStyle: r.text('labelStyle'),
        secondaryLabelStyle: r.text('secondaryLabelStyle'),
        elevation: r.elevation('elevation'),
        pressElevation: r.elevation('pressElevation'),
        iconTheme: r.icon('iconTheme'),
        avatarBoxConstraints: r.constraints('avatarBoxConstraints'),
        deleteIconBoxConstraints: r.constraints('deleteIconBoxConstraints'),
      ),
    ),
  ),
  ThemeComponent(
    'data-table',
    (t, r, _) => t.copyWith(
      dataTableTheme: DataTableThemeData(
        decoration: r.decoration('decoration'),
        dataRowColor: r.stateColor('dataRowColor'),
        dataRowMinHeight: r.number('dataRowMinHeight'),
        dataRowMaxHeight: r.number('dataRowMaxHeight'),
        dataTextStyle: r.text('dataTextStyle'),
        headingRowColor: r.stateColor('headingRowColor'),
        headingRowHeight: r.number('headingRowHeight'),
        headingTextStyle: r.text('headingTextStyle'),
        horizontalMargin: r.number('horizontalMargin'),
        columnSpacing: r.number('columnSpacing'),
        dividerThickness: r.number('dividerThickness'),
        checkboxHorizontalMargin: r.number('checkboxHorizontalMargin'),
        headingCellCursor: r.stateCursor('headingCellCursor'),
        dataRowCursor: r.stateCursor('dataRowCursor'),
        headingRowAlignment: r.choice(
          'headingRowAlignment',
          MainAxisAlignment.values,
        ),
      ),
    ),
  ),
  ThemeComponent(
    'date-picker',
    (t, r, _) => t.copyWith(
      datePickerTheme: DatePickerThemeData(
        backgroundColor: r.color('backgroundColor'),
        elevation: r.elevation('elevation'),
        shadowColor: r.color('shadowColor'),
        surfaceTintColor: r.color('surfaceTintColor'),
        shape: r.shape('shape'),
        headerBackgroundColor: r.color('headerBackgroundColor'),
        headerForegroundColor: r.color('headerForegroundColor'),
        headerHeadlineStyle: r.text('headerHeadlineStyle'),
        headerHelpStyle: r.text('headerHelpStyle'),
        weekdayStyle: r.text('weekdayStyle'),
        dayStyle: r.text('dayStyle'),
        dayForegroundColor: r.stateColor('dayForegroundColor'),
        dayBackgroundColor: r.stateColor('dayBackgroundColor'),
        dayOverlayColor: r.stateColor('dayOverlayColor'),
        dayShape: r.stateShape('dayShape'),
        todayForegroundColor: r.stateColor('todayForegroundColor'),
        todayBackgroundColor: r.stateColor('todayBackgroundColor'),
        todayBorder: r.side('todayBorder'),
        yearStyle: r.text('yearStyle'),
        yearForegroundColor: r.stateColor('yearForegroundColor'),
        yearBackgroundColor: r.stateColor('yearBackgroundColor'),
        yearOverlayColor: r.stateColor('yearOverlayColor'),
        yearShape: r.stateShape('yearShape'),
        rangePickerBackgroundColor: r.color('rangePickerBackgroundColor'),
        rangePickerElevation: r.elevation('rangePickerElevation'),
        rangePickerShadowColor: r.color('rangePickerShadowColor'),
        rangePickerSurfaceTintColor: r.color('rangePickerSurfaceTintColor'),
        rangePickerShape: r.shape('rangePickerShape'),
        rangePickerHeaderBackgroundColor: r.color(
          'rangePickerHeaderBackgroundColor',
        ),
        rangePickerHeaderForegroundColor: r.color(
          'rangePickerHeaderForegroundColor',
        ),
        rangePickerHeaderHeadlineStyle: r.text(
          'rangePickerHeaderHeadlineStyle',
        ),
        rangePickerHeaderHelpStyle: r.text('rangePickerHeaderHelpStyle'),
        rangeSelectionBackgroundColor: r.color('rangeSelectionBackgroundColor'),
        rangeSelectionOverlayColor: r.stateColor('rangeSelectionOverlayColor'),
        dividerColor: r.color('dividerColor'),
        inputDecorationTheme: _ifSet(
          r.group('inputDecoration'),
          inputDecorationOf,
        ),
        cancelButtonStyle: _ifSet(r.group('cancelButtonStyle'), buttonStyleOf),
        confirmButtonStyle: _ifSet(
          r.group('confirmButtonStyle'),
          buttonStyleOf,
        ),
        toggleButtonTextStyle: r.text('toggleButtonTextStyle'),
        subHeaderForegroundColor: r.color('subHeaderForegroundColor'),
      ),
    ),
  ),
  ThemeComponent(
    'dialog',
    shapeToken: 'extralarge',
    (t, r, _) => t.copyWith(
      dialogTheme: DialogThemeData(
        backgroundColor: r.color('backgroundColor'),
        elevation: r.elevation('elevation'),
        shadowColor: r.color('shadowColor'),
        surfaceTintColor: r.color('surfaceTintColor'),
        shape: r.shape('shape'),
        alignment: r.alignment('alignment'),
        titleTextStyle: r.text('titleTextStyle'),
        contentTextStyle: r.text('contentTextStyle'),
        actionsPadding: r.insets('actionsPadding'),
        iconColor: r.color('iconColor'),
        barrierColor: r.color('barrierColor'),
        insetPadding: r.insets('insetPadding'),
        clipBehavior: r.choice('clipBehavior', Clip.values),
        constraints: r.constraints('constraints'),
      ),
    ),
  ),
  ThemeComponent(
    'divider',
    (t, r, _) => t.copyWith(
      dividerTheme: DividerThemeData(
        color: r.color('color'),
        space: r.number('space'),
        thickness: r.number('thickness'),
        indent: r.number('indent'),
        endIndent: r.number('endIndent'),
        radius: r.borderRadius('radius'),
      ),
    ),
  ),
  ThemeComponent(
    'drawer',
    (t, r, _) => t.copyWith(
      drawerTheme: DrawerThemeData(
        backgroundColor: r.color('backgroundColor'),
        scrimColor: r.color('scrimColor'),
        elevation: r.elevation('elevation'),
        shadowColor: r.color('shadowColor'),
        surfaceTintColor: r.color('surfaceTintColor'),
        shape: r.shape('shape'),
        endShape: r.shape('endShape'),
        width: r.number('width'),
        clipBehavior: r.choice('clipBehavior', Clip.values),
      ),
    ),
  ),
  ThemeComponent(
    'dropdown-menu',
    (t, r, _) => t.copyWith(
      dropdownMenuTheme: DropdownMenuThemeData(
        textStyle: r.text('textStyle'),
        inputDecorationTheme: _ifSet(
          r.group('inputDecoration'),
          inputDecorationOf,
        ),
        menuStyle: _ifSet(r.group('menuStyle'), menuStyleOf),
        disabledColor: r.color('disabledColor'),
      ),
    ),
  ),
  ThemeComponent(
    'expansion-tile',
    (t, r, _) => t.copyWith(
      expansionTileTheme: ExpansionTileThemeData(
        backgroundColor: r.color('backgroundColor'),
        collapsedBackgroundColor: r.color('collapsedBackgroundColor'),
        tilePadding: r.insets('tilePadding'),
        expandedAlignment: r.alignment('expandedAlignment'),
        childrenPadding: r.insets('childrenPadding'),
        iconColor: r.color('iconColor'),
        collapsedIconColor: r.color('collapsedIconColor'),
        textColor: r.color('textColor'),
        collapsedTextColor: r.color('collapsedTextColor'),
        shape: r.shape('shape'),
        collapsedShape: r.shape('collapsedShape'),
        clipBehavior: r.choice('clipBehavior', Clip.values),
        expansionAnimationStyle: r.animation('expansionAnimationStyle'),
      ),
    ),
  ),
  ThemeComponent(
    'icon',
    (t, r, _) => t.copyWith(iconTheme: r.iconFields()),
  ),
  ThemeComponent(
    'primary-icon',
    (t, r, _) => t.copyWith(primaryIconTheme: r.iconFields()),
  ),
  ThemeComponent(
    'input',
    shapeToken: 'extrasmall',
    (t, r, _) => t.copyWith(inputDecorationTheme: inputDecorationOf(r)),
  ),
  ThemeComponent(
    'list-tile',
    (t, r, _) => t.copyWith(
      listTileTheme: ListTileThemeData(
        dense: r.flag('dense'),
        shape: r.shape('shape'),
        style: r.choice('style', ListTileStyle.values),
        selectedColor: r.color('selectedColor'),
        iconColor: r.color('iconColor'),
        textColor: r.color('textColor'),
        titleTextStyle: r.text('titleTextStyle'),
        subtitleTextStyle: r.text('subtitleTextStyle'),
        leadingAndTrailingTextStyle: r.text('leadingAndTrailingTextStyle'),
        contentPadding: r.insets('contentPadding'),
        tileColor: r.color('tileColor'),
        selectedTileColor: r.color('selectedTileColor'),
        horizontalTitleGap: r.number('horizontalTitleGap'),
        minVerticalPadding: r.number('minVerticalPadding'),
        minLeadingWidth: r.number('minLeadingWidth'),
        minTileHeight: r.number('minTileHeight'),
        enableFeedback: r.flag('enableFeedback'),
        mouseCursor: r.stateCursor('mouseCursor'),
        visualDensity: r.density('visualDensity'),
        titleAlignment: r.choice(
          'titleAlignment',
          ListTileTitleAlignment.values,
        ),
        controlAffinity: r.choice(
          'controlAffinity',
          ListTileControlAffinity.values,
        ),
        isThreeLine: r.flag('isThreeLine'),
      ),
    ),
  ),
  ThemeComponent(
    'menu',
    (t, r, _) => t.copyWith(menuTheme: MenuThemeData(style: menuStyleOf(r))),
  ),
  ThemeComponent(
    'menu-bar',
    (t, r, _) =>
        t.copyWith(menuBarTheme: MenuBarThemeData(style: menuStyleOf(r))),
  ),
  ThemeComponent(
    'navigation-bar',
    (t, r, _) => t.copyWith(
      navigationBarTheme: NavigationBarThemeData(
        height: r.number('height'),
        backgroundColor: r.color('backgroundColor'),
        elevation: r.elevation('elevation'),
        shadowColor: r.color('shadowColor'),
        surfaceTintColor: r.color('surfaceTintColor'),
        indicatorColor: r.color('indicatorColor'),
        indicatorShape: r.shape('indicatorShape'),
        labelTextStyle: r.stateText('labelTextStyle'),
        iconTheme: r.stateIcon('iconTheme'),
        labelBehavior: r.choice(
          'labelBehavior',
          NavigationDestinationLabelBehavior.values,
        ),
        overlayColor: r.stateColor('overlayColor'),
        labelPadding: r.insets('labelPadding'),
      ),
    ),
  ),
  ThemeComponent(
    'navigation-drawer',
    (t, r, _) => t.copyWith(
      navigationDrawerTheme: NavigationDrawerThemeData(
        tileHeight: r.number('tileHeight'),
        backgroundColor: r.color('backgroundColor'),
        elevation: r.elevation('elevation'),
        shadowColor: r.color('shadowColor'),
        surfaceTintColor: r.color('surfaceTintColor'),
        indicatorColor: r.color('indicatorColor'),
        indicatorShape: r.shape('indicatorShape'),
        indicatorSize: r.size('indicatorSize'),
        labelTextStyle: r.stateText('labelTextStyle'),
        iconTheme: r.stateIcon('iconTheme'),
      ),
    ),
  ),
  ThemeComponent(
    'navigation-rail',
    (t, r, _) => t.copyWith(
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: r.color('backgroundColor'),
        elevation: r.elevation('elevation'),
        unselectedLabelTextStyle: r.text('unselectedLabelTextStyle'),
        selectedLabelTextStyle: r.text('selectedLabelTextStyle'),
        unselectedIconTheme: r.icon('unselectedIconTheme'),
        selectedIconTheme: r.icon('selectedIconTheme'),
        groupAlignment: r.number('groupAlignment'),
        labelType: r.choice('labelType', NavigationRailLabelType.values),
        useIndicator: r.flag('useIndicator'),
        indicatorColor: r.color('indicatorColor'),
        indicatorShape: r.shape('indicatorShape'),
        minWidth: r.number('minWidth'),
        minExtendedWidth: r.number('minExtendedWidth'),
      ),
    ),
  ),
  ThemeComponent(
    'popup-menu',
    shapeToken: 'extrasmall',
    (t, r, _) => t.copyWith(
      popupMenuTheme: PopupMenuThemeData(
        color: r.color('color'),
        shape: r.shape('shape'),
        menuPadding: r.insets('menuPadding'),
        elevation: r.elevation('elevation'),
        shadowColor: r.color('shadowColor'),
        surfaceTintColor: r.color('surfaceTintColor'),
        textStyle: r.text('textStyle'),
        labelTextStyle: r.stateText('labelTextStyle'),
        enableFeedback: r.flag('enableFeedback'),
        mouseCursor: r.stateCursor('mouseCursor'),
        position: r.choice('position', PopupMenuPosition.values),
        iconColor: r.color('iconColor'),
        iconSize: r.number('iconSize'),
      ),
    ),
  ),
  ThemeComponent(
    'progress-indicator',
    (t, r, _) => t.copyWith(
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: r.color('color'),
        linearTrackColor: r.color('linearTrackColor'),
        linearMinHeight: r.number('linearMinHeight'),
        circularTrackColor: r.color('circularTrackColor'),
        refreshBackgroundColor: r.color('refreshBackgroundColor'),
        borderRadius: r.borderRadius('borderRadius'),
        stopIndicatorColor: r.color('stopIndicatorColor'),
        stopIndicatorRadius: r.number('stopIndicatorRadius'),
        strokeWidth: r.number('strokeWidth'),
        strokeAlign: r.number('strokeAlign'),
        strokeCap: r.choice('strokeCap', StrokeCap.values),
        constraints: r.constraints('constraints'),
        trackGap: r.number('trackGap'),
        circularTrackPadding: r.insets('circularTrackPadding'),
      ),
    ),
  ),
  ThemeComponent(
    'radio',
    (t, r, _) => t.copyWith(
      radioTheme: RadioThemeData(
        mouseCursor: r.stateCursor('mouseCursor'),
        fillColor: r.stateColor('fillColor'),
        overlayColor: r.stateColor('overlayColor'),
        splashRadius: r.number('splashRadius'),
        materialTapTargetSize: r.choice(
          'materialTapTargetSize',
          MaterialTapTargetSize.values,
        ),
        visualDensity: r.density('visualDensity'),
        backgroundColor: r.stateColor('backgroundColor'),
        side: r.side('side'),
        innerRadius: r.stateNumber('innerRadius'),
      ),
    ),
  ),
  ThemeComponent(
    'scrollbar',
    (t, r, _) => t.copyWith(
      scrollbarTheme: ScrollbarThemeData(
        thumbVisibility: r.stateFlag('thumbVisibility'),
        thickness: r.stateNumber('thickness'),
        trackVisibility: r.stateFlag('trackVisibility'),
        interactive: r.flag('interactive'),
        radius: r.radius('radius'),
        thumbColor: r.stateColor('thumbColor'),
        trackColor: r.stateColor('trackColor'),
        trackBorderColor: r.stateColor('trackBorderColor'),
        crossAxisMargin: r.number('crossAxisMargin'),
        mainAxisMargin: r.number('mainAxisMargin'),
        minThumbLength: r.number('minThumbLength'),
      ),
    ),
  ),
  ThemeComponent(
    'search-bar',
    (t, r, _) => t.copyWith(
      searchBarTheme: SearchBarThemeData(
        elevation: r.stateElevation('elevation'),
        backgroundColor: r.stateColor('backgroundColor'),
        shadowColor: r.stateColor('shadowColor'),
        surfaceTintColor: r.stateColor('surfaceTintColor'),
        overlayColor: r.stateColor('overlayColor'),
        side: r.stateSide('side'),
        shape: r.stateShape('shape'),
        padding: r.stateInsets('padding'),
        textStyle: r.stateText('textStyle'),
        hintStyle: r.stateText('hintStyle'),
        constraints: r.constraints('constraints'),
        textCapitalization: r.choice(
          'textCapitalization',
          TextCapitalization.values,
        ),
      ),
    ),
  ),
  ThemeComponent(
    'search-view',
    (t, r, _) => t.copyWith(
      searchViewTheme: SearchViewThemeData(
        backgroundColor: r.color('backgroundColor'),
        elevation: r.elevation('elevation'),
        surfaceTintColor: r.color('surfaceTintColor'),
        side: r.side('side'),
        shape: r.shape('shape'),
        headerHeight: r.number('headerHeight'),
        headerTextStyle: r.text('headerTextStyle'),
        headerHintStyle: r.text('headerHintStyle'),
        constraints: r.constraints('constraints'),
        padding: r.insets('padding'),
        barPadding: r.insets('barPadding'),
        shrinkWrap: r.flag('shrinkWrap'),
        dividerColor: r.color('dividerColor'),
      ),
    ),
  ),
  ThemeComponent(
    'slider',
    (t, r, _) => t.copyWith(
      sliderTheme: SliderThemeData(
        trackHeight: r.number('trackHeight'),
        activeTrackColor: r.color('activeTrackColor'),
        inactiveTrackColor: r.color('inactiveTrackColor'),
        secondaryActiveTrackColor: r.color('secondaryActiveTrackColor'),
        disabledActiveTrackColor: r.color('disabledActiveTrackColor'),
        disabledSecondaryActiveTrackColor: r.color(
          'disabledSecondaryActiveTrackColor',
        ),
        disabledInactiveTrackColor: r.color('disabledInactiveTrackColor'),
        activeTickMarkColor: r.color('activeTickMarkColor'),
        inactiveTickMarkColor: r.color('inactiveTickMarkColor'),
        disabledActiveTickMarkColor: r.color('disabledActiveTickMarkColor'),
        disabledInactiveTickMarkColor: r.color('disabledInactiveTickMarkColor'),
        thumbColor: r.color('thumbColor'),
        overlappingShapeStrokeColor: r.color('overlappingShapeStrokeColor'),
        disabledThumbColor: r.color('disabledThumbColor'),
        overlayColor: r.color('overlayColor'),
        valueIndicatorColor: r.color('valueIndicatorColor'),
        valueIndicatorStrokeColor: r.color('valueIndicatorStrokeColor'),
        showValueIndicator: r.choice(
          'showValueIndicator',
          ShowValueIndicator.values,
        ),
        valueIndicatorTextStyle: r.text('valueIndicatorTextStyle'),
        minThumbSeparation: r.number('minThumbSeparation'),
        mouseCursor: r.stateCursor('mouseCursor'),
        allowedInteraction: r.choice(
          'allowedInteraction',
          SliderInteraction.values,
        ),
        padding: r.insets('padding'),
        thumbSize: r.stateSize('thumbSize'),
        trackGap: r.number('trackGap'),
      ),
    ),
  ),
  ThemeComponent(
    'snack-bar',
    shapeToken: 'extrasmall',
    (t, r, _) => t.copyWith(
      snackBarTheme: SnackBarThemeData(
        backgroundColor: r.color('backgroundColor'),
        actionTextColor: r.color('actionTextColor'),
        disabledActionTextColor: r.color('disabledActionTextColor'),
        contentTextStyle: r.text('contentTextStyle'),
        elevation: r.elevation('elevation'),
        shape: r.shape('shape'),
        behavior: r.choice('behavior', SnackBarBehavior.values),
        width: r.number('width'),
        insetPadding: r.insets('insetPadding'),
        showCloseIcon: r.flag('showCloseIcon'),
        closeIconColor: r.color('closeIconColor'),
        actionOverflowThreshold: r.number('actionOverflowThreshold'),
        actionBackgroundColor: r.color('actionBackgroundColor'),
        disabledActionBackgroundColor: r.color('disabledActionBackgroundColor'),
        dismissDirection: r.choice('dismissDirection', DismissDirection.values),
      ),
    ),
  ),
  ThemeComponent(
    'switch',
    (t, r, _) => t.copyWith(
      switchTheme: SwitchThemeData(
        thumbColor: r.stateColor('thumbColor'),
        trackColor: r.stateColor('trackColor'),
        trackOutlineColor: r.stateColor('trackOutlineColor'),
        trackOutlineWidth: r.stateNumber('trackOutlineWidth'),
        materialTapTargetSize: r.choice(
          'materialTapTargetSize',
          MaterialTapTargetSize.values,
        ),
        mouseCursor: r.stateCursor('mouseCursor'),
        overlayColor: r.stateColor('overlayColor'),
        splashRadius: r.number('splashRadius'),
        padding: r.insets('padding'),
      ),
    ),
  ),
  ThemeComponent(
    'tab-bar',
    (t, r, _) => t.copyWith(
      tabBarTheme: TabBarThemeData(
        indicator: r.decoration('indicator'),
        indicatorColor: r.color('indicatorColor'),
        indicatorSize: r.choice('indicatorSize', TabBarIndicatorSize.values),
        dividerColor: r.color('dividerColor'),
        dividerHeight: r.number('dividerHeight'),
        labelColor: r.color('labelColor'),
        labelPadding: r.insets('labelPadding'),
        labelStyle: r.text('labelStyle'),
        unselectedLabelColor: r.color('unselectedLabelColor'),
        unselectedLabelStyle: r.text('unselectedLabelStyle'),
        overlayColor: r.stateColor('overlayColor'),
        splashFactory: r.splash('splashFactory'),
        mouseCursor: r.stateCursor('mouseCursor'),
        tabAlignment: r.choice('tabAlignment', TabAlignment.values),
        indicatorAnimation: r.choice(
          'indicatorAnimation',
          TabIndicatorAnimation.values,
        ),
        splashBorderRadius: r.borderRadius('splashBorderRadius'),
      ),
    ),
  ),
  ThemeComponent(
    'text-selection',
    (t, r, _) => t.copyWith(
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: r.color('cursorColor'),
        selectionColor: r.color('selectionColor'),
        selectionHandleColor: r.color('selectionHandleColor'),
      ),
    ),
  ),
  ThemeComponent(
    'time-picker',
    (t, r, _) => t.copyWith(
      timePickerTheme: TimePickerThemeData(
        backgroundColor: r.color('backgroundColor'),
        cancelButtonStyle: _ifSet(r.group('cancelButtonStyle'), buttonStyleOf),
        confirmButtonStyle: _ifSet(
          r.group('confirmButtonStyle'),
          buttonStyleOf,
        ),
        dayPeriodBorderSide: r.side('dayPeriodBorderSide'),
        dayPeriodColor: r.color('dayPeriodColor'),
        dayPeriodShape: r.shape('dayPeriodShape'),
        dayPeriodTextColor: r.color('dayPeriodTextColor'),
        dayPeriodTextStyle: r.text('dayPeriodTextStyle'),
        dialBackgroundColor: r.color('dialBackgroundColor'),
        dialHandColor: r.color('dialHandColor'),
        dialTextColor: r.color('dialTextColor'),
        dialTextStyle: r.text('dialTextStyle'),
        elevation: r.elevation('elevation'),
        entryModeIconColor: r.color('entryModeIconColor'),
        helpTextStyle: r.text('helpTextStyle'),
        hourMinuteColor: r.color('hourMinuteColor'),
        hourMinuteShape: r.shape('hourMinuteShape'),
        hourMinuteTextColor: r.color('hourMinuteTextColor'),
        hourMinuteTextStyle: r.text('hourMinuteTextStyle'),
        inputDecorationTheme: _ifSet(
          r.group('inputDecoration'),
          inputDecorationOf,
        ),
        padding: r.insets('padding'),
        shape: r.shape('shape'),
        timeSelectorSeparatorColor: r.stateColor('timeSelectorSeparatorColor'),
        timeSelectorSeparatorTextStyle: r.stateText(
          'timeSelectorSeparatorTextStyle',
        ),
      ),
    ),
  ),
  ThemeComponent(
    'tooltip',
    shapeToken: 'extrasmall',
    (t, r, _) {
      final shape = r.shape('shape');
      final background = r.color('background');
      final decoration = r.decoration('decoration');
      return t.copyWith(
        tooltipTheme: TooltipThemeData(
          constraints: r.constraints('constraints'),
          padding: r.insets('padding'),
          margin: r.insets('margin'),
          verticalOffset: r.number('verticalOffset'),
          preferBelow: r.flag('preferBelow'),
          excludeFromSemantics: r.flag('excludeFromSemantics'),
          decoration: shape == null && background == null
              ? decoration
              : ShapeDecoration(
                  shape:
                      shape ??
                      RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(
                          r.theme.shape('extrasmall'),
                        ),
                      ),
                  color: background ?? t.colorScheme.inverseSurface,
                ),
          textStyle: r.text('textStyle'),
          textAlign: r.choice('textAlign', TextAlign.values),
          waitDuration: r.duration('waitDuration'),
          showDuration: r.duration('showDuration'),
          exitDuration: r.duration('exitDuration'),
          triggerMode: r.choice('triggerMode', TooltipTriggerMode.values),
          enableFeedback: r.flag('enableFeedback'),
        ),
      );
    },
  ),
];
