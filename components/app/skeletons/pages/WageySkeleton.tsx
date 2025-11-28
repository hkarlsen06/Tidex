/**
 * WageySkeleton - Loading skeleton for the /wagey chat page
 * Matches the WageyInterface layout
 */
export function WageySkeleton() {
  return (
    <div className="fixed inset-0 top-(--header-height,4rem) bottom-0 md:static md:inset-auto">
      <div className="flex flex-col h-full md:relative md:top-0 md:inset-auto md:max-w-3xl md:mx-auto md:mt-6 md:h-[calc(100vh-6rem)] md:min-h-[calc(100vh-6rem)] md:max-h-[calc(100vh-6rem)] md:rounded-card md:border md:border-border/60 md:shadow-app-lg overflow-hidden bg-background">
        {/* Background gradient */}
        <div className="absolute inset-0 bg-[radial-gradient(circle_at_20%_20%,hsla(var(--brand-gradientStart)/0.08),transparent_45%),radial-gradient(circle_at_80%_10%,hsla(var(--brand-gradientEnd)/0.06),transparent_35%)] pointer-events-none" />

        {/* Fixed Header */}
        <header className="relative z-10 shrink-0 px-4 py-4 md:py-5 border-b border-border/60 bg-surface-primary/95 backdrop-blur-lg flex items-center justify-between shadow-app-sm">
          <div className="flex-1 min-w-0 mr-3">
            <div className="h-7 w-32 bg-surface-secondary rounded animate-pulse md:w-36" />
            <div className="h-4 w-56 bg-surface-secondary rounded animate-pulse mt-2" />
          </div>
        </header>

        {/* Scrollable Messages Area - empty state */}
        <div className="relative z-10 flex-1 min-h-0 overflow-y-auto overscroll-contain px-3 pb-2 pt-8 md:px-5 md:pb-6 md:pt-10">
          <div className="flex flex-col gap-3 md:gap-4 py-2 max-w-3xl mx-auto">
            {/* Empty message area - no skeleton needed as it starts empty */}
          </div>
        </div>

        {/* Fixed Input */}
        <div className="relative z-20 shrink-0 px-4 pt-3 pb-[calc(5rem+env(safe-area-inset-bottom))] md:pb-4 md:pt-4 bg-linear-to-t from-background via-background/95 to-transparent md:bg-none">
          <div className="max-w-3xl mx-auto">
            <div className="flex items-end gap-2">
              <div className="flex-1 h-12 bg-surface-secondary rounded-2xl border border-border animate-pulse" />
              <div className="h-12 w-12 bg-surface-secondary rounded-2xl animate-pulse shrink-0" />
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}
