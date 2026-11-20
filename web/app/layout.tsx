import type { Metadata, Viewport } from "next";
import { Footer, Header } from "@/components/Chrome";
import { siteUrl, TAGLINE } from "@/lib/site";
import "./globals.css";

export const metadata: Metadata = {
  metadataBase: new URL(siteUrl()),
  title: { default: "ClipForge: a free, simple video editor", template: "%s · ClipForge" },
  description: `${TAGLINE} For Windows, Mac and Android. No subscription, no watermark, works offline.`,
  applicationName: "ClipForge",
  openGraph: { type: "website", siteName: "ClipForge", locale: "en" },
  twitter: { card: "summary_large_image" },
  alternates: { canonical: "./" },
};

export const viewport: Viewport = {
  themeColor: [
    { media: "(prefers-color-scheme: light)", color: "#eef0f4" },
    { media: "(prefers-color-scheme: dark)", color: "#12161d" },
  ],
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en">
      <body>
        <a className="skip" href="#main">
          Skip to the page
        </a>
        <Header />
        <main id="main">{children}</main>
        <Footer />
      </body>
    </html>
  );
}
