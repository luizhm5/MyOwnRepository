<?php

namespace App\Http\Controllers;

use App\Exceptions\CustomException;
use App\Services\ProcessTokenService;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Facades\Response;

class ProcessController extends Controller
{

    public function __invoke(Request $request)
    {
        Log::info("Process action dispatched");

        $params = $request->all();
        $taskId = (int)($params['taskId'] ?? 0);
        $token = $params['token'] ?? '';
        $application = $params['app'] ?? config("constants.APP_KEY_INVOICE_EXPORT");

        if ($taskId == 0) {
            return Response::json(["message" => 'Error: taskId not found, please contact your system administrator'], 400);
        }

        // Validate token-based authentication
        $validation = ProcessTokenService::validate($token, $taskId);

        if (!$validation['valid']) {
            Log::warning("Token validation failed", [
                'taskId' => $taskId,
                'error' => $validation['error'] ?? 'Unknown error',
                'ip' => $request->ip(),
                'user_agent' => $request->userAgent()
            ]);

            return Response::json([
                "message" => 'Error: Invalid or expired access token'
            ], 403);
        }

        $data = [];

        $data["canvasClient"] = [];
        if (session()->has('canvasClient')) {
            $data["canvasClient"] = session('canvasClient')->client;
        }

        switch ($application) {
            case config("constants.APP_KEY_PFX_EXPORT"):
                $tempTable = config("constants.PFX_EXPORT_TMP_TABLE");
                break;
            case config("constants.APP_KEY_HISTORY_EXPORT"):
                $tempTable = config("constants.HISTORY_EXPORT_TMP_TABLE");
                break;
            default:
                $tempTable = config("constants.BILLING_EXPORT_TMP_TABLE");
                break;
        }

        $res = DB::select("SELECT * FROM " . $tempTable . " WHERE taskId=" . $taskId);

        if (count($res) > 0) {
            // Verify the token's userId matches the task owner in the database
            if ($res[0]->user_id !== $validation['userId']) {
                Log::warning("Token userId mismatch with task owner", [
                    'taskId' => $taskId,
                    'tokenUserId' => $validation['userId'],
                    'taskUserId' => $res[0]->user_id,
                    'ip' => $request->ip(),
                    'user_agent' => $request->userAgent()
                ]);

                return Response::json([
                    "message" => 'Error: Unauthorized access'
                ], 403);
            }

            $data['task'] = $res[0];
            if ($application === config("constants.APP_KEY_INVOICE_EXPORT")) {
                $data['task']->isFinal = (int)$res[0]->is_final;
            } else {
                $data['task']->isFinal = 0;
            }
        } else {
            Log::critical("can't select task with id " . $taskId);
            throw new CustomException('Error: Cant select task, please contact your system administrator');
        }

        return view("process", $data);
    }

}
