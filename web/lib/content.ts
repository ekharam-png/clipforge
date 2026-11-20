// Typed access to what scripts/build-content.mjs wrote.
import helpJson from "../content/generated/help.json";
import changelogJson from "../content/generated/changelog.json";
import featuresJson from "../content/generated/features.json";
import shotsJson from "../content/generated/shots.json";
import versionJson from "../content/generated/version.json";
import examplesJson from "../content/examples.json";

export type Inline = { t: "text" | "b" | "code"; v: string } | { t: "a"; v: string; href: string };
export type ListBlock = { t: "ul" | "ol"; items: { c: Inline[]; sub?: ListBlock }[] };
export type Block = { t: "p"; c: Inline[] } | { t: "h"; c: Inline[] } | ListBlock;

export type HelpArticle = {
  id: string;
  title: string;
  section: string;
  keywords: string[];
  related: string[];
  comingLater: boolean;
  body: Block[];
  summary: string;
};

export type Where = "both" | "computer" | "phone";
export type FeatureRow = { feature: Inline[]; since: string; where: Where; whereNote: string; what: Inline[] };
export type FeatureSection = { title: string; intro: Inline[] | null; rows: FeatureRow[] };
export type Version = { version: string; date: string; body: Block[] };
export type ShotInfo = { w: number; h: number; alt: string };

export type Example = {
  id: string;
  title: string;
  kind?: string;
  description: string;
  done: string[];
  before?: string;
  after?: string;
  beforeLabel?: string;
  afterLabel?: string;
  poster?: string;
  video?: string;
  link?: { href: string; label: string };
};

export const help = helpJson as unknown as HelpArticle[];
export const changelog = changelogJson as unknown as Version[];
export const features = featuresJson as unknown as { sections: FeatureSection[]; planned: Inline[][] };
export const shots = shotsJson as unknown as Record<string, ShotInfo>;
export const builtVersion = (versionJson as { version: string }).version;
export const examples = examplesJson as unknown as { notice: string; examples: Example[] };

// Help sections in the order the app's own help file introduces them.
export function helpSections(): { name: string; articles: HelpArticle[] }[] {
  const order: string[] = [];
  for (const a of help) if (!order.includes(a.section)) order.push(a.section);
  const last = "Coming later";
  order.sort((a, b) => Number(a === last) - Number(b === last));
  return order.map((name) => ({ name, articles: help.filter((a) => a.section === name) }));
}

export function helpArticle(id: string): HelpArticle | undefined {
  return help.find((a) => a.id === id);
}
