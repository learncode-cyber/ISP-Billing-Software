<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use App\Models\Crm\Lead;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Validation\Rule;
use App\Rules\SchemaExists;

/**
 * CRM Lead Management (Blueprint Section 16). Lead conversion re-uses
 * the exact Phase-1 customer creation path (CustomerController::store
 * logic, extracted into CustomerProvisioningService in this phase so
 * both entry points share one implementation) — MikroTik secret
 * auto-creation and all verified Create Customer fields behave
 * identically whether the customer came from a lead or direct entry.
 */
class LeadController extends Controller
{
    public function index(Request $request)
    {
        $query = Lead::query()
            ->when($request->filled('status'), fn ($q) => $q->where('status', $request->status))
            ->when($request->filled('assigned_to_user_id'), fn ($q) => $q->where('assigned_to_user_id', $request->assigned_to_user_id));

        return response()->json($query->orderByDesc('created_at')->paginate(25));
    }

    public function store(Request $request)
    {
        $validated = $request->validate([
            'full_name' => 'required|string|max:255',
            'mobile' => 'required|string|max:30',
            'email' => 'nullable|email',
            'address' => 'nullable|string',
            'source_id' => ['nullable', 'uuid', new \App\Rules\SchemaExists('crm.lead_sources', 'id')],
            'interested_package_id' => ['nullable', 'uuid', new \App\Rules\SchemaExists('isp.packages', 'id')],
            'assigned_to_user_id' => ['nullable', 'uuid', new \App\Rules\SchemaExists('identity.users', 'id')],
        ]);

        return response()->json(Lead::create($validated), 201);
    }

    public function update(Request $request, Lead $lead)
    {
        $validated = $request->validate([
            'status' => 'sometimes|in:new,contacted,qualified,converted,lost',
            'lost_reason' => 'nullable|string',
            'assigned_to_user_id' => ['nullable', 'uuid', new \App\Rules\SchemaExists('identity.users', 'id')],
        ]);

        $lead->update($validated);
        return response()->json($lead->fresh());
    }

    /**
     * Converts a qualified lead into a customer via
     * CustomerProvisioningService — the same code path Phase 1's
     * CustomerController::store uses, so field mapping and MikroTik
     * secret creation stay in exactly one place.
     */
    public function convert(Request $request, Lead $lead)
    {
        $validated = $request->validate([
            'package_id' => ['required', 'uuid', new \App\Rules\SchemaExists('isp.packages', 'id')],
            'zone_id' => ['required', 'uuid', new \App\Rules\SchemaExists('isp.zones', 'id')],
            'billing_person_id' => ['required', 'uuid', new \App\Rules\SchemaExists('identity.users', 'id')],
            'router_id' => ['required', 'uuid', new \App\Rules\SchemaExists('network.mikrotik_routers', 'id')],
            'pppoe_username' => 'required|string',
            'pppoe_secret_password' => 'required|string',
            'monthly_bill' => 'required|numeric|min:0',
            'disconnect_day' => 'required|integer|min:1|max:28',
        ]);

        $customer = DB::transaction(function () use ($lead, $validated, $request) {
            $customer = app(\App\Services\CustomerProvisioningService::class)->create([
                'full_name' => $lead->full_name,
                'mobile' => $lead->mobile,
                'email' => $lead->email,
                'address' => $lead->address,
                ...$validated,
            ], $request->user());

            $lead->update(['status' => 'converted', 'converted_customer_id' => $customer->id]);

            return $customer;
        });

        return response()->json($customer, 201);
    }
}
