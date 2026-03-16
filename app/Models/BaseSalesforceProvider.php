<?php

namespace App\Models;

use Illuminate\Support\Facades\Log;

/**
 * Base class for Salesforce provider classes that use Canvas OAuth tokens
 */
abstract class BaseSalesforceProvider
{
    /**
     * Retrieve OAuth token from Canvas session
     *
     * @return string|null The OAuth token if found, null otherwise
     */
    protected function getSessionIdFromCanvas(): ?string
    {
        if (session()->has('canvasClient')) {
            $canvasClient = session('canvasClient');
            if (isset($canvasClient->client->oauthToken)) {
                Log::info('Retrieved OAuth token from Canvas session', [
                    'class' => static::class
                ]);
                return $canvasClient->client->oauthToken;
            }
        }

        Log::warning('No Canvas OAuth token found in session', [
            'class' => static::class
        ]);

        return null;
    }
}
