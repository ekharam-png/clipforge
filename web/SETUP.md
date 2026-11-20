# Putting the ClipForge website online

**Who this is for:** a Claude Code session running on the owner's own
computer. The owner is not technical; you do the account-side work with
them, one step at a time, and say in plain words what you are doing.

**What you end with:** the site live on Vercel, feedback arriving in the
owner's inbox, and the site's address reported back.

## Hard rules

1. **No secrets in the repository.** API keys and the owner's e-mail address
   go into Vercel's Environment Variables only. Never write them into a
   file in this repository, a commit message, an issue, or the chat. Do not
   create `.env` files inside the repository other than a local
   `.env.local` for a test, and delete that afterwards (it is ignored by
   git; check with `git status` that it does not show).
2. **Ask before anything that costs money.** Vercel's Hobby plan and
   Resend's free plan are enough for this site. Do not choose a paid plan,
   buy a domain, or add a paid add-on without the owner saying yes to that
   exact thing and its price.
3. **Do not change the app's code.** Nothing under `video-editor/` is
   edited in this work. The site only reads from it.
4. If a screen looks different from what is described here, stop and tell
   the owner what you see instead of guessing. Product screens change.

## Before you start

- The branch with `web/` must be merged into `main` on GitHub
  (`ekharam-png/clipforge`). Check: `web/package.json` exists on `main`.
- Check that the site builds on this computer (Node.js 22.18 or newer):

  ```sh
  cd web
  npm ci && npm run lint && npm test && npm run build
  ```

- The owner needs: their GitHub login, an e-mail inbox they can open now,
  and about 30 minutes.

## 1. Create the Vercel project

1. With the owner, open <https://vercel.com> and sign up or log in **with
   GitHub** (the Hobby plan, free).
2. **Add New… > Project**, and import the repository `clipforge`. If it is
   not listed, follow Vercel's prompt to give its GitHub app access to that
   one repository.
3. On the configure screen set:
   - **Root Directory:** `web`
   - **Framework Preset:** Next.js (detected by itself)
   - Build and install commands: leave the defaults.
4. Do not deploy yet if the screen lets you add environment variables
   first; go to step 2. (If it deploys anyway, nothing breaks: the feedback
   form will simply answer "not set up yet" until step 2 is done.)
5. After the project exists, check in **Settings**:
   - **Git > Production Branch:** `main`.
   - **General > Root Directory:** `web`, and **"Include files outside of
     the Root Directory in the Build Step"** switched **on**. The build
     reads `../video-editor`, so it fails without this.
   - **Git > Ignored Build Step:** nothing to type. `web/vercel.json`
     already carries the command, so a build only starts when something
     under `web/` or one of the files the site reads changed:

     ```
     git diff --quiet HEAD^ HEAD -- . ../video-editor/assets/help/help_en.md ../video-editor/CHANGELOG.md ../video-editor/docs/FEATURES.md ../video-editor/docs/screenshots
     ```

     If the Settings page shows its own "Ignored Build Step" field with a
     different choice, set it to **Custom** with the line above, or leave it
     on the default so that `vercel.json` is used. Changes to the app's code
     alone then show up as "Canceled / Ignored" builds: that is intended.

If you prefer the command line: `npx vercel link` and `npx vercel env add`
do the same. Do not install anything globally, and never commit the
`.vercel` folder (it is ignored by git).

## 2. Resend: the service that sends the feedback e-mails

1. With the owner, open <https://resend.com> and create an account with the
   e-mail address the owner wants feedback sent to. The free plan is enough
   (it has a daily and a monthly limit; read the current numbers on their
   pricing page and tell the owner).
2. **API Keys > Create API Key.** Name it "ClipForge website", permission
   **Sending access**. The key (it starts with `re_`) is shown once. Put it
   straight into Vercel (step 3). Do not paste it into the chat or a file.
3. Choose the sender. Two ways:

   **A. For a first test: Resend's test sender.**
   `FEEDBACK_FROM` = `ClipForge feedback <onboarding@resend.dev>`.
   Understand its limit: with the test sender, Resend only delivers to
   **the e-mail address of the Resend account itself**. So `FEEDBACK_TO`
   must be exactly that address. That is fine for this site, because
   feedback only ever goes to the owner. It can look less trustworthy to
   mail filters, so check the spam folder.

   **B. Properly: a sending domain the owner controls.**
   Only if the owner has a domain. **Domains > Add Domain** (a subdomain
   such as `mail.their-domain` is the usual choice), then add the DNS
   records Resend shows at the domain's provider and press Verify. Then
   `FEEDBACK_FROM` = `ClipForge feedback <feedback@that-domain>`.
   Buying a domain costs money: rule 2.

## 3. Environment variables in Vercel

**Project > Settings > Environment Variables.** Add these for
**Production** (and Preview if the owner wants previews to send too):

