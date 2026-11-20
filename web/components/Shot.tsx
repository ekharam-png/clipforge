import Image from "next/image";
import { shots } from "@/lib/content";

type Props = {
  /** A name from content/shots.json. */
  name: string;
  caption?: React.ReactNode;
  /** Load it first: only for the one picture at the top of a page. */
  first?: boolean;
  /** How wide it is shown, for the browser to pick the right file. */
  sizes?: string;
};

// A real screenshot of the app, with its description. A name that is not in
// content/shots.json stops the build, so no page can show a missing picture.
export function Shot({ name, caption, first, sizes }: Props) {
  const info = shots[name];
  if (!info) throw new Error(`Screenshot "${name}" is not listed in content/shots.json.`);
  const phone = info.h > info.w;
  return (
    <figure className={phone ? "shot phone" : "shot"}>
      <Image
        src={`/shots/${name}.png`}
        width={info.w}
        height={info.h}
        alt={info.alt}
        preload={first}
        loading={first ? "eager" : "lazy"}
        sizes={sizes ?? (phone ? "250px" : "(max-width: 1120px) 100vw, 1040px")}
      />
      {caption ? <figcaption>{caption}</figcaption> : null}
    </figure>
  );
}

/** A computer screenshot with the phone's version of the same step next to it. */
export function ShotPair({ computer, phone }: { computer: string; phone?: string }) {
  return (
    <div className={phone ? "pair" : "pair solo"}>
      <Shot name={computer} sizes={phone ? "(max-width: 620px) 100vw, 760px" : "(max-width: 1000px) 100vw, 940px"} />
      {phone ? <Shot name={phone} sizes="210px" /> : null}
    </div>
  );
}
