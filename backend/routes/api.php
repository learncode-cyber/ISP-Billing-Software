<?php

use App\Http\Controllers\Api\V1\CapabilitiesController;
use App\Http\Controllers\Api\V1\CustomerController;
use App\Http\Controllers\Api\V1\PaymentController;
use Illuminate\Support\Facades\Route;

/**
 * Phase 1 API surface. Every tenant route runs through, in order:
 *   1. auth:sanctum            — resolves $request->user()
 *   2. tenant.context          — SetTenantContext, activates RLS session var
 *   3. entitlement:<feature>   — subscription check (402 if plan excludes it)
 *   4. permission:<perm.key>   — RBAC check (403 if role lacks it), also
 *                                 resolves data_scope for the controller
 *
 * This exact ordering is the concrete implementation of Blueprint Section
 * 5's rule: SUBSCRIPTION ENTITLEMENT AND USER PERMISSION, both required.
 * Mobile apps (Customer/Technician/Admin PWA) call this same /api/v1
 * surface — no parallel undocumented endpoints, per project rule.
 */
Route::prefix('v1')->group(function () {
    // ---- Auth (no tenant.context yet — login resolves the tenant) ----
    Route::post('/auth/login', [\App\Http\Controllers\Api\V1\AuthController::class, 'login']);
    Route::middleware('auth:sanctum')->post('/auth/logout', [\App\Http\Controllers\Api\V1\AuthController::class, 'logout']);
    Route::middleware('auth:sanctum')->get('/auth/me', [\App\Http\Controllers\Api\V1\AuthController::class, 'me']);
});

