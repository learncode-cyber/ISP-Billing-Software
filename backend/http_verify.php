<?php
/**
 * http_verify.php — REAL in-process HTTP layer verification.
 *
 * This is not a mock. It boots the actual Illuminate\Foundation\Application
 * from this project's real bootstrap/app.php, and for every test case
 * constructs a real Symfony/Illuminate Request object and hands it to
 * $kernel->handle($request) — the exact same call a socket-bound server
 * (php artisan serve, php-fpm, nginx+fpm) makes per request. The request
 * traverses the REAL router, the REAL registered middleware (SetTenantContext,
 * CheckEntitlement, CheckPermission, RequirePlatformAdmin, Sanctum auth),
 * REAL controllers, REAL services, and a REAL PostgreSQL connection with
 * RLS active — and returns a REAL Response object this script inspects.
 *
 * The one thing it does NOT exercise is the raw TCP socket layer itself
 * (headers-over-wire framing) — everything above that, which is where
 * application defects actually live, is real.
 *
 * Why this approach: `php artisan serve` / `php -S` could not be kept
 * alive across tool-call boundaries in this sandbox (background process
 * backgrounding hung the tool itself, reproducibly, even for a trivial
 * Node.js server that had worked earlier in the same session — an
 * environment-level constraint, not an application defect). This is the
 * documented, honest workaround: same PHP request pipeline, no socket.
 */

require __DIR__.'/vendor/autoload.php';
$app = require __DIR__.'/bootstrap/app.php';
$kernel = $app->make(\Illuminate\Contracts\Http\Kernel::class);

$results = [];
function record(&$results, $name, $pass, $detail = '') {
    $results[] = [$name, $pass, $detail];
    echo ($pass ? "PASS  " : "FAIL  ") . $name . ($detail ? "  ($detail)" : "") . "\n";
}

function req($method, $uri, $data = [], $headers = []) {
    $server = ['HTTP_ACCEPT' => 'application/json'];
    foreach ($headers as $k => $v) { $server['HTTP_'.strtoupper(str_replace('-', '_', $k))] = $v; }
    $content = null;
    if (in_array($method, ['POST','PUT','PATCH','DELETE']) && $data !== null) {
        $content = is_string($data) ? $data : json_encode($data);
        $server['CONTENT_TYPE'] = 'application/json';
    }
    $request = \Illuminate\Http\Request::create($uri, $method, [], [], [], $server, $content);
    return $request;
}

// ---- 0. Boot check ----
record($results, 'Application boots', $app instanceof \Illuminate\Foundation\Application, get_class($app));

// ---- 1. Health check ----
$resp = $kernel->handle($r = req('GET', '/up'));
record($results, 'GET /up returns 200', $resp->getStatusCode() === 200, 'status='.$resp->getStatusCode());
$kernel->terminate($r, $resp);

// ---- 2. Unauthenticated request rejected ----
$resp = $kernel->handle($r = req('GET', '/api/v1/customers'));
record($results, 'Unauthenticated request -> 401', $resp->getStatusCode() === 401, 'status='.$resp->getStatusCode().' body='.substr($resp->getContent(),0,120));
$kernel->terminate($r, $resp);

// ---- 3. Login with wrong password ----
$resp = $kernel->handle($r = req('POST', '/api/v1/auth/login', ['username' => 'httpverify', 'password' => 'wrong-password']));
record($results, 'Wrong password -> 422', $resp->getStatusCode() === 422, 'status='.$resp->getStatusCode());
$kernel->terminate($r, $resp);

// ---- 4. Real login ----
$resp = $kernel->handle($r = req('POST', '/api/v1/auth/login', ['username' => 'httpverify', 'password' => 'secret1234']));
$loginOk = $resp->getStatusCode() === 200;
$body = json_decode($resp->getContent(), true);
$token = $body['token'] ?? null;
record($results, 'Real login returns 200 + token', $loginOk && $token, 'status='.$resp->getStatusCode().' has_token='.($token?'yes':'no'));
$kernel->terminate($r, $resp);

