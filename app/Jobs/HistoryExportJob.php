<?php

namespace App\Jobs;

use App\Exceptions\CustomException;
use App\Models\FileHelper;
use App\Models\SFHistoryProvider;
use Illuminate\Bus\Queueable;
use Illuminate\Contracts\Queue\ShouldQueue;
use Illuminate\Foundation\Bus\Dispatchable;
use Illuminate\Queue\InteractsWithQueue;
use Illuminate\Queue\SerializesModels;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Log;

require __DIR__ . "/../../" . 'vendor/weatherfx/box-jwt/helpers/helpers.php';
class HistoryExportJob implements ShouldQueue
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

            $res = DB::select("SELECT * FROM " . config('constants.HISTORY_EXPORT_TMP_TABLE') . " WHERE taskId=?", [$taskId]);

            if (count($res) > 0) {
                $obj = $res[0];
                $proposalId = $obj->proposal_id;

            }else{
                throw new CustomException("cant select task");
            }

            $progress = 0;

            Log::info("Start worker", ['taskId' => $taskId, 'proposalId' => $proposalId]);

            $this->dbLogger($taskId, "Start proposalId: " . $proposalId);

            // Extract session ID from config
            $sessionId = $this->config["sessionId"] ?? null;

            $sfp = new SFHistoryProvider($proposalId, $sessionId);

            $this->dbLogger($taskId, "Get data");

            $writer = new \XLSXWriter();
            $writer->setAuthor('The Weather Channel');

            $headerRaw = $sfp->getHistoryReport();
            if (count($headerRaw['histories']) == 0) {
                throw new CustomException('Proposal history is missing, please contact system administrator');
            }

            $this->dbLogger($taskId, "Received data for: " . $headerRaw['proposalName']);

            if (!array_key_exists('historyType', $headerRaw)) {
                throw new CustomException("No History Data Available");
            } else {
                if(!isset($headerRaw['historyType']) || $headerRaw['historyType'] === "null") {
                    throw new CustomException("No History Data Available");
                }
            }

            $this->dbLogger($taskId," -- type: " . $headerRaw['historyType'], 5);

            $writer->writeSheetHeader($headerRaw['historyType'], $this->getHeaderTypes($headerRaw['histories'][0]), array('font-style' => 'bold'));

            foreach ($headerRaw['histories'] as $history){
                $writer->writeSheetRow($headerRaw['historyType'], array_values($history));
            }

            for ($i = 1; $i < count($headerRaw['allowedHistoryTypes']); $i++) {
                $type = $headerRaw['allowedHistoryTypes'][$i];
                $this->dbLogger($taskId, " -- type: " . $type, (10 * $i));

                $result = $sfp->getHistoryReport($type);

                if(count($result['histories'])){

                    $writer->writeSheetHeader($type, $this->getHeaderTypes($result['histories'][0]), array('font-style' => 'bold'));
                    foreach ($result['histories'] as $history){
                        $writer->writeSheetRow($type, array_values(array_map(function($value){
                            if(is_array($value)){
                                return json_encode($value);
                            }
                            return $value;
                        }, $history)));
                    }
                }
            }


            $this->dbLogger($taskId, "End processing data");

            $this->dbLogger($taskId, "Start upload process");

            //UPLOAD FILE IN BOX.COM
            $outFileName = sys_get_temp_dir() . '/History_report_N' . $taskId . '_D' . date('m-d-y_h-i') . ".xlsx";

            $writer->writeToFile($outFileName);

            $fileHelper = app()->make(FileHelper::class);
            $downloadLink = $fileHelper->uploadAndPublishFile($outFileName, env('GOOGLE_HISTORY_EXPORT_FOLDER_ID'), basename($outFileName));

            $affected = DB::update("update " . config("constants.HISTORY_EXPORT_TMP_TABLE") . " set state=10, progress=100, file_url=? where taskId=?", [$downloadLink, $taskId]);
            if ($affected === 0) {
                Log::critical("Unable to update database, no changes made to temp table");
                throw new CustomException("Unable to update process info");
            };

            Log::info("End worker", ['taskId' => $taskId, 'proposalId' => $proposalId]);

            $this->dbLogger($taskId, "Process finished");

        }catch (\Exception $exception){

            DB::update("update " . config("constants.HISTORY_EXPORT_TMP_TABLE") . " set state=-1, error_msg=? where taskId=?", [ $exception->getMessage(), $taskId]);

            $this->dbLogger($taskId,"Process error: " . $exception->getMessage());

            Log::critical($exception->getMessage());
        }
    }


    function dbLogger(int $taskId, string $message, int $progress = 0): void
    {
        $tempTable = config("constants.HISTORY_EXPORT_TMP_TABLE");
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

    function getHeaderTypes($fields){
        $result = [];
        foreach (array_keys($fields) as $field){
            $result[$field] = 'string';
        }

        return $result;
    }

}
