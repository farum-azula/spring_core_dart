// `Functions.stats` of the test application: echoes the query parameter
// `from`, who called (read from the token, and asked of Auth with that
// same token), and what the gateway passed on. `from=fail` answers 422.
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

// The id Auth gives for the caller's token: null unless it is a user's
// token Auth accepts.
async function verified(request: Request): Promise<string | null> {
  const url = Deno.env.get("SUPABASE_URL");
  const authorization = request.headers.get("authorization");
  if (!url || !authorization) {
    return null;
  }
  try {
    const response = await fetch(`${url}/auth/v1/user`, {
      headers: {
        authorization,
        apikey: request.headers.get("apikey") ??
          Deno.env.get("SUPABASE_ANON_KEY") ?? "",
      },
    });
    if (!response.ok) {
      await response.body?.cancel();
      return null;
    }
    const user = await response.json();
    return typeof user.id === "string" ? user.id : null;
  } catch (_) {
    return null;
  }
}

Deno.serve(async (request: Request) => {
  const from = new URL(request.url).searchParams.get("from");
  if (from === "fail") {
    return Response.json({ error: "no stats from fail" }, { status: 422 });
  }
  const who = caller(request);
  return Response.json({
    from,
    method: request.method,
    user: who.sub,
    role: who.role,
    verified: await verified(request),
    apikey: request.headers.has("apikey"),
  });
});
