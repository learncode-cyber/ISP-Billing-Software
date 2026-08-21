<?php

namespace App\Http\Controllers\Api\V1\Platform;

use App\Http\Controllers\Controller;
use App\Services\TenantProvisioningService;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;
use Illuminate\Validation\Rule;
use App\Rules\SchemaExists;

/**
 * AR Qudrix Super Admin console API.
 *
 * Everything the platform owner needs to run the SaaS without touching
 * the database directly: tenant lifecycle, plan/feature catalogue,
 * per-tenant overrides, usage, platform-wide analytics, BTRC news
 * moderation, and platform audit.
 *
 * Guarded by RequirePlatformAdmin — tenant accounts cannot reach any of it.
 */
class PlatformController extends Controller
{
    // ---------- Tenants ----------

    public function tenants(Request $request)
    {
        $rows = DB::table('tenancy.tenants as t')
            ->leftJoin('subscription.tenant_subscriptions as s', 's.tenant_id', '=', 't.id')
            ->leftJoin('subscription.plans as p', 'p.id', '=', 's.plan_id')
            ->whereNull('t.deleted_at')
            ->when($request->filled('status'), fn ($q) => $q->where('t.status', $request->status))
            ->when($request->filled('search'), fn ($q) => $q->where('t.name', 'ilike', "%{$request->search}%"))
            ->select('t.id', 't.name', 't.slug', 't.business_type', 't.status', 't.created_at',
                     'p.code as plan_code', 'p.name as plan_name',
                     's.status as subscription_status', 's.current_period_end')
            ->orderByDesc('t.created_at')
            ->paginate(min((int) $request->get('per_page', 25), 200));

        return response()->json($rows);
    }

    public function tenantDetail(string $tenant)
    {
        $t = DB::table('tenancy.tenants')->where('id', $tenant)->first();
        abort_if(! $t, 404);

        // Usage counters drive both support conversations and plan-limit
        // enforcement, so they come from live counts, not cached guesses.
        $usage = [
            'customers' => DB::table('isp.customers')->where('tenant_id', $tenant)->whereNull('deleted_at')->count(),
            'users' => DB::table('identity.users')->where('tenant_id', $tenant)->whereNull('deleted_at')->count(),
            'branches' => DB::table('tenancy.branches')->where('tenant_id', $tenant)->whereNull('deleted_at')->count(),
            'routers' => DB::table('network.mikrotik_routers')->where('tenant_id', $tenant)->whereNull('deleted_at')->count(),
            'olts' => DB::table('network.olt_devices')->where('tenant_id', $tenant)->whereNull('deleted_at')->count(),
            'invoices_this_month' => DB::table('billing.invoices')->where('tenant_id', $tenant)
                ->whereRaw("date_trunc('month', generated_at) = date_trunc('month', now())")->count(),
        ];

        $subscription = DB::table('subscription.tenant_subscriptions as s')
            ->leftJoin('subscription.plans as p', 'p.id', '=', 's.plan_id')
            ->where('s.tenant_id', $tenant)
            ->select('s.*', 'p.code as plan_code', 'p.name as plan_name')->first();

        $overrides = DB::table('subscription.tenant_feature_overrides as o')
            ->join('subscription.features as f', 'f.id', '=', 'o.feature_id')
            ->where('o.tenant_id', $tenant)
            ->select('o.id', 'f.key', 'f.name', 'o.is_enabled', 'o.limit_value', 'o.reason', 'o.expires_at')
            ->get();

        return response()->json(compact('t', 'usage', 'subscription', 'overrides') + ['tenant' => $t]);
    }

    public function createTenant(Request $request, TenantProvisioningService $provisioner)
    {
        $v = $request->validate([
            'name' => 'required|string|max:255',
            'business_type' => 'nullable|in:isp,wisp,ftth,cable_tv,ip_phone,cctv,corporate_network',
            'plan' => ['required', 'string', new \App\Rules\SchemaExists('subscription.plans', 'code')],
            'owner_name' => 'required|string|max:255',
            'owner_username' => 'required|string|max:100',
            'owner_email' => 'nullable|email',
            'owner_password' => 'required|string|min:8',
        ]);

        $tenant = $provisioner->provision($v);

        $this->auditPlatform($request, 'platform.tenant_created', $tenant->id);

        return response()->json($tenant, 201);
    }

