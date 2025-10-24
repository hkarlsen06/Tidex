import type { ReactNode } from "react";
import type { Metadata } from "next";

export const metadata: Metadata = {
  title: "Innstillinger",
};

export default function SettingsLayout({
  children,
}: {
  children: ReactNode;
}) {
  return <>{children}</>;
}
