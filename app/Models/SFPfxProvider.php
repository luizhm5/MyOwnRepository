<?php
namespace App\Models;

use Illuminate\Support\Facades\Log;

class SFPfxProvider extends BaseSalesforceProvider {

    protected $client;
    protected $sessionId;

    protected $proposalId;
    protected $viewId;
    protected $viewName;
    protected $longName;


    public function __construct($proposalId, $viewId, $viewName, $longName, $sessionId = null)
    {
        $this->proposalId = $proposalId;
        $this->viewId = $viewId;
        $this->viewName = $viewName;
        $this->longName = $longName;
        $this->sessionId = $sessionId;
        $this->initConnect();
    }

    public function getHeader(){
        $res = $this->client->getHeader([
            "proposalId" => $this->proposalId,
            "viewId" => $this->viewId,
            "viewName" => $this->viewName
        ]);

        return json_decode($res->result, true);
    }

    public function getData($offset){
        $res = $this->client->getData([
            "proposalId" => $this->proposalId,
            "viewId" => $this->viewId,
            "viewName" => $this->viewName,
            "longName" => $this->longName,
            "offset" => $offset,
        ]);

        return json_decode($res->result, true);
    }

    public function getExternalUnmappedData()
    {
        $res = $this->client->getExternalUnmappedData([
            "proposalId" => $this->proposalId,
            "viewId" => $this->viewId,
            "viewName" => $this->viewName,
            "longName" => $this->longName,
        ]);

        return json_decode($res->result, true);
    }

    private function initConnect(): void
    {
        try {
            // Get session ID from Canvas or passed parameter
            $sessionId = $this->sessionId ?? $this->getSessionIdFromCanvas();

            if (!$sessionId) {
                throw new \Exception('No Salesforce session ID available');
            }

            Log::info('Using Salesforce session ID for PFX Export', [
                'class' => static::class,
                'sessionId' => substr($sessionId, 0, 10) . '...'
            ]);

            // Create SOAP client with PFX Export View WSDL configuration
            $client = new \SoapClient(
                config("constants.PFX_EXPORT_VIEW_WSDL_PFX"),
                [
                    'trace' => 1,
                    'exceptions' => true,
                    'cache_wsdl' => WSDL_CACHE_NONE
                ]
            );

            $client->__setLocation(config("constants.WSDL_PFX_PFX_EXPORT_VIEW_END_POINT"));

            // Use the PFX_ExportViewService namespace
            $header = new \SoapHeader(
                'http://soap.sforce.com/schemas/class/PFX_ExportViewService',
                'SessionHeader',
                ['sessionId' => $sessionId]
            );

            $client->__setSoapHeaders([$header]);
            $this->client = $client;

            Log::info('SOAP Client initialized successfully for PFX Export', [
                'class' => static::class
            ]);

        } catch (\SoapFault $e) {
            Log::error('SOAP Client initialization failed for PFX Export', [
                'class' => static::class,
                'error' => $e->getMessage(),
                'trace' => $e->getTraceAsString()
            ]);
            throw new \Exception('Failed to connect to Salesforce: ' . $e->getMessage());
        } catch (\Exception $e) {
            Log::error('Unexpected error during SOAP Client initialization for PFX Export', [
                'class' => static::class,
                'error' => $e->getMessage(),
                'trace' => $e->getTraceAsString()
            ]);
            throw $e;
        }
    }

}
