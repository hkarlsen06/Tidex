"use client";

import {
  InputOTP as BaseInputOTP,
  InputOTPGroup as BaseInputOTPGroup,
  InputOTPSlot as BaseInputOTPSlot,
  InputOTPSeparator as BaseInputOTPSeparator,
} from "@/components/ui/input-otp";
import { cn } from "@/lib/utils";
import { ComponentPropsWithoutRef, ElementRef, forwardRef } from "react";

// Wrapped InputOTP with app-specific styling
const InputOTP = forwardRef<
  ElementRef<typeof BaseInputOTP>,
  ComponentPropsWithoutRef<typeof BaseInputOTP>
>((props, ref) => <BaseInputOTP ref={ref} {...props} />);
InputOTP.displayName = "InputOTP";

const InputOTPGroup = forwardRef<
  ElementRef<typeof BaseInputOTPGroup>,
  ComponentPropsWithoutRef<typeof BaseInputOTPGroup>
>((props, ref) => <BaseInputOTPGroup ref={ref} {...props} />);
InputOTPGroup.displayName = "InputOTPGroup";

// Styled slot matching the app design system
const InputOTPSlot = forwardRef<
  ElementRef<typeof BaseInputOTPSlot>,
  ComponentPropsWithoutRef<typeof BaseInputOTPSlot>
>(({ className, ...props }, ref) => (
  <BaseInputOTPSlot
    ref={ref}
    className={cn(
      // Size and shape
      "h-14 w-14 rounded-lg",
      // Colors matching design system
      "border-2 border-border-subtle bg-background-primary",
      "text-text-primary text-lg font-semibold",
      // Focus state with brand colors
      "focus-within:border-brand-highlight focus-within:ring-2 focus-within:ring-brand-highlight/60",
      // Hover state
      "hover:border-border",
      // Transitions
      "transition-all duration-200",
      className
    )}
    {...props}
  />
));
InputOTPSlot.displayName = "InputOTPSlot";

const InputOTPSeparator = forwardRef<
  ElementRef<typeof BaseInputOTPSeparator>,
  ComponentPropsWithoutRef<typeof BaseInputOTPSeparator>
>(({ className, ...props }, ref) => (
  <BaseInputOTPSeparator
    ref={ref}
    className={cn("text-text-muted", className)}
    {...props}
  />
));
InputOTPSeparator.displayName = "InputOTPSeparator";

export { InputOTP, InputOTPGroup, InputOTPSlot, InputOTPSeparator };
