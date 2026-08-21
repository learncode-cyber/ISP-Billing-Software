<?php

namespace App\Models\Network;

use App\Models\Concerns\BelongsToTenant;
use Illuminate\Database\Eloquent\Model;

class PonPort extends Model
{
    use BelongsToTenant;

    protected $table = 'network.pon_ports';
    protected $keyType = 'string';
    public $incrementing = false;
    public $timestamps = false;

    protected $fillable = ['tenant_id', 'olt_device_id', 'port_label', 'max_onu_capacity'];

    public function onuDevices()
    {
        return $this->hasMany(OnuDevice::class, 'pon_port_id');
    }
}
