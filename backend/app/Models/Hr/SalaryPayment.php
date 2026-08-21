<?php

namespace App\Models\Hr;

use App\Models\Concerns\BelongsToTenant;
use Illuminate\Database\Eloquent\Model;

class SalaryPayment extends Model
{
    use BelongsToTenant;

    protected $table = 'hr.salary_payments';
    protected $keyType = 'string';
    public $incrementing = false;
    public $timestamps = false;

    protected $fillable = [
        'tenant_id', 'employee_id', 'period_month', 'period_year',
        'payment_amount', 'conveyance_amount', 'punishment_amount',
        'description', 'paid_by', 'paid_at',
    ];

    public function employee()
    {
        return $this->belongsTo(Employee::class, 'employee_id');
    }
}
