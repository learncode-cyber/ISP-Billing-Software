<?php

namespace App\Models\Inventory;

use App\Models\Concerns\BelongsToTenant;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\SoftDeletes;

class Product extends Model
{
    use BelongsToTenant, SoftDeletes;
    protected $table = 'inventory.products';
    protected $keyType = 'string';
    public $incrementing = false;
    protected $fillable = ['tenant_id','category_id','name','sku','unit','is_serialized','low_stock_threshold'];
}
