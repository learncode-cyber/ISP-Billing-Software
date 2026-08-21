<?php

namespace App\Services;

/**
 * AutomationConditionEvaluator — evaluates an automation rule's condition
 * JSON against the trigger context. A small, explicit interpreter over
 * KNOWN condition keys only — never a generic expression evaluator, so no
 * arbitrary user-supplied logic is ever executed server-side.
 */
class AutomationConditionEvaluator
{
    public function evaluate(array $conditions, array $context): bool
    {
        foreach ($conditions as $key => $expected) {
            switch ($key) {
                case 'invoice.status':
                    if (($context['invoice.status'] ?? null) !== $expected) return false;
                    break;
                case 'secret.status':
                    if (($context['secret.status'] ?? null) !== $expected) return false;
                    break;
                case 'exclude_partially_paid':
                    if ($expected && ($context['invoice.status'] ?? null) === 'partial') return false;
                    break;
                case 'past_disconnect_day':
                    if ($expected && ! ($context['past_disconnect_day'] ?? false)) return false;
                    break;
                default:
                    // Unknown condition key -> fail safe (do not fire).
                    if (($context[$key] ?? null) !== $expected) return false;
            }
        }
        return true;
    }
}
