<?php

namespace App\Http\Controllers\Api\V1\Portal;

use App\Http\Controllers\Controller;
use App\Services\Payments\PaymentGatewayManager;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;

/**
 * Public payment-gateway callback endpoint. Providers POST here after a
 * customer completes payment. Verified inside each adapter's
 * handleCallback via signature/HMAC — NOT session auth, since the caller
 * is the payment provider. Resolves the tenant from the staged
 * payment_gateway_transactions row, sets RLS context, then confirms.
 */
class GatewayCallbackController extends Controller
{
    public function handle(Request $request, string $provider, PaymentGatewayManager $gateways)
    {
        // The gateway reference in the payload maps to a staged txn row,
        // which carries the tenant_id — set RLS context from it before
        // any tenant-scoped write.
        $ref = $request->input('gateway_reference') ?? $request->input('paymentID') ?? $request->input('tran_id');
        $txn = DB::table('billing.payment_gateway_transactions')->where('gateway_reference', $ref)->first();

        if ($txn) {
            DB::statement("SELECT set_config('app.current_tenant_id', ?, false)", [$txn->tenant_id]);
        }

        // Delegate to the provider adapter. It verifies + calls
        // PaymentGatewayManager::confirmPayment on success.
        $result = $gateways->forTenant($txn->tenant_id ?? '', $provider)->handleCallback($request->all());

        return response()->json(['success' => $result->success, 'message' => $result->message]);
    }
}
