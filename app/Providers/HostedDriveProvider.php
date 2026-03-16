<?php

namespace App\Providers;

use App\Models\FileHelper;
use App\Models\Google\GoogleDriveHelper;
use Illuminate\Foundation\Application;
use Illuminate\Support\ServiceProvider;

class HostedDriveProvider extends ServiceProvider
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
        $this->app->singleton(FileHelper::class, function (Application $application) {
            return new GoogleDriveHelper();
        });
    }
}
