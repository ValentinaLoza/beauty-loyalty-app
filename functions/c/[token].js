function validUuid(value) {
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(
    value || ""
  );
}

export function onRequestGet(context) {
  const token = context.params.token;

  if (!validUuid(token)) {
    return new Response("Invalid client token", {
      status: 400,
      headers: { "Content-Type": "text/plain; charset=utf-8" }
    });
  }

  // Backwards compatibility for old shared links.
  return Response.redirect(
    new URL(`/card/${encodeURIComponent(token)}`, context.request.url).toString(),
    302
  );
}
