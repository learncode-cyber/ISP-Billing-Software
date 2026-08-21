# Backend Skeleton — Phase 1

This is **not** a runnable Laravel project on its own (no `composer.json`
install was run — this environment has no Packagist access). These files
are the reviewable application-layer skeleton to be dropped into a fresh
`laravel new arq-isp-os-backend` install, in this exact structure, as the
first implementation step of Phase 1.

## What's here

```
backend/
├── app/
│   ├── Http/
│   │   ├── Middleware/
│   │   │   ├── SetTenantContext.php     -- activates Postgres RLS session var
│   │   │   ├── CheckEntitlement.php      -- subscription plan gate (402)
│   │   │   └── CheckPermission.php        -- RBAC gate (403) + data_scope
│   │   └── Controllers/Api/V1/
│   │       ├── CapabilitiesController.php -- single source of truth for frontend nav
│   │       ├── CustomerController.php      -- reproduces verified Customer module
│   │       └── PaymentController.php        -- reproduces verified Payment modal
│   ├── Models/
│   │   ├── Concerns/BelongsToTenant.php    -- app-layer tenant scope (defense-in-depth w/ RLS)
│   │   ├── Customer.php
│   │   ├── CustomerService.php
│   │   ├── Invoice.php
│   │   └── Payment.php
│   └── Services/
│       ├── EntitlementResolver.php          -- cached mirror of the SQL resolver function
│       └── MikrotikService.php                -- RouterOS integration boundary (queued)
└── routes/
    └── api.php                                -- Phase 1 route surface + middleware chain
```

## Middleware chain (applies to every tenant-facing route)

```
auth:sanctum → tenant.context → entitlement:<feature.key> → permission:<perm.key>
```

This is the literal implementation of Blueprint Section 5's rule:
**subscription entitlement AND user permission**, both required, entitlement
checked first so a plan-excluded feature returns 402 (upgrade prompt) rather
than 403 (permission denied) — the frontend needs to tell those apart.

## Not yet included (intentionally deferred to their own phases)

- Queue job bodies (`App\Jobs\Network\*`) — stubs referenced, not implemented;
  land with the actual RouterOS API client integration.
- `App\Events\PaymentReceived` listener wiring to the Automation Engine —
  Phase 4.
- `ComplianceNewsController`, `MikrotikController` — referenced in
  `routes/api.php`, implemented next alongside the OLT/RADIUS Phase 3 work
  and the BTRC news ingestion pipeline.
- Laravel boilerplate (`bootstrap/`, `config/`, Sanctum install, Horizon
  install) — standard framework setup, not project-specific, so not
  reproduced here; the `README` at the repo root notes it as a Phase 1 task.

## Security note carried over from the Blueprint

`network.mikrotik_routers.username_encrypted` / `password_encrypted` are
encrypted with Laravel's `Crypt` facade (AES-256-GCM, keyed from `APP_KEY`
sourced from the deployment's secrets manager). Decryption happens only
inside `MikrotikService`, only in-memory, only for the duration of a single
RouterOS API call — never logged, never serialized into any API response.
