// `Functions.report` of the test application (`reports/{year}`): the
// year is the last segment of the path; answers text. The year 0 is a 404.
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
  const segments = new URL(request.url).pathname.split("/").filter(Boolean);
  const year = Number(segments[segments.length - 1]);
  if (!Number.isInteger(year) || year === 0) {
    return new Response("no report of that year", {
      status: 404,
      headers: { "content-type": "text/plain; charset=utf-8" },
    });
  }
  const who = caller(request);
  return new Response(`report ${year} for ${who.sub ?? who.role}`, {
    headers: { "content-type": "text/plain; charset=utf-8" },
  });
});
