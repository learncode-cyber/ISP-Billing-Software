<?php

namespace App\Models;

use App\Models\Concerns\BelongsToTenant;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\SoftDeletes;

class CustomerService extends Model
{
    use BelongsToTenant, SoftDeletes;

    protected $table = 'isp.customer_services';
    protected $keyType = 'string';
    public $incrementing = false;

    protected $fillable = [
        'tenant_id', 'customer_id', 'service_type', 'package_id', 'monthly_bill',
        'effective_from_current_month', 'running_month_paid_amount',
        'connection_fee_paid', 'disconnect_day', 'status',
    ];

    public function customer()
    {
        return $this->belongsTo(Customer::class, 'customer_id');
    }

    public function package()
    {
        return $this->belongsTo(Package::class, 'package_id');
    }

    public function pppoeSecret()
    {
        return $this->hasOne(\App\Models\Network\PppoeSecret::class, 'customer_service_id');
    }

    public function invoices()
    {
        return $this->hasMany(Invoice::class, 'customer_service_id');
    }
}
