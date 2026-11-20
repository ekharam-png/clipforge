import type { MetadataRoute } from "next";
import { help } from "@/lib/content";
import { siteUrl } from "@/lib/site";

export default function sitemap(): MetadataRoute.Sitemap {
  const base = siteUrl();
  const pages = ["", "/install", "/walkthrough", "/features", "/examples", "/claude", "/help", "/whats-new", "/feedback", "/privacy"];
  return [
    ...pages.map((path) => ({ url: `${base}${path}`, priority: path === "" ? 1 : 0.8 })),
    ...help.map((a) => ({ url: `${base}/help/${a.id}`, priority: 0.5 })),
  ];
}
