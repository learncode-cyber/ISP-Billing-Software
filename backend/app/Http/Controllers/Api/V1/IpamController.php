<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;

/**
 * IPAM — IP Address Management (Blueprint module 13).
 *
 * Conflict detection is enforced in PostgreSQL (overlap trigger, subnet
 * containment trigger, partial unique index on live allocations), so a
 * bad allocation is impossible regardless of which code path attempts it.
 * This controller surfaces those errors as clean 422s.
 */
class IpamController extends Controller
{
    public function subnets(Request $request)
    {
        return response()->json(
            DB::table('network.v_subnet_utilisation')
                ->where('tenant_id', $request->user()->tenant_id)
                ->orderBy('name')->get()
        );
    }

    public function storeSubnet(Request $request)
    {
        $v = $request->validate([
            'name' => 'required|string|max:150',
            'cidr' => 'required|string|max:64',
            'gateway' => 'nullable|ip',
            'vlan_id' => 'nullable|integer',
            'description' => 'nullable|string',
        ]);

        try {
            $id = (string) Str::uuid();
            DB::table('network.ip_subnets')->insert([
                'id' => $id, 'tenant_id' => $request->user()->tenant_id,
                'name' => $v['name'], 'cidr' => $v['cidr'],
                'gateway' => $v['gateway'] ?? null, 'vlan_id' => $v['vlan_id'] ?? null,
                'description' => $v['description'] ?? null,
                'created_at' => now(), 'updated_at' => now(),
            ]);
            return response()->json(['id' => $id], 201);
        } catch (\Illuminate\Database\QueryException $e) {
            return response()->json(['message' => $this->friendly($e)], 422);
        }
    }

    public function allocations(Request $request)
    {
        $q = DB::table('network.ip_allocations as a')
            ->join('network.ip_subnets as s', 's.id', '=', 'a.subnet_id')
            ->where('a.tenant_id', $request->user()->tenant_id)
            ->when($request->filled('subnet_id'), fn ($x) => $x->where('a.subnet_id', $request->subnet_id))
            ->when($request->filled('status'), fn ($x) => $x->where('a.status', $request->status))
            ->select('a.*', 's.name as subnet_name', 's.cidr')
            ->orderBy('a.ip_address');

        return response()->json($q->paginate(min((int) $request->get('per_page', 50), 500)));
    }

    public function allocate(Request $request)
    {
        $v = $request->validate([
            'subnet_id' => 'required|uuid',
            'ip_address' => 'required|ip',
            'status' => 'nullable|in:allocated,reserved,quarantined',
            'customer_service_id' => 'nullable|uuid',
            'hostname' => 'nullable|string|max:150',
            'note' => 'nullable|string',
        ]);

        try {
            $id = (string) Str::uuid();
            DB::table('network.ip_allocations')->insert([
                'id' => $id, 'tenant_id' => $request->user()->tenant_id,
                'subnet_id' => $v['subnet_id'], 'ip_address' => $v['ip_address'],
                'status' => $v['status'] ?? 'allocated',
                'customer_service_id' => $v['customer_service_id'] ?? null,
                'hostname' => $v['hostname'] ?? null, 'note' => $v['note'] ?? null,
                'allocated_at' => now(), 'created_by' => $request->user()->id,
            ]);
            return response()->json(['id' => $id], 201);
        } catch (\Illuminate\Database\QueryException $e) {
            return response()->json(['message' => $this->friendly($e)], 422);
        }
    }

    public function release(Request $request, string $allocation)
    {
        DB::table('network.ip_allocations')
            ->where('id', $allocation)->where('tenant_id', $request->user()->tenant_id)
            ->update(['status' => 'released', 'released_at' => now()]);
        return response()->json(['status' => 'released']);
    }

    /** Next free address in a subnet — server-side so two operators can't
     *  race to the same IP (the unique index is the final arbiter). */
    public function nextFree(Request $request, string $subnet)
    {
        $row = DB::table('network.ip_subnets')
            ->where('id', $subnet)->where('tenant_id', $request->user()->tenant_id)->first();
        abort_if(! $row, 404);

        $taken = DB::table('network.ip_allocations')
            ->where('subnet_id', $subnet)
            ->whereIn('status', ['allocated', 'reserved', 'quarantined'])
            ->pluck('ip_address')->map(fn ($i) => (string) $i)->all();

        $candidate = DB::selectOne(
            "SELECT host(a) AS ip FROM generate_series(
                (network(?::cidr) + 1)::inet, (broadcast(?::cidr) - 1)::inet, 1
             ) AS a WHERE NOT (host(a) = ANY(?::text[])) LIMIT 1",
            [$row->cidr, $row->cidr, '{'.implode(',', $taken).'}']
        );

        return response()->json(['next_free' => $candidate->ip ?? null]);
    }

    private function friendly(\Throwable $e): string
    {
        $m = $e->getMessage();
        if (str_contains($m, 'overlaps existing subnet')) return 'This subnet overlaps an existing subnet.';
        if (str_contains($m, 'is outside subnet')) return 'That IP address is outside the selected subnet.';
        if (str_contains($m, 'duplicate key')) return 'That IP address is already allocated.';
        return 'The IP operation was rejected.';
    }
}
