<?php

namespace App\Http\Middleware;

use Closure;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Symfony\Component\HttpFoundation\Response;

/**
 * RequirePlatformAdmin
 *
 * Hard boundary between AR Qudrix platform staff and tenant users.
 *
 * A platform admin is defined structurally: identity.users.tenant_id IS
 * NULL. A tenant administrator — however many permissions their role
 * carries — always has a tenant_id, so they can never satisfy this check.
 * There is no permission or role a tenant can be granted that opens this
 * door; the separation is by identity shape, not by privilege level.
 *
 * Platform routes also switch to the `pgsql_platform` connection, which
 * authenticates as the BYPASSRLS role. That connection is unreachable
 * from any tenant-facing code path.
 */
class RequirePlatformAdmin
{
    public function handle(Request $request, Closure $next): Response
    {
        $user = $request->user();

        if (! $user) {
            abort(401);
        }

        if ($user->tenant_id !== null) {
            // Deliberately logged: a tenant user reaching a platform route
            // is either a bug or an attack, and we want to see both.
            DB::table('audit.activity_logs')->insert([
                'id' => (string) \Illuminate\Support\Str::uuid(),
                'tenant_id' => $user->tenant_id,
                'user_id' => $user->id,
                'action' => 'platform.access_denied',
                'entity_type' => 'platform',
                'ip_address' => $request->ip(),
                'device' => $request->userAgent(),
                'result' => 'failed',
                'source' => 'user',
                'created_at' => now(),
            ]);

            abort(403, 'Platform administration is not available to tenant accounts.');
        }

        // Platform work runs on the BYPASSRLS connection so cross-tenant
        // reporting is possible — but only from here.
        config(['database.default' => 'pgsql_platform']);
        DB::statement("SELECT set_config('app.is_platform_admin', 'true', false)");

        return $next($request);
    }
}
