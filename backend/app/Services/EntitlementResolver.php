<?php

namespace App\Services;

use App\Models\Tenant;
use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Facades\DB;

/**
 * EntitlementResolver
 *
 * Application-layer mirror of subscription.resolve_feature_access() from
 * 003_subscription.sql. Both exist deliberately:
 *   - the SQL function is the authoritative, always-correct fallback and
 *     is used by admin diagnostics / support tooling
 *   - this service is the hot path, cached per tenant per feature key,
 *     invalidated whenever a tenant's subscription/override changes
 *
 * Blueprint Section 5 rule enforced here:
 *   effective_access = (plan_or_override_enabled) AND (user_permission_allowed)
 * This class answers ONLY the first half. CheckPermission middleware
 * answers the second half. Both must pass — see CheckEntitlement +
 * CheckPermission running back-to-back on every protected route.
 */
class EntitlementResolver
{
    private const CACHE_TTL_SECONDS = 300;

    public function isEnabled(string $tenantId, string $featureKey): bool
    {
        $cacheKey = "tenant:{$tenantId}:entitlement:{$featureKey}";

        return Cache::remember($cacheKey, self::CACHE_TTL_SECONDS, function () use ($tenantId, $featureKey) {
            $result = DB::selectOne(
                'SELECT subscription.resolve_feature_access(?, ?) AS enabled',
                [$tenantId, $featureKey]
            );

            return (bool) ($result->enabled ?? false);
        });
    }

    /**
     * Returns the full resolved capability map for the authenticated
     * tenant — this is what /api/v1/me/capabilities serves, and what the
     * React frontend uses to render navigation. Single source of truth:
     * no plan logic is ever hard-coded into individual components.
     */
    public function capabilitiesFor(string $tenantId): array
    {
        $features = DB::table('subscription.features')->select('key', 'module')->get();

        $capabilities = [];
        foreach ($features as $feature) {
            $capabilities[$feature->key] = $this->isEnabled($tenantId, $feature->key);
        }

        return $capabilities;
    }

    public function invalidate(string $tenantId): void
    {
        // Called from TenantSubscription observers (plan change, override
        // added/removed, subscription suspended) so stale entitlements
        // never persist past a 5-minute worst case even without this call.
        $features = DB::table('subscription.features')->pluck('key');
        foreach ($features as $key) {
            Cache::forget("tenant:{$tenantId}:entitlement:{$key}");
        }
    }
}
