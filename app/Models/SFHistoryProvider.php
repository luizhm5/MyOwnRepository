<?php
namespace App\Models;

use Illuminate\Support\Facades\Log;

class SFHistoryProvider extends BaseSalesforceProvider {

    protected $client;
    protected $sessionId;
    protected $proposalId;

    /**
     * SFProvider constructor.
     * @param $proposalId
     * @param $sessionId
     */
    public function __construct($proposalId, $sessionId = null)
    {
        $this->proposalId = $proposalId;
        $this->sessionId = $sessionId;
        $this->initConnect();
    }

    public function getHistoryReport($historyType = "Order History"){
        $res = $this->client->getHistoryReport([
            "proposalId" => $this->proposalId,
            "historyType" => $historyType
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

            Log::info('Using Salesforce session ID for History Export', [
                'class' => static::class,
                'sessionId' => substr($sessionId, 0, 10) . '...'
            ]);

            // Create SOAP client with History Report WSDL configuration
            $client = new \SoapClient(
                config('constants.HISTORY_REPORT_WSDL_PFX'),
                [
                    'trace' => 1,
                    'exceptions' => true,
                    'cache_wsdl' => WSDL_CACHE_NONE
                ]
            );

            $client->__setLocation(config('constants.WSDL_PFX_HISTORY_REPORT_END_POINT'));

            // Use the PFX_HistoryReportService namespace
            $header = new \SoapHeader(
                'http://soap.sforce.com/schemas/class/PFX_HistoryReportService',
                'SessionHeader',
                ['sessionId' => $sessionId]
            );

            $client->__setSoapHeaders([$header]);
            $this->client = $client;

            Log::info('SOAP Client initialized successfully for History Export', [
                'class' => static::class
            ]);

        } catch (\SoapFault $e) {
            Log::error('SOAP Client initialization failed for History Export', [
                'class' => static::class,
                'error' => $e->getMessage(),
                'trace' => $e->getTraceAsString()
            ]);
            throw new \Exception('Failed to connect to Salesforce: ' . $e->getMessage());
        } catch (\Exception $e) {
            Log::error('Unexpected error during SOAP Client initialization for History Export', [
                'class' => static::class,
                'error' => $e->getMessage(),
                'trace' => $e->getTraceAsString()
            ]);
            throw $e;
        }
    }

}
