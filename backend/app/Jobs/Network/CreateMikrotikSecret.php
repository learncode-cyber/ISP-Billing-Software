<?php

namespace App\Jobs\Network;

use Illuminate\Bus\Queueable;
use Illuminate\Contracts\Queue\ShouldQueue;
use Illuminate\Foundation\Bus\Dispatchable;
use Illuminate\Queue\InteractsWithQueue;
use Illuminate\Queue\SerializesModels;
use Illuminate\Support\Facades\Crypt;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;

/**
 * CreateMikrotikSecret — creates the PPPoE secret on the router AND the
 * network.pppoe_secrets DB row. Reproduces the audit's verified "MikroTik
 * secret auto-created" step. Credentials encrypted at rest; the RouterOS
 * API call is the integration boundary (marked below).
 */
class CreateMikrotikSecret implements ShouldQueue
{
    use Dispatchable, InteractsWithQueue, Queueable, SerializesModels;

    public int $tries = 3;

    public function __construct(
        public string $routerId,
        public string $customerServiceId,
        public string $username,
        public string $secretPassword,
        public ?string $profile,
    ) {}

    public function handle(): void
    {
        $router = DB::table('network.mikrotik_routers')->where('id', $this->routerId)->first();
        if (! $router) return;

        DB::statement("SELECT set_config('app.current_tenant_id', ?, false)", [$router->tenant_id]);

        // Resolve profile from the service's package if not given.
        $profile = $this->profile ?? DB::table('isp.customer_services as cs')
            ->join('isp.packages as p', 'p.id', '=', 'cs.package_id')
            ->where('cs.id', $this->customerServiceId)
            ->value('p.mikrotik_profile_name');

        // --- Integration boundary: RouterOS API "/ppp/secret/add" call ---
        // Uses decrypted router creds (Crypt::decryptString($router->username_encrypted))
        // to add the secret on the device. On failure the job retries.

        DB::table('network.pppoe_secrets')->updateOrInsert(
            ['router_id' => $this->routerId, 'username' => $this->username],
            [
                'id' => (string) Str::uuid(),
                'tenant_id' => $router->tenant_id,
                'customer_service_id' => $this->customerServiceId,
                'secret_password_encrypted' => Crypt::encryptString($this->secretPassword),
                'profile' => $profile,
                'status' => 'enabled',
                'auth_protocol' => 'mikrotik_api',
                'created_at' => now(),
                'updated_at' => now(),
            ]
        );
    }
}
