"use client";

import type { CSSProperties } from "react";

interface SafeAnimateNumberProps {
  children: number;
  routePattern?: string;
  staticFormatter?: (value: number) => string;
  format?: Intl.NumberFormatOptions;
  locales?: string | string[];
  prefix?: string;
  suffix?: string;
  className?: string;
  style?: CSSProperties;
  layout?: boolean;
  transition?: object;
}

/**
 * Wrapper that was previously backed by motion-plus AnimateNumber.
 * Now renders static formatted text with the same formatting logic.
 */
export function SafeAnimateNumber({
  children,
  staticFormatter,
  format,
  locales,
  prefix = "",
  suffix = "",
  className,
  style,
}: SafeAnimateNumberProps) {
  const value = typeof children === "number" ? children : Number(children);

  let formattedValue: string;

  if (staticFormatter) {
    formattedValue = staticFormatter(value);
  } else if (format) {
    const formatter = new Intl.NumberFormat(locales, format);
    formattedValue = formatter.format(value);
  } else {
    formattedValue = String(value);
  }

  return (
    <span className={className} style={style}>
      {prefix}{formattedValue}{suffix}
    </span>
  );
}
