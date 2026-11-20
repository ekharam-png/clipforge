import type { Block, Inline, ListBlock } from "@/lib/content";

// Turns the plain data made by scripts/markdown.mjs into elements.

export function Text({ c }: { c: Inline[] }) {
  return (
    <>
      {c.map((piece, i) => {
        if (piece.t === "b") return <b key={i}>{piece.v}</b>;
        if (piece.t === "code") return <code key={i}>{piece.v}</code>;
        if (piece.t === "a")
          return (
            <a key={i} href={piece.href}>
              {piece.v}
            </a>
          );
        return <span key={i}>{piece.v}</span>;
      })}
    </>
  );
}

function List({ block }: { block: ListBlock }) {
  const Tag = block.t;
  return (
    <Tag>
      {block.items.map((item, i) => (
        <li key={i}>
          <Text c={item.c} />
          {item.sub ? <List block={item.sub} /> : null}
        </li>
      ))}
    </Tag>
  );
}

export function Rich({ blocks, heading = "h2" }: { blocks: Block[]; heading?: "h2" | "h3" | "h4" }) {
  const H = heading;
  return (
    <>
      {blocks.map((block, i) => {
        if (block.t === "p")
          return (
            <p key={i}>
              <Text c={block.c} />
            </p>
          );
        if (block.t === "h")
          return (
            <H key={i}>
              <Text c={block.c} />
            </H>
          );
        return <List key={i} block={block} />;
      })}
    </>
  );
}
