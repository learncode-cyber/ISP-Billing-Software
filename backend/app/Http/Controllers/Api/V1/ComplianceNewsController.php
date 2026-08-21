<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;

/**
 * BTRC Regulatory News (Blueprint Section 23). Platform-level content,
 * free on every plan — the route for this is intentionally NOT wrapped
 * in an entitlement middleware group (compliance.news.view resolves true
 * for all tenants via is_platform_default). Every admin/staff of every
 * tenant can read the published feed, matching the product decision.
 *
 * Read-only for tenants. Publishing/moderation happens in the AR Qudrix
 * Super Admin console (platform scope), never here.
 */
class ComplianceNewsController extends Controller
{
    public function index(Request $request)
    {
        // No tenant_id filter — btrc_news is platform-level, shared by all
        // tenants. Only published items are visible to tenant staff.
        $news = DB::table('compliance.btrc_news')
            ->where('is_published', true)
            ->when($request->filled('category'), fn ($q) => $q->where('category', $request->category))
            ->orderByDesc('published_at')
            ->paginate(20);

        return response()->json($news);
    }

    public function show(string $id)
    {
        $item = DB::table('compliance.btrc_news')
            ->where('id', $id)->where('is_published', true)->first();

        abort_if(! $item, 404);

        return response()->json($item);
    }
}
