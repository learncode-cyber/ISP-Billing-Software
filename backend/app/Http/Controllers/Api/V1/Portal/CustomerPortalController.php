<?php

namespace App\Http\Controllers\Api\V1\Portal;

use App\Http\Controllers\Controller;
use App\Services\Payments\PaymentGatewayManager;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;

/**
 * Customer Self-Service Portal (Blueprint Section 25). Closes the largest
 * confirmed competitive gap. Authenticated via the `customer` guard
 * (isp.customer_portal_accounts) — strictly OWN scope: every query is
 * bound to $request->user()->customer_id, and RLS tenant isolation
 * applies on top. Never exposes support.ticket_internal_notes (only
 * ticket_replies), by design of the separate-tables split in Phase 4.
 */
class CustomerPortalController extends Controller
{
    public function dashboard(Request $request)
    {
        $customerId = $request->user()->customer_id;

        $service = DB::table('isp.customer_services')
            ->where('customer_id', $customerId)->where('deleted_at', null)->first();

        $latestInvoice = DB::table('billing.invoices')
            ->where('customer_service_id', $service->id ?? null)
            ->orderByDesc('generated_at')->first();

        $onuStatus = DB::table('network.onu_devices')
            ->where('customer_service_id', $service->id ?? null)->value('status');

        return response()->json([
            'service' => $service,
            'current_bill' => $latestInvoice,
            'connection_status' => $onuStatus ?? 'unknown',
        ]);
    }

    public function invoices(Request $request)
    {
        $customerId = $request->user()->customer_id;

        return response()->json(
            DB::table('billing.invoices as i')
                ->join('isp.customer_services as cs', 'cs.id', '=', 'i.customer_service_id')
                ->where('cs.customer_id', $customerId)
                ->orderByDesc('i.generated_at')
                ->select('i.*')
                ->paginate(12)
        );
    }

    public function payOnline(Request $request, PaymentGatewayManager $gateways)
    {
        $validated = $request->validate([
            'invoice_id' => 'required|uuid',
            'provider' => 'required|in:bkash,nagad,sslcommerz,stripe',
        ]);

        // Ownership guard: the invoice must belong to THIS customer.
        $invoice = DB::table('billing.invoices as i')
            ->join('isp.customer_services as cs', 'cs.id', '=', 'i.customer_service_id')
            ->where('i.id', $validated['invoice_id'])
            ->where('cs.customer_id', $request->user()->customer_id)
            ->select('i.*')->first();

        abort_if(! $invoice, 403, 'Invoice does not belong to this account.');

        $result = $gateways->forTenant($request->user()->tenant_id, $validated['provider'])
            ->initiate($request->user()->tenant_id, $invoice->id, $invoice->total_due - $invoice->total_paid);

        return response()->json($result);
    }

    public function tickets(Request $request)
    {
        return response()->json(
            DB::table('support.tickets')
                ->where('customer_id', $request->user()->customer_id)
                ->orderByDesc('created_at')
                ->get()
        );
    }

    /** Customer profile — own record only, sensitive fields stripped. */
    public function profile(Request $request)
    {
        $c = DB::table('isp.customers')
            ->where('id', $request->user()->customer_id)
            ->select('id','customer_code','full_name','mobile','other_mobile','email','address',
                     'connection_date','connection_type','status')
            ->first();
        abort_if(! $c, 404);

        // Package/service info shown alongside the profile.
        $service = DB::table('isp.customer_services as cs')
            ->leftJoin('isp.packages as p', 'p.id', '=', 'cs.package_id')
            ->where('cs.customer_id', $c->id)->whereNull('cs.deleted_at')
            ->select('cs.id','cs.monthly_bill','cs.disconnect_day','cs.status',
                     'p.name as package_name','p.bandwidth_down_mbps','p.bandwidth_up_mbps')
            ->first();

        return response()->json(['customer' => $c, 'service' => $service]);
    }

    /** Payment history for this customer only. */
    public function payments(Request $request)
    {
        $rows = DB::table('billing.payments as pay')
            ->join('billing.invoices as i', 'i.id', '=', 'pay.invoice_id')
            ->join('isp.customer_services as cs', 'cs.id', '=', 'i.customer_service_id')
            ->where('cs.customer_id', $request->user()->customer_id)
            ->orderByDesc('pay.paid_at')
            ->select('pay.id','pay.amount','pay.discount_amount','pay.method',
                     'pay.transaction_reference','pay.paid_at','i.invoice_no')
            ->paginate(25);

        return response()->json($rows);
    }

