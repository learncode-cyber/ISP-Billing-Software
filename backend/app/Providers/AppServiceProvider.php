<?php

namespace App\Providers;

use App\Listeners\AutomationEventSubscriber;
use Illuminate\Support\Facades\Event;
use Illuminate\Support\Facades\Request;
use Illuminate\Support\ServiceProvider;
use Laravel\Sanctum\Sanctum;

class AppServiceProvider extends ServiceProvider
{
    public function register(): void
    {
        // Bind 'current_tenant_id' used by the BelongsToTenant trait's
        // global scope. Resolves from the authenticated user at request
        // time; null for unauthenticated / console contexts (where RLS +
        // explicit tenant params handle isolation instead).
        $this->app->bind('current_tenant_id', function () {
            return optional(Request::user())->tenant_id;
        });
    }

    public function boot(): void
    {
        // Sanctum stores tokens in identity.sanctum_tokens (migration 027),
        // not its own default table — see App\Models\PersonalAccessToken
        // for why (tenant-aware RLS on the token store).
        Sanctum::usePersonalAccessTokenModel(\App\Models\PersonalAccessToken::class);

        // Route domain events into the Automation Engine.
        Event::subscribe(AutomationEventSubscriber::class);
    }
}
