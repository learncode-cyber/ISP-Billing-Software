<?php

namespace App\Services\Payments;

use Illuminate\Support\Facades\DB;

/**
 * BkashGateway — representative concrete adapter (Nagad/SSLCommerz/Stripe
 * follow the identical shape). The actual bKash Checkout/Tokenized API
 * HTTP calls are the integration boundary, filled in during Phase 5
 * hardening with sandbox credentials; the contract + the shared
 * confirmPayment path are complete so wiring one gateway wires them all.
 */
class BkashGateway implements PaymentGatewayContract
{
    public function __construct(
        private array $credentials,
        private bool $sandbox,
    ) {}

    public function initiate(string $tenantId, string $invoiceId, float $amount): array
    {
        $txnId = (string) \Illuminate\Support\Str::uuid();

        DB::table('billing.payment_gateway_transactions')->insert([
            'id' => $txnId,
            'tenant_id' => $tenantId,
            'gateway_id' => DB::table('billing.payment_gateways')
                ->where('tenant_id', $tenantId)->where('provider', 'bkash')->value('id'),
            'invoice_id' => $invoiceId,
            'amount' => $amount,
            'status' => 'initiated',
            'initiated_at' => now(),
        ]);

        // bKash Create Payment API call -> returns bkashURL + paymentID.
        // Returned here for the portal/app to redirect the customer.
        return [
            'transaction_id' => $txnId,
            'redirect_url' => null, // set from bKash Create Payment response
            'message' => 'bKash API integration pending (Phase 5 hardening).',
        ];
    }

    public function handleCallback(array $payload): PaymentResult
    {
        // 1. Verify signature/execute payment against bKash Execute API.
        // 2. Look up the payment_gateway_transactions row by gateway_reference.
        // 3. On success -> PaymentGatewayManager::confirmPayment(...).
        // 4. On failure -> mark txn 'failed', return PaymentResult(false).
        return new PaymentResult(success: false, message: 'Pending integration.');
    }
}
