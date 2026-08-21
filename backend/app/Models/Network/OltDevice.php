<?php

namespace App\Models\Network;

use App\Models\Concerns\BelongsToTenant;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\SoftDeletes;

class OltDevice extends Model
{
    use BelongsToTenant, SoftDeletes;

    protected $table = 'network.olt_devices';
    protected $keyType = 'string';
    public $incrementing = false;

    protected $fillable = [
        'tenant_id', 'device_name', 'device_type', 'device_ip',
        'login_username_encrypted', 'password_encrypted', 'snmp_port',
        'snmp_community_encrypted', 'telnet_port', 'connection_status', 'last_checked_at',
    ];

    protected $hidden = ['login_username_encrypted', 'password_encrypted', 'snmp_community_encrypted'];

    public function ponPorts()
    {
        return $this->hasMany(PonPort::class, 'olt_device_id');
    }
}
