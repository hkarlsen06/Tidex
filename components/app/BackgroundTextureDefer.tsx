"use client";

import { useEffect, useState } from "react";
import dynamic from "next/dynamic";

// Load the heavy decorative background on the client only
const BackgroundTexture = dynamic(
  () => import("@/components/app/BackgroundTexture").then((m) => m.BackgroundTexture),
  { ssr: false }
);

export default function BackgroundTextureDefer() {
  const [ready, setReady] = useState(false);

  useEffect(() => {
    // Defer until the browser is idle or after a small delay
    const id = (window as any).requestIdleCallback
      ? (window as any).requestIdleCallback(() => setReady(true), { timeout: 1200 })
      : setTimeout(() => setReady(true), 600);

    return () => {
      if (typeof id === "number") clearTimeout(id);
      else if ((window as any).cancelIdleCallback) (window as any).cancelIdleCallback(id);
    };
  }, []);

  if (!ready) return null;
  return <BackgroundTexture intensity="subtle" />;
}

