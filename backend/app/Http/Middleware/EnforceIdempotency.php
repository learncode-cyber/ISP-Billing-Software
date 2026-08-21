<?php

namespace App\Http\Middleware;

use Closure;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;
use Symfony\Component\HttpFoundation\Response;

/**
 * EnforceIdempotency
 *
 * Makes offline retries safe. An offline device that times out never learns
 * whether its write landed, so it retries — carrying the SAME
 * `Idempotency-Key`. This middleware guarantees the operation is applied
 * exactly once.
 *
 * Flow:
 *   1. No key → pass through (online-only clients are unaffected).
 *   2. Key seen before and completed → replay the stored response. The
 *      handler never runs again, so no second payment is created.
 *   3. Key seen and still in_progress → 409; the client retries later
 *      rather than racing a request that may still be committing.
 *   4. New key → reserve it (the UNIQUE constraint on
 *      (tenant_id, idempotency_key) wins any race between two concurrent
 *      retries), run the handler, store the response.
 *
 * The reservation row is inserted BEFORE the handler runs, so even two
 * simultaneous retries from a flapping connection cannot both proceed —
 * one hits the unique violation and replays instead. This is what makes a
 * duplicate payment structurally impossible rather than merely unlikely.
 */
class EnforceIdempotency
{
    public function handle(Request $request, Closure $next): Response
    {
        $key = $request->header('Idempotency-Key');

        // Only mutating verbs need this.
        if (! $key || ! in_array($request->method(), ['POST', 'PATCH', 'PUT', 'DELETE'], true)) {
            return $next($request);
        }

        $tenantId = $request->user()?->tenant_id;
        if (! $tenantId) {
            return $next($request);
        }

        $endpoint = $request->method().' '.$request->path();
        $requestHash = hash('sha256', json_encode($request->all()));

        $existing = DB::table('platform.idempotency_keys')
            ->where('tenant_id', $tenantId)
            ->where('idempotency_key', $key)
            ->first();

        if ($existing) {
            // Same key with a DIFFERENT body is a client bug, not a retry —
            // refuse rather than silently returning the wrong response.
            if ($existing->request_hash && $existing->request_hash !== $requestHash) {
                return response()->json([
                    'message' => 'This idempotency key was already used with a different request body.',
                ], 422);
            }

            if ($existing->status === 'completed') {
                return response()->json(
                    json_decode($existing->response_body ?? '{}', true),
                    $existing->response_status ?? 200
                )->header('Idempotent-Replay', 'true');
            }

            // Still in flight — tell the client to back off and retry.
            return response()->json([
                'message' => 'This operation is already being processed.',
            ], 409);
        }

        try {
            DB::table('platform.idempotency_keys')->insert([
                'id' => (string) Str::uuid(),
                'tenant_id' => $tenantId,
                'idempotency_key' => $key,
                'device_id' => $request->header('X-Device-Id'),
                'endpoint' => $endpoint,
                'request_hash' => $requestHash,
                'status' => 'in_progress',
                'created_at' => now(),
            ]);
        } catch (\Illuminate\Database\QueryException $e) {
            // Lost the race to a concurrent retry — that request owns it.
            return response()->json(['message' => 'This operation is already being processed.'], 409);
        }

        $response = $next($request);

        DB::table('platform.idempotency_keys')
            ->where('tenant_id', $tenantId)
            ->where('idempotency_key', $key)
            ->update([
                'status' => $response->isSuccessful() ? 'completed' : 'failed',
                'response_status' => $response->getStatusCode(),
                'response_body' => $response->getContent(),
                'completed_at' => now(),
            ]);

        return $response;
    }
}
