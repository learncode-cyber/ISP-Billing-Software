<?php

namespace App\Listeners;

use App\Events\PaymentReceived;
use App\Events\TicketCreated;
use App\Services\AutomationEngine;
use Illuminate\Events\Dispatcher;

/**
 * AutomationEventSubscriber
 *
 * The single bridge between domain events and the Automation Engine. Each
 * controller fires a plain domain event (PaymentReceived, TicketCreated,
 * …); this subscriber translates it into the engine's event-type string
 * and hands off. Keeps controllers ignorant of automation entirely — they
 * just announce that something happened.
 *
 * Registered in AppServiceProvider::boot() via Event::subscribe().
 */
class AutomationEventSubscriber
{
    public function __construct(private AutomationEngine $engine) {}

    public function handlePaymentReceived(PaymentReceived $event): void
    {
        $payment = $event->payment;
        $invoice = $payment->invoice;

        $this->engine->handleEvent($payment->tenant_id, 'event.payment_received', [
            'payment_id' => $payment->id,
            'invoice_id' => $payment->invoice_id,
            'invoice.status' => $invoice?->status,
            'customer_service_id' => $invoice?->customer_service_id,
            'is_advance' => $payment->is_advance,
        ]);

        if ($payment->is_advance) {
            $this->engine->handleEvent($payment->tenant_id, 'event.advance_payment_received', [
                'payment_id' => $payment->id,
            ]);
        }
    }

    public function handleTicketCreated(TicketCreated $event): void
    {
        $ticket = $event->ticket;
        $this->engine->handleEvent($ticket->tenant_id, 'event.ticket_created', [
            'ticket_id' => $ticket->id,
            'customer_id' => $ticket->customer_id,
            'priority' => $ticket->priority,
        ]);
    }

    public function subscribe(Dispatcher $events): array
    {
        return [
            PaymentReceived::class => 'handlePaymentReceived',
            TicketCreated::class => 'handleTicketCreated',
        ];
    }
}
