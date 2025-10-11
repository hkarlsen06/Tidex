import Image from "next/image";
import { UserMenu } from "./UserMenu";

export type TopHeaderProps = {
  userName: string;
  avatarUrl?: string | null;
};

export function TopHeader({ userName, avatarUrl }: TopHeaderProps) {
  const cleanedName = userName.trim();
  const [firstWord] = cleanedName.split(/\s+/).filter(Boolean);
  const displayName = (firstWord ?? cleanedName) || "Guest";

  return (
    <header className="sticky top-4 z-50 px-4">
      <div className="flex items-center justify-between rounded-full border border-border-subtle bg-surface-primary/80 px-4 py-2 shadow-app-lg backdrop-blur">
        <div className="flex items-center gap-3">
          <a
            href="https://www.kkarlsen.dev/"
            className="inline-flex h-10 w-10 items-center justify-center rounded-full"
            aria-label="Go to kkarlsen.dev"
          >
            <Image
              src="/icons/icon.png"
              alt="App icon"
              width={32}
              height={32}
              className="h-8 w-8"
              priority
            />
          </a>
        </div>

        <UserMenu displayName={displayName} avatarUrl={avatarUrl ?? null} />
      </div>
    </header>
  );
}
