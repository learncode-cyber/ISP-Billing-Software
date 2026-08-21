<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;

/** Inventory: products, stock levels, low-stock alerts (verified module +
 *  serialized tracking + customer hardware linkage). */
class InventoryController extends Controller
{
    public function products(Request $request)
    {
        return response()->json(DB::table('inventory.products')
            ->where('tenant_id', $request->user()->tenant_id)->whereNull('deleted_at')
            ->paginate(min((int)$request->get('per_page',25),200)));
    }

    public function stock(Request $request)
    {
        $rows = DB::table('inventory.stock_levels as sl')
            ->join('inventory.products as p', 'p.id', '=', 'sl.product_id')
            ->join('inventory.warehouses as w', 'w.id', '=', 'sl.warehouse_id')
            ->where('sl.tenant_id', $request->user()->tenant_id)
            ->select('p.name as product','w.name as warehouse','sl.quantity','p.low_stock_threshold',
                DB::raw('(sl.quantity <= p.low_stock_threshold) as is_low'))
            ->get();
        return response()->json($rows);
    }

    public function createProduct(Request $request)
    {
        $v = $request->validate([
            'name' => 'required|string', 'category_id' => 'nullable|uuid',
            'sku' => 'nullable|string', 'unit' => 'nullable|string',
            'is_serialized' => 'boolean', 'low_stock_threshold' => 'nullable|integer',
        ]);
        $id = (string) Str::uuid();
        DB::table('inventory.products')->insert([
            'id' => $id, 'tenant_id' => $request->user()->tenant_id, ...$v,
            'unit' => $v['unit'] ?? 'piece', 'low_stock_threshold' => $v['low_stock_threshold'] ?? 5,
            'created_at' => now(), 'updated_at' => now(),
        ]);
        return response()->json(['id' => $id], 201);
    }
}
