<?php

/**
 * Authentication guards (Blueprint Section 25 / 27). TWO separate guards,
 * deliberately never mixed:
 *   - 'sanctum' (default): staff / admin users (identity.users)
 *   - 'customer': customer self-service portal (isp.customer_portal_accounts)
 *
 * Keeping customer auth on its own guard + provider means a portal token
 * can never resolve to a staff identity or carry staff RBAC — a customer
 * is structurally incapable of reaching admin endpoints.
 */
return [
    'defaults' => [
        'guard' => 'sanctum',
        'passwords' => 'users',
    ],

    'guards' => [
        'sanctum' => [
            'driver' => 'sanctum',
            'provider' => 'users',
        ],
        'customer' => [
            'driver' => 'sanctum',
            'provider' => 'customers',
        ],
    ],

    'providers' => [
        'users' => [
            'driver' => 'eloquent',
            'model' => App\Models\User::class,
        ],
        'customers' => [
            'driver' => 'eloquent',
            'model' => App\Models\CustomerPortalAccount::class,
        ],
    ],

    'password_timeout' => 10800,
];
