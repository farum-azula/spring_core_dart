# spring_ai_starter_mcp_server (planned)

> **Priority: later.** After Spring Security and the Spring AI starters
> ([spring_ai.md](spring_ai.md)); the tool calling of Spring AI and the MCP
> tools share the generated JSON schemas, so this comes after them.

MCP (Model Context Protocol) servers in Dart, like Spring AI's MCP server
starters. Beans' methods become tools, resources and prompts that AI
clients (Claude, IDEs, agents) call. Runs on a backend, as a command-line
tool, or inside a Flutter desktop or mobile app, exposing the app's own
beans.

```dart
@Service()
class BookTools {
  BookTools(this.books);
  final BookService books;

  @McpTool(description: 'Find a book by its ISBN')
  Future<Book> findBook(
    @McpToolParam(description: 'ISBN-10 or ISBN-13') @Size(min: 10, max: 13) String isbn,
  ) => books.find(isbn);

  @McpResource(uri: 'books://catalog', description: 'The whole catalog')
  Future<List<Book>> catalog() => books.all();

  @McpPrompt(description: 'Summarize a book for a reader')
  String summarize(String isbn) => 'Summarize the book $isbn in three sentences.';
}
```

```yaml
spring:
  ai:
    mcp:
      server:
        name: books
        version: 1.0.0
        protocol: streamable   # streamable | stateless | stdio
```

- **Tools from beans, no reflection.** The generator knows every
  parameter's type, so it writes each tool's JSON Schema at build time:
  - types and nullability from the method;
  - descriptions from `@McpToolParam`;
  - constraints from validation annotations (`@Size`, `@Min`, `@Matches`,
    ...).

  Arguments are read with the `ObjectMapper` and validated; results are
  written as JSON or text.
- **Transports:**
  - **Streamable HTTP** on [spring_boot_starter_web](spring_boot_starter_web.md)
    (section *MCP servers*): `POST` / `GET` / `DELETE` on one endpoint,
    SSE answers, `SseEmitter`s for server messages, `Mcp-Session-Id`,
    `Last-Event-ID`. **The web starter's prerequisites exist now:** a
    handler may answer a `POST` with an event stream (an `EventStream`
    or `SseEmitter` result), emitters can be kept in a registry bean and
    sent to later, `@RequestHeader` reads `Mcp-Session-Id`,
    `MCP-Protocol-Version` and `Last-Event-ID`, `ResponseEntity` sets
    them, a `WebFilter` checks `Origin`, and `MockMvc` reads event
    streams in tests. Only the authorization part waits for the security
    starter.
  - **Stateless HTTP**, without sessions.
  - **stdio** for local tools started by the client: no web starter
    needed, a compiled Dart executable is enough.
- **Server to client:** progress notifications, logging,
  `notifications/tools/list_changed` when beans change, and sampling or
  elicitation requests through the open stream.
- **Security:**
  - `Origin` checks and `127.0.0.1` by default for local servers;
  - the OAuth 2.1 resource server and protected resource metadata from
    [spring_boot_starter_security](spring_boot_starter_security.md);
  - `@PreAuthorize` on tool methods works through the beans' proxies.
- **Flutter:** the app's beans as tools for a desktop assistant. The
  server runs in the main isolate with the same beans as the UI and pauses
  with the app (see *Flutter* in the web starter).
- **Tests:** an in-memory MCP client over `MockMvc` (`tools/list`,
  `tools/call`) and over stdio pipes.
- **Dependencies:** only this repository and the Dart team (JSON-RPC and
  the schema are small enough to write here). The MCP protocol version is
  pinned and listed in the README.

Later: an MCP client starter (tools of other MCP servers as beans, like a
Feign client), next to a chat client starter.
