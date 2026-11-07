---
title: "Theme styles and states — Spring for Dart"
description: "Give your own widgets a look per state (hovered, focused, pressed, selected, disabled) in YAML, with transitions, ThemeStates and component states."
slug: /docs/flutter/theme/styles-and-states
section: Flutter / Theme
order: 7
keywords: [flutter, theme, yaml, styles, widget states, hovered, pressed, focused, selected, disabled, ThemeStates, transition]
---

# Styles and states

Material's components have a look for each state (hovered, pressed, focused,
disabled...). Your own widgets can have the same. Under `styles.<name>` you
write a look, and for each property either one value or a value per state.
`ThemeStates` follows the mouse, focus and taps for you and hands the right
values to your widget.

```yaml
spring:
  flutter:
    theme:
      styles:
        neon-chip:
          padding: [12, 6]
          radius: $shape.small
          border:
            default: $colors.outline
            hovered: $colors.primary
            selected: $colors.primary
          fill:
            default: transparent
            selected: { color: $colors.primary, alpha: 12% }
          text:
            default: $colors.on-surface-variant
            hovered: $colors.primary
            disabled: { color: $colors.on-surface, alpha: 38% }
          transition: 120ms ease-out
```

## Properties

| Property | Type | Values | Default | What it does |
|---|---|---|---|---|
| `styles.<name>` | map | any name | none | One style. The name is read in any spelling: `neon-chip`, `neonChip` and `neon_chip` are the same |
| `styles.<name>.<property>` | value, or map of states | the value kinds below | none | One property of the style. Any property name is allowed; your widget decides what it reads |
| `styles.<name>.<property>.<state>` | value | `default`, `hovered`, `focused`, `pressed`, `dragged`, `selected`, `scrolled-under`, `disabled`, `error` | none | The value of the property in that state |
| `styles.<name>.transition` | text | `<duration> [<curve>]` | no animation | How long the values take to change when the state changes, and along which curve |

### Value kinds

