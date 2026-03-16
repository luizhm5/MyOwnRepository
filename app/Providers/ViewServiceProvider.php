<?php

namespace App\Providers;

use Illuminate\Support\ServiceProvider;

class ViewServiceProvider extends ServiceProvider
{
    /**
     * Register services.
     */
    public function register(): void
    {
        //
    }

    /**
     * Bootstrap services.
     */
    public function boot(): void
    {
        view()->composer('*', function ($view)
        {
            $basePath = $this->getBasePath();

            $data['basePath'] = $basePath;

            foreach ($data as $key => $value) {
                $view->with($key, $value);
            }
        });
    }


    function getBasePath(): string
    {
        $path = dirname($_SERVER['PHP_SELF']);
        if (strlen($path) === 1) {
            return "/";
        }
        return str_replace('\\', '/', $path) . "/";
    }
}
