import { NextRequest, NextResponse } from "next/server";
import { randomUUID } from "crypto";

import { createSupabaseRouteHandlerClient } from "@/lib/supabase/server";

const MAX_FILE_SIZE = 5 * 1024 * 1024; // 5MB
const BUCKET = "profile-pictures";

function propagateCookies(from: NextResponse, to: NextResponse) {
  for (const cookie of from.cookies.getAll()) {
    to.cookies.set(cookie);
  }
}

function parseStoragePath(url: string | null | undefined) {
  if (!url) return null;
  const marker = "/storage/v1/object/public/";
  const markerIndex = url.indexOf(marker);
  if (markerIndex === -1) return null;

  const pathWithBucket = url.slice(markerIndex + marker.length);
  const [bucket, ...rest] = pathWithBucket.split("/");
  if (bucket !== BUCKET) return null;

  return rest.join("/");
}

function extFromFilename(name: string | undefined | null) {
  if (!name) return null;
  const lastDot = name.lastIndexOf(".");
  if (lastDot === -1 || lastDot === name.length - 1) return null;
  return name.slice(lastDot + 1).toLowerCase();
}

function extFromMime(type: string | undefined | null) {
  if (!type) return null;
  const parts = type.split("/");
  if (parts.length !== 2) return null;
  return parts[1];
}

export async function POST(request: NextRequest) {
  const baseResponse = new NextResponse(null, {
    headers: { "cache-control": "no-store" },
  });

  try {
    const formData = await request.formData();
    const file = formData.get("file");
    const previousUrl = formData.get("previousUrl");

    if (!(file instanceof File)) {
      const errorResponse = NextResponse.json(
        { error: "Mangler fil i forespørselen." },
        { status: 400, headers: { "cache-control": "no-store" } }
      );
      propagateCookies(baseResponse, errorResponse);
      return errorResponse;
    }

    if (file.size > MAX_FILE_SIZE) {
      const errorResponse = NextResponse.json(
        { error: "Bildet må være mindre enn 5MB." },
        { status: 413, headers: { "cache-control": "no-store" } }
      );
      propagateCookies(baseResponse, errorResponse);
      return errorResponse;
    }

    const supabase = createSupabaseRouteHandlerClient(request, baseResponse);
    const {
      data: { user },
      error: userError,
    } = await supabase.auth.getUser();

    if (userError) {
      console.error("[PROFILE PICTURE] Failed to fetch user:", userError);
      const errorResponse = NextResponse.json(
        { error: "Kunne ikke bekrefte innlogging." },
        { status: 401, headers: { "cache-control": "no-store" } }
      );
      propagateCookies(baseResponse, errorResponse);
      return errorResponse;
    }

    if (!user) {
      const errorResponse = NextResponse.json(
        { error: "Ikke autentisert." },
        { status: 401, headers: { "cache-control": "no-store" } }
      );
      propagateCookies(baseResponse, errorResponse);
      return errorResponse;
    }

    const fileExt = extFromFilename(file.name) ?? extFromMime(file.type) ?? "bin";
    const storagePath = `${user.id}/${randomUUID()}.${fileExt}`;

    const { error: uploadError } = await supabase.storage
      .from(BUCKET)
      .upload(storagePath, file, {
        cacheControl: "3600",
        upsert: true,
        contentType: file.type || undefined,
      });

    if (uploadError) {
      console.error("[PROFILE PICTURE] Upload failed:", uploadError);
      const errorResponse = NextResponse.json(
        { error: "Kunne ikke laste opp bildet." },
        { status: 500, headers: { "cache-control": "no-store" } }
      );
      propagateCookies(baseResponse, errorResponse);
      return errorResponse;
    }

    if (typeof previousUrl === "string" && previousUrl) {
      const previousPath = parseStoragePath(previousUrl);
      if (previousPath) {
        const { error: removeError } = await supabase.storage
          .from(BUCKET)
          .remove([previousPath]);

        if (removeError) {
          console.error("[PROFILE PICTURE] Failed to remove previous image:", removeError);
        }
      }
    }

    const {
      data: { publicUrl },
    } = supabase.storage.from(BUCKET).getPublicUrl(storagePath);

    const successResponse = NextResponse.json(
      { publicUrl, path: storagePath },
      { status: 200, headers: { "cache-control": "no-store" } }
    );
    propagateCookies(baseResponse, successResponse);
    return successResponse;
  } catch (error) {
    console.error("[PROFILE PICTURE] Unexpected error during upload:", error);
    const errorResponse = NextResponse.json(
      { error: "Uventet feil ved opplasting." },
      { status: 500, headers: { "cache-control": "no-store" } }
    );
    propagateCookies(baseResponse, errorResponse);
    return errorResponse;
  }
}

export async function DELETE(request: NextRequest) {
  const baseResponse = new NextResponse(null, {
    headers: { "cache-control": "no-store" },
  });

  try {
    const supabase = createSupabaseRouteHandlerClient(request, baseResponse);
    const {
      data: { user },
      error: userError,
    } = await supabase.auth.getUser();

    if (userError) {
      console.error("[PROFILE PICTURE] Failed to fetch user:", userError);
      const errorResponse = NextResponse.json(
        { error: "Kunne ikke bekrefte innlogging." },
        { status: 401, headers: { "cache-control": "no-store" } }
      );
      propagateCookies(baseResponse, errorResponse);
      return errorResponse;
    }

    if (!user) {
      const errorResponse = NextResponse.json(
        { error: "Ikke autentisert." },
        { status: 401, headers: { "cache-control": "no-store" } }
      );
      propagateCookies(baseResponse, errorResponse);
      return errorResponse;
    }

    const { searchParams } = new URL(request.url);
    const url = searchParams.get("url");

    if (!url) {
      const errorResponse = NextResponse.json(
        { error: "Ingen URL angitt for sletting." },
        { status: 400, headers: { "cache-control": "no-store" } }
      );
      propagateCookies(baseResponse, errorResponse);
      return errorResponse;
    }

    const path = parseStoragePath(url);

    if (!path) {
      const errorResponse = NextResponse.json(
        { error: "Ugyldig bilde-URL." },
        { status: 400, headers: { "cache-control": "no-store" } }
      );
      propagateCookies(baseResponse, errorResponse);
      return errorResponse;
    }

    const { error: removeError } = await supabase.storage.from(BUCKET).remove([path]);

    if (removeError) {
      console.error("[PROFILE PICTURE] Failed to delete image:", removeError);
      const errorResponse = NextResponse.json(
        { error: "Kunne ikke fjerne profilbildet." },
        { status: 500, headers: { "cache-control": "no-store" } }
      );
      propagateCookies(baseResponse, errorResponse);
      return errorResponse;
    }

    const successResponse = NextResponse.json(
      { success: true },
      { status: 200, headers: { "cache-control": "no-store" } }
    );
    propagateCookies(baseResponse, successResponse);
    return successResponse;
  } catch (error) {
    console.error("[PROFILE PICTURE] Unexpected error during deletion:", error);
    const errorResponse = NextResponse.json(
      { error: "Uventet feil ved sletting." },
      { status: 500, headers: { "cache-control": "no-store" } }
    );
    propagateCookies(baseResponse, errorResponse);
    return errorResponse;
  }
}

export const dynamic = "force-dynamic";
