import { NextRequest, NextResponse } from "next/server";
import { getSession } from "@/data-access/auth";
import { updateShift, type UpdateShiftInput } from "@/app/[locale]/(app)/shifts/_actions/updateShift";
import { deleteShift } from "@/app/[locale]/(app)/shifts/_actions/deleteShift";

/**
 * API route for individual shift operations
 *
 * PATCH: Update a shift
 * DELETE: Delete a shift
 */

/**
 * PATCH /api/shifts/[id]
 * Update an existing shift
 *
 * Body:
 * {
 *   shift_date: string, // ISO date (YYYY-MM-DD)
 *   start: string,      // Start time (HH:mm)
 *   end: string,        // End time (HH:mm)
 *   series_id?: string  // Optional series ID (for ghost shifts)
 * }
 */
export async function PATCH(
  request: NextRequest,
  { params }: { params: Promise<{ id: string }> }
) {
  // Manual auth check for API routes
  const session = await getSession();
  if (!session) {
    return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });
  }

  try {
    const { id } = await params;

    let body;
    try {
      body = await request.json();
    } catch {
      return NextResponse.json(
        { error: 'Invalid JSON in request body' },
        { status: 400 }
      );
    }

    // Validate required fields
    if (!body.shift_date || !body.start || !body.end) {
      return NextResponse.json(
        { error: 'shift_date, start, and end are required' },
        { status: 400 }
      );
    }

    // Build update input
    const input: UpdateShiftInput = {
      id,
      shift_date: body.shift_date,
      start: body.start,
      end: body.end,
      series_id: body.series_id,
    };

    // Call the existing server action
    const result = await updateShift(input);

    return NextResponse.json(result);
  } catch (error) {
    console.error('Failed to update shift:', error);

    const errorMessage = error instanceof Error ? error.message : 'Failed to update shift';

    // Determine appropriate status code based on error message
    let statusCode = 500;
    if (errorMessage.includes('Unauthorized')) {
      statusCode = 401;
    } else if (errorMessage.includes('not found')) {
      statusCode = 404;
    } else if (errorMessage.includes('Invalid')) {
      statusCode = 400;
    }

    return NextResponse.json(
      { error: errorMessage },
      { status: statusCode }
    );
  }
}

/**
 * DELETE /api/shifts/[id]
 * Delete a shift
 *
 * Query params (optional for series ghosts):
 * - seriesId: string   // Series ID if deleting a ghost
 * - shiftDate: string  // ISO date if deleting a ghost
 */
export async function DELETE(
  request: NextRequest,
  { params }: { params: Promise<{ id: string }> }
) {
  // Manual auth check for API routes
  const session = await getSession();
  if (!session) {
    return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });
  }

  try {
    const { id } = await params;
    const { searchParams } = new URL(request.url);
    const seriesId = searchParams.get('seriesId') || undefined;
    const shiftDate = searchParams.get('shiftDate') || undefined;

    // Call the existing server action
    const result = await deleteShift({
      shiftId: id,
      seriesId,
      shiftDate,
    });

    return NextResponse.json(result);
  } catch (error) {
    console.error('Failed to delete shift:', error);

    const errorMessage = error instanceof Error ? error.message : 'Failed to delete shift';

    // Determine appropriate status code based on error message
    let statusCode = 500;
    if (errorMessage.includes('Unauthorized')) {
      statusCode = 401;
    } else if (errorMessage.includes('not found')) {
      statusCode = 404;
    } else if (errorMessage.includes('Invalid')) {
      statusCode = 400;
    }

    return NextResponse.json(
      { error: errorMessage },
      { status: statusCode }
    );
  }
}
