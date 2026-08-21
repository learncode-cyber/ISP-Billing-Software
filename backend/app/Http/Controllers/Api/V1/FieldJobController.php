<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use App\Models\Support\FieldJob;
use Illuminate\Http\Request;

/**
 * Field Service / Technician workflow (Blueprint Section 19 second half,
 * consumed by the Technician mobile app in Phase 6). GPS check-in/out,
 * photos, signature, spare parts consumption — parts recorded here draw
 * down inventory.stock_items/stock_levels via a queued job so a flaky
 * mobile connection never leaves inventory in an inconsistent state
 * (the job retries; the field job record itself is the source of truth).
 */
class FieldJobController extends Controller
{
    public function myJobs(Request $request)
    {
        $employeeId = \Illuminate\Support\Facades\DB::table('hr.employees')
            ->where('user_id', $request->user()->id)->value('id');

        return response()->json(
            FieldJob::where('assigned_technician_id', $employeeId)
                ->whereIn('status', ['assigned', 'en_route', 'in_progress'])
                ->orderBy('scheduled_at')
                ->get()
        );
    }

    public function checkIn(Request $request, FieldJob $fieldJob)
    {
        $validated = $request->validate(['lat' => 'required|numeric', 'lng' => 'required|numeric']);

        $fieldJob->update([
            'status' => 'in_progress',
            'check_in_at' => now(),
            'check_in_lat' => $validated['lat'],
            'check_in_lng' => $validated['lng'],
        ]);

        return response()->json($fieldJob->fresh());
    }

    public function checkOut(Request $request, FieldJob $fieldJob)
    {
        $validated = $request->validate([
            'lat' => 'required|numeric',
            'lng' => 'required|numeric',
            'signature_path' => 'nullable|string',
            'parts_used' => 'nullable|array',
            'parts_used.*.stock_item_id' => 'nullable|uuid',
            'parts_used.*.product_id' => 'nullable|uuid',
            'parts_used.*.quantity' => 'required_with:parts_used|integer|min:1',
        ]);

        \Illuminate\Support\Facades\DB::transaction(function () use ($fieldJob, $validated) {
            $fieldJob->update([
                'status' => 'completed',
                'check_out_at' => now(),
                'check_out_lat' => $validated['lat'],
                'check_out_lng' => $validated['lng'],
                'customer_signature_path' => $validated['signature_path'] ?? null,
            ]);

            foreach ($validated['parts_used'] ?? [] as $part) {
                $fieldJob->partsUsed()->create($part);
            }

            // Async: draws down inventory.stock_levels / marks
            // stock_items as 'assigned' or 'sold' per part type.
            \App\Jobs\Inventory\ConsumeFieldJobParts::dispatch($fieldJob->id)->onQueue('reports');
        });

        return response()->json($fieldJob->fresh('partsUsed'));
    }
}
