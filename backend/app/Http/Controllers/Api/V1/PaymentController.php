<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use App\Models\Invoice;
use App\Models\Payment;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;

/**
 * Reproduces the audit's verified Payment modal exactly:
 * Due Amount (readonly), Pay Amount (prefilled = due), Discount Amount,
 * Description (auto-generated), Submit Payment.
 *
 * Side effects preserved from the audit's Customer Lifecycle (Section 8):
 * paying clears "Due" status, which prevents/reverses the auto-disconnect
 * cron, and the payment appears in Customer Ledger + Accounts Statement.
 * The invoice status recalculation itself happens in the DB trigger
 * (billing.recalc_invoice_on_payment, see 007_billing.sql) so it can
 * never drift out of sync regardless of which code path inserts a payment
 * row (this controller, a payment-gateway webhook, or a bulk import).
 */
class PaymentController extends Controller
{
    public function store(Request $request, Invoice $invoice)
    {
        $validated = $request->validate([
            'amount' => 'required|numeric|min:0',
            'discount_amount' => 'nullable|numeric|min:0',
            'method' => 'required|in:cash,bkash,nagad,sslcommerz,stripe,bank,other',
            'transaction_reference' => 'nullable|string|max:150',
            'description' => 'nullable|string',
        ]);

        $customer = $invoice->customerService->customer;

        $description = $validated['description'] ?? sprintf(
            'Bill collection for %s-%d From Customer %s',
            \Carbon\Carbon::create()->month($invoice->billing_period_month)->format('F'),
            $invoice->billing_period_year,
            $customer->full_name
        );

        $payment = DB::transaction(function () use ($validated, $invoice, $request, $description) {
            $payment = Payment::create([
                'invoice_id' => $invoice->id,
                'amount' => $validated['amount'],
                'discount_amount' => $validated['discount_amount'] ?? 0,
                'method' => $validated['method'],
                'transaction_reference' => $validated['transaction_reference'] ?? null,
                'collector_id' => $request->user()->id, // "Billing Person" in audit
                'description' => $description,
                'paid_at' => now(),
            ]);

            // Trigger auto-recalculates invoice.status; if it flips to 'paid'
            // and the automation rule "Payment Received -> Reconnect" is
            // active for this tenant (Phase 4), the automation engine picks
            // it up from here via a domain event, not a direct call — keeps
            // this controller decoupled from network operations.
            event(new \App\Events\PaymentReceived($payment));

            return $payment;
        });

        return response()->json($payment->fresh('invoice'), 201);
    }
}
