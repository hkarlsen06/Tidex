import React from "react";
import { AbsoluteFill, Easing, Img, interpolate, spring, staticFile, useCurrentFrame, useVideoConfig } from "remotion";
import { ICON_MARK, NOTCHES, RULER_W, SLIP, Wordmark } from "../brand";
import { C, COPY, Lang, SANS } from "../config";
import { Caption, Ruler, Sfx, Slip } from "../parts";

const clamp = { extrapolateLeft: "clamp", extrapolateRight: "clamp" } as const;
// 09:00 plus the measured part of the 8-hour shift, in 15-minute steps.
const clock = (fill: number) => {
  const minutes = 9 * 60 + Math.round(fill * 32) * 15;
  return `${String(Math.floor(minutes / 60)).padStart(2, "0")}:${String(minutes % 60).padStart(2, "0")}`;
};

// Social opener: a ruler measures a 09:00-17:00 shift, a payslip prints its pay,
// and the two pieces snap together into the Tidex app icon.
export const Hook: React.FC<{ lang: Lang }> = ({ lang }) => {
  const frame = useCurrentFrame();
  const { fps, width } = useVideoConfig();
  const copy = COPY[lang];

  const rulerW = 800;
  const k0 = rulerW / RULER_W;
  const start = { x: (width - rulerW) / 2, y: 650 };
  const icon = 220;
  const lockupW = icon + 34 + (104 * 345) / 106;
  const iconPos = { x: (width - lockupW) / 2, y: 850 };
  const k1 = icon * ICON_MARK.scale;
  const end = { x: iconPos.x + ICON_MARK.x * icon, y: iconPos.y + ICON_MARK.y * icon };

  const slide = spring({ frame: frame - 12, fps, config: { damping: 16, stiffness: 110 } });
  const fill = interpolate(frame, [30, 60], [0, 1], { ...clamp, easing: Easing.inOut(Easing.quad) });
  const body = interpolate(frame, [58, 63, 67, 72, 76, 82], [0, 120, 140, 270, 290, SLIP.body], clamp);
  const morph = interpolate(frame, [84, 102], [0, 1], { ...clamp, easing: Easing.inOut(Easing.cubic) });
  const details = interpolate(frame, [78, 88], [1, 0], clamp);
  const k = Math.exp(Math.log(k0) + (Math.log(k1) - Math.log(k0)) * morph);
  const x = start.x + (end.x - start.x) * morph + (1 - slide) * -1200;
  const y = start.y + (end.y - start.y) * morph;
  const squircle = spring({ frame: frame - 90, fps, config: { damping: 13, stiffness: 160 } });
  const photo = interpolate(frame, [100, 106], [0, 1], clamp);
  const printIn = interpolate(frame, [57, 61], [0, 1], clamp);
  const leave = interpolate(frame, [106, 118], [0, 1], { ...clamp, easing: Easing.in(Easing.cubic) });
  const label = (at: number) => spring({ frame: frame - at, fps, config: { damping: 12, stiffness: 200 } });

  return (
    <AbsoluteFill>
      <Caption text={copy.hook} size={104} top={150} bottom={590} delay={4} exitAt={80} weight={700} />
      <AbsoluteFill
        style={{
          opacity: 1 - leave,
          scale: `${1 - 0.15 * leave}`,
          translate: `0 ${-80 * leave}px`,
        }}
      >
        <div
          style={{
            position: "absolute",
            left: iconPos.x,
            top: iconPos.y,
            width: icon,
            height: icon,
            borderRadius: icon * 0.2237,
            background: "linear-gradient(180deg, #4174F2 0%, #2C58E0 100%)",
            boxShadow: "0 30px 60px rgba(8, 20, 60, 0.55)",
            scale: `${0.55 + 0.45 * squircle}`,
            opacity: Math.min(1, squircle * 2),
          }}
        />
        <div
          style={{
            position: "absolute",
            left: x,
            top: y,
            width: RULER_W,
            height: SLIP.y + SLIP.body + SLIP.teeth,
            scale: `${k}`,
            transformOrigin: "0 0",
          }}
        >
          <Ruler width={RULER_W} fill={fill * details} style={{ position: "absolute", left: 0, top: 0 }} />
          <div
            style={{
              position: "absolute",
              left: SLIP.x,
              top: SLIP.y,
              opacity: printIn > 0 ? 1 : 0,
              scale: `1 ${printIn}`,
              transformOrigin: "top",
            }}
          >
            <Slip width={SLIP.w} body={body}>
              <div
                style={{
                  opacity: details,
                  fontFamily: SANS,
                  textAlign: "center",
                  color: C.paperInk,
                  paddingTop: 70,
                }}
              >
                <div style={{ fontSize: 25, fontWeight: 600, color: C.paperMuted }}>{copy.shift}</div>
                <div style={{ fontSize: 54, fontWeight: 700, marginTop: 18, letterSpacing: -1 }}>{copy.shiftPay}</div>
                <div style={{ fontSize: 23, fontWeight: 500, color: C.paperMuted, marginTop: 8 }}>{copy.afterTax}</div>
              </div>
            </Slip>
          </div>
          <div
            style={{
              position: "absolute",
              left: NOTCHES[0] - 80,
              width: 160,
              top: 176,
              textAlign: "center",
              fontFamily: SANS,
              fontWeight: 600,
              fontSize: 30,
              color: C.text,
              opacity: Math.min(1, label(30) * 2) * details,
              scale: `${label(30)}`,
            }}
          >
            09:00
          </div>
          <div
            style={{
              position: "absolute",
              left: NOTCHES[0] + fill * (NOTCHES[8] - NOTCHES[0]) - 80,
              width: 160,
              top: 176,
              textAlign: "center",
              fontFamily: SANS,
              fontWeight: 600,
              fontSize: 30,
              fontVariantNumeric: "tabular-nums",
              color: C.text,
              opacity: interpolate(fill, [0.22, 0.32], [0, 1], clamp) * details,
            }}
          >
            {clock(fill)}
          </div>
        </div>
        <Img
          src={staticFile("brand/tidex-app-icon.png")}
          style={{ position: "absolute", left: iconPos.x, top: iconPos.y, width: icon, height: icon, opacity: photo }}
        />
        <div style={{ position: "absolute", left: iconPos.x + icon + 34, top: iconPos.y + icon / 2 - 54 }}>
          <Wordmark
            height={104}
            progress={(i) => spring({ frame: frame - 98 - i * 3, fps, config: { damping: 12, stiffness: 180 } })}
          />
        </div>
      </AbsoluteFill>
      {NOTCHES.map((_, n) => (
        <Sfx key={n} name="tick" at={30 + (n * 30) / 8} volume={0.14} />
      ))}
      <Sfx name="pop" at={91} volume={0.18} />
      <Sfx name="whoosh" at={110} volume={0.14} />
    </AbsoluteFill>
  );
};
