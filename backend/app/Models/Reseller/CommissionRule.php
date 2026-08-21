<?php

namespace App\Models\Reseller;

use App\Models\Concerns\BelongsToTenant;
use Illuminate\Database\Eloquent\Model;

class CommissionRule extends Model
{
    use BelongsToTenant;

    protected $table = 'reseller.commission_rules';
    protected $keyType = 'string';
    public $incrementing = false;
    public $timestamps = false;

    protected $fillable = [
        'tenant_id', 'name', 'calculation_type', 'percentage',
        'fixed_amount', 'tier_config_json',
    ];

    protected $casts = ['tier_config_json' => 'array'];
}
