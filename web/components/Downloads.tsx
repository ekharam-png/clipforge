import { DOWNLOADS, RELEASES_URL } from "@/lib/site";

/** The three downloads, drawn as clips on a timeline, one track per system. */
export function Downloads() {
  return (
    <>
      <div className="timeline" role="group" aria-label="Downloads">
        <div className="tl-ruler" aria-hidden="true">
          <span>0:00</span>
          <span>0:02</span>
          <span>0:04</span>
          <span>0:06</span>
          <span>0:08</span>
          <span>0:10</span>
        </div>
        <span className="playhead" aria-hidden="true" />
        <div className="tl-row" data-os="windows">
          <span className="tl-label">
            Windows <span className="tl-mine">this device</span>
          </span>
          <div className="lane" style={{ "--c": "var(--c-video)" } as React.CSSProperties}>
            <a className="clip" href={DOWNLOADS.windowsInstaller}>
              <span className="top-line">
                <span>ClipForge-Setup.exe</span>
                <span>Windows 10 and 11</span>
              </span>
              <span className="act">Download for Windows</span>
            </a>
          </div>
        </div>
        <div className="tl-row" data-os="mac">
          <span className="tl-label">
            Mac <span className="tl-mine">this device</span>
          </span>
          <div className="lane" style={{ "--c": "var(--c-music)" } as React.CSSProperties}>
            <a className="clip w2" href={DOWNLOADS.mac}>
              <span className="top-line">
                <span>ClipForge-macos.zip</span>
                <span>macOS 12 or newer</span>
              </span>
              <span className="act">Download for Mac</span>
            </a>
          </div>
        </div>
        <div className="tl-row" data-os="android">
          <span className="tl-label">
            Android <span className="tl-mine">this device</span>
          </span>
          <div className="lane" style={{ "--c": "var(--c-title)" } as React.CSSProperties}>
            <a className="clip w3" href={DOWNLOADS.android}>
              <span className="top-line">
                <span>ClipForge-android.apk</span>
                <span>Phones and tablets</span>
              </span>
              <span className="act">Download for Android</span>
            </a>
          </div>
        </div>
      </div>
      <p className="small">
        Past versions are on the{" "}
        <a href={RELEASES_URL}>releases page</a>. After downloading, the <a href="/install">install steps</a> take a
        minute.
      </p>
    </>
  );
}
