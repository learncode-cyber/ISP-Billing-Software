<?php

namespace App\Jobs\Network;

use Illuminate\Bus\Queueable;
use Illuminate\Contracts\Queue\ShouldQueue;
use Illuminate\Foundation\Bus\Dispatchable;
use Illuminate\Queue\InteractsWithQueue;
use Illuminate\Queue\SerializesModels;
use Illuminate\Support\Facades\DB;

/**
 * ToggleMikrotikSecret — enables/disables a PPPoE secret on the router
 * and updates its DB status. Backs the verified per-row Enable button and
 * the bulk Disconnect/Reconnect actions, plus the automation engine's
 * mikrotik.disconnect / mikrotik.reconnect actions.
 */
class ToggleMikrotikSecret implements ShouldQueue
{
    use Dispatchable, InteractsWithQueue, Queueable, SerializesModels;

    public int $tries = 3;

    public function __construct(
        public string $pppoeSecretId,
        public bool $enable,
        public ?string $reason,
    ) {}

    public function handle(): void
    {
        $secret = DB::table('network.pppoe_secrets')->where('id', $this->pppoeSecretId)->first();
        if (! $secret) return;

        DB::statement("SELECT set_config('app.current_tenant_id', ?, false)", [$secret->tenant_id]);

        // --- Integration boundary: RouterOS "/ppp/secret/set disabled=yes|no" ---

        DB::table('network.pppoe_secrets')->where('id', $this->pppoeSecretId)->update([
            'status' => $this->enable ? 'enabled' : 'disabled',
            'disabled_reason' => $this->enable ? null : $this->reason,
            'updated_at' => now(),
        ]);
    }
}
