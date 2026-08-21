<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;

/**
 * GET /api/v1/dashboard
 *
 * Preserves every verified Dashboard card (Total/Active/Inactive/
 * Discontinue/Free Customers, monthly new/inactive counts, Total
 * Collected Bill) by reading analytics.mv_dashboard_summary /
 * mv_collection_summary — materialized, refreshed on a schedule
 * (Blueprint Section 29 `reports` queue), never computed live, so the
 * dashboard stays fast regardless of tenant customer-count scale.
 *
 * tenant_id filter applied explicitly here because materialized views
 * cannot carry RLS policies in PostgreSQL (see 012_analytics.sql note) —
 * this is the one query pattern in the codebase where tenant isolation
 * relies on application code alone, so it is called out deliberately
 * and covered by its own dedicated test in the tenant-isolation suite.
 */
class DashboardController extends Controller
{
    public function __invoke(Request $request)
    {
        $tenantId = $request->user()->tenant_id;

        $summary = DB::table('analytics.mv_dashboard_summary')
            ->where('tenant_id', $tenantId)
            ->first();

        $collection = DB::table('analytics.mv_collection_summary')
            ->where('tenant_id', $tenantId)
            ->orderByDesc('period_month')
            ->first();

        return response()->json([
            'total_customers' => $summary->total_customers ?? 0,
            'active_customers' => $summary->active_customers ?? 0,
            'inactive_customers' => $summary->inactive_customers ?? 0,
            'discontinue_customers' => $summary->discontinue_customers ?? 0,
            'free_customers' => $summary->free_customers ?? 0,
            'monthly_new_customers' => $summary->monthly_new_customers ?? 0,
            'monthly_inactive_customers' => $summary->monthly_inactive_customers ?? 0,
            'total_collected_this_month' => $collection->total_collected ?? 0,
        ]);
    }
}
