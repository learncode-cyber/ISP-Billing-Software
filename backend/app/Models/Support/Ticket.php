<?php

namespace App\Models\Support;

use App\Models\Concerns\BelongsToTenant;
use Illuminate\Database\Eloquent\Model;

class Ticket extends Model
{
    use BelongsToTenant;

    protected $table = 'support.tickets';
    protected $keyType = 'string';
    public $incrementing = false;

    protected $fillable = [
        'tenant_id', 'ticket_no', 'customer_id', 'category_id', 'template_id',
        'priority', 'note', 'assigned_employee_id', 'status', 'sla_due_at',
        'resolved_at', 'resolution_time_minutes', 'csat_rating',
        'customer_sms_enabled', 'employee_sms_enabled', 'created_by',
    ];

    public function customer()
    {
        return $this->belongsTo(\App\Models\Customer::class, 'customer_id');
    }

    public function supportStaff()
    {
        return $this->belongsToMany(
            \App\Models\Hr\Employee::class,
            'support.ticket_support_staff',
            'ticket_id',
            'employee_id'
        );
    }

    public function replies()
    {
        return $this->hasMany(TicketReply::class, 'ticket_id')->orderBy('created_at');
    }
}
