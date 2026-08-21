<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;

/** Reports: Monthly/Yearly balance (verified), from accounting views. */
class ReportController extends Controller
{
    public function monthlyBalance(Request $request)
    {
        return response()->json(DB::table('accounting.v_monthly_balance')
            ->where('tenant_id',$request->user()->tenant_id)->orderByDesc('period_month')->limit(24)->get());
    }

    public function yearlyBalance(Request $request)
    {
        return response()->json(DB::table('accounting.v_yearly_balance')
            ->where('tenant_id',$request->user()->tenant_id)->orderByDesc('period_year')->get());
    }

    public function statement(Request $request)
    {
        return response()->json(DB::table('accounting.ledger_entries')
            ->where('tenant_id',$request->user()->tenant_id)
            ->orderByDesc('entry_date')->paginate(50));
    }
}
