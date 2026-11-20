import Link from "next/link";
import { ISSUES_URL, NAV, REPO_URL } from "@/lib/site";

export function Header() {
  return (
    <header className="top">
      <div className="wrap">
        <Link className="brand" href="/">
          {/* The app icon, served by app/icon.png. */}
          <img src="/icon.png" alt="" width={28} height={28} />
          ClipForge
        </Link>
        <nav className="nav-wide" aria-label="Main">
          <ul>
            {NAV.map((item) => (
              <li key={item.href}>
                <Link href={item.href}>{item.label}</Link>
              </li>
            ))}
            <li>
              <Link className="cta" href="/#download">
                Download
              </Link>
            </li>
          </ul>
        </nav>
        <details className="nav-narrow">
          <summary>Menu</summary>
          <nav aria-label="Main">
            <ul>
              <li>
                <Link href="/#download">Download</Link>
              </li>
              {NAV.map((item) => (
                <li key={item.href}>
                  <Link href={item.href}>{item.label}</Link>
                </li>
              ))}
              <li>
                <Link href="/whats-new">What&rsquo;s new</Link>
              </li>
            </ul>
          </nav>
        </details>
      </div>
    </header>
  );
}

export function Footer() {
  return (
    <footer className="foot">
      <div className="wrap">
        <ul className="cols">
          <li>
            <Link href="/whats-new">What&rsquo;s new</Link>
          </li>
          <li>
            <Link href="/help">Help</Link>
          </li>
          <li>
            <Link href="/feedback">Feedback</Link>
          </li>
          <li>
            <Link href="/privacy">Privacy</Link>
          </li>
          <li>
            <a href={REPO_URL}>Source code on GitHub</a>
          </li>
          <li>
            <a href={ISSUES_URL}>Report a problem on GitHub</a>
          </li>
        </ul>
        <p>
          ClipForge is free software under the <a href={`${REPO_URL}/blob/main/LICENSE`}>GNU GPL version 3</a>. It is a
          beta made for personal use and comes with no warranty. Keep copies of videos you care about.
        </p>
        <p>This site uses no cookies and no analytics.</p>
      </div>
    </footer>
  );
}

export function PageHead({ eyebrow, title, children }: { eyebrow: string; title: string; children?: React.ReactNode }) {
  return (
    <div className="pagehead wrap">
      <p className="eyebrow">{eyebrow}</p>
      <h1>{title}</h1>
      {children}
      <div className="ruler" aria-hidden="true" />
    </div>
  );
}
