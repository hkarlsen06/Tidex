"use client";

import { useEffect, useState } from "react";
import { Analytics } from "@vercel/analytics/react";
import { SpeedInsights } from "@vercel/speed-insights/next";

export default function TelemetryDefer() {
  const [ready, setReady] = useState(false);

  useEffect(() => {
    const id = (window as any).requestIdleCallback
      ? (window as any).requestIdleCallback(() => setReady(true), { timeout: 100 })
      : setTimeout(() => setReady(true), 50);
    return () => {
      if (typeof id === "number") clearTimeout(id);
      else if ((window as any).cancelIdleCallback) (window as any).cancelIdleCallback(id);
    };
  }, []);

  if (!ready) return null;
  return (
    <>
      <Analytics />
      <SpeedInsights />
    </>
  );
}

