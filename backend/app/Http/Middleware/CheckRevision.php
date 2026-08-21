<?php

namespace App\Http\Middleware;

use Closure;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Symfony\Component\HttpFoundation\Response;

/**
 * CheckRevision
 *
 * Optimistic concurrency for offline edits. A device that edited a record
 * while offline sends the revision it was working from in
 * `If-Match-Revision`. If the server has moved on since, the write is
 * rejected with 409 and the client surfaces it on the Sync Conflicts
 * screen for a human to resolve.
 *
 * The rule the spec insists on: **never silently overwrite newer server
 * data.** Last-write-wins is not acceptable when the "last" write may be
 * a three-day-old edit from a technician's phone that was in a basement.
 *
 * Usage: ->middleware('revision:isp.customers,customer')
 *   arg 1 = fully-qualified table
 *   arg 2 = route parameter holding the record id
 */
class CheckRevision
{
    public function handle(Request $request, Closure $next, string $table, string $routeParam): Response
    {
        $clientRevision = $request->header('If-Match-Revision');

        if (! $clientRevision) {
            return $next($request); // online clients that always read-then-write
        }

        $record = $request->route($routeParam);
        $id = is_object($record) ? $record->id : $record;

        if (! $id) {
            return $next($request);
        }

        $serverRevision = DB::table($table)->where('id', $id)->value('revision');

        if ($serverRevision !== null && (int) $clientRevision < (int) $serverRevision) {
            return response()->json([
                'message' => 'This record was changed on the server after your offline edit.',
                'server_revision' => $serverRevision,
                'your_revision' => (int) $clientRevision,
                'conflict' => true,
            ], 409);
        }

        return $next($request);
    }
}
