function validUuid(value) {
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(
    value || ""
  );
}

export async function onRequestGet(context) {
  const token = context.params.token;

  if (!validUuid(token)) {
    return new Response("Invalid token", {
      status: 400,
      headers: {
        "Content-Type": "text/plain; charset=utf-8",
        "Cache-Control": "no-store"
      }
    });
  }

  const cardUrl = `/card/${token}`;
  const manifest = {
    id: cardUrl,
    name: "Bellamia Lashes Studio",
    short_name: "Bellamia",
    description: "Mi tarjeta Bellamia, beneficios y turnos",
    start_url: cardUrl,
    scope: "/card/",
    display: "standalone",
    orientation: "portrait",
    background_color: "#FFF9FB",
    theme_color: "#8F5E78",
    icons: [
      { src: "/icons/Icon-192.png", sizes: "192x192", type: "image/png" },
      { src: "/icons/Icon-512.png", sizes: "512x512", type: "image/png" },
      { src: "/icons/Icon-maskable-192.png", sizes: "192x192", type: "image/png", purpose: "maskable" },
      { src: "/icons/Icon-maskable-512.png", sizes: "512x512", type: "image/png", purpose: "maskable" }
    ]
  };

  return new Response(JSON.stringify(manifest), {
    status: 200,
    headers: {
      "Content-Type": "application/manifest+json; charset=utf-8",
      "Cache-Control": "private, no-store, max-age=0",
      "X-Content-Type-Options": "nosniff"
    }
  });
}
