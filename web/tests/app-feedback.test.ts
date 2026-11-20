// The app's "Send feedback" (ClipForge 1.16) and this site's /api/feedback
// must agree. Both sides test against ONE file:
//   ../video-editor/test/core/fixtures/feedback_payloads.json
// The app's test (test/core/feedback_test.dart) checks that the app builds
// exactly each "payload"; this test checks that the site accepts exactly
// that and writes the expected mail. Change the schema on both sides.
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { test } from "node:test";
import { fileURLToPath } from "node:url";
import { createFeedbackHandler, LIMITS, validate } from "../lib/feedback.ts";
import type { FeedbackEnv } from "../lib/feedback.ts";

type Case = {
  name: string;
  payload: Record<string, unknown> & { app: Record<string, string>; message: string; kind: string; email?: string };
  mail: { subject: string | null; replyTo: string | null; contains: string[] };
};

const HERE = dirname(fileURLToPath(import.meta.url));
const FIXTURE = join(HERE, "..", "..", "video-editor", "test", "core", "fixtures", "feedback_payloads.json");
const cases = (JSON.parse(readFileSync(FIXTURE, "utf8")) as { cases: Case[] }).cases;

const ENV: FeedbackEnv = {
  RESEND_API_KEY: "re_test_key_not_real",
  FEEDBACK_TO: "owner@example.org",
  FEEDBACK_FROM: "ClipForge feedback <feedback@example.org>",
};

function setup(env: FeedbackEnv = ENV) {
  const mails: { url: string; body: Record<string, unknown> }[] = [];
  const handler = createFeedbackHandler({
    env: () => env,
    now: () => 1_000_000,
    log: () => {},
    fetch: (async (input: RequestInfo | URL, init?: RequestInit) => {
      mails.push({ url: String(input), body: JSON.parse(String(init?.body ?? "{}")) });
      return Response.json({ id: "mail_1" });
    }) as typeof fetch,
  });
  return { handler, mails };
}

// As the app sends it: the exact JSON text, its content type and user agent,
// no cookies, no origin.
function fromApp(payload: unknown, ip = "203.0.113.20") {
  return new Request("https://site.example/api/feedback", {
    method: "POST",
    headers: {
      "Content-Type": "application/json; charset=utf-8",
      Accept: "application/json",
      "User-Agent": "ClipForge (feedback)",
      "x-forwarded-for": ip,
    },
    body: JSON.stringify(payload),
  });
}

test("the fixture is the one the app's test reads, with every kind in it", () => {
  assert.ok(cases.length >= 5);
  assert.deepEqual([...new Set(cases.map((c) => c.payload.kind))].sort(), ["idea", "praise", "problem", "question"]);
});

for (const [i, c] of cases.entries()) {
  test(`the app's payload is accepted as it is: ${c.name}`, async () => {
    // Only the keys of schema v1 that the app is allowed to send.
    assert.deepEqual(
      Object.keys(c.payload).filter((key) => !["v", "kind", "message", "email", "app", "source"].includes(key)),
      [],
    );
    assert.deepEqual(Object.keys(c.payload.app).filter((key) => !["version", "build", "os"].includes(key)), []);
    assert.equal(c.payload.v, 1);
    assert.equal(c.payload.source, "app");
    for (const value of Object.values(c.payload.app)) assert.ok(value.length <= LIMITS.short);

    // Nothing is changed on the way in: what the app showed is what arrives.
    const checked = validate(c.payload);
    assert.equal(checked.message, c.payload.message);
    assert.equal(checked.kind, c.payload.kind);
    assert.equal(checked.source, "app");
    assert.equal(checked.email, c.payload.email);
    assert.deepEqual(checked.app, c.payload.app);

    const { handler, mails } = setup();
    const res = await handler.POST(fromApp(c.payload, `203.0.113.${30 + i}`));
    assert.equal(res.status, 200);
    assert.deepEqual(await res.json(), { ok: true });
    assert.equal(mails.length, 1);
    const mail = mails[0].body;
    if (c.mail.subject !== null) assert.equal(mail.subject, c.mail.subject);
    assert.match(String(mail.subject), new RegExp(`^\\[ClipForge\\] ${c.payload.kind} · `));
    assert.equal(mail.reply_to ?? null, c.mail.replyTo);
    const text = String(mail.text);
    assert.ok(text.includes("From: the app"));
    for (const part of c.mail.contains) assert.ok(text.includes(part), `the mail should contain: ${part}`);
  });
}

test("the app is not asked for the website's extras (honeypot, timing, Turnstile)", async () => {
  const { handler, mails } = setup({ ...ENV, TURNSTILE_SECRET: "ts_test_secret_not_real" });
  const res = await handler.POST(fromApp(cases[0].payload));
  assert.equal(res.status, 200);
  // One call only: the mail. No Turnstile check for the app.
  assert.deepEqual(mails.map((m) => m.url), ["https://api.resend.com/emails"]);
});

test("the answers the app turns into plain messages: 400, 429 and 503 all carry words", async () => {
  const { handler } = setup();
  const bad = await handler.POST(fromApp({ ...cases[0].payload, email: "not an address" }));
  assert.equal(bad.status, 400);
  const badBody = (await bad.json()) as { ok: boolean; error: string };
  assert.equal(badBody.ok, false);
  assert.match(badBody.error, /e-mail address/);

  const limited = setup();
  let last: Response | undefined;
  for (let n = 0; n <= LIMITS.perIp; n++) last = await limited.handler.POST(fromApp(cases[1].payload, "203.0.113.99"));
  assert.equal(last!.status, 429);
  assert.match(((await last!.json()) as { error: string }).error, /wait/);

  const off = setup({});
  const none = await off.handler.POST(fromApp(cases[1].payload));
  assert.equal(none.status, 503);
  assert.equal(typeof ((await none.json()) as { error: string }).error, "string");
});
