// Facts about the product that several pages share. No secrets live here.
//
// The outside addresses are NOT written here: scripts/build-content.mjs
// copies them from ../video-editor/tool/ci/links.json (the one place for
// the app, its release tools and this site) into content/generated/links.json.
import linksJson from "../content/generated/links.json";

const generated = linksJson as {
  links: { site: string; download: string; feedback_api: string; feedback_page: string; help: string; privacy: string };
  claudePage: string;
  repository: string;
  repo: string;
  oldPages: string;
};

/** The addresses the app is told about in latest.json. */
export const LINKS = generated.links;
/** The old GitHub Pages address: old versions of the app still open it. */
export const OLD_PAGES_URL = generated.oldPages;
/** The longer Claude setup page that also travels with the downloads. */
export const CLAUDE_SETUP_URL = `${OLD_PAGES_URL}claude-setup.html`;

export const REPO = generated.repo;
export const REPO_URL = generated.repository;
export const RELEASES_URL = `${REPO_URL}/releases`;
export const RELEASE_API = `https://api.github.com/repos/${REPO}/releases/latest`;
export const ISSUES_URL = `${REPO_URL}/issues`;

const asset = (name: string) => `${REPO_URL}/releases/latest/download/${name}`;

export const DOWNLOADS = {
  windowsInstaller: asset("ClipForge-Setup.exe"),
  mac: asset("ClipForge-macos.zip"),
  android: asset("ClipForge-android.apk"),
} as const;

export const TAGLINE =
  "A free, simple video editor for family videos, podcast clips and sport clips.";

// The public address of the site, for the sitemap and link previews: set by
// hand (NEXT_PUBLIC_SITE_URL), else the address in links.json for the
// production site, else what Vercel says for a preview, else this computer.
export function siteUrl(): string {
  const explicit = process.env.NEXT_PUBLIC_SITE_URL;
  if (explicit) return explicit.replace(/\/+$/, "");
  if (process.env.VERCEL_ENV === "production") return LINKS.site;
  const vercel = process.env.VERCEL_URL || process.env.VERCEL_PROJECT_PRODUCTION_URL;
  if (vercel) return `https://${vercel}`;
  return "http://localhost:3000";
}

export const NAV = [
  { href: "/install", label: "Install" },
  { href: "/walkthrough", label: "Walk-through" },
  { href: "/features", label: "Features" },
  { href: "/examples", label: "Examples" },
  { href: "/claude", label: "Claude" },
  { href: "/help", label: "Help" },
  { href: "/feedback", label: "Feedback" },
] as const;
