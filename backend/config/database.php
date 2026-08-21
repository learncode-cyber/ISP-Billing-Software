<?php

/**
 * Database connections (Blueprint Section 4). TWO PostgreSQL connections
 * to the SAME database, differing only in the DB role they log in as:
 *
 *   'pgsql'          → arq_app_role. RLS-enforced. Used by ALL tenant-
 *                      facing request paths. This is the default.
 *   'pgsql_platform' → arq_platform_admin_role (BYPASSRLS). Used ONLY by
 *                      the Super Admin console service code for cross-
 *                      tenant analytics/administration. Never used on any
 *                      tenant-facing route.
 *
 * The separation is enforced structurally: tenant code never selects the
 * 'pgsql_platform' connection, so even a bug in tenant code cannot bypass
 * RLS — it simply has no route to the BYPASSRLS role.
 */
return [
    'default' => env('DB_CONNECTION', 'pgsql'),

    'connections' => [
        'pgsql' => [
            'driver' => 'pgsql',
            'host' => env('DB_HOST', '127.0.0.1'),
            'port' => env('DB_PORT', '5432'),
            'database' => env('DB_DATABASE', 'arq_isp_os'),
            'username' => env('DB_USERNAME', 'arq_app_role'),
            'password' => env('DB_PASSWORD', ''),
            'charset' => 'utf8',
            'prefix' => '',
            'schema' => 'public',
            'sslmode' => env('DB_SSLMODE', 'prefer'),
        ],

        'pgsql_platform' => [
            'driver' => 'pgsql',
            'host' => env('DB_HOST', '127.0.0.1'),
            'port' => env('DB_PORT', '5432'),
            'database' => env('DB_DATABASE', 'arq_isp_os'),
            'username' => env('DB_PLATFORM_USERNAME', 'arq_platform_admin_role'),
            'password' => env('DB_PLATFORM_PASSWORD', ''),
            'charset' => 'utf8',
            'prefix' => '',
            'schema' => 'public',
            'sslmode' => env('DB_SSLMODE', 'prefer'),
        ],
    ],

    'redis' => [
        'client' => 'predis',
        'default' => [
            'host' => env('REDIS_HOST', '127.0.0.1'),
            'port' => env('REDIS_PORT', 6379),
            'database' => 0,
        ],
    ],
];
