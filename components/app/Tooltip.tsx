// components/app/Tooltip.tsx
"use client";

import * as React from "react";
import {
  createContext,
  useContext,
  useState,
  useCallback,
  type ReactNode,
  type ComponentPropsWithoutRef,
} from "react";
import * as TooltipPrimitive from "@radix-ui/react-tooltip";
import {
  Tooltip as UITooltip,
  TooltipContent as UITooltipContent,
  TooltipProvider as UITooltipProvider,
  TooltipTrigger as UITooltipTrigger,
} from "../ui/tooltip";
import { cn } from "@/lib/utils";

// Context to share open state between Tooltip components
type TooltipContextValue = {
  open: boolean;
  setOpen: (open: boolean) => void;
  toggle: () => void;
};

const TooltipContext = createContext<TooltipContextValue | null>(null);

function useTooltipContext() {
  const context = useContext(TooltipContext);
  if (!context) {
    throw new Error("Tooltip components must be used within a TooltipProvider");
  }
  return context;
}

// Re-export TooltipProvider as-is but with delayDuration=0
export function TooltipProvider({
  children,
  delayDuration = 0,
  ...props
}: ComponentPropsWithoutRef<typeof UITooltipProvider>) {
  return (
    <UITooltipProvider delayDuration={delayDuration} {...props}>
      {children}
    </UITooltipProvider>
  );
}

// Wrapped Tooltip that manages click-to-toggle state
export function Tooltip({
  children,
  open: controlledOpen,
  onOpenChange,
  ...props
}: ComponentPropsWithoutRef<typeof UITooltip>) {
  const [internalOpen, setInternalOpen] = useState(false);

  // Use controlled state if provided, otherwise use internal state
  const isControlled = controlledOpen !== undefined;
  const open = isControlled ? controlledOpen : internalOpen;

  const setOpen = useCallback((newOpen: boolean) => {
    if (!isControlled) {
      setInternalOpen(newOpen);
    }
    onOpenChange?.(newOpen);
  }, [isControlled, onOpenChange]);

  const toggle = useCallback(() => {
    setOpen(!open);
  }, [open, setOpen]);

  return (
    <TooltipContext.Provider value={{ open, setOpen, toggle }}>
      <UITooltip open={open} {...props}>
        {children}
      </UITooltip>
    </TooltipContext.Provider>
  );
}

// Wrapped TooltipTrigger that handles click-to-toggle
export const TooltipTrigger = React.forwardRef<
  React.ElementRef<typeof UITooltipTrigger>,
  ComponentPropsWithoutRef<typeof UITooltipTrigger>
>(({ onClick, onPointerDown, ...props }, ref) => {
  const { toggle } = useTooltipContext();

  const handleClick = useCallback(
    (e: React.MouseEvent<HTMLButtonElement>) => {
      toggle();
      onClick?.(e);
    },
    [toggle, onClick]
  );

  // Prevent default pointer down to avoid Radix's hover behavior interfering
  const handlePointerDown = useCallback(
    (e: React.PointerEvent<HTMLButtonElement>) => {
      e.preventDefault();
      onPointerDown?.(e);
    },
    [onPointerDown]
  );

  return (
    <UITooltipTrigger
      ref={ref}
      onClick={handleClick}
      onPointerDown={handlePointerDown}
      {...props}
    />
  );
});
TooltipTrigger.displayName = "TooltipTrigger";

// Wrapped TooltipContent with dark mode fix and click-outside handling
export const TooltipContent = React.forwardRef<
  React.ElementRef<typeof TooltipPrimitive.Content>,
  ComponentPropsWithoutRef<typeof UITooltipContent>
>(({ className, onPointerDownOutside, onEscapeKeyDown, ...props }, ref) => {
  const { setOpen } = useTooltipContext();

  const handlePointerDownOutside = useCallback(
    (e: Parameters<NonNullable<typeof onPointerDownOutside>>[0]) => {
      // Don't close if clicking the trigger button
      const target = e.target as HTMLElement | null;
      if (target?.closest?.("button")) return;
      setOpen(false);
      onPointerDownOutside?.(e);
    },
    [setOpen, onPointerDownOutside]
  );

  const handleEscapeKeyDown = useCallback(
    (e: KeyboardEvent) => {
      setOpen(false);
      onEscapeKeyDown?.(e);
    },
    [setOpen, onEscapeKeyDown]
  );

  return (
    <UITooltipContent
      ref={ref}
      className={cn("bg-popover text-popover-foreground", className)}
      onPointerDownOutside={handlePointerDownOutside}
      onEscapeKeyDown={handleEscapeKeyDown}
      {...props}
    />
  );
});
TooltipContent.displayName = "TooltipContent";

// Convenience component for simple use cases
type ClickTooltipProps = {
  trigger: ReactNode;
  children: ReactNode;
  side?: ComponentPropsWithoutRef<typeof TooltipContent>["side"];
  className?: string;
  triggerClassName?: string;
  ariaLabel?: string;
};

/**
 * A convenience wrapper for click-to-toggle tooltips.
 * For more control, use Tooltip, TooltipTrigger, TooltipContent directly.
 */
export function ClickTooltip({
  trigger,
  children,
  side = "left",
  className,
  triggerClassName,
  ariaLabel,
}: ClickTooltipProps) {
  return (
    <TooltipProvider>
      <Tooltip>
        <TooltipTrigger asChild>
          <button
            type="button"
            className={triggerClassName}
            aria-label={ariaLabel}
          >
            {trigger}
          </button>
        </TooltipTrigger>
        <TooltipContent side={side} className={className}>
          {children}
        </TooltipContent>
      </Tooltip>
    </TooltipProvider>
  );
}
