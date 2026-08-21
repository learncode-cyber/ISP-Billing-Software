<?php

namespace App\Models\Accounting;

use App\Models\Concerns\BelongsToTenant;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\SoftDeletes;

class ExpenseEntry extends Model
{
    use BelongsToTenant, SoftDeletes;

    protected $table = 'accounting.expense_entries';
    protected $keyType = 'string';
    public $incrementing = false;
    public $timestamps = false;

    protected $fillable = [
        'tenant_id', 'head_id', 'sub_head_id', 'amount', 'description',
        'entry_date', 'approval_status', 'approved_by', 'created_by',
    ];

    public function head()
    {
        return $this->belongsTo(AccountHead::class, 'head_id');
    }
}
