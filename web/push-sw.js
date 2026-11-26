self.addEventListener("push", (event) => {
  let data = {};

  try {
    data = event.data ? event.data.json() : {};
  } catch (_) {
    data = {
      title: "{{APP_SHORT_NAME}}",
      body: event.data ? event.data.text() : "Tenés una nueva notificación.",
    };
  }

  const title = data.title || "{{APP_NAME}}";
  const url = data.url || "/";

  event.waitUntil(
    self.registration.showNotification(title, {
      body: data.body || "",
      icon: "/icons/Icon-192.png",
      badge: "/icons/Icon-192.png",
      tag: data.tag || undefined,
      renotify: false,
      data: { url },
    })
  );
});

self.addEventListener("notificationclick", (event) => {
  event.notification.close();

  const targetUrl = new URL(
    event.notification.data?.url || "/",
    self.location.origin
  );

  event.waitUntil(
    (async () => {
      const clientList = await clients.matchAll({
        type: "window",
        includeUncontrolled: true,
      });

      const targetPath = targetUrl.pathname;

      // Admin notifications must never reuse/focus a client-card window,
      // and client notifications must never reuse/focus the admin PWA.
      const matchingClient = clientList.find((client) => {
        try {
          const current = new URL(client.url);

          if (targetPath.startsWith("/admin")) {
            return current.pathname.startsWith("/admin");
          }

          if (targetPath.startsWith("/card/")) {
            return current.pathname.startsWith("/card/");
          }

          return current.origin === targetUrl.origin;
        } catch (_) {
          return false;
        }
      });

      if (matchingClient) {
        try {
          if ("navigate" in matchingClient) {
            await matchingClient.navigate(targetUrl.href);
          }
        } catch (_) {}

        if ("focus" in matchingClient) {
          return matchingClient.focus();
        }
      }

      // No matching app window exists: open the exact notification URL.
      if (clients.openWindow) {
        return clients.openWindow(targetUrl.href);
      }
    })()
  );
});
