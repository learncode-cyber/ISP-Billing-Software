<?php

namespace App\Services;

use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;

/**
 * TicketAutoCreator — creates a support ticket from an automation action
 * (e.g. "ONU LOS -> Ticket"). Resolves the affected customer from the
 * trigger context and files a ticket in the configured category/priority.
 */
class TicketAutoCreator
{
    public function create(string $tenantId, array $config, array $context): array
    {
        $customerId = $context['customer_id'] ?? null;
        if (! $customerId && isset($context['onu_device_id'])) {
            $customerId = DB::table('network.onu_devices as o')
                ->join('isp.customer_services as cs', 'cs.id', '=', 'o.customer_service_id')
                ->where('o.id', $context['onu_device_id'])->value('cs.customer_id');
        }
        if (! $customerId) return ['created' => false, 'reason' => 'no_customer'];

        $ticketNo = app(TicketCodeGenerator::class)->next($tenantId);
        DB::table('support.tickets')->insert([
            'id' => (string) Str::uuid(),
            'tenant_id' => $tenantId,
            'ticket_no' => $ticketNo,
            'customer_id' => $customerId,
            'priority' => $config['priority'] ?? 'high',
            'note' => 'Auto-created by automation: '.($config['category'] ?? 'system'),
            'status' => 'pending',
            'created_at' => now(),
            'updated_at' => now(),
        ]);

        return ['created' => true, 'ticket_no' => $ticketNo];
    }
}
