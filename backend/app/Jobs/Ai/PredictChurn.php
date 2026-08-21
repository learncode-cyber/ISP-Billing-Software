<?php

namespace App\Jobs\Ai;

use Illuminate\Bus\Queueable;
use Illuminate\Contracts\Queue\ShouldQueue;
use Illuminate\Foundation\Bus\Dispatchable;
use Illuminate\Queue\InteractsWithQueue;
use Illuminate\Queue\SerializesModels;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;

/**
 * PredictChurn — nightly per-tenant churn scoring. Computes a risk score
 * per active customer from signals already in the DB (payment lateness,
 * ticket volume, tenure, due amount) — a transparent heuristic baseline
 * that an ML model can later replace behind the same table. Writes to
 * ai.churn_predictions with explainability factors.
 */
class PredictChurn implements ShouldQueue
{
    use Dispatchable, InteractsWithQueue, Queueable, SerializesModels;

    public function __construct(public string $tenantId) {}

    public function handle(): void
    {
        DB::statement("SELECT set_config('app.current_tenant_id', ?, false)", [$this->tenantId]);

        $customers = DB::table('isp.customers')
            ->where('tenant_id', $this->tenantId)
            ->where('status', 'active')
            ->whereNull('deleted_at')
            ->get();

        foreach ($customers as $c) {
            // Signals (all already tenant-scoped by RLS):
            $overdueInvoices = DB::table('billing.invoices as i')
                ->join('isp.customer_services as cs', 'cs.id', '=', 'i.customer_service_id')
                ->where('cs.customer_id', $c->id)->where('i.status', 'unpaid')->count();
            $ticketCount = DB::table('support.tickets')->where('customer_id', $c->id)->count();

            // Transparent heuristic 0-100; documented factors for explainability.
            $score = min(100, ($overdueInvoices * 25) + ($ticketCount * 8) + ((float) $c->previous_due > 0 ? 15 : 0));
            $band = $score >= 60 ? 'high' : ($score >= 30 ? 'medium' : 'low');

            DB::table('ai.churn_predictions')->updateOrInsert(
                ['tenant_id' => $this->tenantId, 'customer_id' => $c->id, 'predicted_at' => now()->toDateString()],
                [
                    'id' => (string) Str::uuid(),
                    'churn_risk_score' => $score,
                    'risk_band' => $band,
                    'top_factors_json' => json_encode([
                        'overdue_invoices' => $overdueInvoices,
                        'ticket_count' => $ticketCount,
                        'has_previous_due' => (float) $c->previous_due > 0,
                    ]),
                    'predicted_at' => now(),
                ]
            );
        }
    }
}
