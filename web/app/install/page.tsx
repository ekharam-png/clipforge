import type { Metadata } from "next";
import Link from "next/link";
import { PageHead } from "@/components/Chrome";
import { DeviceMark } from "@/components/Live";
import { DOWNLOADS, RELEASES_URL, REPO_URL } from "@/lib/site";

export const metadata: Metadata = {
  title: "Install",
  description: "How to install ClipForge on Windows, Mac and Android, step by step, with the warnings explained.",
};

const css = (c: string) => ({ "--c": `var(--c-${c})` }) as React.CSSProperties;

// The install steps are the same sentences as the app's "Read me first" guide
// (video-editor/tool/ci/make_readme_html.py) and site/index.html.
export default function Install() {
  return (
    <>
      <DeviceMark />
      <PageHead eyebrow="Install" title="Install ClipForge">
        <p className="lede">
          Pick your system, download, and follow the steps. It takes a minute or two. Your device shows a warning the
          first time: that is expected, and explained below.
        </p>
      </PageHead>

      <div className="wrap">
        <section className="band" aria-label="Steps for each system">
          <div className="grid c3">
            <div className="card osbox" data-os="windows" style={css("video")}>
              <h2>
                Windows <span className="yours">this device</span>
              </h2>
              <p className="dl">
                <a className="button" href={DOWNLOADS.windowsInstaller}>
                  Download the installer
                </a>
              </p>
              <h4>With the installer (recommended)</h4>
              <ol>
                <li>
                  Open the downloaded <b>ClipForge-Setup.exe</b>.
                </li>
                <li>
                  If you see &quot;Windows protected your PC&quot;, click <b>More info</b>, then <b>Run anyway</b>.
                </li>
                <li>
                  Click through the installer. It needs no administrator password and puts ClipForge in the Start menu.
                </li>
                <li>
                  Open the <b>Start menu</b> and choose <b>ClipForge</b>.
                </li>
              </ol>
              <h4>Or with the zip (nothing is installed)</h4>
              <ol>
                <li>
                  Right-click the downloaded <a href={DOWNLOADS.windowsZip}>ClipForge-windows.zip</a> and choose{" "}
                  <b>Extract All</b>.
                </li>
                <li>
                  Inside is a folder called <b>ClipForge</b>. Move it to where you want to keep it, for example
                  Documents.
                </li>
                <li>
                  Keep the folder named <b>ClipForge</b>, with no version number: ClipForge updates itself inside this
                  folder.
                </li>
                <li>
                  Open the folder and double-click <b>clipforge.exe</b>. If you see &quot;Windows protected your
                  PC&quot;, click <b>More info</b>, then <b>Run anyway</b>.
                </li>
              </ol>
              <p className="hint">
                Do not start ClipForge from a folder whose name ends in <b>.update-new</b>: that is a download waiting
                to be put in place.
              </p>
              <p className="hint">
                <a href={DOWNLOADS.readmeWindows}>Full guide for Windows</a> (a small page to download and open; the
                same page is inside the download as &quot;Read me first&quot;).
              </p>
            </div>

            <div className="card osbox" data-os="mac" style={css("music")}>
              <h2>
                Mac <span className="yours">this device</span>
              </h2>
              <p className="dl">
                <a className="button" href={DOWNLOADS.mac}>
                  Download for Mac
                </a>
              </p>
              <ol>
                <li>
                  Double-click the downloaded <b>ClipForge-macos.zip</b> to unzip it. A folder appears with ClipForge
                  in it.
                </li>
                <li>
                  Drag <b>ClipForge</b> into your <b>Applications</b> folder.
                </li>
                <li>
                  <b>macOS 15 or newer:</b> open ClipForge once. macOS says it cannot open it: close that message. Then
                  open <b>System Settings</b>, choose <b>Privacy &amp; Security</b>, scroll down, click{" "}
                  <b>Open Anyway</b> next to the line about ClipForge, and confirm.
                </li>
                <li>
                  <b>Older macOS:</b> right-click ClipForge, choose <b>Open</b>, then <b>Open</b> again.
                </li>
              </ol>
              <p className="hint">
                This is needed once, because ClipForge is not signed by Apple. After that it opens like any other app.
              </p>
              <p className="hint">Needs macOS 12 or newer.</p>
              <p className="hint">
                <a href={DOWNLOADS.readmeMac}>Full guide for Mac</a> (a small page to download and open; the same page
                is inside the download as &quot;Read me first&quot;).
              </p>
            </div>

            <div className="card osbox" data-os="android" style={css("title")}>
              <h2>
                Android <span className="yours">this device</span>
              </h2>
              <p className="dl">
                <a className="button" href={DOWNLOADS.android}>
                  Download for Android
                </a>
              </p>
              <ol>
                <li>
                  Tap the download button on this page, on the phone or tablet itself, and wait for the download to
                  finish.
                </li>
                <li>Open the downloaded file from your notifications or the Files app.</li>
                <li>
                  If asked, allow &quot;Install unknown apps&quot; for your browser or file manager, then go back.
                </li>
                <li>
                  Tap <b>Install</b>. If Play Protect asks, choose <b>Install anyway</b>.
                </li>
                <li>
                  Tap <b>Open</b>, or find ClipForge among your apps.
                </li>
              </ol>
              <p className="hint">New versions install over the old one and keep your projects.</p>
              <p className="hint">
                Very old phone? If the app does not install, use the{" "}
                <a href={DOWNLOADS.androidOld}>version for old 32-bit phones</a>.
              </p>
            </div>
          </div>
        </section>

        <section className="band" aria-labelledby="warnings">
          <h2 id="warnings">Why does my device warn me?</h2>
          <div className="prose">
            <p>
              Microsoft, Apple and Google show a warning for every app that does not come through their shop or carry
              their paid signature. ClipForge is a small free project and has neither yet, so each system asks you to
              confirm once. The warning says &quot;we do not know this app&quot;; it does not say that something was
              found in it.
            </p>
          </div>
          <div className="grid c3" style={{ marginTop: 18 }}>
            <div className="note" style={css("video")}>
              <h3>Windows: &quot;Windows protected your PC&quot;</h3>
              <p>
                The blue SmartScreen window appears because ClipForge is not signed by Microsoft. <b>More info</b>{" "}
                shows the <b>Run anyway</b> button. You see it once for the installer.
              </p>
            </div>
            <div className="note" style={css("music")}>
              <h3>Mac: &quot;ClipForge can&rsquo;t be opened&quot;</h3>
              <p>
                macOS blocks apps that are not signed by Apple until you allow them yourself, with <b>Open Anyway</b>{" "}
                in <b>System Settings</b> &gt; <b>Privacy &amp; Security</b>. It is needed once.
              </p>
            </div>
            <div className="note" style={css("title")}>
              <h3>Android: &quot;Install unknown apps&quot;</h3>
              <p>
                Android only installs files from outside the Play Store after you allow it for the app that opens the
                file (your browser or Files). You can switch that permission off again afterwards; ClipForge keeps
                working.
              </p>
            </div>
          </div>
          <div className="prose">
            <p>
              What you can check for yourself: the downloads on this site come straight from the{" "}
              <a href={RELEASES_URL}>releases page</a> of the project on GitHub, where they are built by an automatic
              process from the <a href={REPO_URL}>public source code</a>. Get ClipForge only from here or from that
              page.
            </p>
            <p>
              Stuck on a step? The help has a page for each one:{" "}
              <Link href="/help/windows-smartscreen">Windows</Link>, <Link href="/help/mac-cant-open">Mac</Link>,{" "}
              <Link href="/help/android-install">Android</Link>. Or <Link href="/feedback">ask us</Link>.
            </p>
          </div>
        </section>

        <section className="band" aria-labelledby="after">
          <h2 id="after">After installing</h2>
          <div className="grid c3">
            <div className="card" style={css("photo")}>
              <h3>Updates come by themselves</h3>
              <p>
                When a new version is out, the project list shows &quot;Version … is available&quot; with an{" "}
                <b>Update</b> button. You only need this page for the first install, or as the other way if an update
                does not work. Your projects are kept. <Link href="/help/updates">More about updates</Link>
              </p>
            </div>
            <div className="card" style={css("caption")}>
              <h3>Where your projects are</h3>
              <p>
                On a computer, in your <b>Documents</b> folder, in <b>ClipForge</b>. Updating, reinstalling or removing
                ClipForge does not touch them. <Link href="/help/where-files-go">Where files are kept</Link>
              </p>
            </div>
            <div className="card" style={css("video")}>
              <h3>Your first video</h3>
              <p>
                The app offers a quick tour the first time it opens. For the longer version, with pictures, follow the{" "}
                <Link href="/walkthrough">walk-through</Link>.
              </p>
            </div>
          </div>
        </section>
      </div>
    </>
  );
}