A value is typed by what it looks like, with the same rules as
[tokens](tokens-and-references.md#how-a-value-is-typed):

| Kind | Written as | In Dart (`StyleValues`) |
|---|---|---|
| color | `#FF40A0`, `deepPurple`, `$colors.primary`, `{ color: $colors.primary, alpha: 12% }` | `values.color('fill')` |
| number | `14`, `1.5` | `values.number('radius')` |
| insets | a YAML list `[12, 6]`, or `12, 6` | `values.insets('padding')` |
| duration | `250ms`, `1.5s`, `2m`, `1h`, `0.5d` | `values.duration('delay')` |
| text | anything else | `values.text('label')` |

Insets are `[all]`, `[horizontal, vertical]` or `[left, top, right, bottom]`.
A list of three numbers, or of five or more, is an error. A number can be used
where insets are read and means the same on all sides.

A property that is a map must hold states only. A map with another key
stops the start and lists the states.

### One value, or a value per state

```yaml
spring:
  flutter:
    theme:
      styles:
        field:
          radius: 8                       # the same in every state
          border:                         # a value per state
            default: $colors.outline
            focused: $colors.primary
            error: $colors.error
```

- A property with states must have a `default`: the value when no other
  state applies.
- Every state of a property has the same kind. A number next to insets is
  widened to insets. Mixing a color and a number is an error.
- A property you wrote for one state only is not an error as long as it has
  a `default`.

### The transition

`transition: <duration> [<curve>]` animates the change between states. The
duration is a number with a unit (`120ms`, `0.2s`, `1h`) and may also be a
bare number of milliseconds. The curve is any [named curve or four
numbers](motion-and-animations.md#curves). Without a curve the change is
linear. Without `transition` the values change at once.

```yaml
spring:
  flutter:
    theme:
      styles:
        tag:
          fill: { default: transparent, hovered: '#33FFFFFF' }
          transition: $motion.durations.fast ease-out
```

Colors, numbers, insets and durations blend smoothly between states. Text
switches halfway through the transition. Padding never goes negative, even
with a curve that overshoots (`ease-out-back`, `elastic-out`).

## States

| State | When a widget is in it |
|---|---|
| `default` | None of the others applies, or the others have no value for this property |
| `hovered` | A mouse pointer is over it |
| `focused` | It has keyboard focus |
| `pressed` | The primary mouse button or a finger is down on it |
| `dragged` | It is being dragged |
| `selected` | It is selected (your `selected` argument) |
| `scrolled-under` | Content scrolls under it |
| `disabled` | It cannot be used (`onPressed` is `null`) |
| `error` | It is in error (your `error` argument) |

A widget can be in several states at once. For each property **the strongest
state that has a value wins**, strongest first:

1. `disabled`
2. `error`
3. `pressed`
4. `dragged`
5. `hovered`
6. `focused`
7. `selected`
8. `scrolled-under`
9. `default`

So a selected chip that is hovered shows its `hovered` value if it has one,
else its `selected` value, else its `default`. Each property is decided on
its own; a property without a `disabled` value in a disabled widget falls
through to the next state that has one.

`ThemeStates` sets `hovered`, `focused`, `pressed`, `disabled`, `selected`
and `error`. `dragged` and `scrolled-under` are never set by it; they are for
code that calls `StateStyle.resolve` with its own set of states.

## `ThemeStates`

`ThemeStates` is the widget that does the work.

```dart
ThemeStates(
  style: context.theme.styles.neonChip,
  selected: selected,
  onPressed: onPressed,          // null: the chip is disabled
  builder: (context, s) => Container(
    padding: s.padding,           // EdgeInsets
    decoration: BoxDecoration(
      color: s.fill,              // Color
      borderRadius: BorderRadius.circular(s.radius),
      border: Border.all(color: s.border),
    ),
    child: Text(label, style: TextStyle(color: s.text)),
  ),
)
```

| Argument | Type | Default | What it does |
|---|---|---|---|
| `style` | `ThemeStyle` | required | The style: `context.theme.styles.<name>` (generated) or a `StateStyle` |
| `builder` | function | required | Builds the child from the values of the current state |
| `selected` | bool | `false` | Whether the widget is selected |
| `error` | bool | `false` | Whether the widget is in error |
| `onPressed` | callback | none | Called on a tap, a click, Enter or Space. `null` disables the widget |
| `focusNode` | `FocusNode` | its own | The focus node to use |
| `autofocus` | bool | `false` | Take focus when first shown |
| `mouseCursor` | `MouseCursor` | click (basic when disabled) | The cursor over the widget |
| `showFocusAlways` | bool | `false` | Show `focused` whatever way the focus came (a tap or click too), not only with the keyboard. Turn it on for a text input, whose frame must light up when the user taps it. Buttons leave it off, as Flutter does |

It follows the mouse, focus and pressing, handles Enter and Space, sets the
cursor, and blends the values over `transition`. When the device asks for
less motion (`MediaQuery.disableAnimations`) the values change at once.

### The generated classes

With the generator, a `styles.<name>` becomes the class `AppStyle<Name>` and
its values the class `AppStyle<Name>Values`, so a style called `text` or
`button` never hides Flutter's `TextStyle` or `ButtonStyle`. The values class
has a typed getter per property (`Color fill`, `double radius`,
`EdgeInsets padding`, `Duration delay`, `String label`). A property must
have one kind in every theme and every state; otherwise the build fails and
names both places.

```dart
context.theme.styles.neonChip;     // AppStyleNeonChip, a ThemeStyle<AppStyleNeonChipValues>
```

Without the generator, read a style by name:

```dart
final style = SpringTheme.of(context).styles['neonchip']!;   // StateStyle
final values = style.resolve({WidgetState.hovered});
values.color('fill');
```

## Per-state values in components

Many properties of Material components are also "per state" in Flutter (they
are a `WidgetStateProperty`). They take either one value or the same map of
states. The component pages mark them with a star.

```yaml
spring:
  flutter:
    theme:
      components:
        filled-button:
          background-color:
            default: $colors.primary
            hovered: { color: $colors.primary, alpha: 90% }
            pressed: $colors.tertiary
            disabled: { color: $colors.on-surface, alpha: 12% }
          side:
            default: none
            focused: { color: $colors.secondary, width: 2 }
          text-style: { style: label-large, weight: bold }
        checkbox:
          fill-color: { default: $colors.outline, selected: $colors.primary, error: $colors.error }
```

- The states and the order are the same as above.
- A plain value next to the states is the `default`.
- A state without a value, and no `default`, keeps Flutter's own value.
- A value is of the property's type. A border side per state is a map of
  maps (`focused: { color: $colors.secondary, width: 2 }`).
- A map per state holds states only. Another key stops the start and lists
  the states.
- A property that takes only one value (no star) given a map of states stops
  the start: "this property takes one value, no states".
- Inside a component a color is written as everywhere else: `#RRGGBB`, a
  name, a reference to a role (`$colors.primary`) or an object with `alpha`
  or `mix`, also per state. Check the page of the
  component for the exact properties: [components](components/index.md),
  for example [app bar](components/app-bar.md).

## Markdown and code: `styles.code`

`MarkdownView` (and the navigation's `RouteContentView`, which shows a
route's Markdown) takes its look from the theme: the headings from
`headline-*` and `title-*`, the text from `body-large`, links from
`colors.primary`. In a `WidgetsApp` or a `CupertinoApp`, which have no
Material `Theme`, it takes the same text styles from the theme shown, with
Material's sizes for the script of the app's language, so a dark theme
does not get Material's black fallback text. Code, inline and in fenced
blocks, uses the `code` text style (`typography.code`) and the colors of
the style `styles.code`:

```yaml
spring:
  flutter:
    theme:
      typography:
        code: { font-family: JetBrains Mono, size: 13 }
      styles:
        code:
          background: $colors.surface-container-low
          text: $colors.on-surface
          keyword: '#C678DD'     # final, class, true
          string: '#98C379'      # 'text', "text"
          comment: '#5C6370'     # // and #
          number: '#D19A66'      # 42, 1.5
          key: '#E06C75'         # YAML and .properties keys
          annotation: '#61AFEF'  # @Service
          variable: '#E5C07B'    # $colors.primary, ${PORT}, &anchor
          type: '#56B6C2'        # String, Basket, int
          punctuation: '#ABB2BF' # { } [ ] , : -
```

| Property | Default | Colors |
|---|---|---|
| `background` | `$colors.surface-container-highest` | The block's fill and inline code's background |
| `text` | the `code` text style's color | Everything not listed below |
| `keyword` | `$colors.primary` | Keywords, `true` / `false` / `null` |
| `string` | `$colors.tertiary` | Strings, and YAML and `.properties` values without quotes (`ease-out`) |
| `comment` | `$colors.outline` | Comments |
| `number` | `$colors.secondary` | Numbers, with a unit too (`120ms`, `1.5s`, `35%`) |
| `key` | `$colors.primary` | Keys of YAML, `.properties` and JSON; options of a shell command (`--port`) |
| `annotation` | `$colors.secondary` | Annotations, YAML tags (`!include`) |
| `variable` | `$colors.on-tertiary-container` | References and placeholders: `$colors.primary`, `${PORT}`, a shell's `$HOME`, YAML anchors and aliases (`&base`, `*base`) |
| `type` | `$colors.on-secondary-container` | Dart types: `String`, `Basket`, `int` |
| `punctuation` | `$colors.on-surface-variant` | Brackets, braces, commas, colons, a list's dash |
| `inline-text` | the `code` text style's color | Inline code (`` `@Bean()` ``) |
| `inline-background` | `background` | Inline code's background |
| `header` | `background` | The header of a block with a title |
| `title` | `$colors.on-surface-variant` | A block's title and its copy button |

The block itself takes four more properties:

| Property | Default | Meaning |
|---|---|---|
| `padding` | `12` | Insets inside the block: `16`, `[16, 12]` |
| `radius` | `6` | Corner radius |
| `border` | none | Border color |
| `border-width` | `1` | Border width, when `border` is set |
| `copy` | `true` | A button that copies the block's text: in the header of a block with a `title=`, in the corner of the others; `false` for none |

A block can be shown in several palettes, with a button for each above it:
name them after the language, `themes="dark light"`, and give each a style
`code-<name>` with the same properties as `styles.code` (colors of the
pieces, `background`, `text`, `border`) and a `label` for its button. A name
the theme has no style for is left out.

```yaml
styles:
  code-night:
    label: Night
    background: '#212121'
    keyword: '#6388d4'
    string: '#ce9178'
```

Every property is optional; without `styles.code` the code follows the
color scheme, so it fits every theme already. A theme of `themes.<name>`
overrides only the colors it writes, like any other key.

A fenced block names its language after the backticks (` ```dart `). The
starter knows no language by itself: what the code is made of comes from
the theme's `syntax.<language>` (next section). A block in a language no
theme has is shown in the `text` color.

## The languages of code: `syntax`

`syntax.<language>` splits code into the pieces `styles.code` colors. A
language is a list of rules, each a regular expression and the kind of
what it matches, tried in order at each position of the code; the first
that matches makes a piece:

```yaml
spring:
  flutter:
    theme:
      syntax:
        java:
          aliases: [jav]                    # other names in a fenced block
          keywords: [class, public, return, new, 'true', 'false', 'null']
          types: '^[A-Z][A-Za-z0-9_]*[a-z]' # a word that is a type name
          rules:
            - { match: '//[^\n]*|/\*[\s\S]*?\*/', kind: comment }
            - { match: '"(?:\\.|[^"\\\n])*"', kind: string }
            - { match: '@[A-Za-z_][\w.]*', kind: annotation }
            - { match: '\b\d+(?:\.\d+)?\b', kind: number }
            - { match: '[A-Za-z_$][\w$]*', kind: word }
            - { match: '[{}()\[\];,]', kind: punctuation }
```

| Property | Meaning |
|---|---|
| `rules` | Required. Each `{ match, kind }`. `match` is a regular expression, taken as written (no `$` reference); `^` and `$` are a line's start and end. `kind` is `comment`, `string`, `annotation`, `number`, `key`, `keyword`, `type`, `variable`, `punctuation`, `plain`, or `word` |
| `keywords` | The words a `word` rule colors as `keyword`. Quote `'true'`, `'false'` and `'null'`, which YAML reads as values |
| `types` | A regular expression: a word of a `word` rule that matches it is a `type` |
| `aliases` | Other names of the language in a fenced block (`yml` for `yaml`) |

What no rule matches is plain text. An invalid rule (an unknown kind, a
regular expression that does not compile, a language without rules)
stops the start and names the property.

### Languages from a URL

You rarely write a language yourself. The repository
[farum-azula/themes](https://github.com/farum-azula/themes) has Dart,
Java, YAML, properties, shell and JSON in one file; download it for every
theme of the app with `source` on `spring.flutter.theme` itself (see
[a theme from a URL](properties.md#a-theme-from-a-url)):

```yaml
spring:
  flutter:
    theme:
      source: github:farum-azula/themes/themes/code.yml@code-v0.2.0
      themes:
        neon:
          syntax:
            java: { ... }   # a theme may still replace one language
```

The downloaded values are shared by every theme and lie under your own
files: a `syntax.<language>` you write wins.

```dart
MarkdownView(text, onLink: (href) => launchUrl(Uri.parse(href)));
MarkdownView.resource('resources:content/docs/beans.md');
const MarkdownView.code('server:\n  port: 8080', language: 'yaml'); // one block
```

A fenced block with a `title` after its language gets a header with the
title and a button that copies the code:

````markdown
```dart title="lib/orders.dart"
@Service()
class OrderService { ... }
```
````

Links take `styles.link.color` (`$colors.primary` by default).

Headings take the sizes of the typography (`#` is `headline-large`, `##`
`headline-medium`, `###` `headline-small`, then `title-large`,
`title-medium`, `title-small`) and the color of `styles.heading`:
`color` for every level, `h1` ... `h6` for one level. Without it they are
in the text's color.

```yaml
styles:
  heading:
    color: $colors.primary     # every heading
    h1: $colors.on-surface     # but # in the text's color
```

A table's column is as wide as its text, up to `styles.table.cell-width`
(280 by default), where the text wraps. A table wider than the view
scrolls sideways instead of squeezing its columns, so it reads on a phone.
A table narrower than the view widens its columns to the view's width, so
it lines up with the text around it; `fill: false` keeps it as wide as its
text.

```yaml
styles:
  table:
    cell-width: 240
    fill: true        # the default
```

### Callouts

GitHub's callouts are boxes in their kind's color, with the kind's name as
a title:

```markdown
> [!WARNING]
> A missing bean stops the start.
```

The kinds are `note`, `tip`, `important`, `warning` and `caution`; their
colors are `styles.callout.<kind>` (by default `primary`, `tertiary`,
`secondary`, `error`, `error`), and the titles the messages
`markdown.alert.<kind>` (`Note`, `Tip`, ... without them), so a
`messages_ja.properties` translates them:

```yaml
styles:
  callout:
    note: $colors.secondary
    warning: '#FF5C7A'
```

### The page's headings

`MarkdownOutline` gets the headings of the page a `MarkdownView` (or the
navigation's `RouteContentView`) shows, each with GitHub's anchor
(`## Bean methods` is `#bean-methods`), for an "On this page" list;
`show(id)` scrolls to one. A link to `#id` in the page scrolls by itself,
and an address with an anchor (`/docs/beans#scopes`) opens at its heading.

```dart
final outline = MarkdownOutline();

RouteContentView(outline: outline);
ListenableBuilder(
  listenable: outline,
  builder: (context, _) => Column(children: [
    for (final heading in outline.headings.where((h) => h.level == 2))
      TextButton(
        onPressed: () => outline.show(heading.id),
        child: Text(heading.text),
      ),
  ]),
);
```

### Languages of resources

`MarkdownView.resource('resources:content/beans.md')` shows
`beans.ja.md` instead when the app's language is Japanese and the file
exists, and changes with the language.

`MarkdownView.code` shows a single block of code exactly as a fenced block
of a Markdown page, so every code sample of an app shares one look. The
text can be selected; outside a `MaterialApp` (a `CupertinoApp`, a
`WidgetsApp`) the selection has no menu.

## See also

- [Tokens and references](tokens-and-references.md): how values are typed and referenced
- [Motion and animations](motion-and-animations.md): curves and durations
- [Shape, spacing and elevation](shape-spacing-elevation.md)
- [Components](components/index.md)
- [Typography](typography.md): the `code` text style
