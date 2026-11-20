// Facts about the product that several pages share. No secrets live here.

export const REPO = "ekharam-png/clipforge";
export const REPO_URL = `https://github.com/${REPO}`;
export const RELEASES_URL = `${REPO_URL}/releases`;
export const RELEASE_API = `https://api.github.com/repos/${REPO}/releases/latest`;
export const ISSUES_URL = `${REPO_URL}/issues`;

const asset = (name: string) => `${REPO_URL}/releases/latest/download/${name}`;

export const DOWNLOADS = {
  windowsInstaller: asset("ClipForge-Setup.exe"),
  mac: asset("ClipForge-macos.zip"),
  android: asset("ClipForge-android.apk"),
  readmeWindows: asset("ClipForge-readme-windows.html"),
  readmeMac: asset("ClipForge-readme-macos.html"),
  claudeWindows: asset("ClipForge-claude-windows.mcpb"),
  claudeMac: asset("ClipForge-claude-macos.mcpb"),
  claudeSkill: asset("ClipForge-claude-skill.zip"),
} as const;

export const TAGLINE =
  "A free, simple video editor for family videos, podcast clips and sport clips.";

// The public address of the site: set by hand, or worked out on Vercel.
export function siteUrl(): string {
  const explicit = process.env.NEXT_PUBLIC_SITE_URL;
  if (explicit) return explicit.replace(/\/+$/, "");
  const vercel = process.env.VERCEL_PROJECT_PRODUCTION_URL || process.env.VERCEL_URL;
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
