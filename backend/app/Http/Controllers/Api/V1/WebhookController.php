<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Crypt;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;

/** Webhook subscription CRUD (Blueprint Section 12). */
class WebhookController extends Controller
{
    public function index(Request $request)
    {
        return response()->json(DB::table('integrations.webhook_subscriptions')
            ->where('tenant_id', $request->user()->tenant_id)->get()
            ->map(fn($w) => collect($w)->except('signing_secret_encrypted')));
    }

    public function store(Request $request)
    {
        $v = $request->validate([
            'event_type' => 'required|string',
            'target_url' => 'required|url',
        ]);
        $secret = Str::random(40);
        $id = (string) Str::uuid();
        DB::table('integrations.webhook_subscriptions')->insert([
            'id' => $id,
            'tenant_id' => $request->user()->tenant_id,
            'event_type' => $v['event_type'],
            'target_url' => $v['target_url'],
            'signing_secret_encrypted' => Crypt::encryptString($secret),
            'is_active' => true,
            'created_at' => now(),
        ]);
        // Secret shown ONCE at creation so the subscriber can verify signatures.
        return response()->json(['id' => $id, 'signing_secret' => $secret], 201);
    }

    public function destroy(Request $request, string $webhook)
    {
        DB::table('integrations.webhook_subscriptions')
            ->where('id', $webhook)->where('tenant_id', $request->user()->tenant_id)->delete();
        return response()->json(null, 204);
    }
}
