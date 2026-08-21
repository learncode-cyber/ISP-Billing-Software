<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use App\Models\User;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Hash;
use Illuminate\Validation\ValidationException;

/**
 * Staff authentication (Blueprint Section 27). Issues Sanctum bearer
 * tokens the React admin console and mobile apps use. Login is scoped by
 * tenant slug so the same username can exist across tenants (usernames
 * are unique per-tenant, not globally — see identity.users).
 *
 * NOTE: this endpoint sets tenant context manually AFTER resolving the
 * user, because at login time there is no authenticated user yet for the
 * SetTenantContext middleware to read — login is one of the few routes
 * that runs before tenant context exists.
 */
class AuthController extends Controller
{
    public function login(Request $request)
    {
        $credentials = $request->validate([
            'username' => 'required|string',
            'password' => 'required|string',
            'tenant_slug' => 'nullable|string', // optional: disambiguate same username across tenants
        ]);

        $query = User::where('username', $credentials['username'])->whereNull('deleted_at');

        if (! empty($credentials['tenant_slug'])) {
            $tenantId = \Illuminate\Support\Facades\DB::table('tenancy.tenants')
                ->where('slug', $credentials['tenant_slug'])->value('id');
            $query->where('tenant_id', $tenantId);
        }

        $user = $query->first();

        if (! $user || ! Hash::check($credentials['password'], $user->password_hash)) {
            throw ValidationException::withMessages(['username' => ['Invalid credentials.']]);
        }

        if ($user->status !== 'active') {
            throw ValidationException::withMessages(['username' => ['This account is inactive.']]);
        }

        // Audit the login (Blueprint Section 28 — verified behavior).
        \Illuminate\Support\Facades\DB::table('audit.activity_logs')->insert([
            'id' => (string) \Illuminate\Support\Str::uuid(),
            'tenant_id' => $user->tenant_id,
            'user_id' => $user->id,
            'action' => 'auth.login',
            'ip_address' => $request->ip(),
            'device' => $request->userAgent(),
            'result' => 'success',
            'source' => 'user',
            'created_at' => now(),
        ]);

        $user->forceFill([
            'last_login_at' => now(),
            'last_login_ip' => $request->ip(),
        ])->saveQuietly();

        $token = $user->createToken('admin-console')->plainTextToken;

        return response()->json([
            'token' => $token,
            'user' => [
                'id' => $user->id,
                'name' => $user->name,
                'tenant_id' => $user->tenant_id,
            ],
        ]);
    }

    public function logout(Request $request)
    {
        $request->user()->currentAccessToken()->delete();
        return response()->json(null, 204);
    }

    public function me(Request $request)
    {
        return response()->json($request->user()->only(['id', 'name', 'username', 'email', 'tenant_id', 'branch_id']));
    }
}
