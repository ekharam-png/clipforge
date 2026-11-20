// The feedback endpoint, written against the standard Request / Response so
// it can be tested without Next.js (see tests/feedback.test.ts). The route
// file app/api/feedback/route.ts only hands requests to it.
//
// What it does: checks one JSON message (schema v1, below), and sends ONE
// e-mail through Resend's REST API. It stores nothing, logs nothing personal
// and never puts a secret into an answer.
//
// Schema v1 (POST, application/json):
//   {
//     v: 1,
//     kind: "problem" | "idea" | "praise" | "question",
//     message: string,                      // 1 to 5000 characters
//     email?: string,                       // only for a reply
//     app?: { version: string, build?: string | number, os: string, device?: string },
//     source: "site" | "app",
//     locale?: string,
//     // The website's form also sends (the app does not need to):
//     website?: string,                     // honeypot: must be empty
//     elapsedMs?: number,                   // time the form was open
//     turnstileToken?: string               // when Turnstile is switched on
//   }
// Answer: { ok: true } or { ok: false, error: "plain words" }.

export const KINDS = ["problem", "idea", "praise", "question"] as const;
export type Kind = (typeof KINDS)[number];

export const LIMITS = {
  message: 5000,
  email: 254,
  short: 60, // version, build, os, device, locale
  body: 24 * 1024, // bytes of JSON accepted
  minFormMs: 3000, // a person needs longer than this to fill the form in
  perIp: 5, // messages per window from one address
  windowMs: 10 * 60 * 1000,
} as const;

export type FeedbackEnv = {
  RESEND_API_KEY?: string;
  FEEDBACK_TO?: string;
  FEEDBACK_FROM?: string;
  TURNSTILE_SECRET?: string;
};

export type FeedbackDeps = {
  env?: () => FeedbackEnv;
  fetch?: typeof fetch;
  now?: () => number;
  log?: (line: string) => void;
};

export type Feedback = {
  kind: Kind;
  message: string;
  email?: string;
  app?: { version: string; build?: string; os: string; device?: string };
  source: "site" | "app";
  locale?: string;
};

const CORS: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type",
  "Access-Control-Max-Age": "86400",
};

function answer(status: number, body: { ok: true } | { ok: false; error: string }, extra?: Record<string, string>) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json; charset=utf-8", "Cache-Control": "no-store", ...CORS, ...extra },
  });
}

const refuse = (status: number, error: string, extra?: Record<string, string>) =>
  answer(status, { ok: false, error }, extra);

// Control characters out (tabs and new lines stay only where asked for),
// also the invisible direction marks that can disguise text in a mail client.
export function clean(value: string, multiline = false): string {
  const unified = value.replace(/\r\n?/g, "\n");
  const stripped = unified.replace(
    multiline
      ? /[\u0000-\u0008\u000B-\u001F\u007F-\u009F\u200B-\u200F\u2028-\u202E\u2060-\u206F\uFEFF]/g
      : /[\u0000-\u001F\u007F-\u009F\u200B-\u200F\u2028-\u202E\u2060-\u206F\uFEFF]/g,
    multiline ? "" : " ",
  );
  return multiline ? stripped.replace(/\n{4,}/g, "\n\n\n").trim() : stripped.replace(/\s+/g, " ").trim();
}

function shortText(value: unknown, name: string): string | undefined {
  if (value === undefined || value === null || value === "") return undefined;
  if (typeof value !== "string" && typeof value !== "number") throw new Invalid(`"${name}" should be text.`);
  const text = clean(String(value));
  if (text.length > LIMITS.short) throw new Invalid(`"${name}" is too long (at most ${LIMITS.short} characters).`);
  return text || undefined;
}

class Invalid extends Error {}

