import { NextRequest, NextResponse } from "next/server";
import { randomUUID } from "crypto";
import sharp from "sharp";

import { createSupabaseRouteHandlerClient } from "@/lib/supabase/server";

const MAX_FILE_SIZE = 5 * 1024 * 1024; // 5MB
const BUCKET = "profile-pictures";
const HEIC_EXTENSIONS = new Set(["heic", "heif", "heics", "heifs"]);

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

function isHeicLike(ext: string | null, mime: string | undefined | null) {
  if (ext && HEIC_EXTENSIONS.has(ext)) {
    return true;
  }

  if (!mime) return false;
  const normalized = mime.toLowerCase();
  return (
    normalized === "image/heic" ||
    normalized === "image/heif" ||
    normalized === "image/heic-sequence" ||
    normalized === "image/heif-sequence"
  );
}

async function convertHeicToJpeg(file: File) {
  const arrayBuffer = await file.arrayBuffer();
  const buffer = Buffer.from(arrayBuffer);
  const converted = await sharp(buffer).rotate().jpeg({ quality: 90 }).toBuffer();
  return converted;
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

    const mimeType = file.type || undefined;
    const filenameExt = extFromFilename(file.name);
    const mimeExt = extFromMime(file.type);
    let fileExt = filenameExt ?? mimeExt ?? "bin";
    let uploadData: File | Buffer = file;
    let contentType = mimeType;

    if (isHeicLike(filenameExt, mimeType)) {
      try {
        const converted = await convertHeicToJpeg(file);

        if (converted.byteLength > MAX_FILE_SIZE) {
          const errorResponse = NextResponse.json(
            { error: "Konvertert bilde er for stort. Velg et mindre bilde." },
            { status: 413, headers: { "cache-control": "no-store" } }
          );
          propagateCookies(baseResponse, errorResponse);
          return errorResponse;
        }

        uploadData = converted;
        contentType = "image/jpeg";
        fileExt = "jpg";
      } catch (conversionError) {
        console.error("[PROFILE PICTURE] Failed to convert HEIC image:", conversionError);
        const errorResponse = NextResponse.json(
          { error: "Kunne ikke konvertere HEIC-bildet. Prøv et annet bilde." },
          { status: 415, headers: { "cache-control": "no-store" } }
        );
        propagateCookies(baseResponse, errorResponse);
        return errorResponse;
      }
    }

    const storagePath = `${user.id}/${randomUUID()}.${fileExt}`;

    const { error: uploadError } = await supabase.storage
      .from(BUCKET)
      .upload(storagePath, uploadData, {
        cacheControl: "3600",
        upsert: true,
        contentType,
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
        // Verify the path belongs to this user (security check)
        if (!previousPath.startsWith(`${user.id}/`)) {
          console.error("[PROFILE PICTURE] Security: User attempted to delete file not owned by them");
          // Don't fail the upload, but log the security issue
        } else {
          const { error: removeError } = await supabase.storage
            .from(BUCKET)
            .remove([previousPath]);

          if (removeError) {
            console.error("[PROFILE PICTURE] Failed to remove previous image:", removeError);
            // Note: We don't fail the upload if old image deletion fails
            // The new image was uploaded successfully, which is the primary operation
          }
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

    // Security check: Verify the path belongs to the authenticated user
    if (!path.startsWith(`${user.id}/`)) {
      console.error("[PROFILE PICTURE] Security: User attempted to delete file not owned by them", {
        userId: user.id,
        attemptedPath: path
      });
      const errorResponse = NextResponse.json(
        { error: "Ingen tilgang til å slette dette bildet." },
        { status: 403, headers: { "cache-control": "no-store" } }
      );
      propagateCookies(baseResponse, errorResponse);
      return errorResponse;
    }

    const { error: removeError } = await supabase.storage.from(BUCKET).remove([path]);

    if (removeError) {
      console.error("[PROFILE PICTURE] Failed to delete image:", removeError);
      const errorResponse = NextResponse.json(
        { error: "Kunne ikke fjerne profilbildet fra lagring." },
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
