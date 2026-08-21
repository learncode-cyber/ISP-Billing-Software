<?php

namespace App\Services\Payments;

use App\Models\Payment;
use Illuminate\Support\Facades\Crypt;
use Illuminate\Support\Facades\DB;

class PaymentResult
{
    public function __construct(
        public bool $success,
        public ?string $paymentId = null,
        public ?string $message = null,
    ) {}
}

/**
 * Resolves the correct adapter for a tenant's active gateway and provides
 * the shared "confirm -> create billing.payment" logic so no individual
 * adapter re-implements it (DRY, and keeps the money-touching code in one
 * auditable place).
 */
class PaymentGatewayManager
{
    /** @var array<string, class-string<PaymentGatewayContract>> */
    private array $adapters = [
        'bkash' => BkashGateway::class,
        'nagad' => NagadGateway::class,
        'sslcommerz' => SslcommerzGateway::class,
        'stripe' => StripeGateway::class,
    ];

    public function forTenant(string $tenantId, string $provider): PaymentGatewayContract
    {
        $config = DB::table('billing.payment_gateways')
            ->where('tenant_id', $tenantId)
            ->where('provider', $provider)
            ->where('is_active', true)
            ->first();

        if (! $config) {
            abort(400, "Payment gateway {$provider} is not configured/active for this tenant.");
        }

        $credentials = json_decode(Crypt::decryptString($config->credentials_encrypted), true);

        $class = $this->adapters[$provider];
        return new $class($credentials, (bool) $config->is_sandbox);
    }

    /**
     * Shared confirmation path — called by every adapter's handleCallback
     * once the gateway confirms funds. Creates the canonical
     * billing.payments row (triggering invoice recalculation) inside a
     * transaction alongside updating the gateway-transaction record.
     */
    public function confirmPayment(string $tenantId, object $gatewayTxn): Payment
    {
        return DB::transaction(function () use ($tenantId, $gatewayTxn) {
            $payment = Payment::create([
                'tenant_id' => $tenantId,
                'invoice_id' => $gatewayTxn->invoice_id,
                'amount' => $gatewayTxn->amount,
                'method' => $gatewayTxn->provider ?? 'other',
                'transaction_reference' => $gatewayTxn->gateway_reference,
                'collector_id' => null, // online self-service payment, no staff collector
                'description' => 'Online payment via '.$gatewayTxn->provider,
                'paid_at' => now(),
            ]);

            DB::table('billing.payment_gateway_transactions')
                ->where('id', $gatewayTxn->id)
                ->update(['payment_id' => $payment->id, 'status' => 'success', 'completed_at' => now()]);

            event(new \App\Events\PaymentReceived($payment)); // fires "Payment Received -> Reconnect" automation

            return $payment;
        });
    }
}
