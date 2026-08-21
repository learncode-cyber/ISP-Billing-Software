<?php

namespace App\Models\Identity;

use Illuminate\Database\Eloquent\Model;

class Role extends Model
{
    protected $table = 'identity.roles';
    protected $keyType = 'string';
    public $incrementing = false;
    protected $fillable = ['tenant_id', 'name', 'code', 'is_system'];
}
