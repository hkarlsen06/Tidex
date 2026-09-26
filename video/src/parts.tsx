import { Audio } from "@remotion/media";
import React from "react";
import {
  AbsoluteFill,
  Easing,
  Img,
  interpolate,
  Sequence,
  spring,
  staticFile,
  useCurrentFrame,
  useVideoConfig,
} from "remotion";
import { RULER_H, RULER_PATH, RULER_W, slipPath } from "./brand";
import { Box, C, MONO, SANS } from "./config";

const clamp = { extrapolateLeft: "clamp", extrapolateRight: "clamp" } as const;
// Shared by the rebuilt payroll sheet slide and the finger that drags it.
export const SLIDE_EASING = Easing.inOut(Easing.cubic);

export const Sfx: React.FC<{ name: string; at: number; volume?: number }> = ({ name, at, volume = 0.5 }) => (
  <Sequence from={Math.round(at)} durationInFrames={60} layout="none">
    <Audio src={staticFile(`audio/${name}.wav`)} volume={volume} />
  </Sequence>
);

export const Background: React.FC = () => {
  const t = useCurrentFrame() / 30;
  const { width } = useVideoConfig();
  return (
    <AbsoluteFill style={{ backgroundColor: C.bg, overflow: "hidden" }}>
      <div
        style={{
          position: "absolute",
          width: 1500,
          height: 1500,
          left: width * 0.62 - 750 + Math.sin(t * 0.4) * 70,
          top: -520 + Math.cos(t * 0.33) * 60,
          background: `radial-gradient(circle, ${C.blue}66 0%, ${C.blue}00 62%)`,
        }}
      />
      <div
        style={{
          position: "absolute",
          width: 1400,
          height: 1400,
          left: width * 0.3 - 700 + Math.cos(t * 0.28) * 80,
          top: 1050 + Math.sin(t * 0.36) * 70,
          background: `radial-gradient(circle, ${C.indigo}55 0%, ${C.indigo}00 60%)`,
        }}
      />
      <AbsoluteFill style={{ background: "radial-gradient(ellipse at 50% 45%, #00000000 55%, #00000073 100%)" }} />
      {/* Static grain dithers the dark gradients so they don't band after platform re-encoding. */}
      <AbsoluteFill style={{ opacity: 0.035 }}>
        <svg width="100%" height="100%">
          <filter id="grain">
            <feTurbulence type="fractalNoise" baseFrequency="0.9" numOctaves="2" stitchTiles="stitch" />
            <feColorMatrix type="saturate" values="0" />
          </filter>
          <rect width="100%" height="100%" filter="url(#grain)" />
        </svg>
      </AbsoluteFill>
    </AbsoluteFill>
  );
};

type Token = { word: string; mark: boolean };
const parse = (text: string): Token[][] =>
  text.split("\n").map((line) => {
    const tokens: Token[] = [];
    let mark = false;
    for (const part of line.split(/([{}])/)) {
      if (part === "{") mark = true;
      else if (part === "}") mark = false;
      else for (const word of part.split(" ").filter(Boolean)) tokens.push({ word, mark });
    }
    return tokens;
  });

