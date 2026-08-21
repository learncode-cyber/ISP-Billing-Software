<?php

namespace App\Jobs\Integrations;

use Illuminate\Bus\Queueable;
use Illuminate\Contracts\Queue\ShouldQueue;
use Illuminate\Foundation\Bus\Dispatchable;
use Illuminate\Queue\InteractsWithQueue;
use Illuminate\Queue\SerializesModels;
use Illuminate\Support\Facades\Crypt;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Http;

/**
 * DeliverWebhook — POSTs a webhook payload to the subscriber's URL,
 * HMAC-signed so the receiver can verify authenticity. Retries with
 * exponential backoff on non-2xx; updates the delivery row's status and
 * attempt count. Backoff schedule: 1m, 5m, 30m, 2h, 6h.
 */
class DeliverWebhook implements ShouldQueue
{
    use Dispatchable, InteractsWithQueue, Queueable, SerializesModels;

    public int $tries = 5;

    public function backoff(): array
    {
        return [60, 300, 1800, 7200, 21600];
    }

    public function __construct(public string $deliveryId) {}

    public function handle(): void
    {
        $delivery = DB::table('integrations.webhook_deliveries')->where('id', $this->deliveryId)->first();
        if (! $delivery || $delivery->status === 'delivered') return;

        DB::statement("SELECT set_config('app.current_tenant_id', ?, false)", [$delivery->tenant_id]);

        $sub = DB::table('integrations.webhook_subscriptions')->where('id', $delivery->subscription_id)->first();
        if (! $sub || ! $sub->is_active) return;

        $secret = Crypt::decryptString($sub->signing_secret_encrypted);
        $payload = $delivery->payload_json;
        $signature = hash_hmac('sha256', $payload, $secret);

        try {
            $res = Http::withHeaders(['X-ARQ-Signature' => $signature, 'Content-Type' => 'application/json'])
                ->timeout(15)->withBody($payload, 'application/json')->post($sub->target_url);

            DB::table('integrations.webhook_deliveries')->where('id', $this->deliveryId)->update([
                'response_status' => $res->status(),
                'attempt_count' => $delivery->attempt_count + 1,
                'status' => $res->successful() ? 'delivered' : 'pending',
                'delivered_at' => $res->successful() ? now() : null,
            ]);

            if (! $res->successful()) {
                $this->release($this->backoff()[$delivery->attempt_count] ?? 21600);
            }
        } catch (\Throwable $e) {
            DB::table('integrations.webhook_deliveries')->where('id', $this->deliveryId)
                ->update(['attempt_count' => $delivery->attempt_count + 1, 'status' => 'failed']);
            throw $e;
        }
    }
}
