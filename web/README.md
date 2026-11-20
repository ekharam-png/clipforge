# ClipForge website

The public website for ClipForge: what it is, downloads, install steps, a
walk-through, features, examples, help, what's new, and a feedback form.
It is a [Next.js](https://nextjs.org) app (App Router, TypeScript, plain
CSS) made to run on Vercel with **Root Directory = `web`**.

Setting it up on Vercel and Resend is described step by step in
[`SETUP.md`](SETUP.md).

## Run it

Needs Node.js 22.18 or newer.

```sh
cd web
npm ci
npm run dev        # http://localhost:3000
npm run lint       # type check
npm test           # unit tests (no network)
npm run build      # the production build
npm start          # serve the build
```

## Where the words and pictures come from

The site does not keep its own copy of the app's texts. Before every build,
`scripts/build-content.mjs` reads them from the app's folder:

| Page | Source |
|---|---|
| Every outside address (this site's own, the repository) | `../video-editor/tool/ci/links.json` |
| Help (one page per article, plus the search index) | `../video-editor/assets/help/help_en.md` |
| What's new | `../video-editor/CHANGELOG.md` |
| Features | `../video-editor/docs/FEATURES.md` |
| Screenshots | `../video-editor/docs/screenshots/*.png`, but only those named in `content/shots.json` |

So when the app's help, change list or feature log changes, the site
follows at its next build. What the script writes (`content/generated/`,
`public/shots/`, `public/help-index.json`) is not committed.

The build needs no internet. The one optional request asks GitHub for the
newest release number; if it fails, the newest version in `CHANGELOG.md` is
shown instead. In the browser the home page asks again and quietly keeps
the built-in number if that fails. `node scripts/build-content.mjs --offline`
skips the request.

### Screenshots

Every screenshot is real, taken from the app by its own tests. To use
another one, add a line to `content/shots.json`: the file name without
`.png`, and a sentence describing it for people who cannot see it. Then use
`<Shot name="…" />` in a page. A name that is not in the list stops the
build, and so does a missing description.

The link-preview picture (`app/opengraph-image.jpg`) is the top 1200 × 630
of `editor_desktop.png`; the icons in `app/` are the app's own icon.

## Examples: adding one, and adding a real video

The Examples page is drawn from one file, `content/examples.json`. Each
entry has a title, a description, a list of what was done, and optional
pictures (`before`, `after`: names from `content/shots.json`) and a link.

**To show a real exported video, add one line to an entry:**

```json
"video": "https://example.org/videos/family-trip.mp4"
```

- **Big videos are not committed to this repository.** Put the file
  somewhere that serves it over https (your own storage, a video host's
  direct file link) and use that address.
- A **small, web-ready file under 5 MB** may live in the repository: save it
  as `web/public/media/family-trip.mp4` and write
  `"video": "/media/family-trip.mp4"`. The build refuses anything larger.
  ClipForge's own "WhatsApp / Telegram" export makes a small MP4; trim the
  example to 15–20 seconds.
- Optional: `"poster": "editor_desktop"` (a name from `content/shots.json`)
  is the still picture shown before the video plays.
- When real videos are there, change or remove the `"notice"` text at the
  top of the file, which says that sample videos are coming.

The video only loads when a visitor presses play.

## Feedback

`app/feedback` is the form; `app/api/feedback/route.ts` receives it. All
the logic and the rules are in [`lib/feedback.ts`](lib/feedback.ts), tested
in `tests/feedback.test.ts`.

**Request** (`POST /api/feedback`, JSON, schema v1; the app can post this
directly, from any origin, without cookies):

```json
{
  "v": 1,
  "kind": "problem | idea | praise | question",
  "message": "up to 5000 characters",
  "email": "optional, only used as reply-to",
  "app": { "version": "1.15.0", "build": "151", "os": "Windows", "device": "optional" },
  "source": "site | app",
  "locale": "optional, e.g. en"
}
```

**Answer:** `{"ok": true}`, or `{"ok": false, "error": "plain words"}` with
status 400 (not valid), 413 (too big), 429 (too many), 502 (the e-mail
service failed) or 503 (not set up).

The app (1.16+) posts the same schema with `"source": "app"`; see "The app
posts feedback here" below.

What it does and does not do:

- Sends **one** plain-text e-mail through Resend's REST API (no SDK), with
  the visitor's address as reply-to when given, and a subject like
  `[ClipForge] idea · 1.15.0 Windows`.
- **Stores nothing.** Logs only that something failed and the status code,
  never the message, the address or a key.
- Strips control characters, caps every field, and refuses bodies over 24 KB.
- The website's form also sends `website` (a hidden box that must stay
  empty) and `elapsedMs` (a form filled in under 3 seconds is refused).