// Kinetic headline: words spring up one by one, highlighted words get a blue marker swipe.
export const Caption: React.FC<{
  text: string;
  size: number;
  top: number;
  bottom: number;
  delay?: number;
  exitAt?: number;
  weight?: number;
}> = ({ text, size, top, bottom, delay = 3, exitAt = Infinity, weight = 600 }) => {
  const frame = useCurrentFrame();
  const { fps, width } = useVideoConfig();
  const exit = Number.isFinite(exitAt)
    ? interpolate(frame, [exitAt, exitAt + 8], [0, 1], { ...clamp, easing: Easing.in(Easing.cubic) })
    : 0;
  let index = 0;
  return (
    <div
      style={{
        position: "absolute",
        left: 0,
        width,
        top,
        height: bottom - top,
        display: "flex",
        flexDirection: "column",
        justifyContent: "center",
        alignItems: "center",
        fontFamily: SANS,
        fontWeight: weight,
        fontSize: size,
        lineHeight: 1.12,
        color: C.text,
        textAlign: "center",
        opacity: 1 - exit,
        translate: `0 ${-40 * exit}px`,
      }}
    >
      {parse(text).map((line, l) => (
        <div key={l} style={{ whiteSpace: "nowrap" }}>
          {line.map((token, w) => {
            const start = delay + index++ * 2.5;
            const s = spring({ frame: frame - start, fps, config: { damping: 12, stiffness: 170, mass: 0.7 } });
            const marker = spring({ frame: frame - start - 7, fps, config: { damping: 200 } });
            const nextMarked = line[w + 1]?.mark && token.mark;
            return (
              <span
                key={w}
                style={{
                  display: "inline-block",
                  position: "relative",
                  opacity: interpolate(s, [0, 0.4], [0, 1], clamp),
                  translate: `0 ${(1 - s) * size * 0.55}px`,
                  rotate: `${(1 - s) * 7}deg`,
                  paddingRight: nextMarked ? "0.26em" : 0,
                  marginRight: nextMarked ? 0 : "0.26em",
                  zIndex: 0,
                }}
              >
                {token.mark ? (
                  <span
                    style={{
                      position: "absolute",
                      left: w > 0 && line[w - 1].mark ? "-0.02em" : "-0.14em",
                      right: nextMarked ? "-0.02em" : "-0.14em",
                      top: "0.08em",
                      bottom: "0.02em",
                      background: C.blue,
                      borderRadius: nextMarked || (w > 0 && line[w - 1].mark) ? 0 : "0.16em",
                      scale: `${marker} 1`,
                      transformOrigin: "left center",
                      rotate: "-1.2deg",
                      zIndex: -1,
                    }}
                  />
                ) : null}
                {token.word}
              </span>
            );
          })}
        </div>
      ))}
    </div>
  );
};

// Touch indicator in card space: press, optional drag, release ripple.
export const TapRing: React.FC<{
  at: number;
  x: number;
  y: number;
  cardW: number;
  cardH: number;
  drag?: { start: number; end: number; x: number; y: number };
}> = ({ at, x, y, cardW, cardH, drag }) => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const release = drag ? drag.end : at + 7;
  if (frame < at - 2 || frame > release + 16) return null;
  const press = spring({ frame: frame - at + 2, fps, config: { damping: 14, stiffness: 260 } });
  const move = drag ? interpolate(frame, [drag.start, drag.end], [0, 1], { ...clamp, easing: SLIDE_EASING }) : 0;
  const cx = (x + ((drag?.x ?? x) - x) * move) * cardW;
  const cy = (y + ((drag?.y ?? y) - y) * move) * cardH;
  const up = interpolate(frame, [release, release + 14], [0, 1], { ...clamp, easing: Easing.out(Easing.quad) });
  const d = cardW * 0.12;
  return (
    <>
      <div
        style={{
          position: "absolute",
          left: cx - d / 2,
          top: cy - d / 2,
          width: d,
          height: d,
          borderRadius: d,
          background: "rgba(255,255,255,0.42)",
          border: "3px solid rgba(255,255,255,0.95)",
          boxShadow: "0 6px 20px rgba(0,0,0,0.35)",
          scale: `${press * (1 - 0.35 * up)}`,
          opacity: 1 - up,
        }}
      />
      <div
        style={{
          position: "absolute",
          left: cx - d / 2,
          top: cy - d / 2,
          width: d,
          height: d,
          borderRadius: d,
          border: "3px solid rgba(255,255,255,0.8)",
          scale: `${1 + up * 0.9}`,
          opacity: up > 0 ? 1 - up : 0,
        }}
      />
    </>
  );
};

