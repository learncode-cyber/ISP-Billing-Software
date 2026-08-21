<?php

namespace App\Events;

use App\Models\Payment;
use Illuminate\Foundation\Events\Dispatchable;

/**
 * Domain events that the Automation Engine listens for. Controllers fire
 * these; a single AutomationEventSubscriber (below in this file's
 * namespace docs) routes them into AutomationEngine::handleEvent so the
 * engine stays decoupled from every controller.
 */
class PaymentReceived
{
    use Dispatchable;

    public function __construct(public Payment $payment) {}
}
