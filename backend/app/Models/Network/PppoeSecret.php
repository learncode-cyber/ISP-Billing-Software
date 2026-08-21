<?php

namespace App\Models\Network;

use App\Models\Concerns\BelongsToTenant;
use Illuminate\Database\Eloquent\Model;

class PppoeSecret extends Model
{
    use BelongsToTenant;

    protected $table = 'network.pppoe_secrets';
    protected $keyType = 'string';
    public $incrementing = false;

    protected $fillable = [
        'tenant_id', 'customer_service_id', 'router_id', 'username',
        'secret_password_encrypted', 'profile', 'ip_type', 'static_ip',
        'status', 'disabled_reason', 'is_online', 'last_synced_at',
    ];

    protected $hidden = ['secret_password_encrypted']; // never serialized into API responses
}
