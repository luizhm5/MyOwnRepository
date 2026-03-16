<?php

namespace App\Jobs;

use App\Exceptions\CustomException;
use App\Models\FileHelper;
use App\Models\SFPfxProvider;
use Illuminate\Bus\Queueable;
use Illuminate\Contracts\Queue\ShouldQueue;
use Illuminate\Foundation\Bus\Dispatchable;
use Illuminate\Queue\InteractsWithQueue;
use Illuminate\Queue\SerializesModels;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Log;

require __DIR__ . "/../../" . 'vendor/weatherfx/box-jwt/helpers/helpers.php';
define('SHEET_NAME', 'PFX export');
class PfxExportJob implements ShouldQueue
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

            $res = DB::select("SELECT * FROM " . config("constants.PFX_EXPORT_TMP_TABLE") . " WHERE taskId=" . $taskId);

            if(count($res) > 0) {
                $obj = $res[0];
                $proposalId = $obj->proposal_id;
                $viewId = $obj->view_id ?: '';
                $viewName = $obj->view_name ?: '';
                $longName = $obj->long_name ?: '0';

            }else{
                throw new CustomException("cant select task");
            }

            $progress = 0;

            Log::info("Start worker", ['proposalId' => $proposalId, 'viewId' => $viewId, 'viewName' => $viewName]);

            $this->dbLogger($taskId, "Start for proposal " . $proposalId . ", view " . $viewId . ", view name " . $viewName);

            // Extract session ID from config
            $sessionId = $this->config["sessionId"] ?? null;

            $sfp = new SFPfxProvider($proposalId, $viewId, $viewName, $longName, $sessionId);

            Log::info("-- get header data");

            $this->dbLogger($taskId, "Get header data");

            $headerRaw = $sfp->getHeader();
            $withExternal = $headerRaw['withExternal'];

            $headerData = [];

            foreach ($headerRaw['fields'] as $field){

                if(isset($headerData[$field['label']])){
                    $headerData[$field['label'] . " "] = $field['type'];
                }else{
                    $headerData[$field['label']] = $field['type'];
                }

            }

            $this->dbLogger($taskId, "Start processing data", 10);

            $writer = new \XLSXWriter();
            $writer->setAuthor('The Weather Channel');
            $writer->writeSheetHeader(SHEET_NAME, $headerData, array('font-style' => 'bold'));

            $this->dbLogger($taskId, "Get data");
            Log::info("-- get data");


            $totalLines = $headerRaw['totalLines'];
            $requestCount = ceil($headerRaw['totalProducts'] / 50);

            $this->dbLogger($taskId, "Found " . $totalLines . " record(s)");
            Log::info("-- records count: " . $totalLines);

            $processed = 0;
            for ($i = 0; $i < $requestCount; $i++) {

                $data = $sfp->getData($i * 50);

                foreach($data["data"] as $row){
                    $writer->writeSheetRow(SHEET_NAME, $row);
                }

                $processed += min($totalLines, count($data['data']));
                $current = round(($processed / $totalLines) * 80) + 10;

                $this->dbLogger($taskId, "Processed ". $processed . " entries from " . $totalLines, $current);
                Log::info("-- progress " . $current . "%");
            }

            if ($withExternal) {
                $this->dbLogger($taskId,"Processing external lines");
                $data = $sfp->getExternalUnmappedData();
                foreach($data["data"] as $row){
                    $writer->writeSheetRow(SHEET_NAME, $row);
                }
                $this->dbLogger($taskId, "External lines processed");
            }

            $this->dbLogger($taskId, "End processing data");

            $this->dbLogger($taskId, "Start upload process");

            //UPLOAD FILE IN BOX.COM
            $outFileName = sys_get_temp_dir() . '/PFX_export_N' . $taskId . '_D' . date('m-d-y_h-i') . ".xlsx";

            $writer->writeToFile($outFileName);

            $fileHelper = app()->make(FileHelper::class);
            $downloadLink = $fileHelper->uploadAndPublishFile($outFileName, config('google.history_export_folder'), basename($outFileName));

            $affected = DB::update("update " . config("constants.PFX_EXPORT_TMP_TABLE") . " set state=10, progress=100, file_url=? where taskId=?", [$downloadLink, $taskId]);
            if ($affected === 0) {
                Log::critical("Unable to update database, no changes made to temp table");
                throw new CustomException("Unable to update process info");
            };

            Log::info("End worker", ['proposalId' => $proposalId, 'viewId' => $viewId, 'viewName' => $viewName]);

            $this->dbLogger($taskId, "Process finished");

        }catch (\Exception $exception){
            DB::update("update " . config("constants.PFX_EXPORT_TMP_TABLE") . " set state=-1, error_msg=? where taskId=?", [ $exception->getMessage(), $taskId]);

            $this->dbLogger($taskId,"Process error: " . $exception->getMessage());

            Log::critical($exception->getMessage());
        }
    }


    function dbLogger(int $taskId, string $message, int $progress = 0): void
    {
        $tempTable = config("constants.PFX_EXPORT_TMP_TABLE");
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
