<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\SoftDeletes;
use Illuminate\Foundation\Auth\User as Authenticatable;
use Laravel\Sanctum\HasApiTokens;

class User extends Authenticatable
{
    use HasApiTokens, SoftDeletes;

    protected $table = 'identity.users';
    protected $keyType = 'string';
    public $incrementing = false;

    protected $fillable = [
        'tenant_id', 'branch_id', 'name', 'username', 'email', 'password_hash',
        'phone', 'nid', 'address', 'avatar_path', 'status',
    ];

    protected $hidden = ['password_hash', 'two_factor_secret'];

    // tenant_id is intentionally NULLABLE for platform staff (Super Admin
    // console users) — this model does NOT use BelongsToTenant's
    // auto-assign-on-create behavior for that reason; tenant_id is set
    // explicitly wherever a tenant user is provisioned.

    public function roles()
    {
        return $this->belongsToMany(
            \App\Models\Identity\Role::class,
            'identity.user_roles',
            'user_id',
            'role_id'
        );
    }
}
