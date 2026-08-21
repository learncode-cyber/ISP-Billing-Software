<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;

/**
 * Tenant-facing Automation Rule builder (Blueprint Section 21: "User
 * should in future be able to create automation themselves"). Rules
 * marked is_system_default=true (seeded per automation.seed_default_
 * rules_for_tenant) can be toggled active/inactive by a tenant admin but
 * not deleted, preserving the audit-verified baseline behavior as a
 * floor tenants can't accidentally remove entirely.
 */
class AutomationRuleController extends Controller
{
    public function index(Request $request)
    {
        return response()->json(
            DB::table('automation.rules')
                ->where('tenant_id', $request->user()->tenant_id)
                ->orderByDesc('created_at')
                ->get()
        );
    }

    public function store(Request $request)
    {
        $validated = $request->validate([
            'name' => 'required|string|max:150',
            'description' => 'nullable|string',
            'trigger_type' => 'required|string',
            'trigger_config_json' => 'nullable|array',
            'condition_json' => 'nullable|array',
            'action_type' => 'required|string',
            'action_config_json' => 'nullable|array',
            'is_active' => 'boolean',
        ]);

        $id = (string) \Illuminate\Support\Str::uuid();
        DB::table('automation.rules')->insert([
            'id' => $id,
            'tenant_id' => $request->user()->tenant_id,
            'name' => $validated['name'],
            'description' => $validated['description'] ?? null,
            'trigger_type' => $validated['trigger_type'],
            'trigger_config_json' => json_encode($validated['trigger_config_json'] ?? []),
            'condition_json' => json_encode($validated['condition_json'] ?? []),
            'action_type' => $validated['action_type'],
            'action_config_json' => json_encode($validated['action_config_json'] ?? []),
            'is_active' => $validated['is_active'] ?? true,
            'is_system_default' => false,
            'created_by' => $request->user()->id,
            'created_at' => now(),
            'updated_at' => now(),
        ]);

        return response()->json(['id' => $id], 201);
    }

    public function update(Request $request, string $automationRule)
    {
        $rule = DB::table('automation.rules')->where('id', $automationRule)->first();

        $validated = $request->validate([
            'name' => 'sometimes|string|max:150',
            'condition_json' => 'nullable|array',
            'action_config_json' => 'nullable|array',
            'is_active' => 'sometimes|boolean',
        ]);

        // System-default rules: only is_active may be toggled, everything
        // else about the seeded baseline behavior stays fixed.
        if ($rule->is_system_default) {
            $validated = collect($validated)->only('is_active')->toArray();
        }

        DB::table('automation.rules')->where('id', $automationRule)->update([
            ...array_map(fn ($v) => is_array($v) ? json_encode($v) : $v, $validated),
            'updated_at' => now(),
        ]);

        return response()->json(['status' => 'updated']);
    }

    public function destroy(string $automationRule)
    {
        $rule = DB::table('automation.rules')->where('id', $automationRule)->first();
        if ($rule && $rule->is_system_default) {
            abort(403, 'System default automation rules cannot be deleted, only disabled.');
        }

        DB::table('automation.rules')->where('id', $automationRule)->delete();
        return response()->json(null, 204);
    }

    public function executions(string $automationRule)
    {
        return response()->json(
            DB::table('automation.executions')
                ->where('rule_id', $automationRule)
                ->orderByDesc('triggered_at')
                ->limit(100)
                ->get()
        );
    }
}
