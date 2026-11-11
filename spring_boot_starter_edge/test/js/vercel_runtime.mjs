// A stand-in for Vercel's Node.js runtime: serves the `fetch` export of
// a built function over HTTP, with what Vercel gives a request (the
// address of the client in `x-real-ip`, whatever the client sent there,
// and the request context with `waitUntil`). Prints "LISTENING <port>".
import { createServer } from "node:http";
import { Readable } from "node:stream";

const [directory] = process.argv.slice(2);
const waiting = [];
globalThis[Symbol.for("@vercel/request-context")] = {
  get: () => ({ waitUntil: (work) => waiting.push(work) }),
};

const { default: handler } = await import(`${directory}/index.mjs`);

const server = createServer(async (incoming, outgoing) => {
  const headers = new Headers();
  for (const [name, value] of Object.entries(incoming.headers)) {
    for (const one of Array.isArray(value) ? value : [value]) {
      headers.append(name, one);
    }
  }
  headers.set("x-real-ip", incoming.socket.remoteAddress);
  const hasBody = incoming.method !== "GET" && incoming.method !== "HEAD";
  const response = await handler.fetch(
    new Request(`http://${incoming.headers.host}${incoming.url}`, {
      method: incoming.method,
      headers,
      body: hasBody ? Readable.toWeb(incoming) : undefined,
      duplex: "half",
    }),
  );
  outgoing.statusCode = response.status;
  // One request for each connection: the stand-in keeps none alive.
  outgoing.setHeader("connection", "close");
  for (const [name, value] of response.headers) {
    if (name !== "set-cookie") outgoing.setHeader(name, value);
  }
  const cookies = response.headers.getSetCookie();
  if (cookies.length) outgoing.setHeader("set-cookie", cookies);
  if (response.body) {
    for await (const chunk of response.body) outgoing.write(chunk);
  }
  outgoing.end();
});
server.listen(0, "127.0.0.1", () => {
  console.log(`LISTENING ${server.address().port}`);
});
