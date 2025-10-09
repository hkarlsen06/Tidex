// components/app/Dialog.tsx
"use client";

import * as React from "react";
import {
  Dialog as BaseDialog,
  DialogContent as BaseDialogContent,
  DialogHeader as BaseDialogHeader,
  DialogTitle as BaseDialogTitle,
  DialogTrigger as BaseDialogTrigger,
  DialogFooter as BaseDialogFooter,
  DialogDescription as BaseDialogDescription,
  DialogPortal,
  DialogOverlay,
} from "@ui/dialog";

export const Dialog = BaseDialog;
export const DialogHeader = BaseDialogHeader;
export const DialogTitle = BaseDialogTitle;
export const DialogTrigger = BaseDialogTrigger;
export const DialogFooter = BaseDialogFooter;
export const DialogDescription = BaseDialogDescription;

// Custom DialogContent with hideCloseButton prop
interface DialogContentProps extends React.ComponentPropsWithoutRef<typeof BaseDialogContent> {
  hideCloseButton?: boolean;
}

export const DialogContent = React.forwardRef<
  React.ElementRef<typeof BaseDialogContent>,
  DialogContentProps
>(({ children, hideCloseButton = false, className, ...props }, ref) => {
  if (hideCloseButton) {
    // Render custom content without close button
    return (
      <DialogPortal>
        <DialogOverlay />
        <BaseDialogContent ref={ref} className={className} {...props}>
          {children}
        </BaseDialogContent>
      </DialogPortal>
    );
  }

  // Default behavior - use base component which includes close button
  return (
    <BaseDialogContent ref={ref} className={className} {...props}>
      {children}
    </BaseDialogContent>
  );
});
