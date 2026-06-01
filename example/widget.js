import { initializeApp } from "https://www.gstatic.com/firebasejs/12.13.0/firebase-app.js";
import {
  getAuth,
  signInAnonymously,
  onAuthStateChanged,
} from "https://www.gstatic.com/firebasejs/12.13.0/firebase-auth.js";
import {
  getFirestore,
  collection,
  doc,
  query,
  orderBy,
  onSnapshot,
  Timestamp,
  writeBatch,
} from "https://www.gstatic.com/firebasejs/12.13.0/firebase-firestore.js";
import { marked } from "https://cdn.jsdelivr.net/npm/marked@13.0.3/+esm";
import DOMPurify from "https://cdn.jsdelivr.net/npm/dompurify@3.1.7/+esm";

marked.setOptions({ gfm: true, breaks: true });

function renderMarkdown(text) {
  const html = marked.parse(text ?? "", { async: false });
  return DOMPurify.sanitize(html, {
    USE_PROFILES: { html: true },
    FORBID_TAGS: ["style", "iframe", "form", "input", "script"],
    FORBID_ATTR: ["style", "onerror", "onclick", "onload"],
  });
}

const REQUIRED_FIREBASE_FIELDS = [
  "apiKey",
  "authDomain",
  "projectId",
  "appId",
];

const FIREBASE_ATTR_MAP = {
  apiKey: "data-firebase-api-key",
  authDomain: "data-firebase-auth-domain",
  projectId: "data-firebase-project-id",
  appId: "data-firebase-app-id",
};

function readScriptAttribute(name) {
  const tagged = document.querySelector(`script[${name}]`);
  const value = tagged?.getAttribute(name);
  return value && value.trim() ? value.trim() : null;
}

function resolveProviderUid() {
  return (
    readScriptAttribute("data-provider-uid") ??
    window.miniCrmConfig?.providerUid ??
    null
  );
}

function resolveTitle() {
  return (
    readScriptAttribute("data-widget-title") ??
    window.miniCrmConfig?.title ??
    "Support"
  );
}

function resolveFirebaseConfig() {
  const fromGlobal = window.miniCrmConfig?.firebase ?? {};
  const config = {};
  for (const field of REQUIRED_FIREBASE_FIELDS) {
    config[field] =
      readScriptAttribute(FIREBASE_ATTR_MAP[field]) ?? fromGlobal[field] ?? null;
  }
  const missing = REQUIRED_FIREBASE_FIELDS.filter((f) => !config[f]);
  if (missing.length > 0) {
    return { config: null, missing };
  }
  return { config, missing: [] };
}

