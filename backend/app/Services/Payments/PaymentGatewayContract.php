<?php

namespace App\Services\Payments;

/**
 * PaymentGatewayContract
 *
 * Blueprint Section 14: pluggable adapter pattern so every payment
 * channel (bKash, Nagad, SSLCommerz, Stripe) writes to the same
 * billing.payments table. Whether a payment came from a field collector's
 * cash entry or a customer's online bKash payment, collector attribution,
 * GL posting (via the payment DB trigger), and the "Payment Received ->
 * Reconnect" automation all behave identically downstream.
 *
 * Each concrete adapter implements exactly this interface; adding a new
 * gateway means one new class, zero changes to PaymentController /
 * automation / accounting.
 */
interface PaymentGatewayContract
{
    /**
     * Begin a payment: returns a redirect URL or token the customer
     * portal / mobile app sends the user to.
     */
    public function initiate(string $tenantId, string $invoiceId, float $amount): array;

    /**
     * Verify + finalize a gateway callback/webhook. On success, creates
     * the billing.payments row (which fires the invoice-recalc trigger)
     * and links it back to the payment_gateway_transactions record.
     */
    public function handleCallback(array $payload): PaymentResult;
}
