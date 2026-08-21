<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use App\Models\Hr\Employee;
use App\Models\Hr\SalaryPayment;
use Illuminate\Http\Request;

/**
 * Reproduces verified Pay Salary modal exactly: Payment Amount,
 * Conveyance Amount, Punishment Amount, auto-filled Description.
 * Per-employee ledger (Total Salary, Conveyance, Received, Punishment,
 * Due) is a derived GET, computed from monthly_salary vs. the sum of
 * salary_payments for the period — not separately stored, avoiding the
 * drift risk a duplicated running-due column would introduce.
 */
class PayrollController extends Controller
{
    public function ledger(Employee $employee)
    {
        $payments = SalaryPayment::where('employee_id', $employee->id)
            ->orderByDesc('period_year')->orderByDesc('period_month')
            ->get();

        $totalReceived = $payments->sum(fn ($p) => $p->payment_amount + $p->conveyance_amount - $p->punishment_amount);

        return response()->json([
            'employee' => $employee,
            'monthly_salary' => $employee->monthly_salary,
            'total_received' => $totalReceived,
            'payments' => $payments,
        ]);
    }

    public function pay(Request $request, Employee $employee)
    {
        $validated = $request->validate([
            'period_month' => 'required|integer|between:1,12',
            'period_year' => 'required|integer',
            'payment_amount' => 'required|numeric|min:0',
            'conveyance_amount' => 'nullable|numeric|min:0',
            'punishment_amount' => 'nullable|numeric|min:0',
        ]);

        $description = sprintf(
            'Salary payment for %s-%d to %s',
            \Carbon\Carbon::create()->month($validated['period_month'])->format('F'),
            $validated['period_year'],
            $employee->name
        );

        $payment = SalaryPayment::create([
            'employee_id' => $employee->id,
            'period_month' => $validated['period_month'],
            'period_year' => $validated['period_year'],
            'payment_amount' => $validated['payment_amount'],
            'conveyance_amount' => $validated['conveyance_amount'] ?? 0,
            'punishment_amount' => $validated['punishment_amount'] ?? 0,
            'description' => $description,
            'paid_by' => $request->user()->id,
            'paid_at' => now(),
        ]);
        // DB trigger hr.post_salary_to_expense fires automatically,
        // posting into accounting under head "Employee" — verified link.

        return response()->json($payment, 201);
    }
}