const SHADOW_CSS = `
  :host { all: initial; }
  * { box-sizing: border-box; }
  .root {
    position: fixed;
    right: 24px;
    bottom: 24px;
    z-index: 2147483600;
    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto,
      "Helvetica Neue", sans-serif;
    color: #1a1d24;
  }
  .bubble {
    width: 56px;
    height: 56px;
    border-radius: 50%;
    background: #2257d6;
    color: white;
    display: flex;
    align-items: center;
    justify-content: center;
    cursor: pointer;
    box-shadow: 0 6px 20px rgba(0, 0, 0, 0.25);
    transition: transform 120ms ease;
  }
  .bubble:hover { transform: scale(1.05); }
  .bubble svg { width: 26px; height: 26px; fill: white; }
  .panel {
    position: absolute;
    right: 0;
    bottom: 72px;
    width: 360px;
    max-width: calc(100vw - 32px);
    height: 520px;
    max-height: calc(100vh - 120px);
    background: white;
    border-radius: 16px;
    box-shadow: 0 16px 48px rgba(0, 0, 0, 0.2);
    display: none;
    flex-direction: column;
    overflow: hidden;
    transform-origin: bottom right;
  }
  .panel.open {
    display: flex;
    animation: pop 140ms ease both;
  }
  @keyframes pop {
    from { transform: scale(0.94) translateY(8px); opacity: 0; }
    to { transform: scale(1) translateY(0); opacity: 1; }
  }
  .header {
    background: #2257d6;
    color: white;
    padding: 14px 16px;
    display: flex;
    align-items: center;
    justify-content: space-between;
  }
  .header .title { font-weight: 600; font-size: 15px; }
  .header .sub { font-size: 11px; opacity: 0.75; margin-top: 2px; }
  .close-btn {
    background: transparent;
    border: none;
    color: white;
    font-size: 22px;
    cursor: pointer;
    line-height: 1;
  }
  .messages {
    flex: 1;
    padding: 12px;
    background: #f5f7fb;
    overflow-y: auto;
    display: flex;
    flex-direction: column;
    gap: 6px;
  }
  .msg {
    max-width: 80%;
    padding: 8px 12px;
    border-radius: 14px;
    font-size: 14px;
    line-height: 1.35;
    white-space: pre-wrap;
    word-wrap: break-word;
  }
  .msg.customer {
    align-self: flex-end;
    background: #2257d6;
    color: white;
    border-bottom-right-radius: 4px;
  }
  .msg.assistant {
    align-self: flex-start;
    background: #e6eaf4;
    color: #1a1d24;
    border-bottom-left-radius: 4px;
  }
  .msg.assistant .body > :first-child { margin-top: 0; }
  .msg.assistant .body > :last-child { margin-bottom: 0; }
  .msg.assistant .body p { margin: 6px 0; }
  .msg.assistant .body h1,
  .msg.assistant .body h2,
  .msg.assistant .body h3,
  .msg.assistant .body h4 {
    margin: 10px 0 4px;
    line-height: 1.2;
    font-weight: 600;
  }
  .msg.assistant .body h1 { font-size: 17px; }
  .msg.assistant .body h2 { font-size: 16px; }
  .msg.assistant .body h3 { font-size: 15px; }
  .msg.assistant .body h4 { font-size: 14px; }
  .msg.assistant .body ul,
  .msg.assistant .body ol {
    margin: 6px 0;
    padding-left: 20px;
  }
  .msg.assistant .body li { margin: 2px 0; }
  .msg.assistant .body a {
    color: #2257d6;
    text-decoration: underline;
  }
  .msg.assistant .body code {
    background: rgba(0, 0, 0, 0.08);
    padding: 1px 5px;
    border-radius: 4px;
    font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
    font-size: 12.5px;
  }
  .msg.assistant .body pre {
    background: #1d222c;
    color: #f0f2f7;
    padding: 8px 10px;
    border-radius: 8px;
    overflow-x: auto;
    margin: 6px 0;
    font-size: 12.5px;
    line-height: 1.4;
  }
  .msg.assistant .body pre code {
    background: transparent;
    padding: 0;
    color: inherit;
  }
  .msg.assistant .body blockquote {
    border-left: 3px solid #b6c0d6;
    margin: 6px 0;
    padding: 2px 10px;
    color: #44516b;
  }
  .msg.assistant .body table {
    border-collapse: collapse;
    margin: 6px 0;
    font-size: 12.5px;
  }
  .msg.assistant .body th,
  .msg.assistant .body td {
    border: 1px solid #c4cce0;
    padding: 4px 8px;
    text-align: left;
  }
  .msg.assistant .body hr {
    border: none;
    border-top: 1px solid #c4cce0;
    margin: 8px 0;
  }
  .meta { font-size: 10px; opacity: 0.7; margin-top: 2px; }
  .empty {
    color: #5b6577;
    text-align: center;
    padding: 24px 12px;
    font-size: 13px;
  }
  .error {
    background: #ffe6e6;
    color: #a01515;
    font-size: 12px;
    padding: 6px 12px;
    text-align: center;
  }
  .input-row {
    display: flex;
    gap: 6px;
    padding: 8px;
    border-top: 1px solid #e0e4ee;
    background: white;
  }
  .input-row textarea {
    flex: 1;
    resize: none;
    border: 1px solid #d9deea;
    border-radius: 10px;
    padding: 8px 10px;
    font-size: 14px;
    font-family: inherit;
    min-height: 38px;
    max-height: 120px;
    outline: none;
  }
  .input-row textarea:focus { border-color: #2257d6; }
  .input-row button {
    background: #2257d6;
    color: white;
    border: none;
    border-radius: 10px;
    padding: 0 14px;
    font-size: 14px;
    cursor: pointer;
  }
  .input-row button:disabled { opacity: 0.5; cursor: not-allowed; }
`;

const CHAT_ICON = `
  <svg viewBox="0 0 24 24" aria-hidden="true">
    <path d="M4 4h16a2 2 0 0 1 2 2v10a2 2 0 0 1-2 2H8l-4 4V6a2 2 0 0 1 2-2z"/>
  </svg>
`;

function escapeHtml(s) {
  return String(s)
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#39;");
}

