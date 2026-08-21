<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;

/**
 * BTRC compliance report (verified export). Returns the exact column set
 * observed in the audit for all active customers. Subscription-gated
 * (compliance.reports.btrc). Excel formatting happens client-side or via
 * an export job; this returns the structured rows.
 */
class BtrcReportController extends Controller
{
    public function __invoke(Request $request)
    {
        $rows = DB::table('isp.customers as c')
            ->join('isp.customer_services as cs','cs.customer_id','=','c.id')
            ->leftJoin('isp.packages as p','p.id','=','cs.package_id')
            ->where('c.tenant_id',$request->user()->tenant_id)
            ->where('c.status','active')
            ->select(
                'c.full_name as client_name','c.connection_type','c.connection_date as activation_date',
                'p.name as bandwidth','c.address','c.mobile as phone','c.email',
                'cs.monthly_bill as selling_bandwidth_bdt'
            )->get();
        return response()->json(['generated_at'=>now(),'rows'=>$rows]);
    }
}
