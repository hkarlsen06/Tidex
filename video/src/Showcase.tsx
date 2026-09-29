import { Audio, Video } from "@remotion/media";
import React from "react";
import {
  AbsoluteFill,
  Easing,
  Freeze,
  interpolate,
  Sequence,
  spring,
  staticFile,
  useCurrentFrame,
  useVideoConfig,
} from "remotion";
import {
  C,
  COPY,
  FEATURES,
  HOOK,
  Lang,
  layout,
  Piece,
  RECEIPT_AT,
  Scene,
  SCENES,
  SCREEN_RATIO,
  SHEET,
  Variant,
} from "./config";
import { Background, Caption, LiftOut, Receipt, Sfx, SLIDE_EASING, TapRing } from "./parts";
import { Hook } from "./scenes/Hook";
import { Outro } from "./scenes/Outro";

export type ShowcaseProps = { lang: Lang; variant: Variant; music: boolean };

const clamp = { extrapolateLeft: "clamp", extrapolateRight: "clamp" } as const;
const fill: React.CSSProperties = { position: "absolute", inset: 0, width: "100%", height: "100%" };

const span = (piece: Piece) => (Array.isArray(piece) ? piece : piece.slide);
const length = (piece: Piece) => (Array.isArray(piece) ? piece[1] - piece[0] : piece.frames);

// Maps a footage frame to the layer's local frame, given the pieces played back to back.
const localFrame = (pieces: Piece[], src: number) => {
  let at = 0;
  for (const piece of pieces) {
    const [a, b] = span(piece);
    if (src >= a && src < b) return at + ((src - a) * length(piece)) / (b - a);
    at += length(piece);
  }
  throw new Error(`Footage frame ${src} is outside the scene pieces`);
};

const Still: React.FC<{ src: string; frame: number; style?: React.CSSProperties }> = ({ src, frame, style = fill }) => (
  <Freeze frame={0}>
    <Video src={src} trimBefore={frame} muted objectFit="cover" style={style} />
  </Freeze>
);

// Slides the settled sheet up over the medium-detent frame; the recording itself stalls here. Like iOS, the
// floating medium-detent card grows to full width while it rises.
const SheetSlide: React.FC<{ src: string; from: number; to: number; frames: number; cardW: number }> = ({
  src,
  from,
  to,
  frames,
  cardW,
}) => {
  const frame = useCurrentFrame();
  const t = interpolate(frame, [0, frames], [0, 1], { ...clamp, easing: SLIDE_EASING });
  const cardH = cardW * SCREEN_RATIO;
  const scale = SHEET.mediumScale + (1 - SHEET.mediumScale) * t;
  const inset = ((1 - scale) / 2) * cardW;
  const bottomRadius = (SHEET.bottomRadius + (0.115 - SHEET.bottomRadius) * t) * cardW;
  return (
    <AbsoluteFill>
      <Still src={src} frame={from} />
      <div style={{ position: "absolute", inset: 0, top: SHEET.statusBar * cardH, background: "#000", opacity: t }} />
      <div
        style={{
          position: "absolute",
          left: inset,
          right: inset,
          top: 0,
          bottom: SHEET.bottomInset * cardH * (1 - t),
          overflow: "hidden",
          borderBottomLeftRadius: bottomRadius,
          borderBottomRightRadius: bottomRadius,
        }}
      >
        <div
          style={{
            position: "absolute",
            left: -inset,
            width: cardW,
            top: (SHEET.medium + (SHEET.large - SHEET.medium) * t) * cardH,
            height: (1 - SHEET.large) * cardH,
            scale: `${scale}`,
            transformOrigin: "top center",
            overflow: "hidden",
            borderTopLeftRadius: SHEET.radius * cardW,
            borderTopRightRadius: SHEET.radius * cardW,
          }}
        >
          <Still
            src={src}
            frame={to}
            style={{ position: "absolute", left: 0, width: cardW, top: -SHEET.large * cardH, height: cardH }}
          />
        </div>
      </div>
      {/* Dissolve out of the real frame to hide the remaining 1-2 px of resampling offset. */}
      <AbsoluteFill style={{ opacity: interpolate(frame, [0, 3], [1, 0], clamp) }}>
        <Still src={src} frame={from} />
      </AbsoluteFill>
    </AbsoluteFill>
  );
};

