<?php

namespace App\Http\Middleware;

use Closure;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Symfony\Component\HttpFoundation\Response;

/**
 * SetTenantContext
 *
 * Runs immediately after authentication, before any other query. Sets the
 * Postgres session variables every RLS policy reads via
 * platform.current_tenant_id().
 *
 * ── CRITICAL FIX (found by live database testing) ──
 * This previously used `SET LOCAL`, which Postgres only honours inside a
 * transaction block. Laravel does NOT wrap requests in a transaction, so
 * `SET LOCAL` silently did nothing — Postgres emits
 * "WARNING: SET LOCAL can only be used in transaction blocks" — and every
 * RLS-protected query returned ZERO rows. The app was fail-closed (no data
 * leak) but completely non-functional.
 *
 * Fixed by using set_config(..., is_local => false), which is session
 * scoped and therefore effective outside a transaction.
 *
 * ── Connection-reuse safety ──
 * Session scope persists on the connection. Safe here because:
 *   1. this middleware runs on EVERY tenant route and overwrites the value
 *      before any query executes, and
 *   2. when there is no authenticated tenant we explicitly reset it to ''
 *      so platform.current_tenant_id() returns NULL and every RLS policy
 *      matches nothing — fail closed, never fail open.
 *
 * If a transaction-mode pooler (PgBouncer) is ever placed in front of
 * Postgres, connections can swap mid-request; in that topology this
 * middleware MUST wrap the request in a transaction and use SET LOCAL.
 * Documented in DEPLOYMENT.md.
 */
class SetTenantContext
{
    public function handle(Request $request, Closure $next): Response
    {
        $user = $request->user();

        // Platform Super Admin console uses a separate BYPASSRLS connection.
        if ($user && $user->tenant_id === null) {
            DB::statement("SELECT set_config('app.current_tenant_id', '', false)");
            DB::statement("SELECT set_config('app.is_platform_admin', 'true', false)");
            return $next($request);
        }

        if (! $user || ! $user->tenant_id) {
            // Fail closed: clear inherited context before rejecting.
            DB::statement("SELECT set_config('app.current_tenant_id', '', false)");
            DB::statement("SELECT set_config('app.is_platform_admin', 'false', false)");
            abort(403, 'No tenant context resolved for this request.');
        }

        DB::statement("SELECT set_config('app.current_tenant_id', ?, false)", [$user->tenant_id]);
        DB::statement("SELECT set_config('app.is_platform_admin', 'false', false)");

        return $next($request);
    }
}
