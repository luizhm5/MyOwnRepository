<?php

namespace App\Http\Controllers;

use App\Exceptions\CustomException;
use App\Jobs\HistoryExportJob;
use App\Jobs\InvoiceExportJob;
use App\Jobs\PfxExportJob;
use App\Models\SignedRequest;
use App\Services\ProcessTokenService;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Log;

class SalesforceController
{

    /**
     * @throws CustomException
     */
    public function __invoke(Request $request)
    {
        Log::info("Salesforce action dispatched");

        $data = $request->all();

        $application = array_key_exists("app", $data) ? $data["app"] : null;
        $signedRequest = new SignedRequest($data["signed_request"], $application);
        $decodedRequest = $signedRequest->getDecodedRequest();

        if ($decodedRequest != null) {
            $userEmail = $decodedRequest->context->user->email;
            $this->setSessionVars($userEmail, $decodedRequest);

            $userId = $decodedRequest->context->user->userId;
            switch ($signedRequest->getApplication()) {
                case config("constants.APP_KEY_HISTORY_EXPORT"):
                    $taskId = $this->processHistoryExportRequest($decodedRequest, $userId, $userEmail);
                    break;
                case config("constants.APP_KEY_PFX_EXPORT"):
                    $taskId = $this->processPfxExportRequest($decodedRequest, $userId, $userEmail);
                    break;
                default:
                    $taskId = $this->processInvoiceExportRequest($decodedRequest, $userId, $userEmail);
                    break;
            }

            $token = ProcessTokenService::generate(
                $taskId,
                $userId,
                $signedRequest->getApplication() ?? config("constants.APP_KEY_INVOICE_EXPORT")
            );

            return redirect("process?taskId={$taskId}&token={$token}&app=" . $signedRequest->getApplication());

        } else {
            throw new CustomException('Error: Request invalid, please contact your system administrator');
        }
    }

    /**
     * @param mixed $decodedRequest
     * @param $userId
     * @param $userEmail
     * @return int
     */
    public function processInvoiceExportRequest(mixed $decodedRequest, $userId, $userEmail): int
    {
        $periodId = $decodedRequest->context->environment->parameters->periodId;
        $periodName = $decodedRequest->context->environment->parameters->periodName;
        $billingStatus = $decodedRequest->context->environment->parameters->billingStatus ?? '';
        $searchTerm = $decodedRequest->context->environment->parameters->searchTerm ?? '';
        $isFinal = (int)$decodedRequest->context->environment->parameters->isFinal ?? 0;
        $isIERP = property_exists($decodedRequest->context->environment->parameters, 'isIERP') ?
            ($decodedRequest->context->environment->parameters->isIERP === "true" ? 1 : 0) : 0;
        $invoiceIds = $decodedRequest->context->environment->parameters->invoiceIds;

        $lookupSql = "SELECT taskId FROM " . config("constants.BILLING_EXPORT_TMP_TABLE") . " WHERE user_id=? AND period_id=? AND billing_status=? AND period_name=? AND search_term=? AND is_final=? AND is_ierp=? AND invoice_ids=? AND state = 1 limit 0, 1";

        $res = DB::select($lookupSql, [$userId, $periodId, $billingStatus, $periodName, $searchTerm, $isFinal, $isIERP, $invoiceIds]);

        if (count($res) > 0) {
            $taskId = $res[0]->taskId;
        } else {
            $taskId = DB::table(config("constants.BILLING_EXPORT_TMP_TABLE"))
                ->insertGetId([
                    'period_id' => $periodId,
                    'period_name' => $periodName,
                    'billing_status' => $billingStatus,
                    'search_term' => $searchTerm,
                    'user_id' => $userId,
                    'user_email' => $userEmail,
                    'is_final' => $isFinal,
                    'is_ierp' => $isIERP,
                    'invoice_ids' => $invoiceIds
                ]);
        }

        // Extract OAuth token and instance URL from Canvas signed request
        $sessionId = $decodedRequest->client->oauthToken ?? null;
        $instanceUrl = $decodedRequest->client->instanceUrl ?? null;

        InvoiceExportJob::dispatch(["taskId" => $taskId, "sessionId" => $sessionId, "instanceUrl" => $instanceUrl]);
        return $taskId;
    }

    /**
     * @param mixed $decodedRequest
     * @param $userId
     * @param $userEmail
     * @return int
     */
    public function processHistoryExportRequest(mixed $decodedRequest, $userId, $userEmail): int
    {
        $proposalId = $decodedRequest->context->environment->parameters->proposalId;
        $res = DB::select("SELECT taskId FROM " . config('constants.HISTORY_EXPORT_TMP_TABLE') . " WHERE user_id=? AND proposal_id=? AND state = 1 limit 0, 1", [$userId, $proposalId]);
        if (count($res) > 0) {
            $taskId = $res[0]->taskId;
        } else {

            $taskId = DB::table(config('constants.HISTORY_EXPORT_TMP_TABLE'))->insertGetId([
                'proposal_id' => $proposalId,
                'user_id' => $userId,
                'user_email' => $userEmail
            ]);

            // Extract OAuth token from Canvas signed request
            $sessionId = $decodedRequest->client->oauthToken ?? null;

            HistoryExportJob::dispatch(["taskId" => $taskId, "sessionId" => $sessionId]);
        }
        return $taskId;
    }

    /**
     * @param mixed $decodedRequest
     * @param $userId
     * @param $userEmail
     * @return int
     */
    public function processPfxExportRequest(mixed $decodedRequest, $userId, $userEmail): int
    {
        $proposalId = $decodedRequest->context->environment->parameters->proposalId;
        $viewId = $decodedRequest->context->environment->parameters->viewId;
        $viewName = $decodedRequest->context->environment->parameters->viewName;
        $longName = $decodedRequest->context->environment->parameters->longName;

        if ($proposalId === "null") {
            $proposalId = null;
        }
        if ($viewId === "null") {
            $viewId = "";
        }
        if ($viewName === "null") {
            $viewName = "";
        }
        if ($longName !== "1") {
            $longName = "0";
        }

        if (!$proposalId) {
            throw new CustomException('proposalId not found');
        }
        if (!$viewId && !$viewName) {
            throw new CustomException('viewId or viewName not found');
        }

        $res = DB::select("select taskId, progress from " . config("constants.PFX_EXPORT_TMP_TABLE") . " where user_id=? "
            . " and view_id=?"
            . " and view_name=?"
            . " and long_name=?"
            . " and proposal_id=? and state = 1 limit 0, 1", [$userId, $viewId, $viewName, $longName, $proposalId]);

        // Extract OAuth token from Canvas signed request
        $sessionId = $decodedRequest->client->oauthToken ?? null;

        if (count($res) > 0) {
            $resObj = $res[0];
            $taskId = $resObj->taskId;
            if ($res[0]->progress === 0) {
                PfxExportJob::dispatch(["taskId" => $taskId, "sessionId" => $sessionId]);
            }
        } else {
            $taskId = DB::table(config("constants.PFX_EXPORT_TMP_TABLE"))->insertGetId([
                "view_id" => $viewId,
                "view_name" => $viewName,
                "long_name" => $longName,
                "proposal_id" => $proposalId,
                "user_id" => $userId,
                "user_email" => $userEmail,
            ]);

            PfxExportJob::dispatch(["taskId" => $taskId, "sessionId" => $sessionId]);
        }

        return $taskId;
    }

    private function setSessionVars($userEmail, $decodedRequest): void
    {
        session([
            'canvasClient' => $decodedRequest,
            'email' => $userEmail
        ]);
    }


}
