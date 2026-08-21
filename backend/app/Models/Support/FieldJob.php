<?php

namespace App\Models\Support;

use App\Models\Concerns\BelongsToTenant;
use Illuminate\Database\Eloquent\Model;

class FieldJob extends Model
{
    use BelongsToTenant;

    protected $table = 'support.field_jobs';
    protected $keyType = 'string';
    public $incrementing = false;

    protected $fillable = [
        'tenant_id', 'ticket_id', 'customer_id', 'job_type', 'assigned_technician_id',
        'status', 'scheduled_at', 'check_in_at', 'check_in_lat', 'check_in_lng',
        'check_out_at', 'check_out_lat', 'check_out_lng', 'customer_signature_path',
    ];

    public function partsUsed()
    {
        return $this->hasMany(FieldJobPartUsed::class, 'field_job_id');
    }
}
