// Run with: npm test   (Node's own test runner; no network is used.)
import assert from "node:assert/strict";
import { test } from "node:test";
import { createFeedbackHandler, LIMITS, subjectFor, validate, clean } from "../lib/feedback.ts";
import type { FeedbackEnv } from "../lib/feedback.ts";

type Call = { url: string; init: RequestInit };

const ENV: FeedbackEnv = {
  RESEND_API_KEY: "re_test_key_not_real",
  FEEDBACK_TO: "owner@example.org",
  FEEDBACK_FROM: "ClipForge feedback <feedback@example.org>",
};

function setup(options: { env?: FeedbackEnv; respond?: (url: string) => Response | Promise<Response> } = {}) {
  const calls: Call[] = [];
  const logs: string[] = [];
  let time = 1_000_000;
  const handler = createFeedbackHandler({
    env: () => options.env ?? ENV,
    now: () => time,
    log: (line) => logs.push(line),
    fetch: (async (input: RequestInfo | URL, init?: RequestInit) => {
      const url = String(input);
      calls.push({ url, init: init ?? {} });
      return options.respond ? options.respond(url) : Response.json({ id: "mail_1" });
    }) as typeof fetch,
  });
  return { handler, calls, logs, advance: (ms: number) => (time += ms) };
}

function post(body: unknown, headers: Record<string, string> = {}) {
  return new Request("https://site.example/api/feedback", {
    method: "POST",
    headers: { "Content-Type": "application/json", "x-forwarded-for": "203.0.113.7", ...headers },
    body: typeof body === "string" ? body : JSON.stringify(body),
  });
}

const good = {
  v: 1,
  kind: "idea",
  message: "Please add a button for skipping back five seconds.",
  email: "friend@example.com",
  app: { version: "1.15.0", build: 151, os: "Windows" },
  source: "site",
  website: "",
  elapsedMs: 9000,
};

test("a good message becomes exactly one e-mail through Resend", async () => {
  const { handler, calls } = setup();
  const res = await handler.POST(post(good));
  assert.equal(res.status, 200);
  assert.deepEqual(await res.json(), { ok: true });
  assert.equal(res.headers.get("access-control-allow-origin"), "*");
  assert.equal(calls.length, 1);
  assert.equal(calls[0].url, "https://api.resend.com/emails");
  const headers = calls[0].init.headers as Record<string, string>;
  assert.equal(headers.Authorization, "Bearer re_test_key_not_real");
  const mail = JSON.parse(String(calls[0].init.body));
  assert.deepEqual(Object.keys(mail).sort(), ["from", "reply_to", "subject", "text", "to"]);
  assert.equal(mail.from, ENV.FEEDBACK_FROM);
  assert.deepEqual(mail.to, ["owner@example.org"]);
  assert.equal(mail.reply_to, "friend@example.com");
  assert.equal(mail.subject, "[ClipForge] idea · 1.15.0 Windows");
  assert.match(mail.text, /skipping back five seconds/);
  assert.match(mail.text, /Version: 1\.15\.0 \(build 151\)/);
});

test("without an e-mail address there is no reply-to, and the subject names the source", async () => {
  const { handler, calls } = setup();
  const res = await handler.POST(post({ v: 1, kind: "praise", message: "Lovely.", source: "app" }));
  assert.equal(res.status, 200);
  const mail = JSON.parse(String(calls[0].init.body));
  assert.equal("reply_to" in mail, false);
  assert.equal(mail.subject, "[ClipForge] praise · app");
});

test("validation errors are refused in plain words and send nothing", async () => {
  const cases: [unknown, RegExp][] = [
    ["not json at all", /expected form/],
    [[1, 2], /expected form/],
    [{ ...good, v: 2 }, /v: 1/],
    [{ ...good, kind: "rant" }, /kind of message/],
    [{ ...good, source: "elsewhere" }, /source/],
    [{ ...good, message: "   \n " }, /write a message/],
    [{ ...good, message: 42 }, /write a message/],
    [{ ...good, message: "x".repeat(LIMITS.message + 1) }, /too long/],
    [{ ...good, email: "not-an-address" }, /e-mail address/],
    [{ ...good, email: "a@b.co\nBcc: x@y.zz" }, /e-mail address/],
    [{ ...good, app: { version: "1".repeat(200), os: "Mac" } }, /too long/],
    [{ ...good, elapsedMs: 200 }, /very quick/],
  ];
  for (const [body, pattern] of cases) {
    const { handler, calls } = setup();
    const res = await handler.POST(post(body));
    assert.equal(res.status, 400, JSON.stringify(body).slice(0, 60));
    const json = await res.json();
    assert.equal(json.ok, false);
    assert.match(json.error, pattern);
    assert.equal(calls.length, 0);
  }
});

test("a body that is too big is refused", async () => {
  const { handler, calls } = setup();
  const res = await handler.POST(post({ ...good, padding: "x".repeat(LIMITS.body) }));
  assert.equal(res.status, 413);
  assert.equal(calls.length, 0);
});

