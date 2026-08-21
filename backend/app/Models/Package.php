<?php

namespace App\Models;

use App\Models\Concerns\BelongsToTenant;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\SoftDeletes;

class Package extends Model
{
    use BelongsToTenant, SoftDeletes;

    protected $table = 'isp.packages';
    protected $keyType = 'string';
    public $incrementing = false;

    protected $fillable = [
        'tenant_id', 'name', 'mikrotik_profile_name', 'monthly_bill',
        'bandwidth_down_mbps', 'bandwidth_up_mbps', 'is_active',
    ];
}
