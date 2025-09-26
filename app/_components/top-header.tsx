import Image from "next/image";

export type TopHeaderProps = {
  userName: string;
  avatarUrl?: string | null;
};

export function TopHeader({ userName, avatarUrl }: TopHeaderProps) {
  const fallbackInitial = userName.trim().charAt(0).toUpperCase() || "?";

  return (
    <header className="sticky top-4 z-50 mx-auto w-full max-w-5xl px-4">
      <div className="flex items-center justify-between rounded-full border border-slate-800 bg-slate-900/80 px-4 py-2 shadow-lg shadow-slate-950/40 backdrop-blur">
        <div className="flex items-center gap-3">
          <span className="inline-flex h-10 w-10 items-center justify-center overflow-hidden rounded-full bg-slate-800">
            <Image
              src="/icons/icon.png"
              alt="App icon"
              width={32}
              height={32}
              className="h-8 w-8"
              priority
            />
          </span>
        </div>
        <div className="flex items-center gap-3 rounded-full bg-slate-800/80 px-3 py-1 shadow-inner">
          <span className="text-sm font-medium text-slate-200">{userName}</span>
          <span className="relative inline-flex h-10 w-10 items-center justify-center overflow-hidden rounded-full bg-slate-700 text-sm font-semibold uppercase text-slate-300">
            {avatarUrl ? (
              <Image
                src={avatarUrl}
                alt={`${userName} avatar`}
                fill
                sizes="40px"
                className="object-cover"
                unoptimized
              />
            ) : (
              fallbackInitial
            )}
          </span>
        </div>
      </div>
    </header>
  );
}
