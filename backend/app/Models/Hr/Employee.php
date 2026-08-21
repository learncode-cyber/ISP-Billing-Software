<?php

namespace App\Models\Hr;

use App\Models\Concerns\BelongsToTenant;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\SoftDeletes;

class Employee extends Model
{
    use BelongsToTenant, SoftDeletes;

    protected $table = 'hr.employees';
    protected $keyType = 'string';
    public $incrementing = false;

    protected $fillable = [
        'tenant_id', 'branch_id', 'user_id', 'name', 'mobile', 'email', 'nid',
        'designation_id', 'department_id', 'joining_date', 'monthly_salary',
        'status', 'address',
    ];

    public function salaryPayments()
    {
        return $this->hasMany(SalaryPayment::class, 'employee_id');
    }
}
