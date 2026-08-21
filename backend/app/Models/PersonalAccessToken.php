<?php

namespace App\Models;

use Illuminate\Support\Str;
use Laravel\Sanctum\PersonalAccessToken as SanctumPersonalAccessToken;

/**
 * Points Sanctum at identity.sanctum_tokens (migration 027) instead of
 * its own default unqualified table name, and stamps tenant_id onto every
 * new token at creation time from the authenticated tokenable — the one
 * piece of denormalization needed so RLS can protect this table like
 * every other tenant-owned table in the project.
 */
class PersonalAccessToken extends SanctumPersonalAccessToken
{
    protected $table = 'identity.sanctum_tokens';
    protected $keyType = 'int';

    protected static function booted(): void
    {
        static::creating(function (self $token) {
            $tokenable = $token->tokenable;
            if ($tokenable && isset($tokenable->tenant_id)) {
                $token->tenant_id = $tokenable->tenant_id;
            }
        });
    }
}
