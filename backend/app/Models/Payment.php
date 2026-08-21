<?php

namespace App\Models;

use App\Models\Concerns\BelongsToTenant;
use Illuminate\Database\Eloquent\Model;

class Payment extends Model
{
    use BelongsToTenant;

    protected $table = 'billing.payments';
    protected $keyType = 'string';
    public $incrementing = false;
    public $timestamps = false; // created_at only, set by DB default

    protected $fillable = [
        'tenant_id', 'invoice_id', 'amount', 'discount_amount', 'method',
        'transaction_reference', 'collector_id', 'description', 'is_advance', 'paid_at',
    ];

    public function invoice()
    {
        return $this->belongsTo(Invoice::class, 'invoice_id');
    }

    public function collector()
    {
        return $this->belongsTo(User::class, 'collector_id');
    }
}
