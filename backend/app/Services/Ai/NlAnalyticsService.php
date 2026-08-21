<?php

namespace App\Services\Ai;

use Illuminate\Support\Facades\DB;

/**
 * NlAnalyticsService — Natural-Language Analytics (Blueprint Section 22).
 *
 * Answers questions like "which zone had the highest customer churn this
 * month?" WITHOUT ever generating free-form SQL against production tables.
 * Instead it maps the question to a constrained set of pre-built,
 * parameterized analytics queries over the analytics.* materialized views
 * (Phase 2). This is a deliberate safety boundary:
 *   - the AI selects an INTENT + parameters, not raw SQL
 *   - the query it runs is one of a fixed, reviewed set
 *   - every query is tenant-scoped from the authenticated context, so an
 *     AI answer can never leak another tenant's data even if the model
 *     is prompt-injected
 *
 * Entitlement (ai.nl_analytics) and the user's data permissions are
 * checked by middleware BEFORE this service is reached, and logged to
 * ai.request_logs.
 */
class NlAnalyticsService
{
    /** Fixed catalog of answerable intents -> parameterized view queries. */
    private const INTENTS = [
        'highest_churn_zone' => 'queryHighestChurnZone',
        'monthly_collection' => 'queryMonthlyCollection',
        'zone_performance' => 'queryZonePerformance',
        'active_customer_count' => 'queryActiveCustomers',
    ];

    public function answer(string $tenantId, string $userId, string $question): array
    {
        // 1. Classify the question into one of the known intents (this is
        //    the ONLY place the LLM is consulted — to pick an intent +
        //    extract parameters like a month, NOT to write a query).
        $intent = $this->classifyIntent($question); // returns ['intent' => ..., 'params' => [...]]

        $this->log($tenantId, $userId, $question, $intent['intent'] ?? 'unresolved');

        if (! isset(self::INTENTS[$intent['intent'] ?? ''])) {
            return ['answer' => "I can't answer that from the available analytics yet.", 'data' => null];
        }

        $method = self::INTENTS[$intent['intent']];
        return $this->{$method}($tenantId, $intent['params'] ?? []);
    }

    private function queryHighestChurnZone(string $tenantId, array $params): array
    {
        $row = DB::table('analytics.mv_monthly_churn as mc')
            ->join('isp.zones as z', 'z.id', '=', 'mc.zone_id')
            ->where('mc.tenant_id', $tenantId)   // tenant scoping — non-negotiable
            ->where('mc.period_month', $params['month'] ?? now()->startOfMonth()->toDateString())
            ->orderByDesc('mc.churned_count')
            ->select('z.name', 'mc.churned_count')
            ->first();

        return $row
            ? ['answer' => "The zone with the highest churn was {$row->name} with {$row->churned_count} customers.", 'data' => $row]
            : ['answer' => 'No churn recorded for that period.', 'data' => null];
    }

    private function queryMonthlyCollection(string $tenantId, array $params): array
    {
        $row = DB::table('analytics.mv_collection_summary')
            ->where('tenant_id', $tenantId)
            ->orderByDesc('period_month')->first();

        return ['answer' => 'Total collected this period: '.($row->total_collected ?? 0), 'data' => $row];
    }

    private function queryZonePerformance(string $tenantId, array $params): array
    {
        $rows = DB::table('analytics.mv_zone_performance')->where('tenant_id', $tenantId)
            ->orderByDesc('active_revenue_potential')->limit(10)->get();
        return ['answer' => 'Top zones by active revenue potential.', 'data' => $rows];
    }

    private function queryActiveCustomers(string $tenantId, array $params): array
    {
        $row = DB::table('analytics.mv_dashboard_summary')->where('tenant_id', $tenantId)->first();
        return ['answer' => 'Active customers: '.($row->active_customers ?? 0), 'data' => $row];
    }

    private function classifyIntent(string $question): array
    {
        // LLM call (Anthropic API) constrained to return ONLY one of the
        // known intent keys + params as JSON. Integration boundary —
        // wired during Phase 6 hardening with the API credential from the
        // secrets manager. Returns ['intent' => null] on low confidence.
        return ['intent' => null, 'params' => []];
    }

    private function log(string $tenantId, string $userId, string $question, string $capability): void
    {
        DB::table('ai.request_logs')->insert([
            'id' => (string) \Illuminate\Support\Str::uuid(),
            'tenant_id' => $tenantId,
            'user_id' => $userId,
            'capability' => 'nl_analytics',
            'prompt_summary' => mb_substr($question, 0, 500),
            'status' => 'success',
            'created_at' => now(),
        ]);
    }
}
