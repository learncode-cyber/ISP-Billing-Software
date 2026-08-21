<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use App\Models\Customer;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Validation\Rule;
use App\Rules\SchemaExists;

/**
 * Reproduces AS-IS audit's verified Customer View: filter bar (Zone,
 * Billing Person, Package, Status, Date range), pagination (10-500),
 * row actions Edit/Delete/View->Ledger. Route middleware (see routes/api.php)
 * chains entitlement('isp.customer.manage') -> permission('isp.customer.*')
 * before any action here runs, per the mandatory AND rule.
 */
class CustomerController extends Controller
{
    public function index(Request $request)
    {
        $scope = $request->attributes->get('data_scope', 'OWN');
        $user = $request->user();

        $query = Customer::query()
            ->when($request->filled('zone_id'), fn ($q) => $q->where('zone_id', $request->zone_id))
            ->when($request->filled('billing_person_id'), fn ($q) => $q->where('billing_person_id', $request->billing_person_id))
            ->when($request->filled('status'), fn ($q) => $q->where('status', $request->status))
            ->when($request->filled('date_from'), fn ($q) => $q->where('connection_date', '>=', $request->date_from))
            ->when($request->filled('date_to'), fn ($q) => $q->where('connection_date', '<=', $request->date_to))
            ->when($request->filled('search'), function ($q) use ($request) {
                $q->where(fn ($qq) => $qq
                    ->where('full_name', 'ilike', "%{$request->search}%")
                    ->orWhere('mobile', 'ilike', "%{$request->search}%")
                    ->orWhere('customer_code', 'ilike', "%{$request->search}%"));
            });

        // Data-scope enforcement in addition to RLS tenant isolation —
        // e.g. a Reseller (OWN) only ever sees customers they were
        // assigned as billing_person / reseller-owner, never the tenant's
        // full customer list, even though RLS already lets the query
        // through at the tenant boundary.
        if ($scope === 'OWN') {
            $query->where('billing_person_id', $user->id);
        } elseif ($scope === 'BRANCH') {
            $query->where('branch_id', $user->branch_id);
        }

        $perPage = min((int) $request->get('per_page', 10), 500);

        return response()->json($query->with(['zone', 'billingPerson'])->paginate($perPage));
    }

    public function store(Request $request)
    {
        $validated = $request->validate([
            'full_name' => 'required|string|max:255',
            'mobile' => 'required|string|max:30',
            'other_mobile' => 'nullable|string|max:30',
            'email' => 'nullable|email',
            'gender' => 'nullable|in:male,female,other',
            'onu_mac_address' => 'nullable',
            'nid_passport_no' => 'nullable|string|max:50',
            'address' => 'nullable|string',
            'fiber_code' => 'nullable|string|max:100',
            'agent_type' => 'required|in:optical_fiber,cat5',
            'connection_type' => 'required|in:home,corporate',
            'connection_date' => 'required|date',
            'zone_id' => ['required', 'uuid', new \App\Rules\SchemaExists('isp.zones', 'id')],
            'subzone_id' => ['nullable', 'uuid', new \App\Rules\SchemaExists('isp.subzones', 'id')],
            'destination_id' => ['nullable', 'uuid', new \App\Rules\SchemaExists('isp.destinations', 'id')],
            'billing_person_id' => ['required', 'uuid', new \App\Rules\SchemaExists('identity.users', 'id')],
            'status' => ['required', Rule::in(['active', 'inactive', 'free', 'discontinue'])],
            'remarks' => 'nullable|string',
            'sms_notification_enabled' => 'boolean',
            // customer_service fields (package/bill/pppoe) validated separately
            'package_id' => ['required', 'uuid', new \App\Rules\SchemaExists('isp.packages', 'id')],
            'monthly_bill' => 'required|numeric|min:0',
            'running_month_paid_amount' => 'nullable|numeric|min:0',
            'connection_fee_paid' => 'nullable|numeric|min:0',
            'disconnect_day' => 'required|integer|min:1|max:28',
            'pppoe_username' => 'required|string',
            'pppoe_secret_password' => 'required|string',
            'router_id' => ['required', 'uuid', new \App\Rules\SchemaExists('network.mikrotik_routers', 'id')],
        ]);

        return DB::transaction(function () use ($validated, $request) {
            $customer = Customer::create([
                ...collect($validated)->only([
                    'full_name', 'mobile', 'other_mobile', 'email', 'gender',
                    'onu_mac_address', 'nid_passport_no', 'address', 'fiber_code',
                    'agent_type', 'connection_type', 'connection_date', 'zone_id',
                    'subzone_id', 'destination_id', 'billing_person_id', 'status',
                    'remarks',
                ])->toArray(),
                'sms_notification_enabled' => $validated['sms_notification_enabled'] ?? true,
                'customer_code' => app(\App\Services\CustomerCodeGenerator::class)->next($request->user()->tenant_id),
                'created_by' => $request->user()->id,
            ]);

            $service = $customer->services()->create([
                'service_type' => 'internet',
                'package_id' => $validated['package_id'],
                'monthly_bill' => $validated['monthly_bill'],
                'running_month_paid_amount' => $validated['running_month_paid_amount'] ?? 0,
                'connection_fee_paid' => $validated['connection_fee_paid'] ?? 0,
                'disconnect_day' => $validated['disconnect_day'],
                'status' => $validated['status'],
            ]);

            // Auto-creates the MikroTik secret — preserves verified behavior
            // "MikroTik secret auto-created" from the audit's Customer Lifecycle
            // section. Actual RouterOS API call happens async via queue.
            app(\App\Services\MikrotikService::class)->createSecretAsync(
                routerId: $validated['router_id'],
                customerServiceId: $service->id,
                username: $validated['pppoe_username'],
                secretPassword: $validated['pppoe_secret_password'],
                profile: null, // resolved from package.mikrotik_profile_name in the job
            );

            return response()->json($customer->load('services'), 201);
        });
    }

    public function update(Request $request, Customer $customer)
    {
        // Edit adds: previous_due, temp_disconnect_day, subzone/destination —
        // preserved exactly per audit Section 5.
        $validated = $request->validate([
            'previous_due' => 'nullable|numeric',
            'temp_disconnect_day' => 'nullable|integer',
            'subzone_id' => ['nullable', 'uuid', new \App\Rules\SchemaExists('isp.subzones', 'id')],
            'destination_id' => ['nullable', 'uuid', new \App\Rules\SchemaExists('isp.destinations', 'id')],
            'status' => ['sometimes', Rule::in(['active', 'inactive', 'free', 'discontinue'])],
            'remarks' => 'nullable|string',
        ]);

        $customer->update($validated);

        return response()->json($customer->fresh());
    }

    public function destroy(Request $request, Customer $customer)
    {
        DB::transaction(function () use ($request, $customer) {
            DB::table('isp.customer_delete_logs')->insert([
                'id' => (string) \Illuminate\Support\Str::uuid(),
                'tenant_id' => $customer->tenant_id,
                'customer_snapshot_json' => json_encode($customer->toArray()),
                'deleted_by' => $request->user()->id,
                'reason' => $request->input('reason'),
                'deleted_at' => now(),
            ]);
            $customer->delete(); // soft delete
        });

        return response()->json(null, 204);
    }
}
