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
| `NEXT_PUBLIC_SITE_URL` | Optional: the site's address for the sitemap and link previews. |

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

## The old download page (`site/`, GitHub Pages)

`site/` is still published to GitHub Pages and still works; nothing here
changes it. The app and the "Read me first" guide link to it
(`https://ekharam-png.github.io/clipforge/`), so it must keep answering.

When the new site has its final address, the Pages page can become a
signpost. Do it in this order:

1. Replace the body of `site/index.html` with a short page that sends
   people on (GitHub Pages cannot do a real redirect, so this is the way):

   ```html
   <!doctype html>
   <html lang="en">
   <head>
   <meta charset="utf-8">
   <title>ClipForge has moved</title>
   <link rel="canonical" href="https://YOUR-SITE/">
   <meta http-equiv="refresh" content="0; url=https://YOUR-SITE/">
   </head>
   <body>
   <p>ClipForge has a new home: <a href="https://YOUR-SITE/">https://YOUR-SITE/</a></p>
   </body>
   </html>
   ```

2. Do the same for `site/claude-setup.html`, pointing at
   `https://YOUR-SITE/claude`, or leave that page as it is: the Claude page
   of the new site links to it as the full setup guide.
3. `video-editor/tool/ci/make_readme_html_test.py` compares the install
   sentences in `site/index.html` with the "Read me first" guide. When the
   Pages page becomes a signpost, that test has to compare against
   something else (or be dropped) in the same change.
4. Later, in the app: change the download-page address
   (`DOWNLOAD_PAGE` in `video-editor/tool/ci/make_readme_html.py` and the
   address the updater opens) to the new site. Old versions of the app keep
   opening the Pages address, which is why the signpost has to stay.
