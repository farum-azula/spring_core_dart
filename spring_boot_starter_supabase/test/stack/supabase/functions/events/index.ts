// Server-sent events: three events, a moment apart, each with its number
// and who called.
// Who called: the `sub` and the `role` of the bearer token, read without
// checking its signature (the function only echoes them).
function caller(request: Request): { sub: string | null; role: string | null } {
  const header = request.headers.get("authorization") ?? "";
  const token = header.replace(/^Bearer\s+/i, "");
  try {
    const part = token.split(".")[1].replace(/-/g, "+").replace(/_/g, "/");
    const padded = part + "=".repeat((4 - (part.length % 4)) % 4);
    const bytes = Uint8Array.from(atob(padded), (c) => c.charCodeAt(0));
    const claims = JSON.parse(new TextDecoder().decode(bytes));
    return { sub: claims.sub ?? null, role: claims.role ?? null };
  } catch (_) {
    return { sub: null, role: null };
  }
}

Deno.serve((request: Request) => {
  const who = caller(request);
  const encoder = new TextEncoder();
  let n = 0;
  let timer: number | undefined;
  const body = new ReadableStream<Uint8Array>({
    start(controller) {
      timer = setInterval(() => {
        n++;
        const data = JSON.stringify({ n, user: who.sub ?? who.role });
        controller.enqueue(encoder.encode(`id: ${n}\nevent: tick\ndata: ${data}\n\n`));
        if (n === 3) {
          clearInterval(timer);
          controller.close();
        }
      }, 200);
    },
    cancel() {
      clearInterval(timer);
    },
  });
  return new Response(body, {
    headers: {
      "content-type": "text/event-stream",
      "cache-control": "no-cache",
    },
  });
});