| Name | Value |
|---|---|
| `RESEND_API_KEY` | the key from step 2 (mark it **Sensitive**) |
| `FEEDBACK_TO` | the owner's e-mail address. Entered here, never committed. |
| `FEEDBACK_FROM` | `ClipForge feedback <onboarding@resend.dev>` or the verified-domain sender |

Optional:

| Name | Value |
|---|---|
| `NEXT_PUBLIC_SITE_URL` | the final address, e.g. `https://their-domain`, once there is a custom domain |
| `NEXT_TELEMETRY_DISABLED` | `1` (stops Next.js sending anonymous build statistics) |

Environment variables only apply to **new** deployments: after adding or
changing one, redeploy (Deployments > the newest > ⋯ > Redeploy).

## 4. Deploy and look

1. Deploy (or redeploy). The build log should contain a line starting with
   `build-content:` that counts help articles, versions and screenshots,
   and end without errors.
2. Open the address Vercel gives (`https://<project>.vercel.app`) and check
   with the owner, on a computer **and on a phone**:
   - Home: the three downloads, the version number, the editor screenshot.
   - Walk-through, Features, Examples, Claude, What's new open and show
     pictures.
   - Help: type `musci` in the search; "Adding music…" should appear.
   - A made-up address such as `/nothing-here` shows the "This page was
     cut" page.
   - `/robots.txt` and `/sitemap.xml` open and show the right address.

## 5. Send a test feedback and see it arrive

1. On the live site open **Feedback**, choose "A question", write "Test
   from setup", put in an e-mail address the owner can read, tick the box
   and press **Send**. It should say "Sent. Thank you!".
2. The owner opens their inbox (and the spam folder). The e-mail has the
   subject `[ClipForge] question · …`, and pressing Reply addresses the
   answer to the address typed into the form.
3. The same from the command line, as the app will do it later:

   ```sh
   curl -s -X POST https://<site>/api/feedback \
     -H "Content-Type: application/json" \
     -d '{"v":1,"kind":"praise","message":"Test from the command line","source":"app","app":{"version":"1.14.1","os":"Windows"}}'
   ```

   Expected: `{"ok":true}` and a second e-mail.

If it does not work:

| What you see | What it means |
|---|---|
| "Feedback is not set up on this site yet" (503) | One of the three variables is missing for this environment, or the site was not redeployed after adding them. |
| "The message could not be sent just now" (502) | Resend refused. Vercel > Logs shows `feedback: the mail service answered <number>`. 401/403: the key is wrong, or with the test sender `FEEDBACK_TO` is not the Resend account's own address. 422: `FEEDBACK_FROM` is not a verified sender. Resend's own **Logs** page shows the reason. |
| "That is a lot of messages…" (429) | The limit of 5 in 10 minutes from one address. Wait. |
| It says Sent, but no e-mail | Spam folder; then Resend > Emails for the delivery status. |

## 6. Optional: a custom domain

Only if the owner has a domain or decides to buy one (**rule 2: ask, and
name the yearly price**). Project > Settings > Domains > Add, then add the
DNS record Vercel shows at the domain's provider. Afterwards set
`NEXT_PUBLIC_SITE_URL` to the new address and redeploy, so the sitemap and
link previews use it.

## 7. Optional: Cloudflare Turnstile (only if junk arrives)

Not needed at the start. If automatic junk comes through the form:

1. A free Cloudflare account > **Turnstile** > Add widget, for the site's
   host name, mode "Managed".
2. In Vercel add `NEXT_PUBLIC_TURNSTILE_SITE_KEY` (the site key, public) and
   `TURNSTILE_SECRET` (the secret key, Sensitive). Redeploy.
3. The form now shows a small check, and the Privacy page gains a paragraph
   about it by itself. Send a test feedback again (step 5). Step 5's
   command-line test keeps working, because posts from the app are not
   asked for the check.

This part of the code has unit tests but has not been tried against the
real Cloudflare service: test it carefully, and take the two variables out
again if the form stops working.

## 8. Report back

Tell the owner, and write into the hand-over to the developer session:

- **The site's address** (the `vercel.app` one, and the custom domain if
  there is one).
- **The feedback address for the app:** `<site>/api/feedback`. The app can
  get a "Send feedback…" item that posts JSON there (the format is in
  `web/README.md`, "Feedback") or opens
  `<site>/feedback?version=<version>&os=<Windows|Mac|Android>`, which
  fills those two boxes in.
- Which sender is in use (Resend's test sender, or a verified domain).
- That the download-page links can now move: the steps for turning the old
  GitHub Pages page into a signpost are in `web/README.md`, "The old
  download page". That is a change to `site/` and later to the app, to be
  done by the developer session, not in this setup.
- Anything that did not match this guide.

Finally check `git status` in the repository: it must show no new files
with keys or addresses. Nothing in this setup needs a commit.
