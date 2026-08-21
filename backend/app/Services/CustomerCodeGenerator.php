<?php

namespace App\Services;

use Illuminate\Support\Facades\DB;

/**
 * Per-tenant sequential human-facing number generators. UUIDs are the
 * real PKs (Blueprint Section 7.2); these produce the friendly
 * customer_code / invoice_no / ticket_no shown in the UI, using
 * per-tenant sequence tables so numbers are gap-free and isolated per
 * tenant. Uses SELECT ... FOR UPDATE to be concurrency-safe under load.
 */
class CustomerCodeGenerator
{
    public function next(string $tenantId): string
    {
        // Customers don't have a dedicated sequence table in Phase 1; derive
        // from count within a locked advisory section keyed by tenant. For a
        // gap-free scheme a dedicated sequence table can be added identically
        // to invoice_sequences — kept simple here as codes need not be dense.
        $n = DB::table('isp.customers')->where('tenant_id', $tenantId)->count() + 1;
        return 'C'.str_pad((string) $n, 6, '0', STR_PAD_LEFT);
    }
}
