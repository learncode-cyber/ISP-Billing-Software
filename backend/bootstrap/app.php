<?php

use App\Http\Middleware\CheckEntitlement;
use App\Http\Middleware\CheckRevision;
use App\Http\Middleware\EnforceIdempotency;
use App\Http\Middleware\CheckPermission;
use App\Http\Middleware\RequirePlatformAdmin;
use App\Http\Middleware\SetTenantContext;
use Illuminate\Foundation\Application;
use Illuminate\Foundation\Configuration\Exceptions;
use Illuminate\Foundation\Configuration\Middleware;

/**
 * Laravel 11 application bootstrap. Registers the three custom middleware
 * as route aliases so routes/api.php can reference them by name:
 *   'tenant.context' → SetTenantContext (activates Postgres RLS session var)
 *   'entitlement'    → CheckEntitlement (subscription gate, 402)
 *   'permission'     → CheckPermission (RBAC gate, 403, resolves data_scope)
 *
 * The ordering guarantee (entitlement before permission) is expressed in
 * routes/api.php itself via the group nesting; these aliases just make the
 * middleware referenceable.
 */
return Application::configure(basePath: dirname(__DIR__))
    ->withRouting(
        api: __DIR__.'/../routes/api.php',
        commands: __DIR__.'/../routes/console.php',
        health: '/up',
    )
    ->withMiddleware(function (Middleware $middleware) {
        $middleware->alias([
            'tenant.context' => SetTenantContext::class,
            'entitlement' => CheckEntitlement::class,
            'permission' => CheckPermission::class,
            'platform.admin' => RequirePlatformAdmin::class,
            // Offline-first support: exactly-once processing of retried
            // offline mutations, and optimistic-concurrency conflict
            // detection for edits made while disconnected.
            'idempotency' => EnforceIdempotency::class,
            'revision' => CheckRevision::class,
        ]);

        // API routes are stateless (token auth), so no session/CSRF stack.
        $middleware->statefulApi();
    })
    ->withExceptions(function (Exceptions $exceptions) {
        // 402 (plan required) and 403 (permission) are thrown as HTTP
        // exceptions by the middleware and pass through with their status
        // and message intact — the frontend api.js distinguishes them.
    })
    ->create();
