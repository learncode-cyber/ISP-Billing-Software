<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use App\Services\MikrotikService;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;

/**
 * MikroTik control endpoints (verified per-row Enable + bulk actions).
 * Reads are filtered views over network.pppoe_secrets; writes queue jobs.
 */
class MikrotikController extends Controller
{
    public function __construct(private MikrotikService $mikrotik) {}

    public function disconnect(Request $request, string $secret)
    {
        $this->mikrotik->disableSecret($secret, $request->input('reason', 'Manual disconnect'));
        return response()->json(['status' => 'queued']);
    }

    public function reconnect(string $secret)
    {
        $this->mikrotik->enableSecret($secret);
        return response()->json(['status' => 'queued']);
    }

    public function secrets(Request $request)
    {
        // REAL DEFECT found by HTTP-layer boot testing: this used
        // DB::table(...)->paginate() — a raw query builder call — which
        // returns every column including secret_password_encrypted.
        // Eloquent's $hidden (declared on the PppoeSecret model
        // specifically to prevent this) only applies when a model is
        // actually used; a raw query bypasses it entirely. Source review
        // alone could not catch this because the model-level protection
        // looked correct — only an actual response body proved the field
        // was still leaking. Fixed by explicitly whitelisting columns.
        //
        // ?status=enabled|disabled|unmatched ; ?online=true|false
        $q = DB::table('network.pppoe_secrets')
            ->where('tenant_id', $request->user()->tenant_id)
            ->when($request->filled('status'), fn($x) => $x->where('status', $request->status))
            ->when($request->filled('online'), fn($x) => $x->where('is_online', filter_var($request->online, FILTER_VALIDATE_BOOL)))
            ->select([
                'id', 'tenant_id', 'customer_service_id', 'router_id', 'radius_nas_id',
                'username', 'profile', 'ip_type', 'static_ip', 'status', 'disabled_reason',
                'is_online', 'auth_protocol', 'last_synced_at', 'created_at', 'updated_at',
                // secret_password_encrypted deliberately excluded — never sent to any API client.
            ]);
        return response()->json($q->paginate(min((int)$request->get('per_page',50),500)));
    }

    public function bulkDisconnectDue(Request $request)
    {
        return response()->json($this->mikrotik->bulkDisconnectDueCustomers($request->user()->tenant_id));
    }
}
