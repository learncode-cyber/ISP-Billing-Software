<?php

namespace App\Jobs\Billing;

use Illuminate\Bus\Queueable;
use Illuminate\Contracts\Queue\ShouldQueue;
use Illuminate\Foundation\Bus\Dispatchable;
use Illuminate\Queue\InteractsWithQueue;
use Illuminate\Queue\SerializesModels;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;

/**
 * GenerateMonthlyInvoices — the audit's [INFERRED] bill generation, now an
 * explicit, idempotent queued job. For a tenant, for the current billing
 * period, creates one invoice per active customer_service that doesn't yet
 * have one for the period (the UNIQUE(tenant, service, year, month)
 * constraint makes re-runs safe — duplicates are skipped, not errored).
 * Carries forward previous_due from the customer record.
 */
class GenerateMonthlyInvoices implements ShouldQueue
{
    use Dispatchable, InteractsWithQueue, Queueable, SerializesModels;

    public function __construct(public string $tenantId, public ?int $month = null, public ?int $year = null) {}

    public function handle(): void
    {
        DB::statement("SELECT set_config('app.current_tenant_id', ?, false)", [$this->tenantId]);

        $month = $this->month ?? (int) now()->format('n');
        $year = $this->year ?? (int) now()->format('Y');

        $services = DB::table('isp.customer_services as cs')
            ->join('isp.customers as c', 'c.id', '=', 'cs.customer_id')
            ->where('cs.tenant_id', $this->tenantId)
            ->where('cs.status', 'active')
            ->whereNull('cs.deleted_at')
            ->select('cs.id', 'cs.monthly_bill', 'c.previous_due', 'c.id as customer_id')
            ->get();

        foreach ($services as $svc) {
            // Skip if an invoice for this period already exists (idempotent).
            $exists = DB::table('billing.invoices')
                ->where('customer_service_id', $svc->id)
                ->where('billing_period_year', $year)
                ->where('billing_period_month', $month)
                ->exists();
            if ($exists) continue;

            $invoiceNo = $this->nextInvoiceNo($this->tenantId);
            $totalDue = (float) $svc->monthly_bill + (float) $svc->previous_due;

            DB::table('billing.invoices')->insert([
                'id' => (string) Str::uuid(),
                'tenant_id' => $this->tenantId,
                'customer_service_id' => $svc->id,
                'invoice_no' => $invoiceNo,
                'billing_period_month' => $month,
                'billing_period_year' => $year,
                'amount_due' => $svc->monthly_bill,
                'previous_due_carried' => $svc->previous_due,
                'total_due' => $totalDue,
                'status' => 'unpaid',
                'due_date' => now()->startOfMonth()->addDays(9)->toDateString(),
                'generated_at' => now(),
                'generated_by' => 'system',
                'created_at' => now(),
                'updated_at' => now(),
            ]);
        }
    }

    private function nextInvoiceNo(string $tenantId): string
    {
        return DB::transaction(function () use ($tenantId) {
            $row = DB::table('billing.invoice_sequences')->where('tenant_id', $tenantId)->lockForUpdate()->first();
            if (! $row) {
                DB::table('billing.invoice_sequences')->insert(['tenant_id' => $tenantId, 'next_number' => 1]);
                $next = 1;
            } else {
                $next = $row->next_number;
            }
            DB::table('billing.invoice_sequences')->where('tenant_id', $tenantId)->update(['next_number' => $next + 1]);
            return 'INV-'.date('Ym').'-'.str_pad((string) $next, 6, '0', STR_PAD_LEFT);
        });
    }
}
