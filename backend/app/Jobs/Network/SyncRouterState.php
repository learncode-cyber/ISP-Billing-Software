<?php

namespace App\Jobs\Network;

use App\Services\MikrotikService;
use Illuminate\Bus\Queueable;
use Illuminate\Contracts\Queue\ShouldQueue;
use Illuminate\Foundation\Bus\Dispatchable;
use Illuminate\Queue\InteractsWithQueue;
use Illuminate\Queue\SerializesModels;
use Illuminate\Support\Facades\DB;

/**
 * SyncRouterState — refreshes Online/Offline/Static/Unmatched state for
 * one router by pulling live PPPoE data from RouterOS. Sets the tenant
 * RLS context first (jobs run outside an HTTP request, so no middleware
 * has set it). Idempotent: safe to re-run; upserts session rows.
 */
class SyncRouterState implements ShouldQueue
{
    use Dispatchable, InteractsWithQueue, Queueable, SerializesModels;

    public int $tries = 3;
    public int $backoff = 30;

    public function __construct(public string $routerId) {}

    public function handle(MikrotikService $mikrotik): void
    {
        $tenantId = DB::table('network.mikrotik_routers')->where('id', $this->routerId)->value('tenant_id');
        if (! $tenantId) return;

        DB::statement("SELECT set_config('app.current_tenant_id', ?, false)", [$tenantId]);
        $mikrotik->syncRouterState($this->routerId);
    }
}
