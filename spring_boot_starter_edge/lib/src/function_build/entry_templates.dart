/// The JavaScript every entry loads before the application: what the
/// output of `dart compile js` expects from a browser.
///
/// - `self`: where dart2js looks for the global object; plain Node has
///   none.
/// - `scheduleImmediate`: dart2js runs Dart's microtasks through it when
///   it exists, else through a timer; with `queueMicrotask` they are the
///   platform's own microtasks, also while a platform loads the script
///   (Cloudflare Workers allow no timer then).
const preludeScript = '''
// Written by spring_boot_starter_edge; do not edit.
globalThis.self ??= globalThis;
globalThis.scheduleImmediate ??= (callback) => queueMicrotask(callback);
''';

/// `index.ts` of a Supabase Edge Function named [name].
///
/// The platform routes `/functions/v1/<name>/...` to the function and
/// gives it the path with the name in front, so the name is the
/// application's context path (`SERVER_CONTEXT_PATH`, which the
/// function's own environment may replace). The context starts while the
/// instance loads.
String supabaseEntry(String name) =>
    '''
// Written by spring_boot_starter_edge; do not edit.
import "./prelude.js";
import "./main.js";

const app = (globalThis as any).__springEdge;
const env = { SERVER_CONTEXT_PATH: "/$name", ...Deno.env.toObject() };
const runtime = (globalThis as any).EdgeRuntime;

function context(info?: any) {
  return {
    platform: "supabase",
    remoteAddress: info?.remoteAddr?.hostname,
    waitUntil: runtime?.waitUntil
      ? (work: Promise<unknown>) => runtime.waitUntil(work)
      : undefined,
  };
}

app.start(env, context()).catch(() => {
  // Logged by the application; the next request tries again.
});

Deno.serve((request: Request, info: any) =>
  app.fetch(request, env, context(info))
);
''';

/// `worker.mjs` of a Cloudflare Worker.
///
/// The Worker's `env` arrives with a request, so the context starts with
/// the first one. The address of the client is `CF-Connecting-IP`, which
/// Cloudflare sets itself and a client cannot.
const cloudflareEntry = '''
// Written by spring_boot_starter_edge; do not edit.
import "./prelude.js";
import "./main.js";

const app = globalThis.__springEdge;

export default {
  fetch(request, env, ctx) {
    return app.fetch(request, env, {
      platform: "cloudflare",
      remoteAddress: request.headers.get("cf-connecting-ip") ?? undefined,
      waitUntil: (work) => ctx.waitUntil(work),
    });
  },
  // A cron trigger ([triggers] crons of wrangler.toml).
  scheduled(controller, env, ctx) {
    return app.scheduled(
      { schedule: controller.cron, time: controller.scheduledTime },
      env,
      { platform: "cloudflare", waitUntil: (work) => ctx.waitUntil(work) },
    );
  },
};
''';

/// `main.ts` of a Deno Deploy application (`deno run -A main.ts` runs it
/// anywhere Deno does). The context starts while the instance loads; the
/// address of the client is the address of the connection, which Deno
/// Deploy gives as the client's.
const denoEntry = '''
// Written by spring_boot_starter_edge; do not edit.
import "./prelude.js";
import "./main.js";

const app = (globalThis as any).__springEdge;
const env = Deno.env.toObject();

app.start(env, { platform: "deno" }).catch(() => {
  // Logged by the application; the next request tries again.
});

// Deno Deploy listens where it wants; elsewhere PORT says where.
Deno.serve(
  { port: Number(env.PORT ?? 8000) },
  (request: Request, info: any) =>
    app.fetch(request, env, {
      platform: "deno",
      remoteAddress: info?.remoteAddr?.hostname,
    }),
);
''';

/// `<name>.js` of a Netlify Edge Function (`netlify/edge-functions/`),
/// for every path under [path]. The address of the client is
/// `context.ip`, which Netlify gives.
String netlifyEntry(String path) =>
    '''
// Written by spring_boot_starter_edge; do not edit.
import "./prelude.js";
import "./main.js";

const app = globalThis.__springEdge;

export default (request, context) =>
  app.fetch(request, globalThis.Netlify?.env?.toObject?.() ?? {}, {
    platform: "netlify",
    remoteAddress: context?.ip,
    waitUntil: context?.waitUntil
      ? (work) => context.waitUntil(work)
      : undefined,
  });

export const config = { path: "$path" };
''';