function mount() {
  const providerUid = resolveProviderUid();
  if (!providerUid) {
    console.warn(
      "[minicrm-widget] no data-provider-uid on script tag and no window.miniCrmConfig.providerUid set; widget not mounted",
    );
    return;
  }

  const { config: firebaseConfig, missing } = resolveFirebaseConfig();
  if (!firebaseConfig) {
    console.warn(
      `[minicrm-widget] missing Firebase config field(s): ${missing.join(", ")}. ` +
        `Provide them via data-firebase-* script attributes or window.miniCrmConfig.firebase. ` +
        `Widget not mounted.`,
    );
    return;
  }

  const title = resolveTitle();
  const host = document.createElement("div");
  host.setAttribute("data-minicrm-widget", "");
  const shadow = host.attachShadow({ mode: "open" });
  shadow.innerHTML = `
    <style>${SHADOW_CSS}</style>
    <div class="root">
      <div class="panel" data-panel>
        <div class="header">
          <div>
            <div class="title">${escapeHtml(title)}</div>
            <div class="sub" data-sub>connecting…</div>
          </div>
          <button class="close-btn" data-close aria-label="Close">×</button>
        </div>
        <div class="error" data-error style="display:none"></div>
        <div class="messages" data-messages>
          <div class="empty">Starting up…</div>
        </div>
        <form class="input-row" data-form>
          <textarea data-input placeholder="Type your message…" disabled></textarea>
          <button type="submit" data-send disabled>Send</button>
        </form>
      </div>
      <div class="bubble" data-bubble role="button" aria-label="Open chat">
        ${CHAT_ICON}
      </div>
    </div>
  `;
  document.body.appendChild(host);

  const q = (s) => shadow.querySelector(s);
  const panel = q("[data-panel]");
  const bubble = q("[data-bubble]");
  const closeBtn = q("[data-close]");
  const messagesEl = q("[data-messages]");
  const form = q("[data-form]");
  const input = q("[data-input]");
  const sendBtn = q("[data-send]");
  const subEl = q("[data-sub]");
  const errorEl = q("[data-error]");

  bubble.addEventListener("click", () => panel.classList.add("open"));
  closeBtn.addEventListener("click", () => panel.classList.remove("open"));

  const app = initializeApp(firebaseConfig, "minicrm-widget");
  const auth = getAuth(app);
  const db = getFirestore(app);

  let customerUid = null;
  let unsubscribe = null;

  function showError(message) {
    if (!message) {
      errorEl.style.display = "none";
      errorEl.textContent = "";
    } else {
      errorEl.style.display = "block";
      errorEl.textContent = message;
    }
  }

  function setSub(text) {
    subEl.textContent = text;
  }

  function render(docs) {
    if (docs.length === 0) {
      messagesEl.innerHTML = `<div class="empty">Send a message to start the conversation.</div>`;
      return;
    }
    const wasAtBottom =
      messagesEl.scrollHeight - messagesEl.scrollTop - messagesEl.clientHeight <
      80;
    messagesEl.innerHTML = "";
    for (const d of docs) {
      const data = d.data();
      const sender = data.sender === "assistant" ? "assistant" : "customer";
      const text = data.text ?? "";
      const ts =
        data.createdAt && typeof data.createdAt.toDate === "function"
          ? data.createdAt.toDate()
          : null;
      const time = ts
        ? ts.toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" })
        : "";
      const div = document.createElement("div");
      div.className = `msg ${sender}`;
      const body =
        sender === "assistant" ? renderMarkdown(text) : escapeHtml(text);
      div.innerHTML = `<div class="body">${body}</div>${time ? `<div class="meta">${time}</div>` : ""}`;
      messagesEl.appendChild(div);
    }
    if (wasAtBottom) {
      messagesEl.scrollTop = messagesEl.scrollHeight;
    }
  }

  function subscribe() {
    if (unsubscribe) {
      unsubscribe();
      unsubscribe = null;
    }
    if (!customerUid) return;
    setSub("connecting…");
    const ref = collection(
      db,
      "users",
      providerUid,
      "sessions",
      customerUid,
      "messages",
    );
    unsubscribe = onSnapshot(
      query(ref, orderBy("createdAt")),
      (snap) => {
        setSub(`live · ${snap.size} message${snap.size === 1 ? "" : "s"}`);
        render(snap.docs);
        showError("");
        input.disabled = false;
        sendBtn.disabled = false;
      },
      (err) => {
        setSub("stream error");
        showError(`${err.code ?? ""} ${err.message ?? err}`);
      },
    );
  }

  async function sendMessage(text) {
    const trimmed = text.trim();
    if (!trimmed || !customerUid) return;
    const msgId =
      (crypto.randomUUID && crypto.randomUUID()) ||
      `${Date.now()}-${Math.random().toString(36).slice(2)}`;
    const sessionRef = doc(db, "users", providerUid, "sessions", customerUid);
    const msgRef = doc(sessionRef, "messages", msgId);
    const now = Timestamp.now();
    const batch = writeBatch(db);
    batch.set(msgRef, {
      id: msgId,
      sender: "customer",
      text: trimmed,
      createdAt: now,
    });
    batch.set(
      sessionRef,
      {
        lastMessageAt: now,
        lastMessagePreview:
          trimmed.length > 80 ? trimmed.slice(0, 80) + "…" : trimmed,
        lastSender: "customer",
      },
      { merge: true },
    );
    try {
      await batch.commit();
      showError("");
    } catch (err) {
      showError(`Send failed: ${err.code ?? ""} ${err.message ?? err}`);
    }
  }

  form.addEventListener("submit", (e) => {
    e.preventDefault();
    const text = input.value;
    input.value = "";
    sendMessage(text);
  });
  input.addEventListener("keydown", (e) => {
    if (e.key === "Enter" && !e.shiftKey) {
      e.preventDefault();
      form.requestSubmit();
    }
  });

  onAuthStateChanged(auth, (user) => {
    if (user) {
      customerUid = user.uid;
      subscribe();
    } else {
      setSub("signing in…");
      signInAnonymously(auth).catch((err) => {
        setSub("sign-in failed");
        showError(`${err.code ?? ""} ${err.message ?? err}`);
      });
    }
  });
}

if (document.readyState === "loading") {
  document.addEventListener("DOMContentLoaded", mount, { once: true });
} else {
  mount();
}
