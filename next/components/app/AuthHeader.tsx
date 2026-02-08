import Image from "next/image";
import type { ReactNode } from "react";

interface WordmarkHeaderProps {
  variant: "wordmark";
  subtitle?: string;
}

interface IconHeaderProps {
  variant: "icon";
  icon: ReactNode;
  title?: string;
  subtitle?: string;
}

type AuthHeaderProps = WordmarkHeaderProps | IconHeaderProps;

export function AuthHeader(props: AuthHeaderProps) {
  if (props.variant === "wordmark") {
    return (
      <div className="flex flex-col items-center mb-10">
        <Image
          src="/icons/wordmark-transparent.webp"
          alt="Tidex"
          width={160}
          height={48}
          priority
          className="h-12 w-auto"
        />
        {props.subtitle && (
          <p className="mt-4 text-sm text-text-secondary text-center">
            {props.subtitle}
          </p>
        )}
      </div>
    );
  }

  return (
    <div className="flex flex-col items-center gap-4 mb-10">
      <div className="flex h-20 w-20 items-center justify-center rounded-full bg-brand-gradient-start/10">
        {props.icon}
      </div>
      {props.title && (
        <h1 className="text-2xl font-bold text-foreground">{props.title}</h1>
      )}
      {props.subtitle && (
        <p className="text-sm text-text-secondary text-center">
          {props.subtitle}
        </p>
      )}
    </div>
  );
}
