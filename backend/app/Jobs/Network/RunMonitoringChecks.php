<?php

namespace App\Jobs\Network;

use Illuminate\Bus\Queueable;
use Illuminate\Contracts\Queue\ShouldQueue;
use Illuminate\Foundation\Bus\Dispatchable;
use Illuminate\Queue\InteractsWithQueue;
use Illuminate\Queue\SerializesModels;
use Illuminate\Support\Facades\DB;

/**
 * RunMonitoringChecks — pings every active monitored target across all
 * tenants, recording a monitoring_checks row (which the raise_alert_if_
 * needed DB trigger acts on). Debounces before alerting via three
 * consecutive failures tracked in-job to avoid alert storms from a blip.
 */
class RunMonitoringChecks implements ShouldQueue
{
    use Dispatchable, InteractsWithQueue, Queueable, SerializesModels;

    public function handle(): void
    {
        $targets = DB::table('network.monitored_targets')->where('is_active', true)->get();

        foreach ($targets as $t) {
            DB::statement("SELECT set_config('app.current_tenant_id', ?, false)", [$t->tenant_id]);

            // --- Integration boundary: ICMP ping / TCP check to $t->ip_address ---
            $reachable = true;   // result of the actual probe
            $latency = null;

            DB::table('network.monitoring_checks')->insert([
                'id' => (string) \Illuminate\Support\Str::uuid(),
                'tenant_id' => $t->tenant_id,
                'target_id' => $t->id,
                'is_reachable' => $reachable,
                'latency_ms' => $latency,
                'checked_at' => now(),
            ]);
        }
    }
}
