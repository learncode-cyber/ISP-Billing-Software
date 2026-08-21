<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\SoftDeletes;

class Customer extends Model
{
    use HasFactory, SoftDeletes;

    protected $table = 'isp.customers';
    protected $keyType = 'string';
    public $incrementing = false;

    protected $fillable = [
        'tenant_id', 'branch_id', 'customer_code', 'full_name', 'mobile',
        'other_mobile', 'email', 'gender', 'onu_mac_address', 'nid_passport_no',
        'nid_passport_photo_path', 'address', 'fiber_code', 'agent_type',
        'connection_type', 'connection_date', 'zone_id', 'subzone_id',
        'destination_id', 'billing_person_id', 'status', 'remarks',
        'sms_notification_enabled', 'previous_due', 'temp_disconnect_day',
        'created_by',
    ];

    protected $casts = [
        'connection_date' => 'date',
        'sms_notification_enabled' => 'boolean',
        'previous_due' => 'decimal:2',
    ];

    // NOTE: no global tenant scope is defined here on purpose — RLS at the
    // database layer is the authoritative isolation boundary (Blueprint
    // Section 4). This model additionally applies a BootTenantScoped trait
    // (see App\Models\Concerns\BelongsToTenant) as defense-in-depth so a
    // developer forgetting a ->where('tenant_id', ...) clause is still
    // protected by RLS even if the app-layer scope trait is ever bypassed
    // by a raw query — and vice versa.
    use \App\Models\Concerns\BelongsToTenant;

    public function services()
    {
        return $this->hasMany(CustomerService::class, 'customer_id');
    }

    public function zone()
    {
        return $this->belongsTo(Zone::class, 'zone_id');
    }

    public function billingPerson()
    {
        return $this->belongsTo(User::class, 'billing_person_id');
    }
}
