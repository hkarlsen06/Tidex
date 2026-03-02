"use client";

import { AnimateNumber } from "motion-plus/react";
import { useIsRouteActive } from "@/components/app/RouteVisibilityContext";
import type { ComponentProps, CSSProperties } from "react";

type AnimateNumberProps = ComponentProps<typeof AnimateNumber>;

interface SafeAnimateNumberProps extends Omit<AnimateNumberProps, 'style'> {
  /** Route pattern to check for visibility. When route is inactive, renders static text. */
  routePattern?: string;
  /** Fallback formatter when rendering statically (route inactive) */
  staticFormatter?: (value: number) => string;
  /** Style object - simplified to CSSProperties for static rendering compatibility */
  style?: CSSProperties;
}

/**
 * Wrapper around motion-plus AnimateNumber that handles cacheComponents gracefully.
 *
 * When the route is inactive (cached/hidden by Next.js cacheComponents), this renders
 * static text instead of AnimateNumber to prevent animation state corruption.
 *
 * AnimateNumber uses internal AnimatePresence and layout animations that can get into
 * bad states when components are restored from cache with different values.
 */
export function SafeAnimateNumber({
  children,
  routePattern = "/",
  staticFormatter,
  format,
  locales,
  prefix = "",
  suffix = "",
  className,
  style,
  ...rest
}: SafeAnimateNumberProps) {
  const isRouteActive = useIsRouteActive(routePattern);
  const value = typeof children === "number" ? children : Number(children);

  // When route is inactive, render static formatted text
  if (!isRouteActive) {
    let formattedValue: string;

    if (staticFormatter) {
      formattedValue = staticFormatter(value);
    } else if (format) {
      // Use Intl.NumberFormat with the same options as AnimateNumber
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

  // Route is active - use AnimateNumber with animations
  return (
    <AnimateNumber
      format={format}
      locales={locales}
      prefix={prefix}
      suffix={suffix}
      className={className}
      style={style}
      {...rest}
    >
      {children}
    </AnimateNumber>
  );
}
