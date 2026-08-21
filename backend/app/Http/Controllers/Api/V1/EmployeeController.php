<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use App\Models\Hr\Employee;
use Illuminate\Http\Request;

/** Employee list + create (verified Add Employee form). */
class EmployeeController extends Controller
{
    public function index()
    {
        return response()->json(Employee::orderBy('name')->get());
    }

    public function store(Request $request)
    {
        $v = $request->validate([
            'name' => 'required|string', 'mobile' => 'nullable|string', 'email' => 'nullable|email',
            'nid' => 'nullable|string', 'designation_id' => 'nullable|uuid', 'department_id' => 'nullable|uuid',
            'joining_date' => 'nullable|date', 'monthly_salary' => 'required|numeric|min:0',
            'status' => 'nullable|in:active,inactive', 'address' => 'nullable|string',
        ]);
        return response()->json(Employee::create($v), 201);
    }
}
