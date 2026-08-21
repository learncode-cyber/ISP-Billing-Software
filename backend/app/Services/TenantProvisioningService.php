<?php

namespace App\Services;

use App\Models\User;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Str;

/**
 * TenantProvisioningService
 *
 * Creates a complete, ready-to-use tenant in one transaction. Referenced
 * throughout (tests, migration ETL, Super Admin console). Every new
 * tenant gets, atomically:
 *   1. tenancy.tenants row
 *   2. a head-office branch (the "exactly one head office" rule enforced
 *      here, at the app layer, since a partial unique index can't express it)
 *   3. the system role templates cloned into tenant-owned roles
 *   4. an Owner user with the owner role (full permissions)
 *   5. a trial subscription on the requested plan
 *   6. the default automation rules (via the seeded SQL function),
 *      reproducing the audit's verified automations
 *   7. an "Employee" expense account head (so the salary→GL trigger works)
 *
 * Runs under the platform connection so it can insert the tenants row
 * (which has no RLS) and set up cross-schema data before RLS context
 * exists for the new tenant.
 */
class TenantProvisioningService
{
    public function provision(array $input): object
    {
        return DB::transaction(function () use ($input) {
            $tenantId = (string) Str::uuid();
            $slug = $input['slug'] ?? Str::slug($input['name']).'-'.substr($tenantId, 0, 6);
            $planCode = $input['plan'] ?? 'starter';

            // 1. Tenant
            DB::table('tenancy.tenants')->insert([
                'id' => $tenantId,
                'name' => $input['name'],
                'slug' => $slug,
                'business_type' => $input['business_type'] ?? 'isp',
                'status' => 'trial',
                'created_at' => now(),
                'updated_at' => now(),
            ]);

            // Activate RLS context for this new tenant for the rest of the txn.
            DB::statement("SELECT set_config('app.current_tenant_id', ?, true)", [$tenantId]); // is_local=true: txn-scoped

            // 2. Head-office branch
            $branchId = (string) Str::uuid();
            DB::table('tenancy.branches')->insert([
                'id' => $branchId,
                'tenant_id' => $tenantId,
                'name' => $input['name'].' — Head Office',
                'code' => 'HO',
                'is_head_office' => true,
                'status' => 'active',
                'created_at' => now(),
                'updated_at' => now(),
            ]);

            // 3. Clone system role templates into tenant-owned roles
            $roleMap = $this->cloneSystemRoles($tenantId);

            // 4. Owner user
            $ownerId = (string) Str::uuid();
            DB::table('identity.users')->insert([
                'id' => $ownerId,
                'tenant_id' => $tenantId,
                'branch_id' => $branchId,
                'name' => $input['owner_name'] ?? 'Owner',
                'username' => $input['owner_username'] ?? 'owner',
                'email' => $input['owner_email'] ?? null,
                'password_hash' => Hash::make($input['owner_password'] ?? Str::random(16)),
                'status' => 'active',
                'created_at' => now(),
                'updated_at' => now(),
            ]);
            DB::table('identity.user_roles')->insert([
                'id' => (string) Str::uuid(),
                'user_id' => $ownerId,
                'role_id' => $roleMap['owner'],
                'branch_id' => $branchId,
                'created_at' => now(),
            ]);

            // 5. Trial subscription
            $planId = DB::table('subscription.plans')->where('code', $planCode)->value('id');
            DB::table('subscription.tenant_subscriptions')->insert([
                'id' => (string) Str::uuid(),
                'tenant_id' => $tenantId,
                'plan_id' => $planId,
                'status' => 'trial',
                'current_period_start' => now(),
                'current_period_end' => now()->addDays(14),
                'created_at' => now(),
                'updated_at' => now(),
            ]);

            // 6. Default automation rules (verified behavior reproduced)
            DB::statement('SELECT automation.seed_default_rules_for_tenant(?)', [$tenantId]);

            // 7. "Employee" expense head so hr.post_salary_to_expense works
            DB::table('accounting.account_heads')->insert([
                'id' => (string) Str::uuid(),
                'tenant_id' => $tenantId,
                'name' => 'Employee',
                'head_type' => 'expense',
                'created_at' => now(),
            ]);

            return (object) ['id' => $tenantId, 'slug' => $slug, 'owner_id' => $ownerId, 'branch_id' => $branchId];
        });
    }

    /** Clones the tenant_id=NULL system role templates into tenant-owned rows,
     *  copying their permission grants. Returns [role_code => new_role_id]. */
    private function cloneSystemRoles(string $tenantId): array
    {
        $map = [];
        $templates = DB::table('identity.roles')->whereNull('tenant_id')->where('is_system', true)->get();

        foreach ($templates as $tpl) {
            $newRoleId = (string) Str::uuid();
            DB::table('identity.roles')->insert([
                'id' => $newRoleId,
                'tenant_id' => $tenantId,
                'name' => $tpl->name,
                'code' => $tpl->code,
                'is_system' => true,
                'created_at' => now(),
                'updated_at' => now(),
            ]);

            // Copy the template's permission grants (with their data scopes)
            $grants = DB::table('identity.role_permissions')->where('role_id', $tpl->id)->get();
            foreach ($grants as $g) {
                DB::table('identity.role_permissions')->insert([
                    'id' => (string) Str::uuid(),
                    'role_id' => $newRoleId,
                    'permission_id' => $g->permission_id,
                    'data_scope' => $g->data_scope,
                ]);
            }
            $map[$tpl->code] = $newRoleId;
        }

        return $map;
    }
}
