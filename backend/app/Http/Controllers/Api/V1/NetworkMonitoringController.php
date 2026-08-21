<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;

/**
 * Network Monitoring (Blueprint Section 13, closes Gap 0.2). Alerts and
 * incidents list for the NOC Operator role. Actual poll execution lives
 * in the `network` queue (Blueprint Section 29) — this controller is
 * read + acknowledge/resolve only.
 */
class NetworkMonitoringController extends Controller
{
    public function alerts(Request $request)
    {
        $query = DB::table('network.network_alerts')
            ->when($request->filled('status'), fn ($q) => $q->where('status', $request->status))
            ->when($request->filled('severity'), fn ($q) => $q->where('severity', $request->severity))
            ->orderByDesc('created_at');

        return response()->json($query->paginate(min((int) $request->get('per_page', 25), 200)));
    }

    public function acknowledge(Request $request, string $alertId)
    {
        DB::table('network.network_alerts')->where('id', $alertId)->update([
            'status' => 'acknowledged',
            'acknowledged_by' => $request->user()->id,
            'acknowledged_at' => now(),
        ]);

        return response()->json(['status' => 'acknowledged']);
    }

    public function resolve(string $alertId)
    {
        DB::table('network.network_alerts')->where('id', $alertId)->update([
            'status' => 'resolved',
            'resolved_at' => now(),
        ]);

        return response()->json(['status' => 'resolved']);
    }
}