// Lifts a crop of the real capture out of the card, then settles it back.
export const LiftOut: React.FC<{
  still: string;
  box: Box;
  at: number;
  until: number;
  scale: number;
  to: [number, number];
  rotate: number;
  cardW: number;
  cardH: number;
}> = ({ still, box, at, until, scale, to, rotate, cardW, cardH }) => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  if (frame < at || frame > until) return null;
  const up = spring({ frame: frame - at, fps, config: { damping: 11, stiffness: 150, mass: 0.8 } });
  const down = interpolate(frame, [until - 10, until], [0, 1], { ...clamp, easing: Easing.inOut(Easing.cubic) });
  const p = up * (1 - down);
  const [x1, y1, x2, y2] = box;
  return (
    <div
      style={{
        position: "absolute",
        left: x1 * cardW,
        top: y1 * cardH,
        width: (x2 - x1) * cardW,
        height: (y2 - y1) * cardH,
        overflow: "hidden",
        borderRadius: 14 + 8 * p,
        scale: `${1 + (scale - 1) * p}`,
        translate: `${to[0] * cardW * p}px ${to[1] * cardH * p}px`,
        rotate: `${rotate * p}deg`,
        boxShadow: `0 ${34 * p}px ${70 * p}px rgba(0,0,0,${0.6 * p}), 0 0 0 ${2.5 * p}px rgba(76,134,234,${0.9 * p})`,
        zIndex: 5,
      }}
    >
      <Img
        src={staticFile(`stills/${still}.png`)}
        style={{ position: "absolute", left: -x1 * cardW, top: -y1 * cardH, width: cardW, height: cardH }}
      />
    </div>
  );
};

// Ruler + payslip: the two halves of the Tidex mark, drawn white on the dark background.
export const Ruler: React.FC<{ width: number; fill?: number; style?: React.CSSProperties }> = ({
  width,
  fill = 0,
  style,
}) => {
  const id = React.useId().replace(/:/g, "");
  return (
    <svg width={width} height={(width * RULER_H) / RULER_W} viewBox={`0 0 ${RULER_W} ${RULER_H}`} style={style}>
      <defs>
        <clipPath id={`r${id}`}>
          <path d={RULER_PATH} />
        </clipPath>
        <linearGradient id={`g${id}`} x1="0" y1="0" x2="0" y2="1">
          <stop offset="0" stopColor="#FFFFFF" />
          <stop offset="1" stopColor="#DCE3F1" />
        </linearGradient>
      </defs>
      <path d={RULER_PATH} fill={`url(#g${id})`} />
      {fill > 0 ? (
        <rect x={90} y={0} width={fill * 432} height={RULER_H} fill={C.blue} clipPath={`url(#r${id})`} />
      ) : null}
    </svg>
  );
};

export const Slip: React.FC<{ width: number; body: number; stretch?: number; children?: React.ReactNode }> = ({
  width,
  body,
  stretch = 1,
  children,
}) => {
  const k = width / (304 * stretch);
  const id = React.useId().replace(/:/g, "");
  return (
    <div style={{ position: "relative", width, height: (body + 60) * k }}>
      <svg
        width={width}
        height={(body + 60) * k}
        viewBox={`0 0 ${304 * stretch} ${body + 60}`}
        style={{ position: "absolute", inset: 0, overflow: "visible" }}
      >
        <defs>
          <linearGradient id={`p${id}`} x1="0" y1="0" x2="0" y2="1">
            <stop offset="0" stopColor="#FFFFFF" />
            <stop offset="1" stopColor="#E4EAF4" />
          </linearGradient>
        </defs>
        <path d={slipPath(Math.max(0, body), stretch)} fill={`url(#p${id})`} />
      </svg>
      <div style={{ position: "absolute", left: 0, top: 0, width, height: Math.max(0, body) * k, overflow: "hidden" }}>
        {children}
      </div>
    </div>
  );
};

