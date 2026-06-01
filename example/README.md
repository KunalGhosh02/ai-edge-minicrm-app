# Customer support widget

Drop-in chat widget for third-party websites. Visitors sign in anonymously over
Firebase; messages stream live to and from the on-device assistant running in
the MiniCRM admin app on the provider's phone.

The widget ships **without** any embedded Firebase project — every integrator
points it at their own Firebase project by passing the four required config
fields on the embed.

## Quick start (embed)

Add one script tag to any page. Replace the `REPLACE_WITH_*` placeholders with
values from your **Firebase console → Project settings → General → Your apps →
Web → SDK setup and configuration**, plus the admin's Firebase Auth uid.

```html
<script
  type="module"
  src="https://cdn.jsdelivr.net/gh/KunalGhosh02/ai-edge-minicrm-app@main/example/widget.js"
  data-provider-uid="REPLACE_WITH_ADMIN_UID"
  data-widget-title="Support"
  data-firebase-api-key="REPLACE_WITH_API_KEY"
  data-firebase-auth-domain="REPLACE_WITH_PROJECT_ID.firebaseapp.com"
  data-firebase-project-id="REPLACE_WITH_PROJECT_ID"
  data-firebase-app-id="REPLACE_WITH_APP_ID"
></script>
```

A chat bubble appears in the bottom-right corner. The widget renders inside a
Shadow DOM so host-page CSS does not affect it.

## CDN (jsDelivr)

| Resource | URL |
| -------- | --- |
| Latest (`main`) | `https://cdn.jsdelivr.net/gh/KunalGhosh02/ai-edge-minicrm-app@main/example/widget.js` |
| Pinned release | `https://cdn.jsdelivr.net/gh/KunalGhosh02/ai-edge-minicrm-app@v0.1.0/example/widget.js` |

Pin a tag or commit in production so CDN updates do not surprise you.

## Configuration

### Script attributes

Widget behaviour:

| Attribute | Required | Default | Description |
| --------- | -------- | ------- | ----------- |
| `data-provider-uid` | yes | — | Firebase Auth uid of the MiniCRM admin (provider). |
| `data-widget-title` | no | `Support` | Title shown in the chat panel header. |

Firebase project (Auth + Firestore only — no Storage / FCM / Analytics
needed):

| Attribute | Required | Description |
| --------- | -------- | ----------- |
| `data-firebase-api-key` | yes | Web API key from your Firebase web app config. |
| `data-firebase-auth-domain` | yes | `<project-id>.firebaseapp.com`. |
| `data-firebase-project-id` | yes | Firebase project id. |
| `data-firebase-app-id` | yes | Web app id (looks like `1:1234:web:abcd…`). |

The widget intentionally does **not** ask for `storageBucket`,
`messagingSenderId`, or `measurementId` — they are unused.

### Global config (alternative)

Set everything on `window.miniCrmConfig` before loading the script. Useful
when you generate the page server-side and prefer not to interpolate into
script attributes:

```html
<script>
  window.miniCrmConfig = {
    providerUid: "REPLACE_WITH_ADMIN_UID",
    title: "Acme Support",
    firebase: {
      apiKey: "REPLACE_WITH_API_KEY",
      authDomain: "REPLACE_WITH_PROJECT_ID.firebaseapp.com",
      projectId: "REPLACE_WITH_PROJECT_ID",
      appId: "REPLACE_WITH_APP_ID",
    },
  };
</script>
<script
  type="module"
  src="https://cdn.jsdelivr.net/gh/KunalGhosh02/ai-edge-minicrm-app@main/example/widget.js"
></script>
```

Script attributes take precedence over `window.miniCrmConfig` when both are
set. If any required Firebase field is missing the widget logs a warning to
the console and does not mount.

> **Note on secrets.** The Firebase web API key is **not** a secret — it is a
> public identifier and security is enforced by Firebase Auth + Firestore
> rules. See the [Firebase docs on API keys][api-key-docs]. Always pair the
> embed with [tight Firestore rules](#security-rules).

[api-key-docs]: https://firebase.google.com/docs/projects/api-keys

## Firebase setup

1. Create a Firebase project (or reuse an existing one).
2. **Authentication → Sign-in method**: enable **Anonymous**.
3. **Project settings → General → Your apps → Add app → Web** and copy the
   four fields above into the embed.
4. Apply the Firestore rules below (and tighten before production).

### Security rules

Anonymous users must be able to read and write under their own session path:

```
rules_version = '2';
service cloud.firestore {
  match /databases/{db}/documents {
    match /users/{providerUid}/sessions/{customerId}/{document=**} {
      allow read, write: if request.auth != null
                         && request.auth.uid == customerId;
    }
    match /users/{providerUid} {
      allow read: if request.auth != null;
    }
  }
}
```

## How it works

1. The widget calls `signInAnonymously()` — the visitor's Auth uid becomes
   `customerId`.
2. It subscribes to
   `users/<providerUid>/sessions/<customerUid>/messages` ordered by
   `createdAt`.
3. Outgoing customer messages use the same batched write the admin app's
   `SupportReactor` consumes (message doc + merged session metadata).
4. Assistant replies written by the admin app appear in the widget in real
   time.

## Local demos

Serve the **repository root** over HTTP — Firebase Auth refuses `file://`
origins:

```bash
cd ai-edge-minicrm-app
python3 -m http.server 5173
```

| Demo | URL | Description |
| ---- | --- | ----------- |
| Customer test bed | http://localhost:5173/example/customer-demo.html | Full-page chat UI — paste the admin uid, connect, and send messages as an anonymous customer. |
| Embedded host site | http://localhost:5173/example/host-site.html | Fictional coffee-shop page with the floating widget. |

### Prerequisites

1. MiniCRM admin app signed in to Firebase (note the admin Auth uid).
2. Firestore rules that allow anonymous customers to read/write their own
   session (see above).
3. **Authentication → Sign-in method → Anonymous** enabled.

### Customer test bed

[`customer-demo.html`](customer-demo.html) is a self-contained page that does
**not** load `widget.js`. To point it at your Firebase project, replace the
`REPLACE_WITH_*` values in the `firebaseConfig` object (same four fields as
the widget script tag).

It mirrors the Firestore path the admin app expects:

```
users/<providerUid>/sessions/<customerAnonUid>/messages/<msgId>
```

### Embedded host site

[`host-site.html`](host-site.html) loads `./widget.js` locally. Replace the
`REPLACE_WITH_*` placeholders in the script tag with your Firebase web config
and the admin uid before opening the page.

For production, swap `./widget.js` for the jsDelivr URL from the table above.

## Troubleshooting

| Symptom | Likely cause |
| ------- | ------------- |
| `[minicrm-widget] missing Firebase config field(s): …` warning | One or more `data-firebase-*` attributes missing or empty. |
| Auth errors on load | Page opened via `file://`, or domain not added to **Auth → Settings → Authorized domains**. |
| `permission-denied` on send | Firestore rules block the anonymous uid. |
| No assistant replies | Admin app offline, wrong provider uid, or support not online. |
| Widget does not appear | Missing `data-provider-uid` (check the browser console). |

## Files

```
example/
├── README.md
├── widget.js           # Embeddable entry point (CDN target)
├── customer-demo.html  # Standalone customer chat test bed
└── host-site.html      # Sample third-party site with the widget
```
