import { clsx } from "clsx";
import { twMerge } from "tailwind-merge";
export const cn = (...a: any[]) => twMerge(clsx(a));
