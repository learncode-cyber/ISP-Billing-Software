<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use App\Services\Ai\NlAnalyticsService;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;

/**
 * AI Layer endpoints (Blueprint Section 22). Entitlement (ai.*) and
 * permission checks run in the route middleware chain BEFORE this
 * controller; every call is tenant-scoped and logged to ai.request_logs.
 */
class AiController extends Controller
{
    public function ask(Request $request, NlAnalyticsService $nl)
    {
        $validated = $request->validate(['question' => 'required|string|max:500']);

        $result = $nl->answer(
            $request->user()->tenant_id,
            $request->user()->id,
            $validated['question']
        );

        return response()->json($result);
    }

    public function churnRisk(Request $request)
    {
        $predictions = DB::table('ai.churn_predictions')
            ->where('tenant_id', $request->user()->tenant_id)
            ->when($request->filled('risk_band'), fn ($q) => $q->where('risk_band', $request->risk_band))
            ->orderByDesc('churn_risk_score')
            ->paginate(50);

        return response()->json($predictions);
    }
}
