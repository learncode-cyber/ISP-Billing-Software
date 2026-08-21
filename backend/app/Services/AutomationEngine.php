<?php

namespace App\Services;

use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Log;

/**
 * AutomationEngine
 *
 * Core executor for automation.rules. Two entry points:
 *   - runScheduled(): called by the Laravel scheduler for
 *     trigger_type = 'schedule.*' rules (e.g. the daily auto-disconnect,
 *     replacing the audit's verified cron job 1:1 in behavior).
 *   - handleEvent(): called by domain event listeners (PaymentReceived,
 *     TicketCreated, OnuLosDetected, StockLevelChanged, ...) for
 *     trigger_type = 'event.*' rules.
 *
 * Every run writes exactly one automation.executions row — success,
 * failed, or skipped (condition not met) — so tenant admins get full
 * visibility into what the engine did and why, mirroring the audit's
 * verified "No user found to disconnect." log message pattern rather
 * than silently doing nothing.
 */
class AutomationEngine
{
    public function runScheduled(string $tenantId, string $triggerType): void
    {
        $rules = DB::table('automation.rules')
            ->where('tenant_id', $tenantId)
            ->where('trigger_type', $triggerType)
            ->where('is_active', true)
            ->get();

        foreach ($rules as $rule) {
            $this->execute($rule);
        }
    }

    public function handleEvent(string $tenantId, string $eventType, array $context): void
    {
        $rules = DB::table('automation.rules')
            ->where('tenant_id', $tenantId)
            ->where('trigger_type', $eventType)
            ->where('is_active', true)
            ->get();

        foreach ($rules as $rule) {
            $this->execute($rule, $context);
        }
    }

    private function execute(object $rule, array $context = []): void
    {
        try {
            if (! $this->conditionMet($rule, $context)) {
                $this->log($rule, 'skipped', $context, null);
                return;
            }

            $result = $this->runAction($rule, $context);
            $this->log($rule, 'success', $context, $result);
        } catch (\Throwable $e) {
            Log::error("Automation rule {$rule->id} failed: {$e->getMessage()}");
            $this->log($rule, 'failed', $context, null, $e->getMessage());
        }
    }

    private function conditionMet(object $rule, array $context): bool
    {
        $conditions = json_decode($rule->condition_json, true) ?? [];
        // Condition evaluation is intentionally a small, explicit interpreter
        // over known condition keys (invoice.status, past_disconnect_day,
        // secret.status, etc.) rather than a generic expression evaluator —
        // avoids ever evaluating arbitrary user-supplied code server-side.
        return app(AutomationConditionEvaluator::class)->evaluate($conditions, $context);
    }

    private function runAction(object $rule, array $context): array
    {
        $config = json_decode($rule->action_config_json, true) ?? [];

        return match ($rule->action_type) {
            'mikrotik.disconnect' => app(MikrotikService::class)->bulkDisconnectDueCustomers($rule->tenant_id),
            'mikrotik.reconnect' => app(MikrotikService::class)->enableSecret($context['pppoe_secret_id'] ?? null),
            'sms.send' => app(\App\Services\Communication\SmsService::class)->sendFromTemplate($config['template'], $context),
            'ticket.create' => app(\App\Services\TicketAutoCreator::class)->create($rule->tenant_id, $config, $context),
            'notification.send' => app(\App\Services\NotificationService::class)->notifyRole($rule->tenant_id, $config['role'], $context),
            'webhook.call' => app(\App\Services\WebhookDispatcher::class)->dispatch($rule->tenant_id, $config, $context),
            default => ['note' => "Unknown action_type: {$rule->action_type}"],
        };
    }

    private function log(object $rule, string $status, array $context, ?array $result, ?string $error = null): void
    {
        DB::table('automation.executions')->insert([
            'id' => (string) \Illuminate\Support\Str::uuid(),
            'tenant_id' => $rule->tenant_id,
            'rule_id' => $rule->id,
            'trigger_context_json' => json_encode($context),
            'status' => $status,
            'result_json' => $result ? json_encode($result) : null,
            'error_message' => $error,
            'triggered_at' => now(),
        ]);
    }
}