/// `index.mjs` of a Vercel Function with the web `fetch` export (the
/// Node.js runtime). The address of the client is `x-real-ip`, which
/// Vercel sets itself and replaces when a client sends it; `waitUntil` is
/// the one of Vercel's request context.
const vercelEntry = '''
// Written by spring_boot_starter_edge; do not edit.
import "./prelude.js";
import "./main.cjs";

const app = globalThis.__springEdge;
const env = process.env;

app.start(env, { platform: "vercel" }).catch(() => {
  // Logged by the application; the next request tries again.
});

function waitUntil(work) {
  const context = globalThis[Symbol.for("@vercel/request-context")]?.get?.();
  if (context?.waitUntil) context.waitUntil(work);
  // Without a context the work just runs; its failure must not be an
  // unhandled rejection, which ends the process.
  else work.catch(() => {});
}

export default {
  fetch(request) {
    return app.fetch(request, env, {
      platform: "vercel",
      remoteAddress: request.headers.get("x-real-ip") ?? undefined,
      waitUntil,
    });
  },
};
''';

/// `wrangler.toml` written into the application's directory for a Worker
/// named [name] when there is none: [main] is the built `worker.mjs`,
/// from that directory. After that the file is the application's (its
/// bindings, its routes, its cron triggers).
String wranglerConfig(
  String name,
  String compatibilityDate, {
  String main = 'worker.mjs',
}) =>
    '''
name = "$name"
main = "$main"
compatibility_date = "$compatibilityDate"
''';