const EMAIL = /^[^\s@<>(),;:"\\]+@[^\s@<>(),;:"\\]+\.[^\s@<>(),;:"\\.]{2,}$/;

// Turns whatever arrived into a checked message, or throws Invalid.
export function validate(input: unknown): Feedback {
  if (typeof input !== "object" || input === null || Array.isArray(input))
    throw new Invalid("The message was not in the expected form.");
  const o = input as Record<string, unknown>;
  if (o.v !== 1) throw new Invalid("This kind of message is not understood here (expected v: 1).");
  if (typeof o.kind !== "string" || !(KINDS as readonly string[]).includes(o.kind))
    throw new Invalid("Please choose what kind of message this is: problem, idea, praise or question.");
  if (o.source !== "site" && o.source !== "app") throw new Invalid('"source" should be "site" or "app".');
  if (typeof o.message !== "string") throw new Invalid("Please write a message.");
  if (o.message.length > LIMITS.message * 2)
    throw new Invalid(`The message is too long (at most ${LIMITS.message} characters).`);
  const message = clean(o.message, true);
  if (!message) throw new Invalid("Please write a message.");
  if (message.length > LIMITS.message)
    throw new Invalid(`The message is too long (at most ${LIMITS.message} characters).`);

  const out: Feedback = { kind: o.kind as Kind, message, source: o.source };

  if (o.email !== undefined && o.email !== null && o.email !== "") {
    if (typeof o.email !== "string") throw new Invalid("The e-mail address does not look right.");
    const email = clean(o.email);
    if (email.length > LIMITS.email || !EMAIL.test(email))
      throw new Invalid("The e-mail address does not look right. Leave it empty if you do not want a reply.");
    out.email = email;
  }

  if (o.app !== undefined && o.app !== null) {
    if (typeof o.app !== "object" || Array.isArray(o.app)) throw new Invalid('"app" should hold the version and system.');
    const a = o.app as Record<string, unknown>;
    const version = shortText(a.version, "version");
    const os = shortText(a.os, "system");
    const build = shortText(a.build, "build");
    const device = shortText(a.device, "device");
    if (version || os || build || device)
      out.app = { version: version || "?", os: os || "?", ...(build ? { build } : {}), ...(device ? { device } : {}) };
  }

  const locale = shortText(o.locale, "locale");
  if (locale) out.locale = locale;
  return out;
}

export function subjectFor(f: Feedback): string {
  const tail = f.app ? [f.app.version, f.app.os].filter((x) => x && x !== "?").join(" ") : "";
  return clean(`[ClipForge] ${f.kind} · ${tail || (f.source === "app" ? "app" : "site")}`).slice(0, 150);
}

export function textFor(f: Feedback): string {
  const lines = [
    `Kind: ${f.kind}`,
    `From: the ${f.source === "app" ? "app" : "website"}`,
    `Reply to: ${f.email || "(no address given)"}`,
  ];
  if (f.app) {
    lines.push(`Version: ${f.app.version}${f.app.build ? ` (build ${f.app.build})` : ""}`);
    lines.push(`System: ${f.app.os}${f.app.device ? `, ${f.app.device}` : ""}`);
  }
  if (f.locale) lines.push(`Language: ${f.locale}`);
  return lines.join("\n") + "\n\n" + f.message + "\n";
}

function clientKey(request: Request): string {
  const forwarded = request.headers.get("x-forwarded-for");
  const first = forwarded ? forwarded.split(",")[0].trim() : "";
  return first || request.headers.get("x-real-ip") || "unknown";
}

export function createFeedbackHandler(deps: FeedbackDeps = {}) {
  const env = deps.env ?? (() => process.env as FeedbackEnv);
  const now = deps.now ?? Date.now;
  const log = deps.log ?? ((line: string) => console.error(line));
  const doFetch: typeof fetch = (input, init) => (deps.fetch ?? fetch)(input, init);

  // Best effort only: this memory belongs to one running copy of the function.
  // On Vercel several copies can run at once and each starts empty, so this
  // slows a flood down but does not stop a determined sender. Turnstile is
  // the stronger check.
  const seen = new Map<string, number[]>();

  function limited(key: string): boolean {
    const t = now();
    if (seen.size > 5000) {
      for (const [k, times] of seen) if (!times.some((x) => t - x < LIMITS.windowMs)) seen.delete(k);
    }
    const recent = (seen.get(key) ?? []).filter((x) => t - x < LIMITS.windowMs);
    if (recent.length >= LIMITS.perIp) {
      seen.set(key, recent);
      return true;
    }
    recent.push(t);
    seen.set(key, recent);
    return false;
  }

  async function OPTIONS(): Promise<Response> {
    return new Response(null, { status: 204, headers: CORS });
  }

  async function POST(request: Request): Promise<Response> {
    const config = env();
    if (!config.RESEND_API_KEY || !config.FEEDBACK_TO || !config.FEEDBACK_FROM) {
      log("feedback: not set up (RESEND_API_KEY, FEEDBACK_TO and FEEDBACK_FROM are all needed)");
      return refuse(503, "Feedback is not set up on this site yet. Please try again another day.");
    }

    if (limited(clientKey(request))) {
      return refuse(429, "That is a lot of messages in a short time. Please wait ten minutes and try again.", {
        "Retry-After": String(Math.ceil(LIMITS.windowMs / 1000)),
      });
    }

    let raw: string;
    try {
      const declared = Number(request.headers.get("content-length") || 0);
      if (declared > LIMITS.body) return refuse(413, "The message is too big.");
      raw = await request.text();
    } catch {
      return refuse(400, "The message could not be read.");
    }
    if (new TextEncoder().encode(raw).length > LIMITS.body) return refuse(413, "The message is too big.");

    let input: unknown;
    try {
      input = JSON.parse(raw);
    } catch {
      return refuse(400, "The message was not in the expected form.");
    }

    const extras = (typeof input === "object" && input !== null ? input : {}) as Record<string, unknown>;
    if (typeof extras.website === "string" && extras.website.trim() !== "")
      return refuse(400, "This looked like an automatic message, so it was not sent.");

    let feedback: Feedback;
    try {
      feedback = validate(input);
    } catch (e) {
      if (e instanceof Invalid) return refuse(400, e.message);
      throw e;
    }

    if (feedback.source === "site") {
      if (typeof extras.elapsedMs === "number" && extras.elapsedMs < LIMITS.minFormMs)
        return refuse(400, "That was very quick. Please wait a few seconds and press Send again.");

      if (config.TURNSTILE_SECRET) {
        const token = typeof extras.turnstileToken === "string" ? extras.turnstileToken : "";
        if (!token || token.length > 2048) return refuse(400, "Please tick the check above the Send button first.");
        let passed = false;
        try {
          const check = await doFetch("https://challenges.cloudflare.com/turnstile/v0/siteverify", {
            method: "POST",
            headers: { "Content-Type": "application/x-www-form-urlencoded" },
            body: new URLSearchParams({ secret: config.TURNSTILE_SECRET, response: token }).toString(),
          });
          passed = check.ok && (await check.json()).success === true;
        } catch {
          passed = false;
        }
        if (!passed) return refuse(400, "The check above the Send button did not pass. Please try it again.");
      }
    }

    let sent: Response;
    try {
      sent = await doFetch("https://api.resend.com/emails", {
        method: "POST",
        headers: { Authorization: `Bearer ${config.RESEND_API_KEY}`, "Content-Type": "application/json" },
        body: JSON.stringify({
          from: config.FEEDBACK_FROM,
          to: [config.FEEDBACK_TO],
          subject: subjectFor(feedback),
          text: textFor(feedback),
          ...(feedback.email ? { reply_to: feedback.email } : {}),
        }),
      });
    } catch {
      log("feedback: the mail service could not be reached");
      return refuse(502, "The message could not be sent just now. Please try again later.");
    }
    if (!sent.ok) {
      // The status only: never the message, the address or the key.
      log(`feedback: the mail service answered ${sent.status}`);
      return refuse(502, "The message could not be sent just now. Please try again later.");
    }
    return answer(200, { ok: true });
  }

  return { POST, OPTIONS };
}
