## Unreleased

- Initial version: @FeignClient interfaces with request mapping annotations, JSON through ObjectMapper, interceptors, error decoding, retries, fallbacks, spring.cloud.openfeign.client.config.* properties.
- Server-sent events: methods returning `EventStream<T>` (or `Stream<T>`) read `text/event-stream` responses, decode each event's data, reconnect with `Last-Event-ID` (`event-stream.*` properties; not in Spring Cloud OpenFeign).
