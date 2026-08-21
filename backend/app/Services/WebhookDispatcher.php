<?php

namespace App\Services;

use Illuminate\Support\Facades\Crypt;
use Illuminate\Support\Facades\DB;

/**
 * WebhookDispatcher (Blueprint Section 12). Fans out domain events
 * (payment.received, ticket.created, customer.disconnected, invoice.
 * overdue) to a tenant's registered webhook_subscriptions. Each delivery
 * is queued with retry/backoff and HMAC-signed so the receiver can verify
 * authenticity. Deliveries are logged to integrations.webhook_deliveries
 * for observability.
 */
class WebhookDispatcher
{
    public function dispatch(string $tenantId, array $config, array $context): array
    {
        $eventType = $config['event_type'] ?? ($context['event_type'] ?? 'unknown');

        $subscriptions = DB::table('integrations.webhook_subscriptions')
            ->where('tenant_id', $tenantId)
            ->where('event_type', $eventType)
            ->where('is_active', true)
            ->get();

        $queued = 0;
        foreach ($subscriptions as $sub) {
            $deliveryId = (string) \Illuminate\Support\Str::uuid();

            DB::table('integrations.webhook_deliveries')->insert([
                'id' => $deliveryId,
                'tenant_id' => $tenantId,
                'subscription_id' => $sub->id,
                'payload_json' => json_encode(['event' => $eventType, 'data' => $context]),
                'status' => 'pending',
                'attempt_count' => 0,
                'next_retry_at' => now(),
                'created_at' => now(),
            ]);

            // The DeliverWebhook job signs the payload with the
            // subscription's HMAC secret and POSTs it, retrying with
            // exponential backoff on non-2xx, updating the delivery row.
            \App\Jobs\Integrations\DeliverWebhook::dispatch($deliveryId)->onQueue('webhooks');
            $queued++;
        }

        return ['webhooks_queued' => $queued];
    }
}