    /** Raise a complaint from the portal. */
    public function createTicket(Request $request)
    {
        $v = $request->validate([
            'priority' => 'required|in:high,medium,low',
            'note' => 'required|string|max:2000',
        ]);

        $customerId = $request->user()->customer_id;
        $tenantId = $request->user()->tenant_id;

        $ticketNo = app(\App\Services\TicketCodeGenerator::class)->next($tenantId);
        $id = (string) \Illuminate\Support\Str::uuid();

        DB::table('support.tickets')->insert([
            'id' => $id, 'tenant_id' => $tenantId, 'ticket_no' => $ticketNo,
            'customer_id' => $customerId, 'priority' => $v['priority'],
            'note' => $v['note'], 'status' => 'pending',
            'created_at' => now(), 'updated_at' => now(),
        ]);

        return response()->json(['id' => $id, 'ticket_no' => $ticketNo], 201);
    }

    /** Customer-visible reply thread — internal staff notes are in a
     *  separate table and are never exposed here by construction. */
    public function ticketReplies(Request $request, string $ticket)
    {
        $owned = DB::table('support.tickets')->where('id', $ticket)
            ->where('customer_id', $request->user()->customer_id)->exists();
        abort_if(! $owned, 403, 'Ticket does not belong to this account.');

        return response()->json(
            DB::table('support.ticket_replies')->where('ticket_id', $ticket)
                ->orderBy('created_at')->get()
        );
    }

    public function replyToTicket(Request $request, string $ticket)
    {
        $v = $request->validate(['message' => 'required|string|max:2000']);

        $owned = DB::table('support.tickets')->where('id', $ticket)
            ->where('customer_id', $request->user()->customer_id)->exists();
        abort_if(! $owned, 403, 'Ticket does not belong to this account.');

        DB::table('support.ticket_replies')->insert([
            'id' => (string) \Illuminate\Support\Str::uuid(),
            'tenant_id' => $request->user()->tenant_id,
            'ticket_id' => $ticket, 'author_type' => 'customer',
            'author_id' => $request->user()->customer_id,
            'message' => $v['message'], 'created_at' => now(),
        ]);

        return response()->json(['status' => 'sent'], 201);
    }

    /** Usage/session history where RADIUS or MikroTik data exists. */
    public function usage(Request $request)
    {
        $serviceId = DB::table('isp.customer_services')
            ->where('customer_id', $request->user()->customer_id)->value('id');
        if (! $serviceId) return response()->json(['sessions' => []]);

        $sessions = DB::table('network.radius_accounting as ra')
            ->join('network.pppoe_secrets as ps', 'ps.id', '=', 'ra.pppoe_secret_id')
            ->where('ps.customer_service_id', $serviceId)
            ->orderByDesc('ra.session_start')->limit(30)
            ->select('ra.session_start','ra.session_stop','ra.input_octets','ra.output_octets','ra.framed_ip_address')
            ->get();

        return response()->json(['sessions' => $sessions]);
    }

    /** Notifications addressed to this customer. */
    public function notifications(Request $request)
    {
        return response()->json(
            DB::table('crm.communication_history')
                ->where('customer_id', $request->user()->customer_id)
                ->orderByDesc('created_at')->limit(50)
                ->select('id','channel','summary','created_at')->get()
        );
    }

    

    

    public function changePassword(Request $request)
    {
        $v = $request->validate([
            'current_password' => 'required|string',
            'new_password' => 'required|string|min:8',
        ]);

        $acct = DB::table('isp.customer_portal_accounts')->where('id', $request->user()->id)->first();
        abort_if(! $acct, 404);

        if (! \Illuminate\Support\Facades\Hash::check($v['current_password'], $acct->password_hash)) {
            return response()->json(['message' => 'Current password is incorrect.'], 422);
        }

        DB::table('isp.customer_portal_accounts')->where('id', $acct->id)->update([
            'password_hash' => \Illuminate\Support\Facades\Hash::make($v['new_password']),
        ]);

        // Password changes are security-relevant — audit them.
        DB::table('audit.activity_logs')->insert([
            'id' => (string) \Illuminate\Support\Str::uuid(),
            'tenant_id' => $request->user()->tenant_id,
            'action' => 'portal.password_changed',
            'entity_type' => 'isp.customer_portal_accounts',
            'entity_id' => $acct->id,
            'ip_address' => $request->ip(),
            'device' => $request->userAgent(),
            'result' => 'success',
            'source' => 'user',
            'created_at' => now(),
        ]);

        return response()->json(['status' => 'updated']);
    }
}
