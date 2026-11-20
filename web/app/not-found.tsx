import type { Metadata } from "next";
import Link from "next/link";

export const metadata: Metadata = { title: "Page not found" };

export default function NotFound() {
  return (
    <div className="wrap lost">
      <p className="code" aria-hidden="true">
        4:04
      </p>
      <h1>This page was cut</h1>
      <p className="lede">There is nothing at this address. It may have moved, or the link has a typing mistake.</p>
      <div className="buttons">
        <Link className="button" href="/">
          To the start
        </Link>
        <Link className="button quiet" href="/help">
          Search the help
        </Link>
        <Link className="button quiet" href="/feedback">
          Tell us about a broken link
        </Link>
      </div>
    </div>
  );
}
