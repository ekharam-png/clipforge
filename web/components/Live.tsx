"use client";

import { useEffect, useState } from "react";
import { RELEASE_API } from "@/lib/site";

/**
 * The version number. It starts as the one known when the site was built and
 * is then checked against GitHub's newest release. If that fails for any
 * reason, the built-in number simply stays.
 */
export function VersionLive({ built }: { built: string }) {
  const [version, setVersion] = useState(built);
  useEffect(() => {
    const stop = new AbortController();
    fetch(RELEASE_API, { signal: stop.signal, headers: { Accept: "application/vnd.github+json" } })
      .then((r) => (r.ok ? r.json() : null))
      .then((j) => {
        const v = j && j.tag_name ? String(j.tag_name).replace(/^v/, "") : "";
        if (/^\d+(\.\d+){1,3}$/.test(v)) setVersion(v);
      })
      .catch(() => {});
    return () => stop.abort();
  }, []);
  return <span>Version {version}</span>;
}

/** Marks the visitor's own system on <html data-os>, for the stylesheet. */
export function DeviceMark() {
  useEffect(() => {
    const ua = navigator.userAgent || "";
    const os = /Android/i.test(ua)
      ? "android"
      : /Mac/i.test(ua) && !/iPhone|iPad/i.test(ua)
        ? "mac"
        : /Windows/i.test(ua)
          ? "windows"
          : "";
    if (os) document.documentElement.dataset.os = os;
  }, []);
  return null;
}