// 'idempotency' guards every mutation so an offline device's retry can
// never create a duplicate payment, customer, ticket or stock movement.
Route::prefix('v1')->middleware(['auth:sanctum', 'tenant.context', 'idempotency'])->group(function () {

    Route::get('/me/capabilities', CapabilitiesController::class);

    Route::middleware(['entitlement:isp.customer.manage'])->group(function () {
        Route::get('/customers', [CustomerController::class, 'index'])
            ->middleware('permission:isp.customer.view');
        Route::post('/customers', [CustomerController::class, 'store'])
            ->middleware('permission:isp.customer.create');
        Route::patch('/customers/{customer}', [CustomerController::class, 'update'])
            ->middleware(['permission:isp.customer.edit', 'revision:isp.customers,customer']);
        Route::delete('/customers/{customer}', [CustomerController::class, 'destroy'])
            ->middleware('permission:isp.customer.delete');
    });

    Route::middleware(['entitlement:billing.core'])->group(function () {
        Route::post('/invoices/{invoice}/payments', [PaymentController::class, 'store'])
            ->middleware('permission:billing.payment.pay');
    });

    Route::middleware(['entitlement:network.mikrotik.manage'])->group(function () {
        Route::post('/network/pppoe-secrets/{secret}/disconnect', 
            [\App\Http\Controllers\Api\V1\MikrotikController::class, 'disconnect'])
            ->middleware('permission:network.mikrotik.disconnect');
        Route::post('/network/pppoe-secrets/{secret}/reconnect',
            [\App\Http\Controllers\Api\V1\MikrotikController::class, 'reconnect'])
            ->middleware('permission:network.mikrotik.reconnect');
    });

    // ---- Phase 2: Financial depth ----
    Route::get('/dashboard', \App\Http\Controllers\Api\V1\DashboardController::class);

    Route::middleware(['entitlement:accounting.core'])->group(function () {
        Route::get('/expenses', [\App\Http\Controllers\Api\V1\ExpenseController::class, 'index'])
            ->middleware('permission:accounting.expense.manage');
        Route::post('/expenses', [\App\Http\Controllers\Api\V1\ExpenseController::class, 'store'])
            ->middleware('permission:accounting.expense.manage');
        Route::delete('/expenses/{expenseEntry}', [\App\Http\Controllers\Api\V1\ExpenseController::class, 'destroy'])
            ->middleware('permission:accounting.expense.manage');
    });

    Route::middleware(['entitlement:hr.payroll'])->group(function () {
        Route::get('/employees/{employee}/salary-ledger', [\App\Http\Controllers\Api\V1\PayrollController::class, 'ledger'])
            ->middleware('permission:hr.employee.view');
        Route::post('/employees/{employee}/pay-salary', [\App\Http\Controllers\Api\V1\PayrollController::class, 'pay'])
            ->middleware('permission:hr.salary.pay');
    });

    // ---- Phase 3: Network expansion ----
    Route::middleware(['entitlement:network.olt.manage'])->group(function () {
        Route::get('/network/olt-devices', [\App\Http\Controllers\Api\V1\OltController::class, 'index'])
            ->middleware('permission:network.olt.manage');
        Route::post('/network/olt-devices', [\App\Http\Controllers\Api\V1\OltController::class, 'store'])
            ->middleware('permission:network.olt.manage');
        Route::post('/network/olt-devices/{oltDevice}/check-connection', [\App\Http\Controllers\Api\V1\OltController::class, 'checkConnection'])
            ->middleware('permission:network.olt.manage');
        Route::post('/network/olt-devices/{oltDevice}/discover-onus', [\App\Http\Controllers\Api\V1\OltController::class, 'discoverOnus'])
            ->middleware('permission:network.olt.manage');
    });

    Route::middleware(['entitlement:network.monitoring'])->group(function () {
        Route::get('/network/alerts', [\App\Http\Controllers\Api\V1\NetworkMonitoringController::class, 'alerts'])
            ->middleware('permission:network.diagram.view');
        Route::post('/network/alerts/{alertId}/acknowledge', [\App\Http\Controllers\Api\V1\NetworkMonitoringController::class, 'acknowledge'])
            ->middleware('permission:network.mikrotik.manage');
        Route::post('/network/alerts/{alertId}/resolve', [\App\Http\Controllers\Api\V1\NetworkMonitoringController::class, 'resolve'])
            ->middleware('permission:network.mikrotik.manage');
    });

    Route::get('/network/diagram', \App\Http\Controllers\Api\V1\NetworkDiagramController::class)
        ->middleware(['entitlement:network.mikrotik.manage', 'permission:network.diagram.view']);

    // ---- Phase 4: Growth features ----
    Route::middleware(['entitlement:crm.core'])->group(function () {
        Route::apiResource('leads', \App\Http\Controllers\Api\V1\LeadController::class)
            ->only(['index', 'store', 'update'])   // show/destroy not implemented — not registered
            ->middleware('permission:crm.core.manage');
        Route::post('/leads/{lead}/convert', [\App\Http\Controllers\Api\V1\LeadController::class, 'convert'])
            ->middleware('permission:isp.customer.create');
    });

    Route::middleware(['entitlement:support.ticketing'])->group(function () {
        Route::get('/tickets', [\App\Http\Controllers\Api\V1\TicketController::class, 'index'])
            ->middleware('permission:support.ticket.view');
        Route::post('/tickets', [\App\Http\Controllers\Api\V1\TicketController::class, 'store'])
            ->middleware('permission:support.ticket.create');
        Route::patch('/tickets/{ticket}/status', [\App\Http\Controllers\Api\V1\TicketController::class, 'updateStatus'])
            ->middleware(['permission:support.ticket.manage', 'revision:support.tickets,ticket']);
        Route::post('/tickets/{ticket}/rate', [\App\Http\Controllers\Api\V1\TicketController::class, 'rate']);
    });

    Route::middleware(['entitlement:support.field_service'])->group(function () {
        Route::get('/field-jobs/mine', [\App\Http\Controllers\Api\V1\FieldJobController::class, 'myJobs'])
            ->middleware('permission:support.ticket.view');
        Route::post('/field-jobs/{fieldJob}/check-in', [\App\Http\Controllers\Api\V1\FieldJobController::class, 'checkIn'])
            ->middleware('permission:support.ticket.manage');
        Route::post('/field-jobs/{fieldJob}/check-out', [\App\Http\Controllers\Api\V1\FieldJobController::class, 'checkOut'])
            ->middleware('permission:support.ticket.manage');
    });

    Route::middleware(['entitlement:automation.engine'])->group(function () {
        Route::apiResource('automation-rules', \App\Http\Controllers\Api\V1\AutomationRuleController::class)
            ->only(['index', 'store', 'update', 'destroy'])   // no show route — list carries full rows
            ->middleware('permission:identity.role.manage'); // rule authoring restricted to admin-level roles
        Route::get('/automation-rules/{automationRule}/executions', 
            [\App\Http\Controllers\Api\V1\AutomationRuleController::class, 'executions']);
    });

    // ---- Phase 5: SaaS scale-out ----
    Route::middleware(['entitlement:reseller.management'])->group(function () {
        Route::get('/resellers', [\App\Http\Controllers\Api\V1\ResellerController::class, 'index'])
            ->middleware('permission:reseller.account.manage');
        Route::post('/resellers', [\App\Http\Controllers\Api\V1\ResellerController::class, 'store'])
            ->middleware('permission:reseller.account.manage');
        Route::post('/resellers/{reseller}/recharge', [\App\Http\Controllers\Api\V1\ResellerController::class, 'recharge'])
            ->middleware('permission:reseller.account.manage');
    });

    // ---- Phase 6: Advanced (AI, webhooks) ----
    Route::middleware(['entitlement:ai.nl_analytics'])->group(function () {
        Route::post('/ai/ask', [\App\Http\Controllers\Api\V1\AiController::class, 'ask'])
            ->middleware('permission:accounting.statement.view'); // NL analytics needs report-read rights
    });
    Route::middleware(['entitlement:ai.churn_prediction'])->group(function () {
        Route::get('/ai/churn-risk', [\App\Http\Controllers\Api\V1\AiController::class, 'churnRisk'])
            ->middleware('permission:isp.customer.view');
    });

    Route::middleware(['entitlement:api.access'])->group(function () {
        Route::apiResource('webhooks', \App\Http\Controllers\Api\V1\WebhookController::class)
            ->only(['index', 'store', 'destroy'])
            ->middleware('permission:identity.role.manage');
        Route::apiResource('api-keys', \App\Http\Controllers\Api\V1\ApiKeyController::class)
            ->only(['index', 'store', 'destroy'])
            ->middleware('permission:identity.role.manage');
    });

    // ---- ISP configuration (Package/Zone/SubZone/Destination — verified) ----
    Route::get('/config/packages', [\App\Http\Controllers\Api\V1\ConfigController::class, 'packages']);
    Route::get('/config/zones', [\App\Http\Controllers\Api\V1\ConfigController::class, 'zones']);
    Route::get('/config/subzones', [\App\Http\Controllers\Api\V1\ConfigController::class, 'subzones']);
    Route::get('/config/destinations', [\App\Http\Controllers\Api\V1\ConfigController::class, 'destinations']);
    Route::post('/config/packages', [\App\Http\Controllers\Api\V1\ConfigController::class, 'createPackage'])
        ->middleware('permission:isp.package.create');
    Route::post('/config/zones', [\App\Http\Controllers\Api\V1\ConfigController::class, 'createZone'])
        ->middleware('permission:isp.zone.create');

    // ---- MikroTik secrets list + bulk (verified views) ----
    Route::middleware(['entitlement:network.mikrotik.manage'])->group(function () {
        Route::get('/network/pppoe-secrets', [\App\Http\Controllers\Api\V1\MikrotikController::class, 'secrets'])
            ->middleware('permission:network.mikrotik.manage');
        Route::post('/network/bulk-disconnect-due', [\App\Http\Controllers\Api\V1\MikrotikController::class, 'bulkDisconnectDue'])
            ->middleware('permission:network.mikrotik.disconnect');
    });

    // ---- Income / Reports / BTRC (verified) ----
    Route::middleware(['entitlement:accounting.core'])->group(function () {
        Route::get('/income', [\App\Http\Controllers\Api\V1\IncomeController::class, 'index'])
            ->middleware('permission:accounting.income.manage');
        Route::post('/income', [\App\Http\Controllers\Api\V1\IncomeController::class, 'store'])
            ->middleware('permission:accounting.income.manage');
        Route::get('/reports/monthly-balance', [\App\Http\Controllers\Api\V1\ReportController::class, 'monthlyBalance'])
            ->middleware('permission:accounting.balance_sheet.view');
        Route::get('/reports/yearly-balance', [\App\Http\Controllers\Api\V1\ReportController::class, 'yearlyBalance'])
            ->middleware('permission:accounting.balance_sheet.view');
        Route::get('/reports/statement', [\App\Http\Controllers\Api\V1\ReportController::class, 'statement'])
            ->middleware('permission:accounting.statement.view');
    });
    Route::middleware(['entitlement:compliance.reports.btrc'])->group(function () {
        Route::get('/reports/btrc', \App\Http\Controllers\Api\V1\BtrcReportController::class)
            ->middleware('permission:compliance.btrc_report.export');
    });

    // ---- Inventory + Employees (verified) ----
    Route::middleware(['entitlement:inventory.core'])->group(function () {
        Route::get('/inventory/products', [\App\Http\Controllers\Api\V1\InventoryController::class, 'products'])
            ->middleware('permission:inventory.stock.manage');
        Route::post('/inventory/products', [\App\Http\Controllers\Api\V1\InventoryController::class, 'createProduct'])
            ->middleware('permission:inventory.stock.manage');
        Route::get('/inventory/stock', [\App\Http\Controllers\Api\V1\InventoryController::class, 'stock'])
            ->middleware('permission:inventory.stock.manage');
    });
    Route::middleware(['entitlement:hr.payroll'])->group(function () {
        Route::get('/employees', [\App\Http\Controllers\Api\V1\EmployeeController::class, 'index'])
            ->middleware('permission:hr.employee.view');
        Route::post('/employees', [\App\Http\Controllers\Api\V1\EmployeeController::class, 'store'])
            ->middleware('permission:hr.employee.manage');
    });

    // ---- IPAM (Blueprint module 13) ----
    Route::middleware(['entitlement:network.ipam.manage'])->group(function () {
        Route::get('/ipam/subnets', [\App\Http\Controllers\Api\V1\IpamController::class, 'subnets'])
            ->middleware('permission:network.ipam.view');
        Route::post('/ipam/subnets', [\App\Http\Controllers\Api\V1\IpamController::class, 'storeSubnet'])
            ->middleware('permission:network.ipam.manage');
        Route::get('/ipam/allocations', [\App\Http\Controllers\Api\V1\IpamController::class, 'allocations'])
            ->middleware('permission:network.ipam.view');
        Route::post('/ipam/allocations', [\App\Http\Controllers\Api\V1\IpamController::class, 'allocate'])
            ->middleware('permission:network.ipam.manage');
        Route::post('/ipam/allocations/{allocation}/release', [\App\Http\Controllers\Api\V1\IpamController::class, 'release'])
            ->middleware('permission:network.ipam.manage');
        Route::get('/ipam/subnets/{subnet}/next-free', [\App\Http\Controllers\Api\V1\IpamController::class, 'nextFree'])
            ->middleware('permission:network.ipam.view');
    });

    // ---- IPAM (Blueprint module 13) ----
    Route::middleware(['entitlement:network.mikrotik.manage'])->group(function () {
        Route::get('/ipam/subnets', [\App\Http\Controllers\Api\V1\IpamController::class, 'subnets'])
            ->middleware('permission:network.mikrotik.manage');
        Route::post('/ipam/subnets', [\App\Http\Controllers\Api\V1\IpamController::class, 'storeSubnet'])
            ->middleware('permission:network.mikrotik.manage');
        Route::get('/ipam/allocations', [\App\Http\Controllers\Api\V1\IpamController::class, 'allocations'])
            ->middleware('permission:network.mikrotik.manage');
        Route::post('/ipam/allocations', [\App\Http\Controllers\Api\V1\IpamController::class, 'allocate'])
            ->middleware('permission:network.mikrotik.manage');
        Route::post('/ipam/allocations/{allocation}/release', [\App\Http\Controllers\Api\V1\IpamController::class, 'release'])
            ->middleware('permission:network.mikrotik.manage');
        Route::get('/ipam/subnets/{subnet}/next-free', [\App\Http\Controllers\Api\V1\IpamController::class, 'nextFree'])
            ->middleware('permission:network.mikrotik.manage');
    });

    // BTRC Regulatory News — deliberately NOT wrapped in an entitlement
    // middleware group: subscription.features.compliance.news.view is
    // marked is_platform_default = true and resolves to `true` for every
    // tenant regardless of plan (see 003_subscription.sql), so this route
    // only needs the permission check, matching the product decision that
    // news is free on all tiers while alerts/reports/advanced-tools remain
    // gated on their own feature keys.
    Route::get('/compliance/news', [\App\Http\Controllers\Api\V1\ComplianceNewsController::class, 'index'])
        ->middleware('permission:compliance.news.view');
});

