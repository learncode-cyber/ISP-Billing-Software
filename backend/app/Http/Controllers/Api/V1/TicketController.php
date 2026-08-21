<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use App\Models\Support\Ticket;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Validation\Rule;
use App\Rules\SchemaExists;

/**
 * Reproduces the audit's verified Add Complaint / View All Complaint
 * workflow exactly: Select Customer, Category, Priority (High/Medium/
 * Low), Note, single Employee-for-Solve, Multiple Support Employees,
 * Customer SMS + Assigned Employee SMS toggles; View filters by
 * Customer/Category/Status/Priority/Assignee/date with 4 summary counters.
 */
class TicketController extends Controller
{
    public function index(Request $request)
    {
        $scope = $request->attributes->get('data_scope', 'ASSIGNED');
        $user = $request->user();

        $query = Ticket::query()
            ->when($request->filled('customer_id'), fn ($q) => $q->where('customer_id', $request->customer_id))
            ->when($request->filled('category_id'), fn ($q) => $q->where('category_id', $request->category_id))
            ->when($request->filled('status'), fn ($q) => $q->where('status', $request->status))
            ->when($request->filled('priority'), fn ($q) => $q->where('priority', $request->priority))
            ->when($request->filled('assigned_employee_id'), fn ($q) => $q->where('assigned_employee_id', $request->assigned_employee_id))
            ->when($request->filled('date_from'), fn ($q) => $q->where('created_at', '>=', $request->date_from))
            ->when($request->filled('date_to'), fn ($q) => $q->where('created_at', '<=', $request->date_to));

        // Technician role (ASSIGNED scope) only sees tickets assigned to
        // their own hr.employees record, or where they're in the
        // multi-support-staff list.
        if ($scope === 'ASSIGNED') {
            $employeeId = DB::table('hr.employees')->where('user_id', $user->id)->value('id');
            $query->where(function ($q) use ($employeeId) {
                $q->where('assigned_employee_id', $employeeId)
                  ->orWhereIn('id', DB::table('support.ticket_support_staff')->where('employee_id', $employeeId)->pluck('ticket_id'));
            });
        }

        $counters = [
            'pending' => (clone $query)->where('status', 'pending')->count(),
            'processing' => (clone $query)->where('status', 'processing')->count(),
            'solved' => (clone $query)->where('status', 'solved')->count(),
            'not_solved' => (clone $query)->where('status', 'not_solved')->count(),
        ];

        return response()->json([
            'counters' => $counters,
            'data' => $query->orderByDesc('created_at')->paginate(min((int) $request->get('per_page', 25), 200)),
        ]);
    }

    public function store(Request $request)
    {
        $validated = $request->validate([
            'customer_id' => ['required', 'uuid', new \App\Rules\SchemaExists('isp.customers', 'id')],
            'template_id' => ['nullable', 'uuid', new \App\Rules\SchemaExists('support.ticket_templates', 'id')],
            'category_id' => ['nullable', 'uuid', new \App\Rules\SchemaExists('support.ticket_categories', 'id')],
            'priority' => 'required|in:high,medium,low',
            'note' => 'nullable|string',
            'assigned_employee_id' => ['nullable', 'uuid', new \App\Rules\SchemaExists('hr.employees', 'id')],
            'support_employee_ids' => 'nullable|array',
            'support_employee_ids.*' => ['uuid', new \App\Rules\SchemaExists('hr.employees', 'id')],
            'customer_sms_enabled' => 'boolean',
            'employee_sms_enabled' => 'boolean',
        ]);

        $ticket = DB::transaction(function () use ($validated, $request) {
            $ticket = Ticket::create([
                ...collect($validated)->except('support_employee_ids')->toArray(),
                'ticket_no' => app(\App\Services\TicketCodeGenerator::class)->next($request->user()->tenant_id),
                'created_by' => $request->user()->id,
            ]);

            if (! empty($validated['support_employee_ids'])) {
                $ticket->supportStaff()->sync($validated['support_employee_ids']);
            }

            event(new \App\Events\TicketCreated($ticket)); // Automation Engine "event.ticket_created" hook

            return $ticket;
        });

        return response()->json($ticket, 201);
    }

    public function updateStatus(Request $request, Ticket $ticket)
    {
        $validated = $request->validate([
            'status' => 'required|in:pending,processing,solved,not_solved,escalated',
        ]);

        $ticket->update($validated); // DB trigger auto-computes resolution_time_minutes on 'solved'

        return response()->json($ticket->fresh());
    }

    public function rate(Request $request, Ticket $ticket)
    {
        $validated = $request->validate(['csat_rating' => 'required|integer|between:1,5']);
        $ticket->update($validated);

        return response()->json($ticket->fresh());
    }
}
