import type { Where } from "@/lib/content";

const LABEL: Record<Where, string> = {
  both: "Phone and computer",
  computer: "Computer",
  phone: "Phone",
};

const PhoneIcon = () => (
  <svg viewBox="0 0 16 16" aria-hidden="true" fill="none" stroke="currentColor" strokeWidth="1.6">
    <rect x="4.5" y="1.5" width="7" height="13" rx="1.6" />
    <path d="M7 12.4h2" strokeLinecap="round" />
  </svg>
);

const ComputerIcon = () => (
  <svg viewBox="0 0 16 16" aria-hidden="true" fill="none" stroke="currentColor" strokeWidth="1.6">
    <rect x="1.5" y="2.5" width="13" height="8.5" rx="1.4" />
    <path d="M5.5 14h5M8 11v3" strokeLinecap="round" />
  </svg>
);

/** Where something works: a word and a small picture, never colour alone. */
export function Mark({ where, short }: { where: Where; short?: boolean }) {
  return (
    <span className={`mark ${where}`}>
      {where !== "computer" ? <PhoneIcon /> : null}
      {where !== "phone" ? <ComputerIcon /> : null}
      {short && where === "both" ? "Both" : LABEL[where]}
    </span>
  );
}