    public function setTenantStatus(Request $request, string $tenant)
    {
        $v = $request->validate(['status' => 'required|in:trial,active,suspended,cancelled']);

        DB::table('tenancy.tenants')->where('id', $tenant)
            ->update(['status' => $v['status'], 'updated_at' => now()]);

        // Suspending the tenant also suspends the subscription, so
        // entitlement resolution denies everything immediately rather than
        // relying on the UI to hide things.
        if (in_array($v['status'], ['suspended', 'cancelled'], true)) {
            DB::table('subscription.tenant_subscriptions')->where('tenant_id', $tenant)
                ->update(['status' => $v['status'] === 'cancelled' ? 'cancelled' : 'suspended', 'updated_at' => now()]);
        }

        $this->auditPlatform($request, 'platform.tenant_status_changed', $tenant, $v);

        return response()->json(['status' => $v['status']]);
    }

    // ---------- Subscription / plans / features ----------

    public function plans()
    {
        $plans = DB::table('subscription.plans')->orderBy('sort_order')->get();
        foreach ($plans as $p) {
            $p->features = DB::table('subscription.plan_features as pf')
                ->join('subscription.features as f', 'f.id', '=', 'pf.feature_id')
                ->where('pf.plan_id', $p->id)->where('pf.is_enabled', true)
                ->pluck('f.key');
        }
        return response()->json($plans);
    }

    public function features()
    {
        return response()->json(
            DB::table('subscription.features')->orderBy('module')->orderBy('key')->get()
        );
    }

    public function assignPlan(Request $request, string $tenant)
    {
        $v = $request->validate([
            'plan' => ['required', 'string', new \App\Rules\SchemaExists('subscription.plans', 'code')],
            'period_days' => 'nullable|integer|min:1|max:3650',
        ]);

        $planId = DB::table('subscription.plans')->where('code', $v['plan'])->value('id');

        DB::table('subscription.tenant_subscriptions')->updateOrInsert(
            ['tenant_id' => $tenant],
            [
                'id' => (string) Str::uuid(),
                'plan_id' => $planId,
                'status' => 'active',
                'current_period_start' => now(),
                'current_period_end' => now()->addDays($v['period_days'] ?? 30),
                'updated_at' => now(),
            ]
        );

        $this->auditPlatform($request, 'platform.plan_assigned', $tenant, $v);

        return response()->json(['status' => 'assigned', 'plan' => $v['plan']]);
    }

    public function setOverride(Request $request, string $tenant)
    {
        $v = $request->validate([
            'feature_key' => ['required', 'string', new \App\Rules\SchemaExists('subscription.features', 'key')],
            'is_enabled' => 'required|boolean',
            'limit_value' => 'nullable|integer',
            'reason' => 'nullable|string|max:255',
            'expires_at' => 'nullable|date',
        ]);

        $featureId = DB::table('subscription.features')->where('key', $v['feature_key'])->value('id');

        DB::table('subscription.tenant_feature_overrides')->updateOrInsert(
            ['tenant_id' => $tenant, 'feature_id' => $featureId],
            [
                'id' => (string) Str::uuid(),
                'is_enabled' => $v['is_enabled'],
                'limit_value' => $v['limit_value'] ?? null,
                'reason' => $v['reason'] ?? null,
                'expires_at' => $v['expires_at'] ?? null,
                'granted_by' => $request->user()->id,
                'created_at' => now(),
            ]
        );

        $this->auditPlatform($request, 'platform.feature_override', $tenant, $v);

        return response()->json(['status' => 'saved']);
    }

    public function removeOverride(Request $request, string $tenant, string $override)
    {
        DB::table('subscription.tenant_feature_overrides')
            ->where('id', $override)->where('tenant_id', $tenant)->delete();

        $this->auditPlatform($request, 'platform.feature_override_removed', $tenant);

        return response()->json(null, 204);
    }

