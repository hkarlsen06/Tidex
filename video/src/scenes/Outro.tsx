import React from "react";
import { AbsoluteFill, Img, interpolate, spring, staticFile, useCurrentFrame, useVideoConfig } from "remotion";
import { Wordmark } from "../brand";
import { C, COPY, Lang, SANS, Variant } from "../config";
import { Caption, Sfx } from "../parts";

const clamp = { extrapolateLeft: "clamp", extrapolateRight: "clamp" } as const;

// End card: app icon, lettering and tagline. The App Store cut carries the required account and purchase note.
export const Outro: React.FC<{ lang: Lang; variant: Variant }> = ({ lang, variant }) => {
  const frame = useCurrentFrame();
  const { fps, width } = useVideoConfig();
  const copy = COPY[lang];
  const social = variant === "social";
  const icon = social ? 290 : 250;
  const iconTop = social ? 520 : 600;
  const markH = social ? 116 : 100;
  const pop = spring({ frame: frame - 4, fps, config: { damping: 11, stiffness: 140, mass: 0.9 } });
  const glow = spring({ frame, fps, config: { damping: 200 } });
  const float = Math.sin(Math.max(0, frame - 36) / 18) * 6;
  const fadeIn = (at: number) => interpolate(frame, [at, at + 12], [0, 1], clamp);
  const wordTop = iconTop + icon + (social ? 60 : 52);
  const tagTop = wordTop + markH + (social ? 40 : 34);

  return (
    <AbsoluteFill>
      <div
        style={{
          position: "absolute",
          left: width / 2 - 700,
          top: iconTop + icon / 2 - 700,
          width: 1400,
          height: 1400,
          background: `radial-gradient(circle, ${C.blue}8C 0%, ${C.blue}00 58%)`,
          scale: `${0.4 + 0.6 * glow + Math.sin(frame / 22) * 0.02}`,
          opacity: glow,
        }}
      />
      <Img
        src={staticFile("brand/tidex-app-icon.png")}
        style={{
          position: "absolute",
          left: width / 2 - icon / 2,
          top: iconTop + float,
          width: icon,
          height: icon,
          scale: `${pop}`,
          rotate: `${(1 - pop) * -14}deg`,
          filter: "drop-shadow(0 34px 50px rgba(4, 12, 40, 0.6))",
        }}
      />
      <div style={{ position: "absolute", left: 0, width, top: wordTop, display: "flex", justifyContent: "center" }}>
        <Wordmark
          height={markH}
          progress={(i) => spring({ frame: frame - 16 - i * 3, fps, config: { damping: 12, stiffness: 180 } })}
        />
      </div>
      <Caption
        text={copy.tagline}
        size={social ? 74 : 62}
        top={tagTop}
        bottom={tagTop + (social ? 190 : 160)}
        delay={28}
      />
      {social ? (
        <div
          style={{
            position: "absolute",
            left: 0,
            width,
            top: tagTop + 250,
            display: "flex",
            flexDirection: "column",
            alignItems: "center",
            gap: 26,
          }}
        >
          <Img src={staticFile(`brand/app-store-${lang}.svg`)} style={{ height: 108, opacity: fadeIn(46) }} />
          <div style={{ fontFamily: SANS, fontWeight: 500, fontSize: 34, color: C.text2, opacity: fadeIn(54) }}>
            {copy.cta}
          </div>
        </div>
      ) : (
        <div
          style={{
            position: "absolute",
            left: 0,
            width,
            bottom: 110,
            textAlign: "center",
            whiteSpace: "pre-line",
            fontFamily: SANS,
            fontWeight: 500,
            fontSize: 27,
            lineHeight: 1.35,
            color: C.muted,
            opacity: fadeIn(40),
          }}
        >
          {copy.disclaimer}
        </div>
      )}
      <Sfx name="whoosh" at={0} volume={0.14} />
      <Sfx name="pop" at={6} volume={0.2} />
    </AbsoluteFill>
  );
};