const Footage: React.FC<{ src: string; pieces: Piece[]; duration: number; cardW: number }> = ({
  src,
  pieces,
  duration,
  cardW,
}) => {
  let at = 0;
  const layers = pieces.map((piece) => {
    const from = at;
    at += length(piece);
    const [a, b] = span(piece);
    return (
      <Sequence key={a} from={from} durationInFrames={length(piece)} premountFor={20}>
        {Array.isArray(piece) ? (
          <Video src={src} trimBefore={a} muted objectFit="cover" style={fill} />
        ) : (
          <SheetSlide src={src} from={a - 1} to={b + 2} frames={piece.frames} cardW={cardW} />
        )}
      </Sequence>
    );
  });
  const [lastA, lastB] = span(pieces[pieces.length - 1]);
  if (at < duration) {
    layers.push(
      <Sequence key="hold" from={at} premountFor={20}>
        <Freeze frame={lastB - lastA - 1}>
          <Video src={src} trimBefore={lastA} muted objectFit="cover" style={fill} />
        </Freeze>
      </Sequence>,
    );
  }
  return <>{layers}</>;
};

// Dims the screen while a lift-out or the receipt has focus.
const focus = (frame: number, windows: [number, number][]) =>
  Math.max(0, ...windows.map(([a, b]) => interpolate(frame, [a, a + 8, b - 10, b], [0, 1, 1, 0], clamp)));

const SceneScreen: React.FC<{
  scene: Scene;
  lang: Lang;
  length: number;
  cardW: number;
  focusWindows: [number, number][];
}> = ({ scene, lang, length, cardW, focusWindows }) => {
  const frame = useCurrentFrame();
  const opacity = scene.fadeIn ? interpolate(frame, [0, scene.fadeIn], [0, 1], clamp) : 1;
  return (
    <AbsoluteFill style={{ opacity }}>
      <Footage src={staticFile(`footage/${lang}.mp4`)} pieces={scene.pieces[lang]} duration={length} cardW={cardW} />
      <AbsoluteFill style={{ backgroundColor: "#000", opacity: 0.55 * focus(frame - scene.fadeIn, focusWindows) }} />
    </AbsoluteFill>
  );
};

const SceneOverlay: React.FC<{ scene: Scene; lang: Lang; variant: Variant; cardW: number; cardH: number }> = ({
  scene,
  lang,
  variant,
  cardW,
  cardH,
}) => {
  const pieces = scene.pieces[lang];
  const social = variant === "social";
  return (
    <>
      {scene.taps[lang].map((tap) => {
        const at = localFrame(pieces, tap.src);
        return (
          <React.Fragment key={tap.src}>
            <TapRing
              at={at}
              x={tap.x}
              y={tap.y}
              cardW={cardW}
              cardH={cardH}
              drag={
                tap.drag
                  ? {
                      start: localFrame(pieces, tap.drag.srcStart),
                      end: localFrame(pieces, tap.drag.srcEnd),
                      x: tap.drag.x,
                      y: tap.drag.y,
                    }
                  : undefined
              }
            />
            <Sfx name="tap" at={at} volume={0.22} />
          </React.Fragment>
        );
      })}
      {scene.lifts[lang].map((lift) => (
        <React.Fragment key={lift.at}>
          <LiftOut
            still={`${lang}-${scene.id}`}
            box={lift.box}
            at={lift.at + scene.fadeIn}
            until={lift.until + scene.fadeIn}
            scale={social ? lift.scale : 1 + (lift.scale - 1) * 0.75}
            to={lift.to}
            rotate={social ? lift.rotate : 0}
            cardW={cardW}
            cardH={cardH}
          />
          <Sfx name="pop" at={lift.at + scene.fadeIn} volume={0.18} />
        </React.Fragment>
      ))}
    </>
  );
};

