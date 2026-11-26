function validUuid(value) {
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(
    value || ""
  );
}

export async function onRequestGet(context) {
  const token = context.params.token;

  if (!validUuid(token)) {
    return new Response("Invalid client token", {
      status: 400,
      headers: {
        "Content-Type": "text/plain; charset=utf-8",
        "Cache-Control": "no-store"
      }
    });
  }

  // IMPORTANT:
  // Do not fetch /index.html through ASSETS here. Cloudflare Pages clean URLs
  // can canonicalize /index.html to /, which previously turned this Function
  // response into a redirect to the admin root.
  //
  // Instead, return a tiny Flutter app shell directly. The browser keeps the
  // original /card/<token> URL, so GoRouter receives the client token.
  const manifestUrl = `/card-manifest/${encodeURIComponent(token)}`;

  const html = `<!DOCTYPE html>
<html>
<head>
  <base href="/">
  <meta charset="UTF-8">
  <meta content="IE=Edge" http-equiv="X-UA-Compatible">
  <meta name="description" content="Mi tarjeta Bellamia, beneficios y turnos">
  <meta name="theme-color" content="#8F5E78">
  <meta name="mobile-web-app-capable" content="yes">
  <meta name="apple-mobile-web-app-capable" content="yes">
  <meta name="apple-mobile-web-app-status-bar-style" content="default">
  <meta name="apple-mobile-web-app-title" content="Bellamia">
  <link rel="apple-touch-icon" href="/icons/Icon-192.png">
  <link rel="icon" type="image/png" href="/favicon.png">
  <link rel="manifest" href="${manifestUrl}">
  <title>Bellamia</title>
  <script src="/push_bridge.js"></script>
</head>
<body>
  <script src="/flutter_bootstrap.js" async></script>
</body>
</html>`;

  return new Response(html, {
    status: 200,
    headers: {
      "Content-Type": "text/html; charset=utf-8",
      "Cache-Control": "private, no-store, max-age=0",
      "X-Content-Type-Options": "nosniff"
    }
  });
}