- **Rate limit: 5 messages per 10 minutes per internet address, kept in
  memory. This is best effort only:** on Vercel several copies of the
  function can run at once and each forgets when it restarts. It slows a
  flood; it does not stop a determined sender.
- **Optional Cloudflare Turnstile:** when `TURNSTILE_SECRET` is set, posts
  with `"source": "site"` must carry a valid `turnstileToken` (the form
  shows the check when `NEXT_PUBLIC_TURNSTILE_SITE_KEY` is set). Posts from
  the app are not asked for it, so someone can pretend to be the app; the
  rate limit still applies.

Environment variables (names only; values go into Vercel, never into the
repository; see `.env.example`):

| Name | For |
|---|---|
| `RESEND_API_KEY` | Sending the e-mail. Missing: the route answers 503. |
| `FEEDBACK_TO` | Where feedback goes (the owner's address). |
| `FEEDBACK_FROM` | The sender, e.g. `ClipForge feedback <feedback@your-domain>`. |
| `TURNSTILE_SECRET`, `NEXT_PUBLIC_TURNSTILE_SITE_KEY` | Optional check on the form. |
| `NEXT_PUBLIC_SITE_URL` | Optional: overrides the site's address (from `links.json`) for the sitemap and link previews. |

## Privacy promises the code has to keep

The Privacy page says: no cookies, no analytics, no fonts or scripts from
other companies, the help search runs in the browser, feedback contains
exactly what the form shows. Please keep it true: do not add analytics, an
external font, or a hidden field without changing that page first.

## Design

One stylesheet, `app/globals.css`. The look comes from the app: one colour
per kind of track (video blue, photo purple, music green, title orange,
caption pink) and a red playhead; downloads are clips on a timeline, the
walk-through runs along a playhead with time marks. Light and dark follow
the system. Only four small pieces run script in the browser
(`components/Live.tsx`, `HelpSearch.tsx`, `FeedbackForm.tsx`).

## Addresses: one file for the app, the release tools and this site

Nothing in `web/` writes the site's own address. The outside addresses live
in **`../video-editor/tool/ci/links.json`** (the site, the download page,
the feedback address and page, help, privacy, the repository, the old
GitHub Pages address). `scripts/build-content.mjs` copies them into
`content/generated/links.json` before every build and `lib/site.ts` gives
them to the pages (`LINKS`, `REPO_URL`, `OLD_PAGES_URL`, `siteUrl()`).

The same file is written into every release's `latest.json` (`links`), so
installed apps (1.16 and newer) follow a move of the site without a new
build, and it is the built-in default of the app
(`video-editor/lib/core/links.dart`). **To move the site or rename the
product, edit `links.json`**; `video-editor/docs/RENAMING.md` lists the
rest. Tests on both sides (`tests/links.test.ts` here,
`test/core/links_test.dart` in the app) fail when the address is written
anywhere else, or when a page named in `links.json` does not exist here.

`siteUrl()` (sitemap, link previews) is `NEXT_PUBLIC_SITE_URL` when set,
else the `site` of `links.json` on the production deployment, else the
preview's own address.

## The app posts feedback here

From version 1.16 the app has its own **Send feedback** page. It posts
schema v1 straight to `/api/feedback` with `"source": "app"` and `app:
{version, build, os}`; no honeypot, timing or Turnstile fields. So that the
two sides cannot drift apart they share one fixture,
`../video-editor/test/core/fixtures/feedback_payloads.json`: the app's test
checks that it builds exactly those payloads, `tests/app-feedback.test.ts`
checks that this site accepts exactly those and writes the expected mail.
Change the schema on both sides and then the fixture.

When the app cannot send (offline, or this site answers with an error) it
offers "Open the feedback page in the browser", which opens
`/feedback?source=app&kind=…&version=…&os=…`. The form then shows a short
"From the app" note; the message itself is never put into the address
(the app offers "Copy my message" instead).

## The old download page (`site/`, GitHub Pages)

`site/index.html` is a signpost since 1.16: "ClipForge has a new home", a
button to this site, and still the three download buttons. It has no
automatic redirect on purpose. **It must keep answering**: versions of the
app before 1.16 open the Pages address for "Open the download page", and
their "Read me first" guide links to it. `site/claude-setup.html` is
unchanged and still reachable (the Claude page here links to it as the full
setup guide).

`video-editor/tool/ci/links_test.py` fails when the signpost points
anywhere but the `site` of `links.json`, and
`video-editor/tool/ci/release_assets.py --check-links` when it does not
offer exactly the three downloads. The "Read me first" guide's install
steps are compared with `app/install/page.tsx` now (same sentences;
`make_readme_html_test.py`), no longer with the Pages page.
