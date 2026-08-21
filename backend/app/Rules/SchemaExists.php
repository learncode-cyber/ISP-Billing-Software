<?php

namespace App\Rules;

use Closure;
use Illuminate\Contracts\Validation\ValidationRule;
use Illuminate\Support\Facades\DB;

/**
 * SchemaExists
 *
 * REAL DEFECT found by HTTP-layer boot testing: Laravel's built-in
 * exists:table,column rule — AND Rule::exists('table', 'column'), which
 * routes through the identical Concerns\ValidatesAttributes::parseTable()
 * — splits any table string containing a dot into [connection, table].
 * Every validation rule in this project written as
 * 'exists:isp.zones,id' or Rule::exists('isp.zones', 'id') was therefore
 * silently trying to open a database CONNECTION named "isp", not query
 * the isp.zones schema-qualified table, and failing with
 * "Database connection [isp] not configured." on every real HTTP request
 * that exercised it — a defect invisible to any test that only inspects
 * source code, because the code reads correctly at a glance.
 *
 * This rule bypasses parseTable() entirely by querying DB::table()
 * directly, which handles "schema.table" as PostgreSQL expects.
 */
class SchemaExists implements ValidationRule
{
    public function __construct(private string $table, private string $column = 'id')
    {
    }

    public function validate(string $attribute, mixed $value, Closure $fail): void
    {
        if ($value === null) {
            return;
        }

        $exists = DB::table($this->table)->where($this->column, $value)->exists();

        if (! $exists) {
            $fail('The selected :attribute is invalid.');
        }
    }
}
