<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;

/**
 * GET /api/v1/network/diagram
 *
 * Replaces the audit's verified-but-minimal Network Diagram (which
 * rendered only a single "Root" text node with no live data behind it).
 * Reads network.v_topology_edges (016_network_diagram_topology.sql) —
 * always exactly the current Router/OLT/PON/ONU/Customer graph, never a
 * separately-maintained diagram data structure that could drift stale.
 */
class NetworkDiagramController extends Controller
{
    public function __invoke(Request $request)
    {
        $tenantId = $request->user()->tenant_id;

        $edges = DB::table('network.v_topology_edges')
            ->where('tenant_id', $tenantId) // defensive explicit filter — view composes RLS'd source tables
            ->get();

        $nodes = collect();
        foreach ($edges as $edge) {
            $nodes->put("{$edge->from_type}:{$edge->from_id}", ['id' => $edge->from_id, 'type' => $edge->from_type, 'label' => $edge->from_label]);
            $nodes->put("{$edge->to_type}:{$edge->to_id}", ['id' => $edge->to_id, 'type' => $edge->to_type, 'label' => $edge->to_label]);
        }

        return response()->json([
            'nodes' => $nodes->values(),
            'edges' => $edges->map(fn ($e) => [
                'from' => "{$e->from_type}:{$e->from_id}",
                'to' => "{$e->to_type}:{$e->to_id}",
                'status' => $e->edge_status,
            ]),
        ]);
    }
}
