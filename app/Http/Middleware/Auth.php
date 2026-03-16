<?php

namespace App\Http\Middleware;

use Closure;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Session;
use Symfony\Component\HttpFoundation\Response;

class Auth
{
    /**
     * Handle an incoming request.
     *
     * @param  \Closure(Request): (Response)  $next
     */
    public function handle(Request $request, Closure $next): Response
    {
        if (env("ENVIRONMENT") === "dev") {
            Session::put('email', "Test.User@weather.com");
        }
        if(!session()->has('email')) {
            return \Illuminate\Support\Facades\Response::json("Error: Authorization Required, please contact your system administrator", 401);
        }
        return $next($request);
    }
}