/// `index.mjs` of an AWS Lambda function on the Node.js runtime (handler
/// `index.handler`), behind a function URL, an API Gateway HTTP API
/// (payload 2.0), an API Gateway REST API (payload 1.0) or an
/// Application Load Balancer.
///
/// The event becomes a `Request`, the `Response` the result the trigger
/// expects (text as text, anything else as base64). The address of the
/// client is the event's `sourceIp`; behind a load balancer, the last
/// address of `X-Forwarded-For`, which the balancer adds itself.
///
/// With [streaming] the handler is a response-streaming one (a function
/// URL with `InvokeMode: RESPONSE_STREAM`): the body is sent while it is
/// written, which server-sent events need.
String awsEntry({required bool streaming}) => '''
// Written by spring_boot_starter_edge; do not edit.
import "./prelude.js";
import "./main.cjs";

const app = globalThis.__springEdge;
const env = process.env;

app.start(env, { platform: "aws" }).catch(() => {
  // Logged by the application; the next invocation tries again.
});

function kind(event) {
  if (event.requestContext?.elb) return "alb";
  if (event.version === "2.0" || event.rawPath !== undefined) return "v2";
  return "v1";
}

function toRequest(event, type) {
  const headers = new Headers();
  if (event.multiValueHeaders) {
    for (const [name, values] of Object.entries(event.multiValueHeaders)) {
      for (const value of values ?? []) headers.append(name, value);
    }
  } else {
    for (const [name, value] of Object.entries(event.headers ?? {})) {
      if (value !== undefined && value !== null) headers.set(name, value);
    }
  }
  if (event.cookies?.length) headers.set("cookie", event.cookies.join("; "));
  let method;
  let path;
  let query = "";
  if (type === "v2") {
    method = event.requestContext.http.method;
    path = event.rawPath;
    query = event.rawQueryString ?? "";
  } else {
    method = event.httpMethod;
    path = event.path;
    const pairs = [];
    // A load balancer gives the query as it was sent; API Gateway decoded.
    const encode = type === "alb" ? (text) => text : encodeURIComponent;
    if (event.multiValueQueryStringParameters) {
      for (const [name, values] of Object.entries(event.multiValueQueryStringParameters)) {
        for (const value of values ?? []) pairs.push(`\${encode(name)}=\${encode(value)}`);
      }
    } else {
      for (const [name, value] of Object.entries(event.queryStringParameters ?? {})) {
        pairs.push(`\${encode(name)}=\${encode(value ?? "")}`);
      }
    }
    query = pairs.join("&");
  }
  const host = headers.get("host") ?? event.requestContext?.domainName ?? "localhost";
  // A host name or an address, with an optional port: nothing that could
  // add a user, a path or a query to the address the application sees.
  if (!hostPattern.test(host)) throw new TypeError("Invalid Host header");
  // A "?" or "#" cannot be part of a path as it was sent: a trigger that
  // gives the path decoded must not turn a segment into a query.
  path = path.replaceAll("?", "%3F").replaceAll("#", "%23");
  const scheme = headers.get("x-forwarded-proto") === "http" ? "http" : "https";
  const url = `\${scheme}://\${host}\${path}\${query ? "?" + query : ""}`;
  const hasBody = method !== "GET" && method !== "HEAD" && event.body != null && event.body !== "";
  return new Request(url, {
    method,
    headers,
    body: hasBody ? Buffer.from(event.body, event.isBase64Encoded ? "base64" : "utf8") : undefined,
  });
}

const hostPattern = /^(?:\\[[0-9A-Fa-f:.]+\\]|[A-Za-z0-9._~-]+)(?::[0-9]{1,5})?\$/;

function remoteAddress(event, type) {
  if (type === "v2") return event.requestContext?.http?.sourceIp;
  if (type === "v1") return event.requestContext?.identity?.sourceIp;
  const forwarded = event.multiValueHeaders?.["x-forwarded-for"]?.at(-1) ?? event.headers?.["x-forwarded-for"];
  return forwarded?.split(",").at(-1)?.trim();
}

const textTypes = /^(text\\/|application\\/(json|xml|javascript|x-www-form-urlencoded|[a-z0-9.+-]*\\+(json|xml)))/i;

function head(response, type) {
  const cookies = response.headers.getSetCookie();
  const single = {};
  const multi = {};
  response.headers.forEach((value, name) => {
    if (name === "set-cookie") return;
    single[name] = value;
    multi[name] = [value];
  });
  if (type === "v2") return { statusCode: response.status, headers: single, cookies };
  if (cookies.length) {
    single["set-cookie"] = cookies.at(-1);
    multi["set-cookie"] = cookies;
  }
  return { statusCode: response.status, headers: single, multiValueHeaders: multi };
}

// An EventBridge rule or schedule with the function as its target.
function isScheduled(event) {
  return event.source === "aws.events" || event.source === "aws.scheduler" ||
    event["detail-type"] === "Scheduled Event";
}

function scheduled(event) {
  return app.scheduled(
    {
      schedule: event.resources?.[0],
      time: event.time ? Date.parse(event.time) : undefined,
    },
    env,
    { platform: "aws" },
  );
}

const badRequest = () =>
  new Response('{"type":"about:blank","title":"Bad Request","status":400}', {
    status: 400,
    headers: { "content-type": "application/problem+json" },
  });

async function invoke(event, pending) {
  const type = kind(event);
  let request;
  try {
    request = toRequest(event, type);
  } catch (_) {
    // What cannot be a request (a method or a header the runtime refuses,
    // a Host that is no host) is answered, not a failed invocation.
    return { type, response: badRequest() };
  }
  const response = await app.fetch(request, env, {
    platform: "aws",
    remoteAddress: remoteAddress(event, type),
    waitUntil: (work) => pending.push(work),
  });
  return { type, response };
}
${streaming ? _awsStreaming : _awsBuffered}''';

const _awsBuffered = '''

export const handler = async (event) => {
  if (isScheduled(event)) return await scheduled(event);
  const pending = [];
  const { type, response } = await invoke(event, pending);
  const result = head(response, type);
  const bytes = Buffer.from(await response.arrayBuffer());
  const contentType = response.headers.get("content-type") ?? "";
  const charset = /charset="?([^";]+)/i.exec(contentType)?.[1]?.trim().toLowerCase();
  // Text goes as text only when it is UTF-8, which is what the result's
  // body is read as; anything else goes byte for byte.
  const text = textTypes.test(contentType) &&
    (!charset || charset === "utf-8" || charset === "utf8") &&
    !response.headers.get("content-encoding");
  result.body = bytes.toString(text ? "utf8" : "base64");
  result.isBase64Encoded = !text;
  // The instance is frozen when the handler returns: the work goes first.
  await Promise.allSettled(pending);
  return result;
};
''';

