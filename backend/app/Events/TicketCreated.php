<?php

namespace App\Events;

use App\Models\Support\Ticket;
use Illuminate\Foundation\Events\Dispatchable;

class TicketCreated
{
    use Dispatchable;

    public function __construct(public Ticket $ticket) {}
}
