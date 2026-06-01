# MiniCRM

A Flutter Android app that runs a fully on-device, RAG-augmented LLM
assistant alongside a small CRM-style shell. It doubles as a reference
implementation for a strict, feature-first architecture built on Riverpod
and `go_router`, and ships with an embeddable web widget so third-party
sites can talk to the assistant over Firebase.

> Everything inference-related runs **on-device** — the only network calls
> are model downloads from Hugging Face and the optional Firebase support
> channel.

## Table of contents

- [Features](#features)
- [Stack](#stack)
- [Platform](#platform)
- [Getting started](#getting-started)
- [First launch](#first-launch)
- [Customer support widget](#customer-support-widget)
- [Project layout](#project-layout)
- [Architecture](#architecture)
- [Development](#development)
- [Contributing](#contributing)
- [License](#license)

## Features

- **Chat with a local LLM.** Download a `.litertlm` model (Gemma 4, Qwen 2.5,
  Qwen 3, DeepSeek-R1, …), keep it warm in a foreground worker, and chat in
  WhatsApp-style threads that persist across launches.
- **Retrieval-augmented answers.** Add documents (plain text or PDF), chunk
  them, embed each chunk with EmbeddingGemma, and the assistant pulls the
  top-3 most relevant chunks into every prompt via ObjectBox vector search.
- **Thoughts vs. answer.** Reasoning families (Gemma 4, DeepSeek-R1, Qwen 3)
  stream their `<think>` channel into a collapsible "Thoughts" panel while
  the answer renders as markdown / HTML in the bubble.
- **Customer support over Firebase.** Sign in with Google, go online, and a
  background `SupportReactor` answers customer messages routed through
  Firestore. An embeddable `widget.js` lets any website plug into it.
- **Stays alive in the background.** The model and embedder live in a
  `flutter_foreground_task` worker isolate, so generation and indexing
  survive the app being backgrounded.

## Stack

- **Flutter** 3.44 (Material 3, Dart 3.12), pinned via [FVM](https://fvm.app)
- **State management:** [`flutter_riverpod`](https://pub.dev/packages/flutter_riverpod) 3.x
- **Routing:** [`go_router`](https://pub.dev/packages/go_router)
- **On-device inference:** [`flutter_gemma`](https://pub.dev/packages/flutter_gemma)
  (LiteRT-LM FFI) for both LLM and EmbeddingGemma; legacy
  [`tflite_flutter`](https://pub.dev/packages/tflite_flutter) +
  [`dart_sentencepiece_tokenizer`](https://pub.dev/packages/dart_sentencepiece_tokenizer)
  path kept for the older `.tflite` embedder presets
- **Foreground worker:** [`flutter_foreground_task`](https://pub.dev/packages/flutter_foreground_task)
- **Storage:** [`objectbox`](https://pub.dev/packages/objectbox) (HNSW vector
  index for RAG; chat threads + messages; document chunks),
  [`shared_preferences`](https://pub.dev/packages/shared_preferences) for the
  custom system prompt,
  [`flutter_secure_storage`](https://pub.dev/packages/flutter_secure_storage)
  for the Hugging Face token
- **Cloud:** [`firebase_core`](https://pub.dev/packages/firebase_core),
  [`firebase_auth`](https://pub.dev/packages/firebase_auth),
  [`cloud_firestore`](https://pub.dev/packages/cloud_firestore),
  [`google_sign_in`](https://pub.dev/packages/google_sign_in)
- **Downloads:** [`dio`](https://pub.dev/packages/dio) with HTTP Range
  resume + bearer auth (Hugging Face)
- **PDFs:** [`syncfusion_flutter_pdf`](https://pub.dev/packages/syncfusion_flutter_pdf)
  + [`file_picker`](https://pub.dev/packages/file_picker)
- **Rich text:** [`markdown`](https://pub.dev/packages/markdown) +
  [`flutter_widget_from_html_core`](https://pub.dev/packages/flutter_widget_from_html_core)
- **Lints:** [`very_good_analysis`](https://pub.dev/packages/very_good_analysis) + strict analyzer

## Platform

Android only (`arm64-v8a`). `minSdk = 26` — LiteRT-LM needs API 24+ and the
foreground worker needs API 26. iOS, desktop, and web targets are not
configured.

## Getting started

### Prerequisites

- [FVM](https://fvm.app) (the Flutter SDK version is pinned in `.fvmrc`)
- Android SDK + an `arm64-v8a` device or emulator
- _(Optional)_ A Firebase project, if you want Google sign-in and the
  customer support channel — see [Firebase setup](#firebase-setup)

### Install and run

```bash
git clone https://github.com/KunalGhosh02/ai-edge-minicrm-app.git
cd ai-edge-minicrm-app

fvm install                                                       # pinned Flutter SDK
fvm flutter pub get
fvm flutter pub run build_runner build --delete-conflicting-outputs
fvm flutter run                                                   # arm64 Android device
```

The `build_runner` step generates the ObjectBox bindings (`objectbox.g.dart`,
`objectbox-model.json`). Re-run it whenever you change an `@Entity()`.

### Firebase setup

The cloud / customer-support feature is optional. To enable it:

1. Create a Firebase project (or reuse one).
2. Add an Android app with package name `com.minicrm.minicrm` and download
   `google-services.json` into `android/app/`. A redacted template lives at
   [`android/app/google-services.json.example`](android/app/google-services.json.example).
3. Enable **Authentication → Sign-in method → Google** (and **Anonymous**
   if you want to use the customer widget).
4. Apply Firestore rules that allow customer sessions under
   `users/<providerUid>/sessions/<customerUid>/...` — see
   [`example/README.md`](example/README.md#security-rules) for a starter
   ruleset.

## First launch

1. Open **Assistant → Models** and download a model preset (Gemma 4 E2B is a
   good default ~2.5 GB).
2. Optionally download **EmbeddingGemma 300M (seq 512, flutter_gemma)** for
   RAG. Some presets require a Hugging Face token (paste it in the install
   dialog); the app stores it only for the in-flight download.
3. **Context → Add document** to index PDFs or pasted text. Indexing
   progress streams live from the worker.
4. **Settings → System prompt** to customise the assistant's persona.
5. _(Optional)_ **Cloud → Sign in with Google → Go online** to start
   answering customer messages routed through Firestore.

## Customer support widget

Third-party sites can embed a floating chat bubble that talks to the admin
app over Firebase. The visitor signs in anonymously, the message is routed
to the provider's MiniCRM phone, and the on-device assistant answers in
real time.

```html
<script
  type="module"
  src="https://cdn.jsdelivr.net/gh/KunalGhosh02/ai-edge-minicrm-app@main/example/widget.js"
  data-provider-uid="YOUR_ADMIN_UID"
  data-widget-title="Support"
  data-firebase-api-key="YOUR_FIREBASE_API_KEY"
  data-firebase-auth-domain="YOUR_PROJECT_ID.firebaseapp.com"
  data-firebase-project-id="YOUR_PROJECT_ID"
  data-firebase-app-id="YOUR_FIREBASE_APP_ID"
></script>
```

The widget is project-agnostic — every integrator points it at their own
Firebase project. The four `data-firebase-*` fields come from **Firebase
console → Project settings → General → Your apps → Web** and are the only
ones needed for Auth + Firestore.

| Resource | URL |
| -------- | --- |
| Latest (`main`) | `https://cdn.jsdelivr.net/gh/KunalGhosh02/ai-edge-minicrm-app@main/example/widget.js` |
| Pinned release | `https://cdn.jsdelivr.net/gh/KunalGhosh02/ai-edge-minicrm-app@v0.1.0/example/widget.js` |

Full attribute reference, `window.miniCrmConfig` alternative, Firestore
security rules, and runnable demos (`customer-demo.html`, `host-site.html`)
live under [`example/`](example/README.md).

## Project layout

```
lib/
├── main.dart                     # entrypoint; FlutterGemma + ObjectBox bootstrap
├── app/                          # MaterialApp.router, GoRouter, ThemeData
├── core/
│   └── storage/                  # ObjectBoxStore (open + attach)
└── features/
    ├── home/                     # landing screen with nav cards
    ├── assistant/                # on-device LLM chat + threads
    │   ├── domain/               # entities + repository interfaces
    │   ├── data/
    │   │   ├── ipc/              # sealed AssistantCommand / AssistantEvent
    │   │   ├── task/             # AssistantTaskHandler (worker isolate)
    │   │   ├── service/          # ForegroundAssistantService (UI isolate)
    │   │   ├── embedder/         # flutter_gemma + legacy tflite embedders
    │   │   ├── models/           # ObjectBox @Entity for threads + messages
    │   │   └── repositories/     # ChatHistoryRepository impl
    │   └── presentation/         # Riverpod controllers + screens + widgets
    ├── cloud/                    # Firebase auth + Firestore customer sessions
    │   ├── domain/               # AuthUser, CustomerSession, CustomerMessage
    │   ├── data/
    │   │   ├── repositories/     # FirebaseAuth + Firestore impls
    │   │   ├── subscribers/      # CloudResponseSubscriber (assistant → Firestore)
    │   │   └── services/         # SupportReactor (Firestore → assistant)
    │   └── presentation/         # sign-in, customer chat, online toggle
    ├── context/                  # RAG: PDFs, chunking, vector search
    └── settings/                 # custom system prompt

test/
└── features/assistant/data/      # IPC round-trip tests

example/
├── README.md                     # widget docs, jsDelivr URLs, demo guide
├── widget.js                     # embeddable customer chat (jsDelivr CDN)
├── customer-demo.html            # full-page Firestore test bed
└── host-site.html                # sample site with the floating widget
```

## Architecture

- **Two isolates, one wire.** The UI talks to the worker isolate exclusively
  through `FlutterForegroundTask.sendDataToTask` / `sendDataToMain` with
  `Map<String, dynamic>` payloads serialised from the sealed
  `AssistantCommand` / `AssistantEvent` types in
  [`features/assistant/data/ipc/assistant_ipc.dart`](lib/features/assistant/data/ipc/assistant_ipc.dart).
- **Chat threads.** Persisted in ObjectBox. When the user opens a thread,
  the controller calls `service.switchChat(...)` which tears down the
  current `InferenceChat`, recreates it with the thread's
  `systemInstruction` + `chatFamily`, and replays a tail of the history
  (bounded by `maxTokens`) via `chat.addQueryChunk(...)` so the KV cache is
  warm for the next turn.
- **RAG pipeline.** Documents → text (PDF extractor for `.pdf`) → chunks
  inserted into ObjectBox without embeddings → worker drain loop picks
  unembedded chunks in batches of 16 → `embedder.embed(...)` → store
  vectors. Retrieval is HNSW vector search (top-3) with a lexical fallback
  when no embedder is loaded.
- **Cloud loop.** When support is online, `SupportReactor` watches
  `users/<providerUid>/sessions/*` for new customer messages, replays the
  thread's history through the assistant, and `CloudResponseSubscriber`
  writes streamed assistant tokens back into Firestore. The customer widget
  reads the same path.
- **Native LiteRT-LM coexistence.** `flutter_litert_lm` and `flutter_gemma`
  both link the same `libLiteRtLm.so`. Mixing them segfaults; only
  `flutter_gemma` is used here.

For deeper conventions see [`AGENTS.md`](AGENTS.md).

## Development

```bash
fvm flutter analyze                         # static analysis (must be 0 issues)
fvm flutter test                            # unit + widget tests
fvm dart format .
fvm flutter pub run build_runner watch      # regen ObjectBox on entity change
fvm flutter clean && fvm flutter pub get    # reset plugin registrant
```

CI / pre-commit expectations:

- `fvm flutter analyze` reports **0 issues**.
- `fvm flutter test` passes.
- No new files with comments (see [`AGENTS.md`](AGENTS.md#1-no-comments-in-code)
  for the rule and the few allowed exceptions).
- No new builder functions that return `Widget` — widgets are classes.

## Contributing

1. Read [`AGENTS.md`](AGENTS.md) — it documents the non-negotiable
   conventions (feature-first layout, no in-code comments, widgets are
   classes, Riverpod-only state, sealed IPC types for foreground workers).
2. Write a failing test in `test/features/<feature>/...` before fixing a
   bug.
3. Keep `fvm flutter analyze` and `fvm flutter test` green.
4. Format with `fvm dart format .`.
5. Open a PR with a focused diff.

## License

[MIT](LICENSE) © 2026 Kunal Ghosh
