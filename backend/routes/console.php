<?php

use Illuminate\Support\Facades\Schedule;

/**
 * Console entry point. The recurring schedule itself lives in
 * App\Console\Kernel (schedule()) for clarity and testability; this file
 * exists because Laravel 11's bootstrap references it. Ad-hoc artisan
 * closures can also be registered here if needed.
 */

// The scheduled jobs are defined in App\Console\Kernel::schedule().
// Run in production via: php artisan schedule:work  (see docker-compose scheduler service)