export const Showcase: React.FC<ShowcaseProps> = ({ lang, variant, music }) => {
  const frame = useCurrentFrame();
  const { fps, width } = useVideoConfig();
  const L = layout(width);
  const cardH = L.cardW * SCREEN_RATIO;
  const social = variant === "social";
  const offset = social ? HOOK : 0;
  const outroAt = offset + FEATURES;
  const copy = COPY[lang];

  const starts: number[] = [];
  SCENES.reduce((at, scene) => (starts.push(at), at + scene.duration), offset);

  const enter = social ? spring({ frame: frame - offset + 6, fps, config: { damping: 17, stiffness: 110 } }) : 1;
  const leave = interpolate(frame, [outroAt, outroAt + 14], [0, 1], { ...clamp, easing: Easing.in(Easing.cubic) });
  // A small breath on the card when the footage jumps between screens.
  const bump = social
    ? Math.max(0, ...SCENES.map((s, i) => (s.fadeIn ? interpolate(frame, [starts[i] - 9, starts[i] - 2, starts[i] + 10], [0, 1, 0], clamp) : 0)))
    : 0;
  const receiptAt = starts[SCENES.findIndex((s) => s.id === "payroll")] + RECEIPT_AT;
  const receiptW = social ? 560 : 520;

  return (
    <AbsoluteFill style={{ backgroundColor: C.bg }}>
      <Background />
      {music ? (
        <Audio
          src={staticFile("audio/music.wav")}
          trimBefore={social ? 0 : HOOK}
          volume={(f) => 0.5 * interpolate(f, [0, 6], [social ? 1 : 0, 1], clamp)}
        />
      ) : null}

      {social ? (
        <Sequence durationInFrames={HOOK + 12} name="Hook">
          <Hook lang={lang} />
        </Sequence>
      ) : null}

      <div
        style={{
          position: "absolute",
          left: L.cardX,
          top: L.cardY,
          width: L.cardW,
          height: cardH,
          translate: `0 ${(1 - enter) * 1500 + leave * 260}px`,
          scale: `${(1 - 0.08 * leave) * (1 - 0.035 * bump)}`,
          rotate: `${(1 - enter) * 6}deg`,
          opacity: 1 - leave,
        }}
      >
        <div
          style={{
            position: "absolute",
            inset: -11,
            borderRadius: L.cardW * 0.115 + 11,
            background: "#0B111D",
            border: "1.5px solid rgba(255,255,255,0.14)",
            boxShadow: `0 50px 110px rgba(0,0,0,0.6), 0 0 140px ${C.blue}40`,
          }}
        />
        <div style={{ position: "absolute", inset: 0, overflow: "hidden", borderRadius: L.cardW * 0.115, background: "#05070C" }}>
          {SCENES.map((scene, i) => {
            const length = scene.fadeIn + scene.duration + (SCENES[i + 1]?.fadeIn ?? 0);
            return (
              <Sequence key={scene.id} from={starts[i] - scene.fadeIn} durationInFrames={length} name={`${scene.id} footage`}>
                <SceneScreen
                  scene={scene}
                  lang={lang}
                  length={length}
                  cardW={L.cardW}
                  focusWindows={[
                    ...scene.lifts[lang].map((l): [number, number] => [l.at, l.until]),
                    ...(scene.id === "payroll" ? [[RECEIPT_AT, scene.duration] as [number, number]] : []),
                  ]}
                />
              </Sequence>
            );
          })}
        </div>
        {SCENES.map((scene, i) => (
          <Sequence
            key={scene.id}
            from={starts[i] - scene.fadeIn}
            durationInFrames={scene.fadeIn + scene.duration}
            name={`${scene.id} overlays`}
            layout="none"
          >
            <SceneOverlay scene={scene} lang={lang} variant={variant} cardW={L.cardW} cardH={cardH} />
          </Sequence>
        ))}
      </div>

      {SCENES.map((scene, i) => (
        <Sequence key={scene.id} from={starts[i]} durationInFrames={scene.duration} name={`${scene.id} caption`}>
          <Caption
            text={copy.captions[scene.id]}
            size={L.capSize}
            top={L.capTop}
            bottom={L.capBottom}
            exitAt={scene.duration - 8}
          />
          {scene.sfx.map(([name, at]) => (
            <Sfx key={name + at} name={name} at={at} volume={0.16} />
          ))}
        </Sequence>
      ))}

      {social
        ? SCENES.map((scene, i) => (scene.fadeIn ? <Sfx key={scene.id} name="whoosh" at={starts[i] - 8} volume={0.1} /> : null))
        : null}

      <Sequence from={receiptAt} durationInFrames={100} name="Receipt">
        <div
          style={{
            position: "absolute",
            left: (width - receiptW) / 2,
            top: L.cardY + cardH * 0.17,
          }}
        >
          <Receipt rows={copy.receipt} width={receiptW} tilt={social ? -2.5 : 0} />
        </div>
        {/* The printing sound is a hi-hat roll in the music bed that resolves on the net row. */}
      </Sequence>

      <Sequence from={outroAt} name="Outro">
        <Outro lang={lang} variant={variant} />
      </Sequence>
    </AbsoluteFill>
  );
};
