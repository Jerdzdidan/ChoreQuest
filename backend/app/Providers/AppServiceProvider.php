<?php

namespace App\Providers;

use Illuminate\Cache\RateLimiting\Limit;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\RateLimiter;
use Illuminate\Support\ServiceProvider;

class AppServiceProvider extends ServiceProvider
{
    /**
     * Register any application services.
     */
    public function register(): void
    {
        //
    }

    /**
     * Bootstrap any application services.
     */
    public function boot(): void
    {
        // The grown-up stop checks a parent's password on a child's phone
        // (BE-10): five tries a minute per child. A named limiter, because
        // the plain throttle:5,1 keys on getAuthIdentifier(), which a Child
        // (a token holder, not an Authenticatable) does not have.
        RateLimiter::for('alarm-override', fn (Request $request) => Limit::perMinute(5)
            ->by('alarm-override:'.($request->user()?->getKey() ?? $request->ip())));
    }
}
