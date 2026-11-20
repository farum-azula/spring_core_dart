; .properties files, with Spring's placeholders: key=value, key: value, `#` / `!` comments,
; `\` escapes and line continuations, `${key}`, `${key:default}` and `${a:${b}}` in values, and
; values that are a SpEL expression (`#{...}`).
;
; Zed applies the capture pushed last: of two captures of a node, the later pattern's; of a node
; and its child, the child's. The grammar gives plain characters no node, so the default of a
; placeholder is what its substitution's own capture leaves, and a SpEL expression only shows as a
; whole value (dart_spring's semantic tokens colour its parts).

(comment) @comment

(key) @property

(value) @string

; a value that is one SpEL expression: #{@clock.now()}
((value) @string.special
  (#match? @string.special "^#\\{.*\\}[ \t]*$"))

(value
  (escape) @string.escape)

; list indexes: servers[0].host
((index) @number
  (#match? @number "^[0-9]+$"))

; ${PORT:8080}, ${a:${b}}: the default, after the `:` (its own placeholders and escapes keep
; their captures, which come after).
(substitution
  ":") @string.default

(substitution
  (escape) @string.escape)

; ${spring.application.name}, ${PORT:8080}: the referenced key; environment variables
; (UPPER_CASE) as constants.
(substitution
  (key) @variable.special)

((substitution
  (key) @constant)
  (#match? @constant "^[A-Z][A-Z0-9_]*$"))

(substitution
  (key) @function
  "::" @punctuation.special
  (secret) @attribute)

(property
  [
    "="
    ":"
  ] @operator)

[
  "${"
  "}"
] @punctuation.special

(substitution
  ":" @punctuation.special)

[
  "["
  "]"
] @punctuation.bracket

(key
  "." @punctuation.delimiter)

(value
  "\\" @punctuation.delimiter)