    // ---------- Platform analytics & health ----------

    public function stats()
    {
        return response()->json([
            'tenants_total' => DB::table('tenancy.tenants')->whereNull('deleted_at')->count(),
            'tenants_active' => DB::table('tenancy.tenants')->where('status', 'active')->whereNull('deleted_at')->count(),
            'tenants_trial' => DB::table('tenancy.tenants')->where('status', 'trial')->whereNull('deleted_at')->count(),
            'tenants_suspended' => DB::table('tenancy.tenants')->where('status', 'suspended')->count(),
            'customers_total' => DB::table('isp.customers')->whereNull('deleted_at')->count(),
            'mrr_estimate' => DB::table('subscription.tenant_subscriptions as s')
                ->join('subscription.plans as p', 'p.id', '=', 's.plan_id')
                ->whereIn('s.status', ['active', 'trial'])->sum('p.price_amount'),
            'plan_distribution' => DB::table('subscription.tenant_subscriptions as s')
                ->join('subscription.plans as p', 'p.id', '=', 's.plan_id')
                ->select('p.code', DB::raw('count(*) as tenants'))
                ->groupBy('p.code')->get(),
        ]);
    }

    public function platformAudit(Request $request)
    {
        return response()->json(
            DB::table('audit.activity_logs')
                ->when($request->filled('tenant_id'), fn ($q) => $q->where('tenant_id', $request->tenant_id))
                ->when($request->filled('action'), fn ($q) => $q->where('action', 'like', $request->action.'%'))
                ->orderByDesc('created_at')
                ->paginate(min((int) $request->get('per_page', 50), 200))
        );
    }

    // ---------- BTRC news moderation ----------

    public function newsCandidates()
    {
        return response()->json(
            DB::table('compliance.btrc_news_candidates')
                ->where('processed', false)->orderByDesc('scraped_at')->limit(100)->get()
        );
    }

    public function publishNews(Request $request)
    {
        $v = $request->validate([
            'title' => 'required|string|max:500',
            'body' => 'nullable|string',
            'source_url' => 'nullable|url',
            'category' => 'nullable|string|max:50',
            'published_at' => 'nullable|date',
            'candidate_id' => 'nullable|uuid',
        ]);

        $id = (string) Str::uuid();
        DB::table('compliance.btrc_news')->insert([
            'id' => $id,
            'title' => $v['title'],
            'body' => $v['body'] ?? null,
            'source_url' => $v['source_url'] ?? null,
            'category' => $v['category'] ?? null,
            'published_at' => $v['published_at'] ?? now(),
            'ingestion_method' => isset($v['candidate_id']) ? 'scraped' : 'manual',
            'review_status' => 'published',
            'reviewed_by' => $request->user()->id,
            'is_published' => true,
            'created_at' => now(),
            'updated_at' => now(),
        ]);

        if (! empty($v['candidate_id'])) {
            DB::table('compliance.btrc_news_candidates')->where('id', $v['candidate_id'])
                ->update(['processed' => true]);
        }

        $this->auditPlatform($request, 'platform.news_published', null, ['news_id' => $id]);

        return response()->json(['id' => $id], 201);
    }

    public function unpublishNews(Request $request, string $news)
    {
        DB::table('compliance.btrc_news')->where('id', $news)
            ->update(['is_published' => false, 'review_status' => 'rejected', 'updated_at' => now()]);
        $this->auditPlatform($request, 'platform.news_unpublished', null, ['news_id' => $news]);
        return response()->json(['status' => 'unpublished']);
    }

    private function auditPlatform(Request $request, string $action, ?string $tenantId = null, array $ctx = []): void
    {
        DB::table('audit.activity_logs')->insert([
            'id' => (string) Str::uuid(),
            'tenant_id' => $tenantId,
            'user_id' => $request->user()->id,
            'action' => $action,
            'entity_type' => 'platform',
            'after_json' => json_encode($ctx),
            'ip_address' => $request->ip(),
            'device' => $request->userAgent(),
            'result' => 'success',
            'source' => 'user',
            'created_at' => now(),
        ]);
    }
}
