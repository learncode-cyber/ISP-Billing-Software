<?php

namespace App\Models\Network;

use App\Models\Concerns\BelongsToTenant;
use Illuminate\Database\Eloquent\Model;

class OnuDevice extends Model
{
    use BelongsToTenant;

    protected $table = 'network.onu_devices';
    protected $keyType = 'string';
    public $incrementing = false;

    protected $fillable = [
        'tenant_id', 'pon_port_id', 'customer_service_id', 'serial_number',
        'mac_address', 'vlan_id', 'rx_power_dbm', 'tx_power_dbm', 'status', 'last_seen_at',
    ];

    public function customerService()
    {
        return $this->belongsTo(\App\Models\CustomerService::class, 'customer_service_id');
    }
}
