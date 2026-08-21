<?php

namespace App\Services\Payments;

use Illuminate\Support\Facades\DB;

/**
 * NagadGateway — concrete adapter, identical shape to BkashGateway.
 * The provider-specific HTTP API calls are the integration boundary;
 * the contract + shared confirmPayment path (in PaymentGatewayManager)
 * are complete, so wiring one gateway wires the pattern for all.
 */
class NagadGateway implements PaymentGatewayContract
{
    public function __construct(private array $credentials, private bool $sandbox) {}

    public function initiate(string $tenantId, string $invoiceId, float $amount): array
    {
        $txnId = (string) \Illuminate\Support\Str::uuid();
        DB::table('billing.payment_gateway_transactions')->insert([
            'id' => $txnId,
            'tenant_id' => $tenantId,
            'gateway_id' => DB::table('billing.payment_gateways')
                ->where('tenant_id', $tenantId)->where('provider', strtolower('Nagad'))->value('id'),
            'invoice_id' => $invoiceId,
            'amount' => $amount,
            'status' => 'initiated',
            'initiated_at' => now(),
        ]);
        return ['transaction_id' => $txnId, 'redirect_url' => null, 'message' => 'Nagad API integration pending.'];
    }

    public function handleCallback(array $payload): PaymentResult
    {
        return new PaymentResult(success: false, message: 'Pending integration.');
    }
}
