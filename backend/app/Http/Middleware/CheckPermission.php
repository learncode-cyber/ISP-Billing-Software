<?php

namespace App\Http\Middleware;

use Closure;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Symfony\Component\HttpFoundation\Response;

/**
 * CheckPermission
 *
 * Second half of the mandatory AND: RBAC. Usage:
 *   ->middleware(['entitlement:isp.customer.manage', 'permission:isp.customer.edit'])
 *
 * Resolves the user's roles -> role_permissions for the given permission
 * key, and additionally exposes the resolved data_scope (ALL/BRANCH/OWN/
 * ASSIGNED) on the request so controllers can apply the correct query
 * constraint (e.g. a Reseller-scoped user only ever sees isp.customers
 * rows they own — enforced again at the query builder level, on top of
 * RLS tenant isolation, per the project's defense-in-depth rule).
 */
class CheckPermission
{
    public function handle(Request $request, Closure $next, string $permissionKey): Response
    {
        $user = $request->user();

        if (! $user) {
            abort(401);
        }

        // Platform Super Admin (tenant_id null) uses a separate, simpler
        // platform.* permission set — not covered by this middleware.
        if ($user->tenant_id === null) {
            return $next($request);
        }

        $grant = DB::table('identity.user_roles as ur')
            ->join('identity.role_permissions as rp', 'rp.role_id', '=', 'ur.role_id')
            ->join('identity.permissions as p', 'p.id', '=', 'rp.permission_id')
            ->where('ur.user_id', $user->id)
            ->where('p.key', $permissionKey)
            ->orderByRaw("CASE rp.data_scope
                WHEN 'ALL' THEN 1 WHEN 'BRANCH' THEN 2
                WHEN 'ASSIGNED' THEN 3 WHEN 'OWN' THEN 4 END") // widest scope wins if user has multiple roles
            ->select('rp.data_scope')
            ->first();

        if (! $grant) {
            abort(403, "You do not have permission to perform this action ({$permissionKey}).");
        }

        // Available to the controller via $request->attributes->get('data_scope')
        $request->attributes->set('data_scope', $grant->data_scope);

        return $next($request);
    }
}
