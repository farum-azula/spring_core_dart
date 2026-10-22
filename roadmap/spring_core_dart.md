# spring_core_dart

The runtime: container, AOP, SpEL, validation, `ObjectMapper`. Open
differences from Spring found in reviews: [fix_plan.md](fix_plan.md).

## JSON, next steps

Polymorphic types (`sealed` hierarchies with `@JsonTypeInfo` /
`@JsonSubTypes`), date and number patterns (`@JsonFormat`), `@JsonAlias`,
getters as properties, streaming of large documents, editor checks of
`@JsonProperty` names.
