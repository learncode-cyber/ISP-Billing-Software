<?php

namespace App\Http\Controllers\Api\V1\Portal;

use App\Http\Controllers\Controller;
use App\Models\CustomerPortalAccount;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Facades\RateLimiter;
use Illuminate\Validation\ValidationException;

/**
 * Customer portal authentication. Issues tokens on the `customer` guard
 * only — these can never satisfy the staff `sanctum` guard, so a portal
 * token cannot reach admin endpoints even if replayed there.
 *
 * Rate limited per identifier+IP: subscriber portals are a common target
 * for credential stuffing since usernames are just mobile numbers.
 */
class PortalAuthController extends Controller
{
    public function login(Request $request)
    {
        $v = $request->validate([
            'login_identifier' => 'required|string|max:50',
            'password' => 'required|string',
        ]);

        $key = 'portal-login:'.$request->ip().':'.$v['login_identifier'];
        if (RateLimiter::tooManyAttempts($key, 5)) {
            throw ValidationException::withMessages([
                'login_identifier' => ['Too many attempts. Try again in '.RateLimiter::availableIn($key).' seconds.'],
            ]);
        }

        $acct = CustomerPortalAccount::where('login_identifier', $v['login_identifier'])
            ->where('is_active', true)->first();

        if (! $acct || ! Hash::check($v['password'], $acct->password_hash)) {
            RateLimiter::hit($key, 900);
            throw ValidationException::withMessages(['login_identifier' => ['Invalid credentials.']]);
        }

        RateLimiter::clear($key);

        $acct->forceFill(['last_login_at' => now()])->saveQuietly();

        DB::table('audit.activity_logs')->insert([
            'id' => (string) \Illuminate\Support\Str::uuid(),
            'tenant_id' => $acct->tenant_id,
            'action' => 'portal.login',
            'entity_type' => 'isp.customer_portal_accounts',
            'entity_id' => $acct->id,
            'ip_address' => $request->ip(),
            'device' => $request->userAgent(),
            'result' => 'success',
            'source' => 'user',
            'created_at' => now(),
        ]);

        return response()->json([
            'token' => $acct->createToken('customer-portal')->plainTextToken,
            'customer_id' => $acct->customer_id,
        ]);
    }

    public function logout(Request $request)
    {
        $request->user()->currentAccessToken()->delete();
        return response()->json(null, 204);
    }
}
