<?php

namespace Tests\Feature;

use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Tests\TestCase;

/**
 * TenantIsolationTest — Blueprint Section 32's mandated tenant-isolation
 * regression suite. This is the single highest-risk area of a multi-tenant
 * SaaS: a leak here is a security incident, not a bug. These tests assert
 * that Tenant A can NEVER read or write Tenant B's rows through any path.
 *
 * Run in CI on every commit; a failure blocks merge.
 */
class TenantIsolationTest extends TestCase
{
    use RefreshDatabase;

    private string $tenantA;
    private string $tenantB;

    protected function setUp(): void
    {
        parent::setUp();
        [$this->tenantA, $this->tenantB] = $this->seedTwoTenants();
    }

    /** RLS blocks cross-tenant SELECT even via a raw query on the app connection. */
    public function test_customer_select_is_isolated_by_rls(): void
    {
        $this->actingAsTenant($this->tenantA);
        $visible = DB::table('isp.customers')->pluck('tenant_id')->unique();

        $this->assertCount(1, $visible, 'Tenant A must see exactly one tenant_id.');
        $this->assertEquals($this->tenantA, $visible->first());
    }

    /** RLS blocks cross-tenant UPDATE — an attempt to touch Tenant B's row affects 0 rows. */
    public function test_cross_tenant_update_affects_zero_rows(): void
    {
        $tenantBCustomerId = DB::table('isp.customers')->where('tenant_id', $this->tenantB)->value('id');

        $this->actingAsTenant($this->tenantA);
        $affected = DB::table('isp.customers')->where('id', $tenantBCustomerId)->update(['full_name' => 'HACKED']);

        $this->assertEquals(0, $affected, 'Tenant A must not be able to update Tenant B rows.');
    }

    /** RLS blocks cross-tenant DELETE. */
    public function test_cross_tenant_delete_affects_zero_rows(): void
    {
        $tenantBCustomerId = DB::table('isp.customers')->where('tenant_id', $this->tenantB)->value('id');

        $this->actingAsTenant($this->tenantA);
        $affected = DB::table('isp.customers')->where('id', $tenantBCustomerId)->delete();

        $this->assertEquals(0, $affected);
    }

    /** The customers API endpoint returns only the caller's tenant data. */
    public function test_customers_api_is_tenant_scoped(): void
    {
        $userA = DB::table('identity.users')->where('tenant_id', $this->tenantA)->first();

        $response = $this->actingAs($this->userModel($userA))->getJson('/api/v1/customers');

        $response->assertOk();
        foreach ($response->json('data') as $row) {
            $this->assertEquals($this->tenantA, $row['tenant_id']);
        }
    }

    /** Billing, network, accounting, support tables are all isolated too. */
    public function test_all_tenant_tables_enforce_isolation(): void
    {
        $tables = [
            'billing.invoices', 'billing.payments', 'network.mikrotik_routers',
            'network.pppoe_secrets', 'accounting.ledger_entries', 'hr.employees',
            'inventory.products', 'support.tickets', 'reseller.resellers',
            'automation.rules', 'audit.activity_logs',
        ];

        $this->actingAsTenant($this->tenantA);
        foreach ($tables as $table) {
            $foreign = DB::table($table)->where('tenant_id', $this->tenantB)->count();
            $this->assertEquals(0, $foreign, "{$table} leaked Tenant B rows to Tenant A.");
        }
    }

    // ---- helpers ----

    private function actingAsTenant(string $tenantId): void
    {
        DB::statement("SELECT set_config('app.current_tenant_id', ?, false)", [$tenantId]);
        DB::statement("SET app.is_platform_admin = 'false'");
    }

    private function seedTwoTenants(): array
    {
        // Uses TenantProvisioningService to create two full tenants, each
        // with one branch, one owner user, and one customer + service —
        // exercising the real provisioning path, not hand-inserted fixtures.
        $a = app(\App\Services\TenantProvisioningService::class)->provision(['name' => 'Tenant A']);
        $b = app(\App\Services\TenantProvisioningService::class)->provision(['name' => 'Tenant B']);
        return [$a->id, $b->id];
    }

    private function userModel(object $row): \App\Models\User
    {
        return \App\Models\User::find($row->id);
    }
}
