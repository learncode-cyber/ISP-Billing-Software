<?php

namespace App\Services;

use Illuminate\Support\Facades\DB;

class TicketCodeGenerator
{
    /** Gap-free per-tenant ticket number using the locked sequence row. */
    public function next(string $tenantId): string
    {
        return DB::transaction(function () use ($tenantId) {
            $row = DB::table('support.ticket_sequences')
                ->where('tenant_id', $tenantId)
                ->lockForUpdate()
                ->first();

            if (! $row) {
                DB::table('support.ticket_sequences')->insert(['tenant_id' => $tenantId, 'next_number' => 1]);
                $next = 1;
            } else {
                $next = $row->next_number;
            }

            DB::table('support.ticket_sequences')->where('tenant_id', $tenantId)
                ->update(['next_number' => $next + 1]);

            return 'T'.str_pad((string) $next, 6, '0', STR_PAD_LEFT);
        });
    }
}
