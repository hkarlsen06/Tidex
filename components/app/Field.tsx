"use client";

import * as React from "react";
import {
  Field as UIField,
  FieldContent as UIFieldContent,
  FieldDescription as UIFieldDescription,
  FieldError as UIFieldError,
  FieldGroup as UIFieldGroup,
  FieldLabel as UIFieldLabel,
  FieldLegend as UIFieldLegend,
  FieldSeparator as UIFieldSeparator,
  FieldSet as UIFieldSet,
  FieldTitle as UIFieldTitle,
} from "@ui/field";
import { Separator } from "@/components/ui/separator";
import { cn } from "@/lib/utils";

export const Field = UIField;
export const FieldContent = UIFieldContent;
export const FieldDescription = UIFieldDescription;
export const FieldError = UIFieldError;
export const FieldGroup = UIFieldGroup;
export const FieldLabel = UIFieldLabel;
export const FieldLegend = UIFieldLegend;
export const FieldSet = UIFieldSet;
export const FieldTitle = UIFieldTitle;

// Custom FieldSeparator that uses card background instead of page background
export function FieldSeparator({
  children,
  className,
  ...props
}: React.ComponentProps<"div"> & {
  children?: React.ReactNode
}) {
  return (
    <div
      data-slot="field-separator"
      data-content={!!children}
      className={cn(
        "relative -my-2 h-5 text-sm group-data-[variant=outline]/field-group:-mb-2",
        className
      )}
      {...props}
    >
      <Separator className="absolute inset-0 top-1/2" />
      {children && (
        <span
          className="bg-card text-muted-foreground relative mx-auto block w-fit px-2"
          data-slot="field-separator-content"
        >
          {children}
        </span>
      )}
    </div>
  );
}
