<?php
namespace App\Models;

use Illuminate\Support\Facades\Log;

class SFBillingProvider extends BaseSalesforceProvider {

    protected $client;
    protected $sessionId;
    protected $periodId;
    protected $billingStatus;
    protected $searchTerm;
    protected $isFinal;
    protected $isIERP;
    protected $invoiceIds;
    protected $instanceUrl;

    /**
     * SFProvider constructor.
     * @param $periodId
     * @param $billingStatus
     * @param $searchTerm
     * @param $isFinal
     * @param $isIERP
     * @param $invoiceIds
     * @param $sessionId
     * @param $instanceUrl
     */
    public function __construct($periodId = "", $billingStatus = "", $searchTerm = "", $isFinal = 0, $isIERP = false, $invoiceIds = "", $sessionId = null, $instanceUrl = null)
    {
        $this->periodId = $periodId;
        $this->billingStatus = $billingStatus;
        $this->searchTerm = $searchTerm;
        $this->isFinal = $isFinal;
        $this->isIERP = $isIERP;
        $this->invoiceIds = $invoiceIds;
        $this->sessionId = $sessionId;
        $this->instanceUrl = $instanceUrl;

        $this->initConnect();
    }

    public function getReportHeader(){
        $res = $this->client->getReportHeader([
            "periodId" => $this->periodId,
            "billingStatus" => $this->billingStatus,
            "searchTerm" => $this->searchTerm,
            "invoiceIds" => $this->invoiceIds,
        ]);

        return json_decode($res->result, true);
    }

    public function receiveDataByTimeAndBillingStatusAndSearchTerm($page = 0, $to = null){
        $res = $this->client->receiveDataByTimeAndBillingStatusAndSearchTerm([
            "periodId" => $this->periodId,
            "billingStatus" => $this->billingStatus,
            "searchTerm" => $this->searchTerm,
            "isFinal" => $this->isFinal,
            "invoiceIds" => $this->invoiceIds,
            "page" => $page,
            "to" => $to,
        ]);

        return json_decode($res->result, true);
    }

    public function getCumulativeInfo($recordIds = []){
        $res = $this->client->getCumulativeInfo([
            "recordIds" => $recordIds,
            "isFinal" => $this->isFinal,
        ]);

        return json_decode($res->result, true);
    }

    public function cleanUpFinExportRows(){
        $this->client->cleanUpFinExportRows([
            "periodId" => $this->periodId,
            "billingStatus" => $this->billingStatus,
            "searchTerm" => $this->searchTerm
        ]);

        return true;
    }

    public function createFinExportRequests(){
        $this->client->createFinExportRequests([
            "periodId" => $this->periodId,
            "isIERP" => $this->isIERP
        ]);

        return true;
    }

    private function initConnect(): void
    {
        try {
            // Get session ID from Canvas or passed parameter
            $sessionId = $this->sessionId ?? $this->getSessionIdFromCanvas();

            if (!$sessionId) {
                throw new \Exception('No Salesforce session ID available');
            }

            Log::info('Using Salesforce session ID for Invoice Export', [
                'class' => static::class,
                'sessionId' => substr($sessionId, 0, 10) . '...'
            ]);

            // Create SOAP client with Billing Report WSDL configuration
            $client = new \SoapClient(
                config("constants.BILLING_REPORT_WSDL_PFX"),
                [
                    'trace' => 1,
                    'exceptions' => true,
                    'cache_wsdl' => WSDL_CACHE_NONE
                ]
            );

            if ($this->instanceUrl) {
                // Ensure instance URL doesn't end with slash before appending service path
                $baseUrl = rtrim($this->instanceUrl, '/');
                $client->__setLocation($baseUrl . '/services/Soap/class/PFX_BillingReportService');
            } else {
                $client->__setLocation(config("constants.WSDL_PFX_BILLING_REPORT_END_POINT"));
            }

            // Use the PFX_BillingReportService namespace
            $header = new \SoapHeader(
                'http://soap.sforce.com/schemas/class/PFX_BillingReportService',
                'SessionHeader',
                ['sessionId' => $sessionId]
            );

            $client->__setSoapHeaders([$header]);
            $this->client = $client;

            Log::info('SOAP Client initialized successfully for Invoice Export', [
                'class' => static::class
            ]);

        } catch (\SoapFault $e) {
            Log::error('SOAP Client initialization failed for Invoice Export', [
                'class' => static::class,
                'error' => $e->getMessage(),
                'trace' => $e->getTraceAsString()
            ]);
            throw new \Exception('Failed to connect to Salesforce: ' . $e->getMessage());
        } catch (\Exception $e) {
            Log::error('Unexpected error during SOAP Client initialization for Invoice Export', [
                'class' => static::class,
                'error' => $e->getMessage(),
                'trace' => $e->getTraceAsString()
            ]);
            throw $e;
        }
    }

}
