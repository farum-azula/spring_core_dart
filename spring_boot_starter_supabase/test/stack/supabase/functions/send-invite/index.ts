// `Functions.sendInvite` of the test application: answers who called and
// what was sent, as the `id` of an InviteResult (`<sub>|<email>`).
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

Deno.serve(async (request: Request) => {
  if (request.method !== "POST") {
    return Response.json({ error: "POST only" }, { status: 405 });
  }
  const who = caller(request);
  const body = await request.json().catch(() => ({}));
  return Response.json({ id: `${who.sub ?? who.role}|${body.email}` });
});
