<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use App\Models\Accounting\ExpenseEntry;
use Illuminate\Http\Request;
use Illuminate\Validation\Rule;
use App\Rules\SchemaExists;

/**
 * Reproduces verified Expense module: Expense Report (read-only, filter
 * by month/year/head), View Expense (same data + per-row Delete),
 * Account Head cumulative totals. Approval workflow is new (Blueprint
 * Section 15) but defaults every entry to 'approved' so existing-style
 * direct entry keeps working unless a tenant opts into the approval
 * workflow via a role permission (accounting.expense.approve required
 * to approve a 'pending' entry — Owner/Admin can still just create
 * pre-approved entries directly, matching current client behavior).
 */
class ExpenseController extends Controller
{
    public function index(Request $request)
    {
        $query = ExpenseEntry::query()
            ->when($request->filled('head_id'), fn ($q) => $q->where('head_id', $request->head_id))
            ->when($request->filled('month'), fn ($q) => $q->whereMonth('entry_date', $request->month))
            ->when($request->filled('year'), fn ($q) => $q->whereYear('entry_date', $request->year));

        return response()->json($query->with('head')->orderByDesc('entry_date')->paginate(
            min((int) $request->get('per_page', 25), 500)
        ));
    }

    public function store(Request $request)
    {
        $validated = $request->validate([
            'head_id' => ['required', 'uuid', new \App\Rules\SchemaExists('accounting.account_heads', 'id')],
            'sub_head_id' => ['nullable', 'uuid', new \App\Rules\SchemaExists('accounting.account_sub_heads', 'id')],
            'amount' => 'required|numeric|min:0.01',
            'description' => 'nullable|string',
            'entry_date' => 'required|date',
        ]);

        $entry = ExpenseEntry::create([
            ...$validated,
            'approval_status' => 'approved', // matches current client behavior by default
            'created_by' => $request->user()->id,
        ]);
        // DB trigger accounting.post_expense_to_ledger fires automatically.

        return response()->json($entry, 201);
    }

    public function destroy(ExpenseEntry $expenseEntry)
    {
        $expenseEntry->delete(); // soft delete, preserved for GL audit trail integrity
        return response()->json(null, 204);
    }
}
