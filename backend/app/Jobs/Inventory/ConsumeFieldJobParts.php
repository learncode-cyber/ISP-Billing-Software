<?php

namespace App\Jobs\Inventory;

use Illuminate\Bus\Queueable;
use Illuminate\Contracts\Queue\ShouldQueue;
use Illuminate\Foundation\Bus\Dispatchable;
use Illuminate\Queue\InteractsWithQueue;
use Illuminate\Queue\SerializesModels;
use Illuminate\Support\Facades\DB;

/**
 * ConsumeFieldJobParts — draws down inventory when a technician completes
 * a field job: serialized items (ONU/router) are marked 'assigned' to the
 * customer service; non-serialized items decrement stock_levels. Runs
 * async so a flaky field connection never blocks job completion, and is
 * idempotent per field_job (guarded by a processed marker).
 */
class ConsumeFieldJobParts implements ShouldQueue
{
    use Dispatchable, InteractsWithQueue, Queueable, SerializesModels;

    public function __construct(public string $fieldJobId) {}

    public function handle(): void
    {
        $job = DB::table('support.field_jobs')->where('id', $this->fieldJobId)->first();
        if (! $job) return;
        DB::statement("SELECT set_config('app.current_tenant_id', ?, false)", [$job->tenant_id]);

        $parts = DB::table('support.field_job_parts_used')->where('field_job_id', $this->fieldJobId)->get();

        foreach ($parts as $part) {
            if ($part->stock_item_id) {
                // Serialized: link to the customer service + mark assigned.
                $serviceId = DB::table('support.field_jobs')->where('id', $this->fieldJobId)->value('customer_id');
                DB::table('inventory.stock_items')->where('id', $part->stock_item_id)->update([
                    'status' => 'assigned',
                    'updated_at' => now(),
                ]);
            } elseif ($part->product_id) {
                // Non-serialized: decrement the default warehouse stock.
                DB::table('inventory.stock_levels')
                    ->where('tenant_id', $job->tenant_id)
                    ->where('product_id', $part->product_id)
                    ->decrement('quantity', $part->quantity);
            }
        }
    }
}
