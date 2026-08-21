<?php

namespace App\Console;

use Illuminate\Console\Scheduling\Schedule;
use Illuminate\Foundation\Console\Kernel as ConsoleKernel;
use Illuminate\Support\Facades\DB;

/**
 * Central scheduler. Runs per-tenant recurring work by iterating active
 * tenants and dispatching a tenant-scoped job for each — so one tenant's
 * heavy run never blocks another's, and every job sets its own RLS
 * context. Reproduces the audit's verified daily ~10:00 AM auto-disconnect
 * cron, and adds analytics refresh + BTRC news ingestion.
 */
class Kernel extends ConsoleKernel
{
    protected function schedule(Schedule $schedule): void
    {
        // 1. Daily auto-disconnect (verified behavior) — 10:00 AM, per tenant.
        //    Routed through the Automation Engine's 'schedule.daily' rules so
        //    a tenant that disabled the rule is respected.
        $schedule->call(function () {
            foreach ($this->activeTenantIds() as $tenantId) {
                \App\Jobs\Automation\RunScheduledRules::dispatch($tenantId, 'schedule.daily')
                    ->onQueue('automation');
            }
        })->dailyAt('10:00')->name('automation-daily')->withoutOverlapping();

        // 2. Analytics materialized-view refresh — every 15 minutes.
        $schedule->call(function () {
            DB::statement('SELECT analytics.refresh_all_materialized_views()');
        })->everyFifteenMinutes()->name('analytics-refresh')->withoutOverlapping();

        // 3. MikroTik/RADIUS session-state sync — every 5 minutes, per router.
        $schedule->call(function () {
            foreach (DB::table('network.mikrotik_routers')->whereNull('deleted_at')->pluck('id') as $routerId) {
                \App\Jobs\Network\SyncRouterState::dispatch($routerId)->onQueue('network');
            }
        })->everyFiveMinutes()->name('mikrotik-sync')->withoutOverlapping();

        // 4. OLT signal/LOS polling — every 10 minutes, per OLT.
        $schedule->call(function () {
            foreach (DB::table('network.olt_devices')->whereNull('deleted_at')->pluck('id') as $oltId) {
                \App\Jobs\Network\PollOnuSignalLevels::dispatch($oltId)->onQueue('network');
            }
        })->everyTenMinutes()->name('olt-poll')->withoutOverlapping();

        // 5. Network monitoring pings — every minute, per active target.
        $schedule->job(new \App\Jobs\Network\RunMonitoringChecks())->everyMinute()->name('monitoring-checks');

        // 6. BTRC regulatory news ingestion — hourly (platform-level).
        $schedule->call(fn () => app(\App\Services\Compliance\BtrcNewsIngestionService::class)->ingest())
            ->hourly()->name('btrc-news-ingest')->withoutOverlapping();

        // 7. AI churn prediction batch — nightly, per tenant with the feature.
        $schedule->call(function () {
            foreach ($this->activeTenantIds() as $tenantId) {
                if (app(\App\Services\EntitlementResolver::class)->isEnabled($tenantId, 'ai.churn_prediction')) {
                    \App\Jobs\Ai\PredictChurn::dispatch($tenantId)->onQueue('ai');
                }
            }
        })->dailyAt('02:00')->name('ai-churn-batch');

        // 8. Monthly invoice generation — 1st of month, per tenant.
        $schedule->call(function () {
            foreach ($this->activeTenantIds() as $tenantId) {
                \App\Jobs\Billing\GenerateMonthlyInvoices::dispatch($tenantId)->onQueue('billing');
            }
        })->monthlyOn(1, '00:30')->name('monthly-billing')->withoutOverlapping();
    }

    private function activeTenantIds(): array
    {
        return DB::table('tenancy.tenants')
            ->whereIn('status', ['active', 'trial'])
            ->whereNull('deleted_at')
            ->pluck('id')->all();
    }

    protected function commands(): void
    {
        $this->load(__DIR__.'/Commands');
    }
}
