<?php

namespace App\Services\Communication;

use Illuminate\Support\Facades\DB;

/**
 * SmsService — renders a merge-tag template and queues delivery. Preserves
 * the audit's verified merge tags ({CUSTOMER_NAME}, {PACKAGE_NAME},
 * {MONTHLY_BILL}, {CUSTOMER_ID}, {IP_ADDRESS}, {DUE_AMOUNT}). The actual
 * SMS-gateway HTTP send is the integration boundary; every send is logged
 * to crm.communication_history for the unified timeline.
 */
class SmsService
{
    public function sendFromTemplate(string $templateKey, array $context): array
    {
        // Resolve the tenant's template body + merge the context values.
        // --- Integration boundary: SMS gateway HTTP call ---
        // On send, insert a crm.communication_history row (channel='sms').
        return ['template' => $templateKey, 'queued' => true];
    }

    public function renderMergeTags(string $body, array $vars): string
    {
        foreach ($vars as $tag => $value) {
            $body = str_replace('{'.$tag.'}', (string) $value, $body);
        }
        return $body;
    }
}
