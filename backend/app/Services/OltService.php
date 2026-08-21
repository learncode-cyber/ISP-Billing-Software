<?php

namespace App\Services;

use App\Models\Network\OltDevice;
use Illuminate\Support\Facades\Crypt;

/**
 * OltService
 *
 * SNMP + Telnet integration boundary for OLT devices, per the audit's
 * verified device registration fields. Actual SNMP walk / Telnet session
 * implementation (vendor-specific MIBs for BDCOM/V-SOL/ZTE/Huawei/
 * Fiberhome) is deliberately not written here — this is the integration
 * boundary the `network` queue workers call into once a vendor SDK/SNMP
 * library is selected during Phase 3 hardening.
 */
class OltService
{
    public function checkConnection(OltDevice $device): array
    {
        $community = Crypt::decryptString($device->snmp_community_encrypted);

        // SNMP GET on sysDescr (.1.3.6.1.2.1.1.1.0) against $device->device_ip
        // using $community on $device->snmp_port. Returns reachable=true/false.
        // Implementation swapped in per-vendor as each is integration-tested.

        return ['reachable' => false, 'message' => 'SNMP client integration pending (Phase 3 hardening).'];
    }

    public function discoverOnusAsync(string $oltDeviceId): void
    {
        \App\Jobs\Network\DiscoverOnuDevices::dispatch($oltDeviceId)->onQueue('network');
        // Job walks PON interface + ONU tables via SNMP, upserts
        // network.pon_ports and network.onu_devices, and — where a
        // discovered ONU's MAC matches an isp.customers.onu_mac_address
        // on file — auto-links onu_devices.customer_service_id, closing
        // the Customer<->ONU mapping the audit could not verify live.
    }

    public function pollSignalLevels(string $oltDeviceId): void
    {
        \App\Jobs\Network\PollOnuSignalLevels::dispatch($oltDeviceId)->onQueue('network');
        // Updates onu_devices.rx_power_dbm/tx_power_dbm/status; a status
        // flip to 'los' triggers network.onu_status_events (DB trigger)
        // and, once Phase 4's Automation Engine lands, the seeded
        // "ONU LOS -> Ticket" rule.
    }
}
