<?php

namespace App\Models\Crm;

use App\Models\Concerns\BelongsToTenant;
use Illuminate\Database\Eloquent\Model;

class Lead extends Model
{
    use BelongsToTenant;

    protected $table = 'crm.leads';
    protected $keyType = 'string';
    public $incrementing = false;

    protected $fillable = [
        'tenant_id', 'branch_id', 'source_id', 'full_name', 'mobile', 'email',
        'address', 'interested_package_id', 'assigned_to_user_id', 'status',
        'lost_reason', 'converted_customer_id',
    ];
}
