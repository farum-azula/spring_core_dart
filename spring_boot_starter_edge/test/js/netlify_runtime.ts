// A stand-in for Netlify's Edge Functions runtime, which is Deno: gives a
// built function the `Netlify` global and the context Netlify gives, and
// serves it on PORT. Prints "LISTENING <port>" when it is ready.
const [directory] = Deno.args;

(globalThis as any).Netlify = { env: { toObject: () => Deno.env.toObject() } };

const module = await import(`file://${directory}/index.js`);
const pending: Promise<unknown>[] = [];

Deno.serve(
  {
    port: Number(Deno.env.get("PORT") ?? 0),
    hostname: "127.0.0.1",
    onListen: ({ port }) =>
      console.log(`LISTENING ${port} ${module.config?.path}`),
  },
  (request, info) =>
    module.default(request, {
      ip: info.remoteAddr.hostname,
      waitUntil: (work: Promise<unknown>) => pending.push(work),
    }),
);
