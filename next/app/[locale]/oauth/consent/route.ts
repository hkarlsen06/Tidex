import { NextResponse, type NextRequest } from "next/server";

export async function GET(request: NextRequest) {
  const redirectUrl = new URL("/oauth/consent", request.url);
  redirectUrl.search = request.nextUrl.search;

  return NextResponse.redirect(redirectUrl, 307);
}
