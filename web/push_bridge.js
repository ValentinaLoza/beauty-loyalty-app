(function () {
  const CLIENT_PWA_TARGET_KEY = "bellamia_client_pwa_token";

  function isStandaloneDisplay() {
    return (
      window.matchMedia?.("(display-mode: standalone)")?.matches === true ||
      window.navigator.standalone === true
    );
  }

  function validUuid(value) {
    return /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(
      value || ""
    );
  }

  window.bellamiaSetClientPwaTarget = function (token) {
    if (!validUuid(token)) return false;
    localStorage.setItem(CLIENT_PWA_TARGET_KEY, token);
    return true;
  };

  window.bellamiaGetClientPwaTarget = function () {
    return localStorage.getItem(CLIENT_PWA_TARGET_KEY) || "";
  };

  window.bellamiaSetAdminPwaTarget = function () {
    localStorage.removeItem(CLIENT_PWA_TARGET_KEY);
    return true;
  };


  window.bellamiaPrepareClientInstall = function (token) {
    if (!validUuid(token)) return false;

    localStorage.setItem(CLIENT_PWA_TARGET_KEY, token);

    let manifest = document.querySelector('link[rel="manifest"]');

    if (!manifest) {
      manifest = document.createElement("link");
      manifest.setAttribute("rel", "manifest");
      document.head.appendChild(manifest);
    }

    // Keep a manifest tied to this exact client token.
    // This is what makes the installed iPhone PWA reopen /card/<token>.
    manifest.setAttribute(
      "href",
      "/card-manifest/" + encodeURIComponent(token)
    );

    return true;
  };

  window.bellamiaPrepareAdminInstall = function () {
    localStorage.removeItem(CLIENT_PWA_TARGET_KEY);

    let manifest = document.querySelector('link[rel="manifest"]');

    if (!manifest) {
      manifest = document.createElement("link");
      manifest.setAttribute("rel", "manifest");
      document.head.appendChild(manifest);
    }

    manifest.setAttribute("href", "/manifest.json");
    return true;
  };



  function env() {
    const ua = navigator.userAgent || "";
    const ios = /iPad|iPhone|iPod/.test(ua) ||
      (navigator.platform === "MacIntel" && navigator.maxTouchPoints > 1);

    const standalone =
      window.matchMedia?.("(display-mode: standalone)")?.matches === true ||
      window.navigator.standalone === true;

    return {
      supported:
        "serviceWorker" in navigator &&
        "PushManager" in window &&
        "Notification" in window,
      permission:
        "Notification" in window ? Notification.permission : "unsupported",
      ios,
      standalone,
    };
  }

  function urlBase64ToUint8Array(base64String) {
    const padding = "=".repeat((4 - (base64String.length % 4)) % 4);
    const base64 = (base64String + padding)
      .replace(/-/g, "+")
      .replace(/_/g, "/");

    const rawData = window.atob(base64);
    const outputArray = new Uint8Array(rawData.length);

    for (let i = 0; i < rawData.length; ++i) {
      outputArray[i] = rawData.charCodeAt(i);
    }
    return outputArray;
  }

  async function waitForActivation(registration) {
    if (registration.active) return;

    const worker = registration.installing || registration.waiting;
    if (!worker) {
      await new Promise((resolve) => setTimeout(resolve, 250));
      if (!registration.active) {
        throw new Error("SERVICE_WORKER_NOT_ACTIVE");
      }
      return;
    }

    if (worker.state === "activated") return;

    await new Promise((resolve, reject) => {
      const timeout = setTimeout(
        () => reject(new Error("SERVICE_WORKER_TIMEOUT")),
        10000
      );

      worker.addEventListener("statechange", () => {
        if (worker.state === "activated") {
          clearTimeout(timeout);
          resolve();
        } else if (worker.state === "redundant") {
          clearTimeout(timeout);
          reject(new Error("SERVICE_WORKER_REDUNDANT"));
        }
      });
    });
  }

  window.bellamiaPushEnvironment = function () {
    return JSON.stringify(env());
  };

  window.bellamiaPushSubscribe = async function (vapidPublicKey) {
    const current = env();

    if (!current.supported) {
      throw new Error("PUSH_NOT_SUPPORTED");
    }

    // On iOS/iPadOS Web Push is intended for a Home Screen web app.
    if (current.ios && !current.standalone) {
      throw new Error("IOS_HOME_SCREEN_REQUIRED");
    }

    if (!vapidPublicKey) {
      throw new Error("VAPID_PUBLIC_KEY_MISSING");
    }

    let permission = Notification.permission;
    if (permission === "default") {
      permission = await Notification.requestPermission();
    }

    if (permission !== "granted") {
      throw new Error("NOTIFICATION_PERMISSION_DENIED");
    }

    // Use a deliberately narrow SW scope so it does not conflict with any
    // Flutter caching service worker that might already exist at "/".
    const registration = await navigator.serviceWorker.register(
      "/push-sw.js",
      { scope: "/push-notifications/" }
    );

    await waitForActivation(registration);

    let subscription = await registration.pushManager.getSubscription();

    if (!subscription) {
      subscription = await registration.pushManager.subscribe({
        userVisibleOnly: true,
        applicationServerKey: urlBase64ToUint8Array(vapidPublicKey),
      });
    }

    const json = subscription.toJSON();

    return JSON.stringify({
      endpoint: json.endpoint,
      p256dh: json.keys?.p256dh || "",
      auth: json.keys?.auth || "",
      deviceLabel: navigator.userAgent || "Web",
    });
  };
})();
