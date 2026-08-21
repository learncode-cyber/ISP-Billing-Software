<?php

namespace App\Services;

use App\Models\Customer;
use App\Models\User;
use Illuminate\Support\Facades\DB;

/**
 * CustomerProvisioningService
 *
 * The ONE place a customer is created — used by both CustomerController
 * (direct entry) and LeadController (lead conversion), so the verified
 * Create Customer field mapping and MikroTik secret auto-creation live in
 * exactly one implementation (DRY, and no drift between the two paths).
 */
class CustomerProvisioningService
{
    public function __construct(
        private CustomerCodeGenerator $codes,
        private MikrotikService $mikrotik,
    ) {}

    public function create(array $data, User $actor): Customer
    {
        return DB::transaction(function () use ($data, $actor) {
            $customer = Customer::create([
                'full_name' => $data['full_name'],
                'mobile' => $data['mobile'],
                'other_mobile' => $data['other_mobile'] ?? null,
                'email' => $data['email'] ?? null,
                'gender' => $data['gender'] ?? null,
                'onu_mac_address' => $data['onu_mac_address'] ?? null,
                'nid_passport_no' => $data['nid_passport_no'] ?? null,
                'address' => $data['address'] ?? null,
                'fiber_code' => $data['fiber_code'] ?? null,
                'agent_type' => $data['agent_type'] ?? 'optical_fiber',
                'connection_type' => $data['connection_type'] ?? 'home',
                'connection_date' => $data['connection_date'] ?? now()->toDateString(),
                'zone_id' => $data['zone_id'],
                'subzone_id' => $data['subzone_id'] ?? null,
                'destination_id' => $data['destination_id'] ?? null,
                'billing_person_id' => $data['billing_person_id'],
                'status' => $data['status'] ?? 'active',
                'remarks' => $data['remarks'] ?? null,
                'sms_notification_enabled' => $data['sms_notification_enabled'] ?? true,
                'reseller_id' => $data['reseller_id'] ?? null,
                'customer_code' => $this->codes->next($actor->tenant_id),
                'created_by' => $actor->id,
            ]);

            $service = $customer->services()->create([
                'service_type' => 'internet',
                'package_id' => $data['package_id'],
                'monthly_bill' => $data['monthly_bill'],
                'running_month_paid_amount' => $data['running_month_paid_amount'] ?? 0,
                'connection_fee_paid' => $data['connection_fee_paid'] ?? 0,
                'disconnect_day' => $data['disconnect_day'],
                'status' => $data['status'] ?? 'active',
            ]);

            // Verified behavior: MikroTik secret auto-created on customer creation.
            if (! empty($data['router_id']) && ! empty($data['pppoe_username'])) {
                $this->mikrotik->createSecretAsync(
                    routerId: $data['router_id'],
                    customerServiceId: $service->id,
                    username: $data['pppoe_username'],
                    secretPassword: $data['pppoe_secret_password'],
                    profile: null,
                );
            }

            // Fires "New Customer -> Welcome SMS" automation.
            event(new \App\Events\CustomerCreated($customer));

            return $customer;
        });
    }
}
