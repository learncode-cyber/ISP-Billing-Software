<?php

namespace App\Http\Middleware;

use App\Services\EntitlementResolver;
use Closure;
use Illuminate\Http\Request;
use Symfony\Component\HttpFoundation\Response;

/**
 * CheckEntitlement
 *
 * First half of the mandatory AND: subscription entitlement.
 * Usage on a route: ->middleware('entitlement:network.olt.manage')
 *
 * Runs BEFORE CheckPermission (registered first in the route middleware
 * chain) so a tenant whose plan excludes a module gets a clean "not
 * available on your plan" response rather than a permission-denied
 * response that implies the feature exists but the user lacks rights —
 * these are different situations and the UI/UX should distinguish them.
 */
class CheckEntitlement
{
    public function __construct(private EntitlementResolver $entitlements)
    {
    }

    public function handle(Request $request, Closure $next, string $featureKey): Response
    {
        $user = $request->user();

        // Platform Super Admin is not subject to tenant entitlement checks.
        if (! $user || $user->tenant_id === null) {
            return $next($request);
        }

        if (! $this->entitlements->isEnabled($user->tenant_id, $featureKey)) {
            abort(402, "This feature ({$featureKey}) is not included in your current subscription plan.");
            // 402 Payment Required is used intentionally to let the frontend
            // distinguish "upgrade your plan" from 403 "you lack permission".
        }

        return $next($request);
    }
}
