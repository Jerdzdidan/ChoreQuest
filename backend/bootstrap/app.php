<?php

use Illuminate\Foundation\Application;
use Illuminate\Foundation\Configuration\Exceptions;
use Illuminate\Foundation\Configuration\Middleware;
use Illuminate\Http\Request;
use Laravel\Sanctum\Http\Middleware\CheckAbilities;
use Laravel\Sanctum\Http\Middleware\CheckForAnyAbility;

return Application::configure(basePath: dirname(__DIR__))
    ->withRouting(
        web: __DIR__.'/../routes/web.php',
        api: __DIR__.'/../routes/api.php',
        commands: __DIR__.'/../routes/console.php',
        health: '/up',
    )
    ->withMiddleware(function (Middleware $middleware): void {
        $middleware->alias([
            'abilities' => CheckAbilities::class,
            'ability' => CheckForAnyAbility::class,
        ]);

        // This backend serves the mobile client only and has no login page.
        // Laravel's default is to send an unauthenticated guest to
        // route('login'), which does not exist here -- so a request that does
        // not ask for JSON (a photo URL opened in a browser, say) died with a
        // RouteNotFoundException and a 500 instead of a clean 401. Returning
        // null means no redirect is attempted and the AuthenticationException
        // is rendered as intended.
        $middleware->redirectGuestsTo(fn (Request $request) => null);
    })
    ->withExceptions(function (Exceptions $exceptions): void {
        // Everything under /api answers JSON, including failures. Without
        // this, an unauthenticated request that does not send an
        // Accept: application/json header -- a photo URL pasted into a
        // browser, for instance -- makes Laravel try to redirect to a `login`
        // route this application does not have, and the caller gets a 500
        // instead of a 401.
        $exceptions->shouldRenderJsonWhen(
            fn (Request $request) => $request->is('api/*') || $request->expectsJson()
        );
    })->create();
