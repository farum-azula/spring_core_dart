// A file: 4096 bytes, the byte at i is i % 251, as an attachment.
Deno.serve((_request: Request) => {
  const bytes = new Uint8Array(4096);
  for (let i = 0; i < bytes.length; i++) {
    bytes[i] = i % 251;
  }
  return new Response(bytes, {
    headers: {
      "content-type": "application/octet-stream",
      "content-disposition": 'attachment; filename="stack.bin"',
    },
  });
});
