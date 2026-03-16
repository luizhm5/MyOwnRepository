<?php
/**
 * Created by IntelliJ IDEA.
 * User: asychikov
 * Date: 01.02.2019
 * Time: 10:52
 */

namespace App\Models;


class SignedRequest
{
    protected $decodedRequest;
    protected $application;

    public function __construct($request, $application = null)
    {
        if (!$request) {
            throw new \Exception('Error: Signed request invalid, please contact your system administrator');
        }
        $this->application = $application;
        $this->decodedRequest = $this->decodeRequest($request, $application);
    }

    public function getDecodedRequest()
    {
        return $this->decodedRequest;
    }

    public function getApplication()
    {
        return $this->application;
    }

    private function decodeRequest($request, $application)
    {
        if (isset($application)) {
            $consumerSecret = $this->getConsumerSecret($application);
            if (!$this->signatureIsValid($consumerSecret, $request)) {
                throw new \Exception('Error: Signed request invalid, please contact your system administrator');
            }
        } else {
            // Try the various signatures to guess application
            if ($this->signatureIsValid(env("CONSUMER_SECRET"), $request)) {
                $this->application = config("constants.APP_KEY_INVOICE_EXPORT");
            } elseif ($this->signatureIsValid(env("CONSUMER_SECRET_HISTORY"), $request)) {
                $this->application = config("constants.APP_KEY_HISTORY_EXPORT");
            } elseif ($this->signatureIsValid(env("CONSUMER_SECRET_PFX"), $request)) {
                $this->application = config("constants.APP_KEY_PFX_EXPORT");
            } else {
                throw new \Exception('Error: Signed request invalid, please contact your system administrator');
            }
        }

        $sep = strpos($request, '.');
        $encodedEnv = substr($request, $sep + 1);
        $sr = base64_decode($encodedEnv);

        return json_decode($sr);
    }

    private function getConsumerSecret($application)
    {
        if ($application === config("constants.APP_KEY_PFX_EXPORT")) {
            return env("CONSUMER_SECRET_PFX");
        } elseif ($application === config("constants.APP_KEY_HISTORY_EXPORT")) {
            return env("CONSUMER_SECRET_HISTORY");
        } else {
            return env("CONSUMER_SECRET");
        }
    }

    private function signatureIsValid($consumerSecret, $request): bool
    {
        $sep = strpos($request, '.');
        $encodedSig = substr($request, 0, $sep);
        $encodedEnv = substr($request, $sep + 1);

        $calculatedSig = base64_encode(hash_hmac('sha256', $encodedEnv, $consumerSecret, true));

        if ($calculatedSig !== $encodedSig) {
            return false;
        }
        return true;
    }
}
