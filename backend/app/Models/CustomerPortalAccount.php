<?php

namespace App\Models;

use Illuminate\Foundation\Auth\User as Authenticatable;
use Laravel\Sanctum\HasApiTokens;

/**
 * CustomerPortalAccount — the auth model for the customer self-service
 * portal's `customer` guard. Deliberately separate from App\Models\User
 * (staff) so a portal token can never resolve to staff identity or carry
 * staff RBAC. Exposes customer_id, which every portal endpoint scopes to.
 */
class CustomerPortalAccount extends Authenticatable
{
    use HasApiTokens;

    protected $table = 'isp.customer_portal_accounts';
    protected $keyType = 'string';
    public $incrementing = false;

    protected $fillable = [
        'tenant_id', 'customer_id', 'login_identifier', 'password_hash', 'otp_secret', 'is_active',
    ];

    protected $hidden = ['password_hash', 'otp_secret'];

    public function getAuthPassword(): string
    {
        return $this->password_hash;
    }
}
