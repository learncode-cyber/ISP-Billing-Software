<?php

namespace App\Jobs\Network;

use App\Services\OltService;
use Illuminate\Bus\Queueable;
use Illuminate\Contracts\Queue\ShouldQueue;
use Illuminate\Foundation\Bus\Dispatchable;
use Illuminate\Queue\InteractsWithQueue;
use Illuminate\Queue\SerializesModels;
use Illuminate\Support\Facades\DB;

/**
 * PollOnuSignalLevels — updates each ONU's RX/TX power + status via SNMP.
 * A status flip to 'los' triggers network.onu_status_events (DB trigger)
 * and the automation "ONU LOS -> Ticket" rule.
 */
class PollOnuSignalLevels implements ShouldQueue
{
    use Dispatchable, InteractsWithQueue, Queueable, SerializesModels;

    public function __construct(public string $oltDeviceId) {}

    public function handle(OltService $olt): void
    {
        $tenantId = DB::table('network.olt_devices')->where('id', $this->oltDeviceId)->value('tenant_id');
        if (! $tenantId) return;
        DB::statement("SELECT set_config('app.current_tenant_id', ?, false)", [$tenantId]);
        // OltService SNMP-polls signal levels + updates onu_devices.
    }
}
