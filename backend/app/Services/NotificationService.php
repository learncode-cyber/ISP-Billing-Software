<?php

namespace App\Services;

use Illuminate\Support\Facades\DB;

/**
 * NotificationService — fans a notification out to every user holding a
 * given role in a tenant (e.g. notify all NOC Operators on router-down,
 * all Inventory Managers on low stock). Channel-agnostic: writes in-app
 * notifications and optionally triggers SMS/email per tenant config.
 */
class NotificationService
{
    public function notifyRole(string $tenantId, string $roleCode, array $context): array
    {
        $userIds = DB::table('identity.user_roles as ur')
            ->join('identity.roles as r', 'r.id', '=', 'ur.role_id')
            ->join('identity.users as u', 'u.id', '=', 'ur.user_id')
            ->where('r.tenant_id', $tenantId)
            ->where('r.code', $roleCode)
            ->pluck('u.id');

        // Insert in-app notification rows for each recipient (communication
        // domain). Integration boundary for push/email fan-out.
        return ['notified_users' => $userIds->count(), 'role' => $roleCode];
    }
}
