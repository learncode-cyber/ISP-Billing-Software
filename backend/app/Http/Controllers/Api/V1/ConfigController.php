<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use App\Models\Package;
use App\Models\Zone;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;

/** Customer Setting: Package / Zone / SubZone / Destination (verified). */
class ConfigController extends Controller
{
    public function packages() { return response()->json(Package::where('is_active',true)->get()); }
    public function zones() { return response()->json(Zone::where('is_active',true)->orderBy('name')->get()); }

    public function createPackage(Request $request)
    {
        $v = $request->validate([
            'name' => 'required|string', 'monthly_bill' => 'required|numeric|min:0',
            'mikrotik_profile_name' => 'nullable|string',
            'bandwidth_down_mbps' => 'nullable|numeric', 'bandwidth_up_mbps' => 'nullable|numeric',
        ]);
        return response()->json(Package::create($v), 201);
    }

    public function createZone(Request $request)
    {
        $v = $request->validate(['name' => 'required|string']);
        return response()->json(Zone::create($v), 201);
    }

    public function subzones(Request $request)
    {
        return response()->json(DB::table('isp.subzones')->where('tenant_id',$request->user()->tenant_id)->get());
    }

    public function destinations(Request $request)
    {
        return response()->json(DB::table('isp.destinations')->where('tenant_id',$request->user()->tenant_id)->get());
    }
}
