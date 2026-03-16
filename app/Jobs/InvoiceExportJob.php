<?php

namespace App\Jobs;

use App\Exceptions\CustomException;
use App\Models\FileHelper;
use App\Models\SFBillingProvider;
use Illuminate\Bus\Queueable;
use Illuminate\Contracts\Queue\ShouldQueue;
use Illuminate\Foundation\Bus\Dispatchable;
use Illuminate\Queue\InteractsWithQueue;
use Illuminate\Queue\SerializesModels;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Log;

require __DIR__ . "/../../" . 'vendor/weatherfx/box-jwt/helpers/helpers.php';
define('SHEET_NAME', 'PFX export');
class InvoiceExportJob implements ShouldQueue
{
    use Dispatchable, InteractsWithQueue, Queueable, SerializesModels;

    protected $config;
    /**
     * Create a new job instance.
     */
    public function __construct($data)
    {
        $this->config = $data;
    }

    /**
     * Execute the job.
     */
    public function handle(): void
    {
        //
        try{
            $taskId = $this->config["taskId"];

            $res = DB::select("SELECT * FROM " . config("constants.BILLING_EXPORT_TMP_TABLE") . " WHERE taskId=" . $taskId);

            if(count($res) > 0) {
                $obj = $res[0];
                $periodId = $obj->period_id;
                $periodName = $obj->period_name;
                $billingStatus = $obj->billing_status;
                $searchTerm = $obj->search_term;
                $invoiceIds = $obj->invoice_ids;
                $isFinal = (int)$obj->is_final;
                $isIERP = (bool)$obj->is_ierp;

                if ($isFinal && empty(config("constants.BOX_FOLDER_ID_FINAL_INVOICE"))) {
                    throw new CustomException("BOX_FOLDER_ID_FINAL_INVOICE is empty in env file, please contact your system administrator");
                }

            }else{
                throw new CustomException("cant select task");
            }

            $progress = 0;

            Log::info("Start worker", ['taskId' => $taskId, 'periodId' => $periodId, 'billingStatus' => $billingStatus, 'searchTerm' => $searchTerm, 'isFinal' => $isFinal, 'invoiceIds' => $invoiceIds]);

            $this->dbLogger($taskId, "Start period: " . $periodId . ", billing status: " . $billingStatus . ", search term: " . $searchTerm . ", invoice ids: " . $invoiceIds);

            if($isFinal){
                $this->dbLogger($taskId, "############### IS FINAL REPORT ###############");
            }

            // Extract session ID and instance URL from config
            $sessionId = $this->config["sessionId"] ?? null;
            $instanceUrl = $this->config["instanceUrl"] ?? null;

            $sfp = new SFBillingProvider($periodId, $billingStatus, $searchTerm, $isFinal, $isIERP, $invoiceIds, $sessionId, $instanceUrl);

            if($isFinal){
                Log::info("-- cleanUpFinExportRows");
                $this->dbLogger($taskId, "Cleanup fin export rows");
                $sfp->cleanUpFinExportRows();
            }

            Log::info("-- get header data");

            $this->dbLogger($taskId, "Get header data");

            $headerRaw = $sfp->getReportHeader();

            $headerData = [];
            $count = $headerRaw["count"];
            $to = $headerRaw["to"];
            $pageSize = $headerRaw["pageSize"];

            $cumulativeIndexes = $headerRaw["cumulativeIndexes"]; // [69, 71, 72, 73, 74, 75, 168]
            $baseCumulativeIndex = $cumulativeIndexes[0]; // 69

            $this->dbLogger($taskId, "Found " . $count . " record(s)");

            Log::info("-- records count: " . $count);
            Log::info("-- page size: " . $pageSize);
            if ($count <= $pageSize) {
                $pageCount = 0;
            } else {
                $pageCount = floor($count / $pageSize);
            }
            Log::info("-- pageCount: " . $pageCount);

            foreach ($headerRaw['fields'] as $field){

                if(isset($headerData[$field['label']])){
                    $headerData[$field['label'] . " "] = $field['type'];
                }else{
                    $headerData[$field['label']] = $field['type'];
                }

            }
            Log::info("Start processing data");
            $this->dbLogger($taskId, "Start processing data", 10);

            $writer = new \XLSXWriter();
            $writer->setAuthor('The Weather Channel');
            $writer->writeSheetHeader(SHEET_NAME, $headerData, array('font-style' => 'bold'));

            for ($page = 0; $page <= $pageCount; $page++) {

                $data = $sfp->receiveDataByTimeAndBillingStatusAndSearchTerm($page, $to);

                // ["a3J2K000005bYm5UAE", "a3J2K000005bKcRUAU"]
                $ids = array_map(function ($item) use ($baseCumulativeIndex) { return $item[$baseCumulativeIndex]; }, $data['data']);

                // {"a3J2K000005bKcRUAU":{"168":0.0000,"75":0,"74":0,"73":0,"72":0,"71":0.0000,"69":0},"a3J2K000005bYm5UAE":{"168":550000.0000,"75":0,"74":0,"73":0,"72":1,"71":550000.0000,"69":0}}
                $cumulativeInfo = $sfp->getCumulativeInfo($ids);

                foreach($data["data"] as $row){

                    foreach ($cumulativeIndexes as $cIndex){
                        $row[$cIndex] = $cumulativeInfo[$row[$cIndex]][$cIndex];
                    }

                    $writer->writeSheetRow(SHEET_NAME, $row);

                    $progress++;
                    if($progress % 50 === 0){
                        $current = round((($progress / $count) * 80)) + 10;

                        $this->dbLogger($taskId,"Processed ". $progress . " entries from " . $count, $current);

                        Log::info("-- progress " . $current . "%");
                    }
                }
            }

            $this->dbLogger($taskId, "Processed ". $progress . " entries from " . $count);

            if($isFinal){
                Log::info("-- createFinExportRequests");
                $this->dbLogger($taskId, "Create fin export request");
                $sfp->createFinExportRequests();
            }

            $this->dbLogger($taskId, "End processing data");

            $this->dbLogger($taskId, "Start upload process");

            //UPLOAD FILE IN BOX.COM
            if($isFinal){
                $outFileName = sys_get_temp_dir() . '/Invoice_export_final_' . $periodName . ".xlsx";
            }else{
                $outFileName = sys_get_temp_dir() . '/Invoice_export_N' . $taskId . '_D' . date('m-d-y_h-i') . ".xlsx";
            }

            $writer->writeToFile($outFileName);

            $fileHelper = app()->make(FileHelper::class);
            $fileId = $fileHelper->uploadFile($outFileName, config('google.history_export_folder'), basename($outFileName));

            // Not shared file if isFinal
            if($isFinal){
                DB::update("update " . config("constants.BILLING_EXPORT_TMP_TABLE") . " set state=10, progress=100 where taskId=?", [$taskId]);
            }else{
                $downloadLink = $fileHelper->shareReadWithAll($fileId);
                DB::update("update " . config("constants.BILLING_EXPORT_TMP_TABLE") . " set state=10, progress=100, file_url=? where taskId=?", [filter_var($downloadLink, FILTER_SANITIZE_URL), $taskId]);
            }

            $this->dbLogger($taskId, "End upload process");

            Log::info("End worker", ['taskId' => $taskId, 'periodId' => $periodId]);

            $this->dbLogger($taskId, "Process finished", 100);

        }catch (\Exception $exception){
            Log::error($exception);
            DB::update("update " . config("constants.BILLING_EXPORT_TMP_TABLE") . " set state=-1, error_msg=? where taskId=?", [ $exception->getMessage(), $taskId]);

            $this->dbLogger($taskId,"Process error: " . $exception->getMessage());

            Log::critical($exception->getMessage());
        }
    }


    function dbLogger(int $taskId, string $message, int $progress = 0): void
    {
        $tempTable = config("constants.BILLING_EXPORT_TMP_TABLE");
        date_default_timezone_set('America/New_York');
        try {
            $message = preg_replace("/'/", "\'", $message);
            if ($progress > 0) {
                $sql = sprintf("update " . $tempTable . " set log=CONCAT(COALESCE(log,''), '%s'), progress=%d where taskId=%d", htmlspecialchars($message) . "\n", $progress, filter_var($taskId, FILTER_VALIDATE_INT));
            } else {
                $sql = sprintf("update " . $tempTable . " set log=CONCAT(COALESCE(log,''), '%s') where taskId=%d", htmlspecialchars($message) . "\n", filter_var($taskId, FILTER_VALIDATE_INT));
            }
            Log::info($sql);
            if (!DB::update($sql)) {
                Log::critical("Unable to update process progress in DB ".$tempTable);
                throw new CustomException("Unable to update process progress");
            }

        } catch (\Exception $e) {
            echo 'Caught exception: ',  $e->getMessage(), "\n";
        }
    }

}