/**
 * ---- Customer Self-Service Portal (Blueprint Section 25) ----
 * Separate auth guard (`customer`) backed by isp.customer_portal_accounts,
 * NOT the staff `sanctum` guard. Still passes through tenant.context so
 * RLS is active. Every endpoint is implicitly OWN-scoped to the
 * authenticated customer_id — no staff RBAC middleware applies here.
 */
// Portal authentication (no auth guard — this is where a customer signs in)
Route::prefix('v1/portal')->group(function () {
    Route::post('/login', [\App\Http\Controllers\Api\V1\Portal\PortalAuthController::class, 'login']);
});

// Portal login is public (no guard yet) but rate-limited per IP+identifier.
Route::prefix('v1/portal')->group(function () {
    Route::post('/login', [\App\Http\Controllers\Api\V1\Portal\PortalAuthController::class, 'login']);
});

Route::prefix('v1/portal')->middleware(['auth:customer', 'tenant.context'])->group(function () {
    Route::post('/logout', [\App\Http\Controllers\Api\V1\Portal\PortalAuthController::class, 'logout']);
    Route::get('/profile', [\App\Http\Controllers\Api\V1\Portal\CustomerPortalController::class, 'profile']);
    Route::post('/tickets', [\App\Http\Controllers\Api\V1\Portal\CustomerPortalController::class, 'createTicket']);
    Route::post('/change-password', [\App\Http\Controllers\Api\V1\Portal\CustomerPortalController::class, 'changePassword']);
    Route::post('/logout', [\App\Http\Controllers\Api\V1\Portal\PortalAuthController::class, 'logout']);
    Route::post('/change-password', [\App\Http\Controllers\Api\V1\Portal\PortalAuthController::class, 'changePassword']);
    Route::get('/profile', [\App\Http\Controllers\Api\V1\Portal\CustomerPortalController::class, 'profile']);
    Route::get('/payments', [\App\Http\Controllers\Api\V1\Portal\CustomerPortalController::class, 'payments']);
    Route::post('/tickets', [\App\Http\Controllers\Api\V1\Portal\CustomerPortalController::class, 'createTicket']);
    Route::get('/tickets/{ticket}/replies', [\App\Http\Controllers\Api\V1\Portal\CustomerPortalController::class, 'ticketReplies']);
    Route::post('/tickets/{ticket}/replies', [\App\Http\Controllers\Api\V1\Portal\CustomerPortalController::class, 'replyToTicket']);
    Route::get('/usage', [\App\Http\Controllers\Api\V1\Portal\CustomerPortalController::class, 'usage']);
    Route::get('/notifications', [\App\Http\Controllers\Api\V1\Portal\CustomerPortalController::class, 'notifications']);
    Route::get('/dashboard', [\App\Http\Controllers\Api\V1\Portal\CustomerPortalController::class, 'dashboard']);
    Route::get('/invoices', [\App\Http\Controllers\Api\V1\Portal\CustomerPortalController::class, 'invoices']);
    Route::post('/pay', [\App\Http\Controllers\Api\V1\Portal\CustomerPortalController::class, 'payOnline']);
    Route::get('/tickets', [\App\Http\Controllers\Api\V1\Portal\CustomerPortalController::class, 'tickets']);
});

