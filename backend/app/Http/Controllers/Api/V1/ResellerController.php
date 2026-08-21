<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use App\Models\Reseller\Reseller;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Validation\Rule;
use App\Rules\SchemaExists;

/**
 * Reseller/Dealer/Franchise management (Blueprint Section 18). When the
 * authenticated user IS a reseller (reseller role, OWN scope), the
 * customer/report endpoints elsewhere already filter to
 * isp.customers.reseller_id = their reseller record — enforced in
 * CustomerController via data_scope, plus RLS. This controller is the
 * tenant-admin view for MANAGING resellers.
 */
class ResellerController extends Controller
{
    public function index()
    {
        return response()->json(Reseller::with('commissionRule')->get());
    }

    public function store(Request $request)
    {
        $validated = $request->validate([
            'name' => 'required|string|max:255',
            'reseller_type' => 'required|in:franchise,dealer,reseller,sub_reseller',
            'parent_reseller_id' => ['nullable', 'uuid', new \App\Rules\SchemaExists('reseller.resellers', 'id')],
            'mobile' => 'nullable|string|max:30',
            'email' => 'nullable|email',
            'address' => 'nullable|string',
            'commission_rule_id' => ['nullable', 'uuid', new \App\Rules\SchemaExists('reseller.commission_rules', 'id')],
            'credit_limit' => 'nullable|numeric|min:0',
        ]);

        return response()->json(Reseller::create($validated), 201);
    }

    public function recharge(Request $request, Reseller $reseller)
    {
        $validated = $request->validate(['amount' => 'required|numeric|min:0.01', 'description' => 'nullable|string']);

        DB::transaction(function () use ($reseller, $validated, $request) {
            $newBalance = $reseller->wallet_balance + $validated['amount'];
            $reseller->update(['wallet_balance' => $newBalance]);

            DB::table('reseller.wallet_transactions')->insert([
                'id' => (string) \Illuminate\Support\Str::uuid(),
                'tenant_id' => $reseller->tenant_id,
                'reseller_id' => $reseller->id,
                'txn_type' => 'recharge',
                'amount' => $validated['amount'],
                'balance_after' => $newBalance,
                'description' => $validated['description'] ?? 'Wallet recharge',
                'created_by' => $request->user()->id,
                'created_at' => now(),
            ]);
        });

        return response()->json($reseller->fresh());
    }
}
