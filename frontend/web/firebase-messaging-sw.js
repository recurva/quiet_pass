// Firebase Cloud Messaging service worker for QuietPass's web build.
//
// firebase_messaging's web plugin fetches this exact file, at the site
// root, to register the worker that receives a push while no QuietPass
// tab has focus. This file didn't exist, so that fetch 404'd — and
// Flutter web's SPA fallback serves index.html for any unknown path, as
// text/html, which is exactly why the browser console reported
// "firebase-messaging-sw.js" being served as text/html instead of
// JavaScript and the worker failing to register. Adding the real file at
// this path is the actual fix; nothing about MIME-type configuration
// needed to change — a static file that exists here is already served
// correctly (as application/javascript) by both `flutter run -d chrome`'s
// dev server and a real deploy.
//
// This only gets web push registering cleanly. Actually receiving a push
// on web still needs a VAPID key, which hasn't been generated yet (see
// push_client.dart's showPushPermissionSheet._allow doc comment) — until
// that's added in the Firebase console, FirebaseMessaging.getToken() on
// web still throws, and that's already caught there as an accepted,
// non-fatal "this browser won't get pushes" case. This file is what that
// eventual VAPID key needs to exist at all; it does nothing on its own.
importScripts('https://www.gstatic.com/firebasejs/10.13.2/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/10.13.2/firebase-messaging-compat.js');

// Same project config as lib/firebase_options.dart's `web` FirebaseOptions
// — not a secret (it's the same config already baked into the compiled
// web app), so hardcoding it here (service workers can't import Dart
// code) is the normal approach.
firebase.initializeApp({
  apiKey: 'AIzaSyDY_jUeujXElmECRrC2FJxi2pGlR1oOyUg',
  appId: '1:713454357946:web:d447812f5dadab4729a183',
  messagingSenderId: '713454357946',
  projectId: 'quietpass-app',
  authDomain: 'quietpass-app.firebaseapp.com',
  storageBucket: 'quietpass-app.firebasestorage.app',
});

const messaging = firebase.messaging();

// Mirrors push_client.dart's _showLocalNotification for the
// app-in-foreground case: shows the notification payload when a push
// arrives while no QuietPass tab has focus.
messaging.onBackgroundMessage((payload) => {
  const notification = payload.notification;
  if (!notification) return;
  self.registration.showNotification(notification.title, {
    body: notification.body,
    icon: 'icons/Icon-192.png',
  });
});
