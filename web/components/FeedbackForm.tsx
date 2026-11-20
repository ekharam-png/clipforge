"use client";

import { useEffect, useRef, useState } from "react";

const KINDS = [
  { value: "problem", label: "A problem", c: "caption" },
  { value: "idea", label: "An idea", c: "title" },
  { value: "praise", label: "Praise", c: "music" },
  { value: "question", label: "A question", c: "video" },
] as const;

const SYSTEMS = ["", "Windows", "Mac", "Android", "Other"];
const MAX = 5000;
const SITE_KEY = process.env.NEXT_PUBLIC_TURNSTILE_SITE_KEY || "";

type State = { kind: "idle" | "sending" | "sent" | "error"; text?: string };

declare global {
  interface Window {
    turnstile?: { render: (el: HTMLElement, options: Record<string, unknown>) => string; reset: (id?: string) => void };
  }
}

export function FeedbackForm() {
  const [kind, setKind] = useState<string>("idea");
  const [message, setMessage] = useState("");
  const [email, setEmail] = useState("");
  const [version, setVersion] = useState("");
  const [system, setSystem] = useState("");
  const [agree, setAgree] = useState(false);
  const [fromApp, setFromApp] = useState(false);
  const [state, setState] = useState<State>({ kind: "idle" });
  const opened = useRef(0);
  const trap = useRef<HTMLInputElement>(null);
  const token = useRef("");
  const widget = useRef<HTMLDivElement>(null);

  useEffect(() => {
    opened.current = Date.now();
    // The app (or a link) may open this page with ?version=…&os=…&kind=…
    // The app adds source=app (its "Open the feedback page in the browser",
    // shown when a message could not be sent from inside the app).
    const q = new URLSearchParams(window.location.search);
    if (q.get("source") === "app") setFromApp(true);
    const v = q.get("version");
    const os = q.get("os");
    const k = q.get("kind");
    if (v) setVersion(v.slice(0, 40));
    if (os && SYSTEMS.includes(os)) setSystem(os);
    else if (!os) {
      const ua = navigator.userAgent || "";
      setSystem(/Android/i.test(ua) ? "Android" : /Windows/i.test(ua) ? "Windows" : /Mac/i.test(ua) && !/iPhone|iPad/i.test(ua) ? "Mac" : "");
    }
    if (k && KINDS.some((x) => x.value === k)) setKind(k);
  }, []);

  // The optional "are you human" check. Loaded only when the site has a key.
  useEffect(() => {
    if (!SITE_KEY || !widget.current) return;
    const el = widget.current;
    const show = () => window.turnstile?.render(el, { sitekey: SITE_KEY, callback: (t: string) => (token.current = t) });
    if (window.turnstile) {
      show();
      return;
    }
    const script = document.createElement("script");
    script.src = "https://challenges.cloudflare.com/turnstile/v0/api.js?render=explicit";
    script.async = true;
    script.onload = show;
    document.head.appendChild(script);
  }, []);

  async function send(e: React.FormEvent) {
    e.preventDefault();
    if (state.kind === "sending") return;
    if (!message.trim()) return setState({ kind: "error", text: "Please write a message first." });
    if (!agree) return setState({ kind: "error", text: "Please tick the box above the Send button." });
    setState({ kind: "sending" });
    const body = {
      v: 1,
      kind,
      message,
      ...(email.trim() ? { email: email.trim() } : {}),
      ...(version.trim() || system ? { app: { version: version.trim(), os: system } } : {}),
      source: "site",
      website: trap.current?.value ?? "",
      elapsedMs: Date.now() - opened.current,
      ...(SITE_KEY ? { turnstileToken: token.current } : {}),
    };
    try {
      const res = await fetch("/api/feedback", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(body),
      });
      const json = (await res.json().catch(() => null)) as { ok?: boolean; error?: string } | null;
      if (res.ok && json?.ok) {
        setState({ kind: "sent" });
        setMessage("");
        setAgree(false);
      } else {
        setState({ kind: "error", text: json?.error || "The message could not be sent. Please try again later." });
        if (SITE_KEY) window.turnstile?.reset();
      }
    } catch {
      setState({ kind: "error", text: "The message could not be sent. Are you connected to the internet?" });
    }
  }

  if (state.kind === "sent") {
    return (
      <div className="form">
        <p className="status ok" role="status">
          <b>Sent. Thank you!</b> {email.trim() ? "If your message needs an answer, it will come by e-mail." : ""}
        </p>
        <p>
          <button type="button" className="button quiet" onClick={() => setState({ kind: "idle" })}>
            Write another message
          </button>
        </p>
      </div>
    );
  }

  return (
    <form className="form" onSubmit={send} noValidate>
      {fromApp ? (
        <p className="note" id="from-app" role="note">
          <b>From the app.</b> ClipForge opened this page because your message could not be sent from inside the app.
          The kind, version and system are already filled in. In the app, <b>Copy my message</b> copies what you wrote:
          paste it below. Nothing was sent yet.
        </p>
      ) : null}
      <fieldset>
        <legend>What is it?</legend>
        <div className="kinds">
          {KINDS.map((k) => (
            <label key={k.value} style={{ "--c": `var(--c-${k.c})` } as React.CSSProperties}>
              <input type="radio" name="kind" value={k.value} checked={kind === k.value} onChange={() => setKind(k.value)} />
              {k.label}
            </label>
          ))}
        </div>
      </fieldset>

      <fieldset>
        <label className="lab" htmlFor="fb-message">
          Your message
        </label>
        <textarea
          id="fb-message"
          className="field"
          required
          maxLength={MAX}
          value={message}
          onChange={(e) => setMessage(e.target.value)}
          aria-describedby="fb-message-help"
        />
        <p className="help" id="fb-message-help">
          {kind === "problem"
            ? "What did you do, what did you expect, and what happened instead? "
            : "Any language you like. "}
          {message.length > MAX - 500 ? `${MAX - message.length} characters left.` : ""}
        </p>
      </fieldset>

      <fieldset>
        <label className="lab" htmlFor="fb-email">
          Your e-mail address <span className="opt">(optional, only for a reply)</span>
        </label>
        <input
          id="fb-email"
          className="field"
          type="email"
          inputMode="email"
          autoComplete="email"
          maxLength={254}
          value={email}
          onChange={(e) => setEmail(e.target.value)}
        />
      </fieldset>

      <fieldset>
        <div className="two">
          <div>
            <label className="lab" htmlFor="fb-version">
              ClipForge version <span className="opt">(optional)</span>
            </label>
            <input
              id="fb-version"
              className="field"
              maxLength={40}
              placeholder="for example 1.14.1"
              value={version}
              onChange={(e) => setVersion(e.target.value)}
              aria-describedby="fb-version-help"
            />
          </div>
          <div>
            <label className="lab" htmlFor="fb-system">
              System <span className="opt">(optional)</span>
            </label>
            <select id="fb-system" className="field" value={system} onChange={(e) => setSystem(e.target.value)}>
              {SYSTEMS.map((s) => (
                <option key={s} value={s}>
                  {s || "Not given"}
                </option>
              ))}
            </select>
          </div>
        </div>
        <p className="help" id="fb-version-help">
          The version is in Help &gt; About ClipForge. It helps with problems.
        </p>
      </fieldset>

      {/* Not for people: a box that only automatic senders fill in. */}
      <div className="hp" aria-hidden="true">
        <label>
          Leave this box empty
          <input ref={trap} type="text" name="website" tabIndex={-1} autoComplete="off" defaultValue="" />
        </label>
      </div>

      <label className="consent">
        <input type="checkbox" checked={agree} onChange={(e) => setAgree(e.target.checked)} required />
        <span>
          Send this message by e-mail to the person who makes ClipForge. It contains exactly what this form shows: the
          kind, my message, and the e-mail address, version and system if I filled them in. Nothing else is added, and
          the site keeps no copy.
        </span>
      </label>

      {SITE_KEY ? <div ref={widget} style={{ marginTop: 16 }} /> : null}

      <div className="buttons">
        <button className="button" type="submit" disabled={state.kind === "sending"}>
          {state.kind === "sending" ? "Sending…" : "Send"}
        </button>
      </div>
      <p className={`status ${state.kind === "error" ? "bad" : ""}`} role="alert">
        {state.kind === "error" ? state.text : ""}
      </p>
    </form>
  );
}
