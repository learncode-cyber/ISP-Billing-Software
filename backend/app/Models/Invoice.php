<?php

namespace App\Models;

use App\Models\Concerns\BelongsToTenant;
use Illuminate\Database\Eloquent\Model;

class Invoice extends Model
{
    use BelongsToTenant;

    protected $table = 'billing.invoices';
    protected $keyType = 'string';
    public $incrementing = false;

    protected $fillable = [
        'tenant_id', 'customer_service_id', 'invoice_no', 'billing_period_month',
        'billing_period_year', 'amount_due', 'discount_amount', 'previous_due_carried',
        'total_due', 'total_paid', 'status', 'due_date', 'generated_at', 'generated_by',
    ];

    public function customerService()
    {
        return $this->belongsTo(CustomerService::class, 'customer_service_id');
    }

    public function payments()
    {
        return $this->hasMany(Payment::class, 'invoice_id');
    }
}
