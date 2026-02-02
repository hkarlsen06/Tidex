import { getSharerShiftPreviews } from "@/data-access/sharing";
import { SharersList } from "./SharersList";
import type { SharedUser } from "@/data-access/sharing";

type SharersListWithPreviewsProps = {
  sharers: SharedUser[];
  locale: string;
};

/**
 * Async server component that fetches shift previews and renders SharersList
 * Used with Suspense to stream the previews after initial page load
 */
export async function SharersListWithPreviews({
  sharers,
  locale,
}: SharersListWithPreviewsProps) {
  // Fetch shift previews for all sharers
  const shiftPreviews = sharers.length > 0
    ? await getSharerShiftPreviews(sharers.map(s => s.id))
    : [];

  return (
    <SharersList
      sharers={sharers}
      shiftPreviews={shiftPreviews}
      basePath={`/${locale}/sharing`}
    />
  );
}
