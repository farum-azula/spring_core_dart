; .properties files, with Spring's placeholders: key=value, key: value, `#` / `!` comments,
; `\` escapes and line continuations, `${key}` and `${key:default}` in values.

(comment) @comment

(key) @property

(value) @string

(value
  (escape) @string.escape)

; list indexes: servers[0].host
((index) @number
  (#match? @number "^[0-9]+$"))

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
  (secret) @embedded)

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
