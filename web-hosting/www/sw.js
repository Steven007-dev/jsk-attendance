/* Install the click handler before Firebase; Firebase displays background notification payloads. */
self.addEventListener("notificationclick", (event) => {
  event.notification.close();
  const data = event.notification.data || {};
  const url = new URL("/", self.location.origin);
  url.searchParams.set("jskPush", "1");
  ["notificationId", "type", "refType", "refId"].forEach((key) => {
    if (data[key]) url.searchParams.set(key, String(data[key]));
  });
  const target = url.href;
  event.waitUntil(clients.matchAll({ type: "window", includeUncontrolled: true }).then((windows) => {
    for (const client of windows) {
      if (new URL(client.url).origin === self.location.origin) {
        client.postMessage({ type: "JSK_PUSH_OPEN", data });
        return client.focus();
      }
    }
    return clients.openWindow(target);
  }));
});

importScripts("/fcm-config.js");
importScripts("https://www.gstatic.com/firebasejs/10.14.1/firebase-app-compat.js");
importScripts("https://www.gstatic.com/firebasejs/10.14.1/firebase-messaging-compat.js");

const config = self.JSK_FIREBASE_CONFIG || {};
let messaging = null;
if (config.apiKey && config.projectId && config.messagingSenderId && config.appId) {
  try {
    firebase.initializeApp(config);
    messaging = firebase.messaging();
  } catch (error) {
    console.error("JSK FCM worker could not initialize.");
  }
}

// Notification messages are shown by FCM automatically when the site is closed.
