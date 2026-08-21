<?php

namespace App\Models\Support;

use App\Models\Concerns\BelongsToTenant;
use Illuminate\Database\Eloquent\Model;

class FieldJobPartUsed extends Model
{
    use BelongsToTenant;

    protected $table = 'support.field_job_parts_used';
    protected $keyType = 'string';
    public $incrementing = false;
    public $timestamps = false;

    protected $fillable = ['tenant_id', 'field_job_id', 'stock_item_id', 'product_id', 'quantity'];
}