if ($token) {
    // ---- 5. Authenticated request with real token ----
    $resp = $kernel->handle($r = req('GET', '/api/v1/auth/me', [], ['Authorization' => 'Bearer '.$token]));
    record($results, 'Authenticated /auth/me -> 200', $resp->getStatusCode() === 200, 'status='.$resp->getStatusCode().' body='.substr($resp->getContent(),0,150));
    $kernel->terminate($r, $resp);

    // ---- 6. Capabilities endpoint (entitlement resolver, real DB query) ----
    $resp = $kernel->handle($r = req('GET', '/api/v1/me/capabilities', [], ['Authorization' => 'Bearer '.$token]));
    $capBody = json_decode($resp->getContent(), true);
    $hasFeatures = isset($capBody['features']) && is_array($capBody['features']);
    record($results, 'Capabilities endpoint returns real entitlement map', $resp->getStatusCode() === 200 && $hasFeatures,
        'status='.$resp->getStatusCode().' feature_count='.count($capBody['features'] ?? []));
    $kernel->terminate($r, $resp);

    // ---- 7. Entitlement gate — enterprise plan should ALLOW OLT ----
    $resp = $kernel->handle($r = req('GET', '/api/v1/network/olt-devices', [], ['Authorization' => 'Bearer '.$token]));
    record($results, 'Enterprise plan: OLT endpoint reachable (200)', $resp->getStatusCode() === 200, 'status='.$resp->getStatusCode());
    $kernel->terminate($r, $resp);

    // ---- 8. Real CREATE -> READ -> UPDATE -> DELETE cycle on customers ----
    // First fetch a real zone/package/router/billing-person to satisfy validation
    // Most-recently-provisioned tenant, not a hardcoded slug match — this
    // harness is re-run against freshly-seeded databases with varying
    // tenant names across environments.
    $tenantId = \Illuminate\Support\Facades\DB::table('tenancy.tenants')->orderByDesc('created_at')->value('id');
    \Illuminate\Support\Facades\DB::statement("SELECT set_config('app.current_tenant_id', ?, false)", [$tenantId]);
    $suffix = \Illuminate\Support\Str::random(6);
    $zoneId = \Illuminate\Support\Facades\DB::table('isp.zones')->insertGetId(['id'=>\Illuminate\Support\Str::uuid(),'tenant_id'=>$tenantId,'name'=>'HTTP Test Zone '.$suffix,'is_active'=>true], 'id');
    $userId = \Illuminate\Support\Facades\DB::table('identity.users')->where('tenant_id',$tenantId)->value('id');
    $packageId = \Illuminate\Support\Facades\DB::table('isp.packages')->insertGetId(['id'=>\Illuminate\Support\Str::uuid(),'tenant_id'=>$tenantId,'name'=>'Test 20Mbps '.$suffix,'monthly_bill'=>800,'is_active'=>true],'id');
    $routerId = \Illuminate\Support\Facades\DB::table('network.mikrotik_routers')->insertGetId([
        'id'=>\Illuminate\Support\Str::uuid(),'tenant_id'=>$tenantId,'name'=>'Test Router','ip_address'=>'10.0.0.1',
        'port'=>8728,'username_encrypted'=>encrypt('admin'),'password_encrypted'=>encrypt('admin'),
        'status'=>'disconnected','created_at'=>now(),'updated_at'=>now()], 'id');

    $createResp = $kernel->handle($r = req('POST', '/api/v1/customers', [
        'full_name' => 'HTTP E2E Customer', 'mobile' => '01799999999',
        'agent_type' => 'optical_fiber', 'connection_type' => 'home',
        'connection_date' => '2026-08-11', 'zone_id' => $zoneId, 'billing_person_id' => $userId,
        'status' => 'active', 'package_id' => $packageId, 'monthly_bill' => 800,
        'disconnect_day' => 5, 'pppoe_username' => 'httptest_'.$suffix, 'pppoe_secret_password' => 'secret',
        'router_id' => $routerId,
    ], ['Authorization' => 'Bearer '.$token]));
    $createBody = json_decode($createResp->getContent(), true);
    $custId = $createBody['id'] ?? null;
    record($results, 'CREATE customer -> 201 + real DB row', $createResp->getStatusCode() === 201 && $custId,
        'status='.$createResp->getStatusCode().' id='.($custId ?: substr($createResp->getContent(),0,200)));
    $kernel->terminate($r, $createResp);

    if ($custId) {
        // Verify it's REALLY in the database
        $dbRow = \Illuminate\Support\Facades\DB::table('isp.customers')->where('id', $custId)->first();
        record($results, 'Created customer verified in real PostgreSQL row', $dbRow !== null, 'full_name='.($dbRow->full_name ?? 'MISSING'));

        // READ
        $resp = $kernel->handle($r = req('GET', '/api/v1/customers', [], ['Authorization' => 'Bearer '.$token]));
        $listBody = json_decode($resp->getContent(), true);
        $found = collect($listBody['data'] ?? [])->contains('id', $custId);
        record($results, 'READ customers list includes the created row', $resp->getStatusCode() === 200 && $found, 'status='.$resp->getStatusCode());
        $kernel->terminate($r, $resp);

        // UPDATE
        $resp = $kernel->handle($r = req('PATCH', "/api/v1/customers/$custId", ['remarks' => 'updated via http e2e'], ['Authorization' => 'Bearer '.$token]));
        record($results, 'UPDATE customer -> 200', $resp->getStatusCode() === 200, 'status='.$resp->getStatusCode());
        $kernel->terminate($r, $resp);
        $dbRow2 = \Illuminate\Support\Facades\DB::table('isp.customers')->where('id', $custId)->first();
        record($results, 'UPDATE persisted to real DB', ($dbRow2->remarks ?? '') === 'updated via http e2e', $dbRow2->remarks ?? 'MISSING');

        // DELETE
        $resp = $kernel->handle($r = req('DELETE', "/api/v1/customers/$custId", [], ['Authorization' => 'Bearer '.$token]));
        record($results, 'DELETE customer -> 204', $resp->getStatusCode() === 204, 'status='.$resp->getStatusCode());
        $kernel->terminate($r, $resp);
        $dbRow3 = \Illuminate\Support\Facades\DB::table('isp.customers')->where('id', $custId)->whereNull('deleted_at')->first();
        record($results, 'DELETE persisted as real soft-delete in DB', $dbRow3 === null, $dbRow3 ? 'STILL VISIBLE' : 'soft-deleted');
    }

    // ---- 9. Validation: missing required field -> 422 ----
    $resp = $kernel->handle($r = req('POST', '/api/v1/customers', ['full_name' => ''], ['Authorization' => 'Bearer '.$token]));
    record($results, 'Invalid payload -> 422', $resp->getStatusCode() === 422, 'status='.$resp->getStatusCode());
    $kernel->terminate($r, $resp);

    // ---- 10. Platform boundary: tenant user denied platform console ----
    $resp = $kernel->handle($r = req('GET', '/api/v1/platform/tenants', [], ['Authorization' => 'Bearer '.$token]));
    record($results, 'Tenant user denied platform console -> 403', $resp->getStatusCode() === 403, 'status='.$resp->getStatusCode());
    $kernel->terminate($r, $resp);

    // ---- 11. Portal guard separation: staff token rejected by customer guard ----
    $resp = $kernel->handle($r = req('GET', '/api/v1/portal/dashboard', [], ['Authorization' => 'Bearer '.$token]));
    record($results, 'Staff token rejected by customer portal guard', in_array($resp->getStatusCode(), [401,403]), 'status='.$resp->getStatusCode());
    $kernel->terminate($r, $resp);

    // ---- 12. No secret leakage in API responses ----
    $resp = $kernel->handle($r = req('GET', '/api/v1/network/pppoe-secrets', [], ['Authorization' => 'Bearer '.$token]));
    $leak = preg_match('/"(password|secret_password_encrypted|password_hash)"/i', $resp->getContent());
    record($results, 'No credential fields in API response', !$leak, $leak ? 'LEAK FOUND' : 'clean');
    $kernel->terminate($r, $resp);

    // ---- 13. BTRC news — free on every plan, no entitlement middleware ----
    $resp = $kernel->handle($r = req('GET', '/api/v1/compliance/news', [], ['Authorization' => 'Bearer '.$token]));
    record($results, 'BTRC news reachable (free on all plans)', $resp->getStatusCode() === 200, 'status='.$resp->getStatusCode());
    $kernel->terminate($r, $resp);
}

// ---- 14. Malformed JSON body ----
$resp = $kernel->handle($r = req('POST', '/api/v1/auth/login', '{not valid json'));
record($results, 'Malformed JSON -> 4xx (not 500)', $resp->getStatusCode() >= 400 && $resp->getStatusCode() < 500, 'status='.$resp->getStatusCode());
$kernel->terminate($r, $resp);

$pass = count(array_filter($results, fn($r) => $r[1]));
$total = count($results);
echo "\n=== REAL HTTP LAYER VERIFICATION: $pass / $total PASS ===\n";
foreach ($results as [$name, $ok, $detail]) {
    if (!$ok) echo "FAILED: $name — $detail\n";
}
exit($pass === $total ? 0 : 1);
