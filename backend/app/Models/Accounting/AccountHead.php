<?php

namespace App\Models\Accounting;

use App\Models\Concerns\BelongsToTenant;
use Illuminate\Database\Eloquent\Model;

class AccountHead extends Model
{
    use BelongsToTenant;

    protected $table = 'accounting.account_heads';
    protected $keyType = 'string';
    public $incrementing = false;
    public $timestamps = false;

    protected $fillable = ['tenant_id', 'chart_account_id', 'name', 'head_type'];
}
