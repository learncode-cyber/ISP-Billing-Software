<?php

namespace App\Models\Reseller;

use App\Models\Concerns\BelongsToTenant;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\SoftDeletes;

class Reseller extends Model
{
    use BelongsToTenant, SoftDeletes;

    protected $table = 'reseller.resellers';
    protected $keyType = 'string';
    public $incrementing = false;

    protected $fillable = [
        'tenant_id', 'branch_id', 'parent_reseller_id', 'user_id', 'reseller_type',
        'name', 'mobile', 'email', 'address', 'commission_rule_id',
        'wallet_balance', 'credit_limit', 'status',
    ];

    public function commissionRule()
    {
        return $this->belongsTo(CommissionRule::class, 'commission_rule_id');
    }

    public function parent()
    {
        return $this->belongsTo(Reseller::class, 'parent_reseller_id');
    }

    public function customers()
    {
        return $this->hasMany(\App\Models\Customer::class, 'reseller_id');
    }
}
