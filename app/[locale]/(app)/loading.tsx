import { HomeSkeleton } from "@/components/app/skeletons/HomeSkeleton";

export default function HomeLoading() {
  return (
    <div className="flex items-center justify-center h-full">
      <div className="w-full max-w-md">
        <HomeSkeleton />
      </div>
    </div>
  );
}
