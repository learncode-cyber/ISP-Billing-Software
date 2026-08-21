<?php

namespace App\Jobs\Automation;

use App\Services\AutomationEngine;
use Illuminate\Bus\Queueable;
use Illuminate\Contracts\Queue\ShouldQueue;
use Illuminate\Foundation\Bus\Dispatchable;
use Illuminate\Queue\InteractsWithQueue;
use Illuminate\Queue\SerializesModels;
use Illuminate\Support\Facades\DB;

/**
 * RunScheduledRules — runs all active schedule.* automation rules for one
 * tenant (e.g. the daily auto-disconnect). Dispatched per-tenant by the
 * scheduler so one tenant's run never blocks another's.
 */
class RunScheduledRules implements ShouldQueue
{
    use Dispatchable, InteractsWithQueue, Queueable, SerializesModels;

    public function __construct(public string $tenantId, public string $triggerType) {}

    public function handle(AutomationEngine $engine): void
    {
        DB::statement("SELECT set_config('app.current_tenant_id', ?, false)", [$this->tenantId]);
        $engine->runScheduled($this->tenantId, $this->triggerType);
    }
}