// Payroll receipt that prints out of a ruler, echoing the app icon.
export const Receipt: React.FC<{ rows: readonly (readonly [string, string])[]; width: number; tilt: number }> = ({
  rows,
  width,
  tilt,
}) => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const pop = spring({ frame, fps, config: { damping: 12, stiffness: 160 } });
  const rowH = 64;
  const head = 24;
  const printed = interpolate(frame, [8, 18, 22, 30, 34, 42, 46, 54, 58, 68], [0, 1, 1, 2, 2, 3, 3, 4, 4, 5.25], {
    ...clamp,
    easing: Easing.out(Easing.quad),
  });
  const body = head + printed * rowH + (printed > 4.6 ? 14 : 0);
  const paperW = width * 0.9;
  const exit = interpolate(frame, [88, 99], [0, 1], { ...clamp, easing: Easing.in(Easing.cubic) });
  return (
    <div
      style={{
        position: "relative",
        width,
        scale: `${0.6 + 0.4 * pop}`,
        opacity: Math.min(1, pop * 1.5) * (1 - exit),
        rotate: `${tilt * pop}deg`,
        translate: `0 ${exit * -30}px`,
        filter: "drop-shadow(0 26px 40px rgba(0,0,0,0.5))",
      }}
    >
      <div style={{ position: "absolute", left: (width - paperW) / 2, top: (width * RULER_H) / RULER_W - 12 }}>
        <Slip width={paperW} body={(body * 304 * 1.55) / paperW} stretch={1.55}>
          <div style={{ padding: `${head}px 30px 0`, fontFamily: SANS }}>
            {rows.map(([label, value], i) => {
              const shown = interpolate(printed, [i + 0.35, i + 0.9], [0, 1], clamp);
              const net = i === rows.length - 1;
              const stamp = net ? spring({ frame: frame - 60, fps, config: { damping: 10, stiffness: 220 } }) : 1;
              return (
                <div
                  key={label}
                  style={{
                    height: rowH,
                    display: "flex",
                    alignItems: "center",
                    justifyContent: "space-between",
                    borderTop: i === 2 || net ? `2px ${net ? "solid" : "dashed"} #C9D2E0` : undefined,
                    opacity: shown,
                    translate: `0 ${(1 - shown) * -10}px`,
                  }}
                >
                  <span style={{ fontSize: net ? 31 : 26, fontWeight: net ? 700 : 500, color: net ? C.paperInk : C.paperMuted }}>
                    {label}
                  </span>
                  <span
                    style={{
                      fontFamily: MONO,
                      fontSize: net ? 34 : 26,
                      fontWeight: 700,
                      color: value.startsWith("−") ? C.paperRed : net ? C.blue : C.paperInk,
                      scale: `${net ? 0.6 + 0.4 * stamp : 1}`,
                      display: "inline-block",
                    }}
                  >
                    {value}
                  </span>
                </div>
              );
            })}
          </div>
        </Slip>
      </div>
      <Ruler width={width} style={{ position: "absolute", left: 0, top: 0 }} />
    </div>
  );
};

// Four-point sparkles like the Wagey tab icon.
export const Sparkles: React.FC<{ points: [number, number, number, number][] }> = ({ points }) => {
  const frame = useCurrentFrame();
  return (
    <>
      {points.map(([x, y, size, at], i) => {
        const t = interpolate(frame, [at, at + 10, at + 26, at + 40], [0, 1, 1, 0], clamp);
        return (
          <svg
            key={i}
            width={size}
            height={size}
            viewBox="-10 -10 20 20"
            style={{
              position: "absolute",
              left: x - size / 2,
              top: y - size / 2,
              scale: `${t}`,
              rotate: `${(frame - at) * 3}deg`,
              filter: `drop-shadow(0 0 ${size / 5}px rgba(120, 170, 255, 0.9))`,
              zIndex: 6,
            }}
          >
            <path d="M0 -10 Q1.2 -1.2 10 0 Q1.2 1.2 0 10 Q-1.2 1.2 -10 0 Q-1.2 -1.2 0 -10 Z" fill={i % 2 ? C.blueBright : "#FFFFFF"} />
          </svg>
        );
      })}
    </>
  );
};
