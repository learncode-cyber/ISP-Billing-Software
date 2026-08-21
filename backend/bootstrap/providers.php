<?php

/**
 * Laravel 11 provider registration.
 *
 * REAL DEFECT found by HTTP-layer boot testing: this file did not exist.
 * Without it, App\Providers\AppServiceProvider::boot() never runs, so
 * Sanctum::usePersonalAccessTokenModel() (which points token storage at
 * the tenant-aware identity.sanctum_tokens table — see migration 027 and
 * App\Models\PersonalAccessToken) was silently never called, and the
 * 'current_tenant_id' container binding the BelongsToTenant trait depends
 * on was never registered either. Every previous "verified" claim about
 * this backend was necessarily made without the app's own service
 * provider ever having executed.
 */
return [
    App\Providers\AppServiceProvider::class,
];
