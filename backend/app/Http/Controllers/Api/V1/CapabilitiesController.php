<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use App\Services\EntitlementResolver;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;

/**
 * GET /api/v1/me/capabilities
 *
 * Blueprint Section 5 / Section 37 (UI Navigation Architecture):
 * "Menu visibility should derive from Feature entitlement + Permission +
 * Role + Data scope. Do not hard-code plan logic into dozens of frontend
 * components." This endpoint is that single source of truth — the React
 * app renders navigation/buttons purely from this response, never from
 * locally hard-coded plan checks.
 */
class CapabilitiesController extends Controller
{
    public function __construct(private EntitlementResolver $entitlements)
    {
    }

    public function __invoke(Request $request): JsonResponse
    {
        $user = $request->user();

        if ($user->tenant_id === null) {
            return response()->json([
                'scope' => 'platform_admin',
                'features' => [],
                'permissions' => [],
            ]);
        }

        $features = $this->entitlements->capabilitiesFor($user->tenant_id);

        $permissions = DB::table('identity.user_roles as ur')
            ->join('identity.role_permissions as rp', 'rp.role_id', '=', 'ur.role_id')
            ->join('identity.permissions as p', 'p.id', '=', 'rp.permission_id')
            ->where('ur.user_id', $user->id)
            ->select('p.key', 'rp.data_scope')
            ->get()
            ->groupBy('key')
            ->map(fn ($grants) => $grants->pluck('data_scope'))
            ->toArray();

        return response()->json([
            'scope' => 'tenant',
            'tenant_id' => $user->tenant_id,
            'features' => $features,       // { "network.olt.manage": false, "compliance.news.view": true, ... }
            'permissions' => $permissions, // { "isp.customer.edit": ["BRANCH"], ... }
        ]);
    }
}
