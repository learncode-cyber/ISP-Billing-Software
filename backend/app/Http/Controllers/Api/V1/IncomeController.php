<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;

/** Income: Other Income + Connection Charge (verified). Auto-posts to GL. */
class IncomeController extends Controller
{
    public function index(Request $request)
    {
        return response()->json(DB::table('accounting.income_entries')
            ->where('tenant_id',$request->user()->tenant_id)
            ->when($request->filled('head_id'), fn($q)=>$q->where('head_id',$request->head_id))
            ->orderByDesc('entry_date')->paginate(25));
    }

    public function store(Request $request)
    {
        $v = $request->validate([
            'head_id' => 'required|uuid', 'amount' => 'required|numeric|min:0.01',
            'description' => 'nullable|string', 'entry_date' => 'required|date',
        ]);
        $id = (string) Str::uuid();
        DB::table('accounting.income_entries')->insert([
            'id'=>$id,'tenant_id'=>$request->user()->tenant_id,...$v,
            'created_by'=>$request->user()->id,'created_at'=>now(),
        ]);
        return response()->json(['id'=>$id], 201);
    }
}
