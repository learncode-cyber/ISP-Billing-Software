<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Str;

/** API key issuance (Blueprint Section 12). Full key shown once; only the
 *  hash is stored. */
class ApiKeyController extends Controller
{
    public function index(Request $request)
    {
        return response()->json(DB::table('integrations.api_keys')
            ->where('tenant_id', $request->user()->tenant_id)->whereNull('revoked_at')
            ->select('id','name','key_prefix','scopes_json','last_used_at','expires_at','created_at')->get());
    }

    public function store(Request $request)
    {
        $v = $request->validate(['name' => 'required|string', 'scopes' => 'nullable|array']);
        $plain = 'arq_live_'.Str::random(40);
        $id = (string) Str::uuid();
        DB::table('integrations.api_keys')->insert([
            'id' => $id,
            'tenant_id' => $request->user()->tenant_id,
            'name' => $v['name'],
            'key_prefix' => 'arq_live_',
            'key_hash' => Hash::make($plain),
            'scopes_json' => json_encode($v['scopes'] ?? []),
            'created_by' => $request->user()->id,
            'created_at' => now(),
        ]);
        return response()->json(['id' => $id, 'api_key' => $plain, 'note' => 'Store this now — it will not be shown again.'], 201);
    }

    public function destroy(Request $request, string $apiKey)
    {
        DB::table('integrations.api_keys')->where('id', $apiKey)
            ->where('tenant_id', $request->user()->tenant_id)->update(['revoked_at' => now()]);
        return response()->json(null, 204);
    }
}
