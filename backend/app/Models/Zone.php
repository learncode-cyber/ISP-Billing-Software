<?php

namespace App\Models;

use App\Models\Concerns\BelongsToTenant;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\SoftDeletes;

class Zone extends Model
{
    use BelongsToTenant, SoftDeletes;

    protected $table = 'isp.zones';
    protected $keyType = 'string';
    public $incrementing = false;

    protected $fillable = ['tenant_id', 'name', 'is_active'];
}
