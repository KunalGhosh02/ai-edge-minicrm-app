# MiniCRM

A Flutter Android app that runs a fully on-device, RAG-augmented LLM
assistant alongside a small CRM-style shell. It's used as a reference
implementation for a strict, feature-first architecture built on Riverpod
and `go_router`.

## What it does

- **Chat with a local LLM.** Download a `.litertlm` model (Gemma 4, Qwen 2.5,
  Qwen 3, DeepSeek-R1, …), keep it warm in a foreground worker, and chat in
  WhatsApp-style threads that persist across launches.
- **Retrieval-augmented answers.** Add documents (plain text or PDF), chunk
  them, embed each chunk with EmbeddingGemma, and the assistant pulls the
  top-3 most relevant chunks into every prompt via ObjectBox vector search.
- **Thoughts vs. answer.** Reasoning families (Gemma 4, DeepSeek-R1, Qwen 3)
  stream their `<think>` channel into a collapsible "Thoughts" panel while
  the answer renders as markdown / HTML in the bubble.
- **Stays alive in the background.** The model and embedder live in a
  `flutter_foreground_task` worker isolate, so generation and indexing
  survive the app being backgrounded.

Everything runs on-device — no network calls except for model downloads.

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
  custom system prompt
- **Downloads:** [`dio`](https://pub.dev/packages/dio) with HTTP Range
  resume + bearer auth (Hugging Face)
- **PDFs:** [`syncfusion_flutter_pdf`](https://pub.dev/packages/syncfusion_flutter_pdf)
  +  [`file_picker`](https://pub.dev/packages/file_picker)
- **Rich text:** [`markdown`](https://pub.dev/packages/markdown) +
  [`flutter_widget_from_html_core`](https://pub.dev/packages/flutter_widget_from_html_core)
- **Lints:** [`very_good_analysis`](https://pub.dev/packages/very_good_analysis) + strict analyzer

## Platform

Android only (arm64-v8a). `minSdk = 26`; LiteRT-LM needs API 24+ and the
foreground worker needs API 26. iOS / desktop / web are not configured.

## Quick start

```bash
fvm install                       # install the pinned Flutter SDK
fvm flutter pub get
fvm flutter pub run build_runner build --delete-conflicting-outputs
fvm flutter run                   # arm64 Android device
```

The `build_runner` step generates the ObjectBox bindings (`objectbox.g.dart`,
`objectbox-model.json`). Run it again whenever you change an `@Entity()`.

### First launch

1. Open **Assistant → Models** and download a model preset (Gemma 4 E2B is a
   good default ~2.5 GB).
2. Optionally download **EmbeddingGemma 300M (seq 512, flutter_gemma)** for
   RAG. Some presets require a Hugging Face token (paste it in the install
   dialog); the app stores it only for the in-flight download.
3. **Context → Add document** to index PDFs or pasted text. Indexing
   progress streams live from the worker.
4. **Settings → System prompt** to customise the assistant's persona.

## Useful commands

```bash
fvm flutter analyze               # static analysis (must be 0 issues)
fvm flutter test                  # unit + widget tests
fvm dart format .
fvm flutter pub run build_runner watch     # regen ObjectBox on entity change
fvm flutter clean && fvm flutter pub get   # reset plugin registrant
```

## Project layout

```
lib/
├── main.dart                     # entrypoint, FlutterGemma + ObjectBox bootstrap
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
    ├── context/                  # RAG: PDFs, chunking, vector search
    └── settings/                 # custom system prompt

test/
└── features/assistant/data/      # IPC round-trip tests
```

## Architecture notes

- **Two isolates, one wire.** The UI talks to the worker isolate exclusively
  through `FlutterForegroundTask.sendDataToTask` / `sendDataToMain` with
  `Map<String, dynamic>` payloads serialised from the sealed `AssistantCommand`
  / `AssistantEvent` types in
  `features/assistant/data/ipc/assistant_ipc.dart`.
- **Chat threads.** Persisted in ObjectBox. When the user opens a thread,
  the controller calls `service.switchChat(...)` which tears down the
  current `InferenceChat`, recreates it with the thread's
  `systemInstruction` + `chatFamily`, and replays a tail of the history
  (bounded by `maxTokens`) via `chat.addQueryChunk(...)` so the KV cache is
  warm for the next turn.
- **RAG pipeline.** Documents → text (PDF extractor for `.pdf`) → chunks
  inserted into ObjectBox without embeddings → worker drain loop picks
  unembedded chunks in batches of 16 → `embedder.embed(...)` → store
  vectors. Retrieval is HNSW vector search (top-3) with a lexical
  fallback when no embedder is loaded.
- **Native LiteRT-LM coexistence.** `flutter_litert_lm` and
  `flutter_gemma` both link the same `libLiteRtLm.so`. Mixing them
  segfaults; only `flutter_gemma` is used here.

## Things to watch

- **Strict analyzer.** `analysis_options.yaml` enables `strict-casts`,
  `strict-inference`, and `strict-raw-types` on top of `very_good_analysis`.
  CI expects `flutter analyze` to be 0 issues.
- **Widgets are classes, not functions.** No `Widget _buildFoo()` helpers;
  extract a private `_Foo extends StatelessWidget` instead.
