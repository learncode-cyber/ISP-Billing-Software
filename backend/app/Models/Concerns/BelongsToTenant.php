<?php

namespace App\Models\Concerns;

use Illuminate\Database\Eloquent\Builder;
use Illuminate\Support\Str;

/**
 * BelongsToTenant
 *
 * App-layer tenant scoping, applied on top of (never instead of) the
 * PostgreSQL RLS policies in 005_rls_policies.sql. Blueprint Section 4:
 * "Backend authorization MUST enforce tenant isolation" — dual enforcement,
 * neither layer alone is considered sufficient.
 *
 * Every model representing a tenant-owned table MUST use this trait.
 * CI includes a lint check (Blueprint Section 32) asserting every table
 * with a tenant_id column has a corresponding model using this trait.
 */
trait BelongsToTenant
{
    protected static function bootBelongsToTenant(): void
    {
        static::addGlobalScope('tenant', function (Builder $builder) {
            if ($tenantId = app('current_tenant_id')) {
                $builder->where($builder->getModel()->getTable().'.tenant_id', $tenantId);
            }
        });

        static::creating(function ($model) {
            if (empty($model->tenant_id) && $tenantId = app('current_tenant_id')) {
                $model->tenant_id = $tenantId;
            }

            // REAL DEFECT found by HTTP-layer boot testing: every table in
            // this schema generates its UUID primary key via a PostgreSQL
            // DEFAULT (gen_random_uuid()), and every model here uses
            // `$incrementing = false`. Eloquent only auto-populates a
            // model's key after INSERT for auto-incrementing integer keys
            // via lastInsertId() — for non-incrementing keys it does
            // nothing, so `Model::create([...])` returned an instance
            // whose ->id was empty immediately after a successful insert.
            // Any code relying on the new ID right away (e.g.
            // CustomerProvisioningService creating a dependent
            // customer_services row) failed with a NOT NULL violation —
            // invisible to source review, only caught by actually running
            // the request through the real database.
            //
            // Generating the UUID here in PHP (rather than leaving it to
            // the DB default) fixes this everywhere at once: the ID is
            // known immediately, and it is still stored as a real UUID
            // primary key exactly as the schema expects.
            if (empty($model->{$model->getKeyName()}) && ! $model->incrementing) {
                $model->{$model->getKeyName()} = (string) Str::uuid();
            }
        });
    }
}