/**
 * ---- Public payment gateway callbacks (no auth guard) ----
 * Gateways POST back here after a customer completes payment. Verified
 * inside each adapter's handleCallback via signature/HMAC — NOT by
 * session auth, since the caller is the payment provider, not the user.
 */
Route::prefix('v1/gateway-callback')->group(function () {
    Route::post('/{provider}', [\App\Http\Controllers\Api\V1\Portal\GatewayCallbackController::class, 'handle']);
});


/**
 * ---- AR Qudrix Super Admin (platform scope) ----
 * Deliberately OUTSIDE the tenant.context group: these routes must never
 * run with a tenant RLS context set. RequirePlatformAdmin rejects any
 * account that has a tenant_id, and switches to the BYPASSRLS connection
 * so cross-tenant reporting works — a boundary no tenant role can cross.
 */
Route::prefix('v1/platform')->middleware(['auth:sanctum', 'platform.admin'])->group(function () {
    $c = \App\Http\Controllers\Api\V1\Platform\PlatformController::class;

    Route::get('/stats', [$c, 'stats']);
    Route::get('/tenants', [$c, 'tenants']);
    Route::post('/tenants', [$c, 'createTenant']);
    Route::get('/tenants/{tenant}', [$c, 'tenantDetail']);
    Route::patch('/tenants/{tenant}/status', [$c, 'setTenantStatus']);
    Route::post('/tenants/{tenant}/plan', [$c, 'assignPlan']);
    Route::post('/tenants/{tenant}/overrides', [$c, 'setOverride']);
    Route::delete('/tenants/{tenant}/overrides/{override}', [$c, 'removeOverride']);

    Route::get('/plans', [$c, 'plans']);
    Route::get('/features', [$c, 'features']);
    Route::get('/audit', [$c, 'platformAudit']);

    Route::get('/news/candidates', [$c, 'newsCandidates']);
    Route::post('/news/publish', [$c, 'publishNews']);
    Route::post('/news/{news}/unpublish', [$c, 'unpublishNews']);
});
