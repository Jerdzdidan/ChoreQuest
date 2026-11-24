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

        // Setting a sign-in PIN checks the parent's password (PA-2): six
        // tries a minute per account. Named for the same reason: the throttle
        // runs before abilities:parent turns a child token away, so it must
        // not need getAuthIdentifier(). Keyed by kind as well as id, so a
        // child cannot use up the parent with the same number's tries.
        RateLimiter::for('pin-change', fn (Request $request) => Limit::perMinute(6)
            ->by('pin-change:'.($request->user() ? class_basename($request->user()).':'.$request->user()->getKey() : $request->ip())));

        // Spending a minute of a locked app (AL-2): one a minute is the
        // pace, so six a minute per child leaves room for two phones and a
        // retry, and stops a runaway phone draining a child's minutes.
        RateLimiter::for('screen-time', fn (Request $request) => Limit::perMinute(6)
            ->by('screen-time:'.($request->user() ? class_basename($request->user()).':'.$request->user()->getKey() : $request->ip())));

        // App Lock's watcher reports (AL-4) every 15 minutes and when a
        // permission changes: ten a minute per phone is plenty. Keyed by the
        // phone, not by the address, so a household's phones behind one
        // router do not use up each other's reports or anyone's sign-ins.
        RateLimiter::for('app-lock-status', fn (Request $request) => Limit::perMinute(10)
            ->by('app-lock-status:'.(is_string($request->input('device_key')) ? $request->input('device_key') : $request->ip())));
    }
}
