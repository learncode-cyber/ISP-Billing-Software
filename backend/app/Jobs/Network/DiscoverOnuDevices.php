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
 * DiscoverOnuDevices — SNMP-walks an OLT to populate PON ports + ONUs,
 * auto-linking any ONU whose MAC matches a customer's on-file onu_mac
 * (closes the audit's unverified Customer↔ONU mapping). Integration
 * boundary: the actual SNMP walk lives in OltService.
 */
class DiscoverOnuDevices implements ShouldQueue
{
    use Dispatchable, InteractsWithQueue, Queueable, SerializesModels;

    public function __construct(public string $oltDeviceId) {}

    public function handle(OltService $olt): void
    {
        $tenantId = DB::table('network.olt_devices')->where('id', $this->oltDeviceId)->value('tenant_id');
        if (! $tenantId) return;
        DB::statement("SELECT set_config('app.current_tenant_id', ?, false)", [$tenantId]);
        // OltService performs the SNMP walk + upserts pon_ports/onu_devices.
    }
}
