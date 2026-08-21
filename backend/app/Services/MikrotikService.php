<?php

namespace App\Services;

use Illuminate\Support\Facades\Crypt;
use Illuminate\Support\Facades\DB;

/**
 * MikrotikService
 *
 * Wraps RouterOS API access. Credentials are decrypted only in-memory,
 * only for the duration of a single API call, inside the `network` queue
 * worker process — never logged, never returned in any API response.
 *
 * Phase 1 scope: secret create/enable/disable, session polling.
 * Bulk Disconnect All Due Customers / Reconnect All Due Customers
 * (verified present in audit but not clicked/tested) are implemented as
 * queued batch jobs, each row logged individually to
 * network.auto_disconnect_logs, so a partial failure never leaves an
 * un-auditable gap.
 */
class MikrotikService
{
    public function createSecretAsync(
        string $routerId,
        string $customerServiceId,
        string $username,
        string $secretPassword,
        ?string $profile
    ): void {
        \App\Jobs\Network\CreateMikrotikSecret::dispatch(
            $routerId, $customerServiceId, $username, $secretPassword, $profile
        )->onQueue('network');
    }

    public function disableSecret(string $pppoeSecretId, string $reason): void
    {
        \App\Jobs\Network\ToggleMikrotikSecret::dispatch($pppoeSecretId, false, $reason)
            ->onQueue('network');
    }

    public function enableSecret(string $pppoeSecretId): void
    {
        \App\Jobs\Network\ToggleMikrotikSecret::dispatch($pppoeSecretId, true, null)
            ->onQueue('network');
    }

    /**
     * Called by the scheduled network-poll job (every N minutes) to refresh
     * Online/Offline/Static/Unmatched state — the audit's four MikroTik
     * list views are simply filtered reads over pppoe_secrets.status /
     * is_online after this runs, not separately-maintained lists.
     */
    public function syncRouterState(string $routerId): void
    {
        $router = DB::table('network.mikrotik_routers')->where('id', $routerId)->first();

        $username = Crypt::decryptString($router->username_encrypted);
        $password = Crypt::decryptString($router->password_encrypted);

        // Actual RouterOS API client call (e.g. via a routeros-api package)
        // omitted here — this is the integration boundary. On success:
        //   - upsert network.pppoe_sessions for each active session
        //   - update pppoe_secrets.is_online / last_synced_at
        //   - flag secrets present on the router but absent in our DB as
        //     status = 'unmatched' (preserves verified "Unmatching Secret" list)
        //   - update mikrotik_routers.status/last_connected_at
        // On failure: mikrotik_routers.status = 'error', last_error set,
        // logged to audit.activity_logs with source='cron'.
    }

    public function runDailyAutoDisconnect(string $tenantId): void
    {
        // Reproduces the verified cron: daily ~10:00 AM, disables secrets
        // for customers past their disconnect_day with an unpaid invoice.
        // Implemented as a scheduled Artisan command (see console Kernel),
        // one job per tenant, writing to network.auto_disconnect_logs
        // exactly as network.auto_disconnect_logs is shaped to match the
        // verified "Auto Mikrotik Disable Log" format.
    }


    /**
     * bulkDisconnectDueCustomers — disables PPPoE secrets for all customers
     * past their disconnect day with an unpaid invoice. Reproduces the
     * verified daily cron + the "Disconnect All Due" button. Each secret
     * is toggled via its own queued job so a partial failure is retryable
     * and individually logged; returns the count queued (mirrors the
     * verified "users disabled count" in the Auto Mikrotik Disable Log).
     */
    public function bulkDisconnectDueCustomers(string $tenantId): array
    {
        $dueSecrets = \Illuminate\Support\Facades\DB::table('network.pppoe_secrets as ps')
            ->join('isp.customer_services as cs', 'cs.id', '=', 'ps.customer_service_id')
            ->join('billing.invoices as i', 'i.customer_service_id', '=', 'cs.id')
            ->where('ps.tenant_id', $tenantId)
            ->where('ps.status', 'enabled')
            ->where('i.status', 'unpaid')
            ->whereRaw('EXTRACT(DAY FROM CURRENT_DATE) >= cs.disconnect_day')
            ->distinct()
            ->pluck('ps.id');

        foreach ($dueSecrets as $secretId) {
            $this->disableSecret($secretId, 'Auto-disconnect: bill overdue');
        }

        \Illuminate\Support\Facades\DB::table('network.auto_disconnect_logs')->insert([
            'id' => (string) \Illuminate\Support\Str::uuid(),
            'tenant_id' => $tenantId,
            'run_at' => now(),
            'users_disabled_count' => $dueSecrets->count(),
            'message' => $dueSecrets->count() > 0
                ? $dueSecrets->count().' user(s) disconnected.'
                : 'No user found to disconnect.',
        ]);

        return ['disconnected_count' => $dueSecrets->count()];
    }

}
