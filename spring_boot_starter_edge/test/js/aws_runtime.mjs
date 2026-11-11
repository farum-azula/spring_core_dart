// A stand-in for the Lambda runtime under Node: loads a built AWS
// function and invokes its handler for every event posted to
//   POST /2015-03-31/functions/function/invocations
// (the address of AWS's runtime interface emulator), answering with the
// handler's result. Prints "LISTENING <port>" when it is ready.
//
// With "streaming", a stand-in for the runtime's `awslambda` records what
// a response-streaming handler writes; the result is then
// { statusCode, headers, cookies, ended, chunks, body }.
import { createServer } from "node:http";

const [directory, mode] = process.argv.slice(2);

if (mode === "streaming") {
  globalThis.awslambda = {
    streamifyResponse: (handler) => async (event, context) => {
      const chunks = [];
      const stream = {
        write(chunk) {
          chunks.push(Buffer.from(chunk));
          return true;
        },
        once() {},
        end() {
          stream.ended = true;
        },
      };
      await handler(event, stream, context);
      return {
        ...stream.meta,
        ended: stream.ended === true,
        chunks: chunks.length,
        body: Buffer.concat(chunks).toString("utf8"),
        isBase64Encoded: false,
      };
    },
    HttpResponseStream: {
      from(stream, meta) {
        stream.meta = meta;
        return stream;
      },
    },
  };
}

const { handler } = await import(`${directory}/index.mjs`);

const server = createServer(async (request, response) => {
  const parts = [];
  for await (const part of request) parts.push(part);
  try {
    const event = JSON.parse(Buffer.concat(parts).toString("utf8"));
    const result = await handler(event, {});
    response.writeHead(200, { "content-type": "application/json" });
    response.end(JSON.stringify(result));
  } catch (error) {
    response.writeHead(500, { "content-type": "application/json" });
    response.end(JSON.stringify({ errorMessage: String(error) }));
  }
});
server.listen(0, "127.0.0.1", () => {
  console.log(`LISTENING ${server.address().port}`);
});
