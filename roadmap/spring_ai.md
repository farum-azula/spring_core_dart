# Spring AI (planned, next)

Spring AI for Dart: one API over the model providers, like Spring AI's
`ChatClient` and `ChatModel`, on the HTTP transports of `spring_web_dart`
(the VM, Flutter and the web). No provider SDKs: each provider is a small
client of its HTTP API.

## One package

Everything is in one starter, `spring_boot_starter_ai`: the API
(`ChatModel`, `ChatClient`, prompts, messages, options, tool calling,
structured output, advisors, `EmbeddingModel`) and every provider. An
application lists only this starter, whatever provider it uses.

| Provider | API |
|---|---|
| Anthropic | Claude, the Messages API |
| OpenAI | OpenAI and compatible servers (Responses / Chat Completions) |
| Google | Gemini |
| Ollama | local models |
| later | Mistral, Bedrock, Azure OpenAI; vector stores |

Spring AI has a starter per provider (`spring-ai-starter-model-anthropic`,
...). Here one package is enough: the providers are small HTTP clients
with no dependencies of their own, so an application pays little for the
ones it does not use. The provider is picked by configuration: the one
whose `spring.ai.<provider>.*` properties are set, or
`spring.ai.model.chat` / `spring.ai.model.embedding` (as in Spring AI)
when several are. The package is split only if it has to be (a provider
that needs a dependency, or size).

MCP goes into the same package later: servers built from beans' methods,
then a client ([spring_ai_mcp.md](spring_ai_mcp.md)).

## ChatClient

```dart
@Service()
class Librarian {
  Librarian(ChatClient.Builder builder)
    : chat = builder.defaultSystem('You recommend books.').build();
  final ChatClient chat;

  Future<String> recommend(String mood) =>
      chat.prompt().user('Something for a $mood evening').call().content();

  Stream<String> recommendStreaming(String mood) =>
      chat.prompt().user('Something for a $mood evening').stream().content();

  Future<List<Book>> list(String topic) =>
      chat.prompt().user('Five books about $topic').call().entity<List<Book>>();
}
```

```yaml
spring:
  ai:
    anthropic:
      api-key: ${ANTHROPIC_API_KEY}
      chat:
        options:
          model: claude-sonnet-5-5
          max-tokens: 1024
```

- **Streaming:** server-sent events read by the existing `EventStream`
  decoder; `stream()` gives text deltas or full `ChatResponse`s.
- **Structured output:** `entity<T>()` asks for JSON matching a schema
  the generator writes from `T` (the same introspection as JSON today) and
  reads the answer with the `ObjectMapper`.
- **Tool calling:** `@Tool(description:)` methods of beans become tools;
  the generator writes their JSON schemas (types, `@ToolParam`
  descriptions, validation constraints), the client runs the tool loop.
  The same schemas serve the MCP server later.
- **Advisors:** chat memory (in memory first, a repository later),
  retrieval (RAG) once vector stores exist, logging, safeguards.
- **Options:** per provider (`AnthropicChatOptions`, ...) and portable
  ones (model, temperature, max tokens), from properties and per call.
- **Observability:** token usage and latency as events and logs, metrics
  with the actuator later.
- **Embeddings:** `EmbeddingModel` per provider; vector stores later.

## Flutter

A model's API key must never ship in an app (anyone can extract it, see
`--dart-define` in [spring_boot_starter_flutter](spring_boot_starter_flutter.md)).
In apps the `ChatClient` talks to the application's own backend (a
controller of the web starter proxying the provider, with the user's
authentication), or to a local model (Ollama on desktop). The starter
warns when an API key property is set in a Flutter build.

## Tests

A `MockChatModel` with scripted answers (text, tool calls, streams), and
recorded provider responses (`MockHttpTransport`) so the providers are
tested without network or keys.
