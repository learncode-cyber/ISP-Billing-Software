<?php

namespace Tests\Feature;

use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Tests\TestCase;

/**
 * EntitlementAndPermissionTest — asserts Blueprint Section 5's core rule:
 *   effective_access = subscription_entitlement AND user_permission
 * Both must be true. This is the second-highest-risk logic area after
 * tenant isolation, so it gets its own dedicated suite.
 */
class EntitlementAndPermissionTest extends TestCase
{
    use RefreshDatabase;

    /** The canonical example from the spec: Plan excludes OLT -> even an
     *  Admin with OLT permission is denied (402, not 403). */
    public function test_plan_excluded_feature_denied_even_with_permission(): void
    {
        // Starter-plan tenant: plan does NOT include network.olt.manage.
        $tenant = app(\App\Services\TenantProvisioningService::class)
            ->provision(['name' => 'Starter Co', 'plan' => 'starter']);

        $admin = $this->ownerOf($tenant->id); // Owner has ALL permissions incl. OLT

        $response = $this->actingAs($admin)->getJson('/api/v1/network/olt-devices');

        $response->assertStatus(402); // Payment Required = "not on your plan"
    }

    /** Feature enabled but user lacks the permission -> 403. */
    public function test_feature_enabled_but_permission_missing_denied(): void
    {
        $tenant = app(\App\Services\TenantProvisioningService::class)
            ->provision(['name' => 'Business Co', 'plan' => 'business']); // includes OLT

        $billingOnlyUser = $this->userWithRole($tenant->id, 'billing_operator'); // no network.olt.manage

        $response = $this->actingAs($billingOnlyUser)->getJson('/api/v1/network/olt-devices');

        $response->assertStatus(403); // Forbidden = "you lack permission"
    }

    /** Both present -> allowed. */
    public function test_feature_and_permission_both_present_allowed(): void
    {
        $tenant = app(\App\Services\TenantProvisioningService::class)
            ->provision(['name' => 'Business Co', 'plan' => 'business']);

        $noc = $this->userWithRole($tenant->id, 'noc_operator'); // has network.olt.manage

        $response = $this->actingAs($noc)->getJson('/api/v1/network/olt-devices');

        $response->assertOk();
    }

    /** BTRC news is free on every plan — even a Starter tenant can read it. */
    public function test_btrc_news_is_free_on_every_plan(): void
    {
        $tenant = app(\App\Services\TenantProvisioningService::class)
            ->provision(['name' => 'Starter Co', 'plan' => 'starter']);

        $this->assertTrue(
            app(\App\Services\EntitlementResolver::class)->isEnabled($tenant->id, 'compliance.news.view'),
            'compliance.news.view must resolve true regardless of plan.'
        );
    }

    /** Unknown feature keys deny by default (secure default). */
    public function test_unknown_feature_denies_by_default(): void
    {
        $tenant = app(\App\Services\TenantProvisioningService::class)->provision(['name' => 'X']);

        $result = DB::selectOne(
            'SELECT subscription.resolve_feature_access(?, ?) AS enabled',
            [$tenant->id, 'nonexistent.feature.key']
        );

        $this->assertFalse((bool) $result->enabled);
    }

    private function ownerOf(string $tenantId): \App\Models\User { /* resolve seeded owner */ return \App\Models\User::where('tenant_id',$tenantId)->firstOrFail(); }
    private function userWithRole(string $tenantId, string $roleCode): \App\Models\User { /* create + assign role */ return \App\Models\User::where('tenant_id',$tenantId)->firstOrFail(); }
}