const _awsStreaming = '''

export const handler = awslambda.streamifyResponse(async (event, stream) => {
  if (isScheduled(event)) {
    await scheduled(event);
    stream.end();
    return;
  }
  const pending = [];
  const { response } = await invoke(event, pending);
  const { statusCode, headers, cookies } = head(response, "v2");
  const out = awslambda.HttpResponseStream.from(stream, { statusCode, headers, cookies });
  if (response.body) {
    for await (const chunk of response.body) {
      if (!out.write(chunk)) await new Promise((resume) => out.once("drain", resume));
    }
  }
  out.end();
  await Promise.allSettled(pending);
});
''';

// What a runtime without the JavaScript string builtins of WebAssembly
// (`wasm:js-string`) is given in their place. Dart 3.14's dart2wasm
// compiles for them and its `app.mjs` brings no stand-in, and the V8 of
// Cloudflare's workerd and of Supabase's Edge Runtime does not have them.
// A runtime that has them takes its own and never asks for these. The
// functions that read and write a Dart string's characters call the
// module's own exports, there once it is instantiated.
const _jsStrings = r'''
let appExports;
const jsStrings = {
  cast: (s) => {
    if (typeof s !== "string") throw new TypeError("not a string");
    return s;
  },
  test: (s) => (typeof s === "string" ? 1 : 0),
  length: (s) => s.length,
  charCodeAt: (s, i) => s.charCodeAt(i),
  codePointAt: (s, i) => s.codePointAt(i),
  concat: (a, b) => a + b,
  substring: (s, start, end) => s.substring(start, end),
  equals: (a, b) => (a === b ? 1 : 0),
  compare: (a, b) => (a < b ? -1 : a > b ? 1 : 0),
  fromCharCode: (c) => String.fromCharCode(c),
  fromCodePoint: (c) => String.fromCodePoint(c),
  fromCharCodeArray: (array, start, end) => {
    const read = appExports.$wasmI16ArrayGet;
    let text = "";
    for (let i = start; i < end; ) {
      const chunk = [];
      for (const stop = Math.min(end, i + 4096); i < stop; i++) {
        chunk.push(read(array, i));
      }
      text += String.fromCharCode(...chunk);
    }
    return text;
  },
  intoCharCodeArray: (s, array, start) => {
    const write = appExports.$wasmI16ArraySet;
    for (let i = 0; i < s.length; i++) write(array, start + i, s.charCodeAt(i));
    return s.length;
  },
};
''';

// Instantiates `app` with [_jsStrings] and runs the application's `main`.
const _run = '''
const instance = await app.instantiate({ "wasm:js-string": jsStrings });
appExports = instance.instantiatedModule.exports;
instance.invokeMain();
''';

/// `main.js` (`main.mjs` on Node) of a WebAssembly build: loads the
/// module `dart compile wasm` wrote (`app.wasm`, with its `app.mjs`) and
/// runs the application's `main`, which the entry file then finds as it
/// finds a JavaScript build.
///
/// - `node`: the module is read from the function's directory;
/// - `deno`: the same with Deno's API;
/// - `cloudflare`: a Worker may not compile WebAssembly at run time, so
///   the module is imported (wrangler compiles it at deploy) and given to
///   `app.mjs` in place of its own compilation.
///
/// Every one gives the module stand-ins for the JavaScript string
/// builtins, which a runtime without them needs.
String wasmLoader(String runtime) => switch (runtime) {
  'node' =>
    '''
// Written by spring_boot_starter_edge; do not edit.
import "./prelude.js";
import { readFileSync } from "node:fs";
import { compile } from "./app.mjs";
$_jsStrings
const app = await compile(readFileSync(new URL("./app.wasm", import.meta.url)));
$_run''',
  'deno' =>
    '''
// Written by spring_boot_starter_edge; do not edit.
import "./prelude.js";
import { compile } from "./app.mjs";
$_jsStrings
const app = await compile(
  await Deno.readFile(new URL("./app.wasm", import.meta.url)),
);
$_run''',
  'cloudflare' =>
    '''
// Written by spring_boot_starter_edge; do not edit.
import "./prelude.js";
import module from "./app.wasm";
import { compile } from "./app.mjs";
$_jsStrings
const compileWasm = WebAssembly.compile;
WebAssembly.compile = async () => module;
let app;
try {
  app = await compile(null);
} finally {
  WebAssembly.compile = compileWasm;
}
$_run''',
  _ => throw ArgumentError.value(runtime, 'runtime'),
};