test("control characters are stripped and cannot reach the subject", async () => {
  assert.equal(clean("a\u0000b‮c\r\nd", true), "abc\nd");
  assert.equal(clean("  one\r\ntwo\tthree  "), "one two three");
  const f = validate({ ...good, app: { version: "1.2\r\nBcc: x", os: "Mac\u0007" } });
  assert.equal(/[\r\n]/.test(subjectFor(f)), false);
  const { handler, calls } = setup();
  await handler.POST(post({ ...good, message: "line one\u0000\r\nline two\u001B[31m" }));
  const mail = JSON.parse(String(calls[0].init.body));
  assert.match(mail.text, /line one\nline two\[31m\n$/);
});

test("a filled honeypot is refused and nothing is sent", async () => {
  const { handler, calls } = setup();
  const res = await handler.POST(post({ ...good, website: "https://spam.example" }));
  assert.equal(res.status, 400);
  assert.equal((await res.json()).ok, false);
  assert.equal(calls.length, 0);
});

test("the per-address limit answers 429, then lets go after the window", async () => {
  const { handler, calls, advance } = setup();
  for (let i = 0; i < LIMITS.perIp; i++) assert.equal((await handler.POST(post(good))).status, 200);
  const blocked = await handler.POST(post(good));
  assert.equal(blocked.status, 429);
  assert.ok(blocked.headers.get("retry-after"));
  assert.equal((await blocked.json()).ok, false);
  assert.equal(calls.length, LIMITS.perIp);
  // Another address is not affected.
  assert.equal((await handler.POST(post(good, { "x-forwarded-for": "198.51.100.9" }))).status, 200);
  advance(LIMITS.windowMs + 1);
  assert.equal((await handler.POST(post(good))).status, 200);
});

test("a missing key answers 503, sends nothing and logs nothing personal", async () => {
  for (const env of [{}, { ...ENV, RESEND_API_KEY: "" }, { ...ENV, FEEDBACK_TO: undefined }]) {
    const { handler, calls, logs } = setup({ env });
    const res = await handler.POST(post(good));
    assert.equal(res.status, 503);
    const json = await res.json();
    assert.equal(json.ok, false);
    assert.match(json.error, /not set up/);
    assert.equal(calls.length, 0);
    const all = logs.join("\n");
    assert.equal(all.includes("friend@example.com"), false);
    assert.equal(all.includes("skipping back"), false);
  }
});

test("a Resend error answers 502 without leaking the key, the message or Resend's words", async () => {
  const { handler, logs } = setup({
    respond: () => Response.json({ message: "API key is invalid: re_test_key_not_real" }, { status: 403 }),
  });
  const res = await handler.POST(post(good));
  assert.equal(res.status, 502);
  const text = await res.text();
  assert.equal(JSON.parse(text).ok, false);
  const everything = text + logs.join("\n");
  assert.equal(everything.includes("re_test_key_not_real"), false);
  assert.equal(everything.includes("friend@example.com"), false);
  assert.equal(everything.includes("skipping back"), false);
  assert.match(logs.join("\n"), /403/);
});

test("a network failure on the way to Resend answers 502", async () => {
  const { handler } = setup({
    respond: () => {
      throw new Error("connect ECONNREFUSED");
    },
  });
  const res = await handler.POST(post(good));
  assert.equal(res.status, 502);
  assert.equal((await res.json()).ok, false);
});

test("Turnstile is checked for the website when its secret is set, and not asked of the app", async () => {
  const env = { ...ENV, TURNSTILE_SECRET: "ts_secret_not_real" };
  const missing = setup({ env });
  assert.equal((await missing.handler.POST(post(good))).status, 400);
  assert.equal(missing.calls.length, 0);

  const failing = setup({ env, respond: (url) => (url.includes("turnstile") ? Response.json({ success: false }) : Response.json({})) });
  assert.equal((await failing.handler.POST(post({ ...good, turnstileToken: "tok" }))).status, 400);
  assert.equal(failing.calls.length, 1);

  const passing = setup({ env, respond: (url) => (url.includes("turnstile") ? Response.json({ success: true }) : Response.json({})) });
  assert.equal((await passing.handler.POST(post({ ...good, turnstileToken: "tok" }))).status, 200);
  assert.equal(passing.calls.length, 2);
  assert.match(String(passing.calls[0].init.body), /secret=ts_secret_not_real&response=tok/);

  const app = setup({ env });
  assert.equal((await app.handler.POST(post({ ...good, source: "app" }))).status, 200);
  assert.equal(app.calls.length, 1);
});

test("OPTIONS answers the browser's pre-flight question", async () => {
  const { handler } = setup();
  const res = await handler.OPTIONS();
  assert.equal(res.status, 204);
  assert.equal(res.headers.get("access-control-allow-origin"), "*");
  assert.match(res.headers.get("access-control-allow-methods") ?? "", /POST/);
  assert.equal(res.headers.get("access-control-allow-credentials"), null);
});

test("the route file hands requests to the same handler", async () => {
  const route = await import("../app/api/feedback/route.ts");
  assert.equal(typeof route.POST, "function");
  assert.equal((await route.OPTIONS()).status, 204);
});
