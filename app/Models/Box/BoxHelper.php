<?php

namespace App\Models\Box;
 use App\Exceptions\CustomException;
 use App\Models\FileHelper;
 use Box\Auth\BoxJWTAuth;
 use Box\Config\BoxConfig;
 use Box\Models\Request\BoxFileRequest;
 use Illuminate\Support\Facades\Log;

 class BoxHelper implements FileHelper {

     private $boxClient;
     public function __construct()
     {
         $boxJwt = new BoxJWTAuth(new BoxConfig(config('box')));
         $boxConfig = $boxJwt->getBoxConfig();
         $adminToken = $boxJwt->adminToken();
         $this->boxClient = new ExtBoxClient($boxConfig, $adminToken->access_token);
     }

     public function uploadFile($fullPath, $folder='', $customName='')
     {
         if (!$customName) {
             $customName=basename($fullPath);
         }
         $fileRequest = new BoxFileRequest(['name' => $customName, 'parent' => ['id' => config('constants.BOX_FOLDER_ID')]]);

         $res = $this->boxClient->filesManager->uploadFile($fileRequest, $fullPath);

         $uploadedFileObject = json_decode($res->getBody());

         $uploadedFileId   = $uploadedFileObject->entries[0]->id;

         Log::info("Uploaded file info", [$uploadedFileObject->entries[0]]);
         return $uploadedFileId;
     }

     public function createFolder($name, $parentId)
     {
         // TODO: Implement createFolder() method.
     }

     public function shareReadWithAll($fileId): string {
         $sharedOptions = ["shared_link" => ["access" => "open"]];

         $res = $this->boxClient->extFilesManager->getFileSharedLink($fileId, $sharedOptions);
         $statusCode = $res->getStatusCode();

         Log::info("Shared link status", [$statusCode]);

         if ($statusCode == 200) {
             $sharedLinkObject = json_decode($res->getBody());

             if(isset($sharedLinkObject->shared_link)){

                 Log::info("shared_link", [$sharedLinkObject->shared_link->download_url]);

                 return $sharedLinkObject->shared_link->download_url;
             }
         }else{
             throw new CustomException("Error shared link creation: Cant select task, please contact your system administrator");
         }
         return '';
     }

     public function uploadAndPublishFile($fullPath, $folder, $customName): string
     {
         try {
             $fileId = $this->uploadFile($fullPath, $folder, $customName);
             return $this->shareReadWithAll($fileId);
         } catch (CustomException $e) {
             Log::error("Unable to upload file and share file ".$e->getMessage());
             throw $e;
         }
     }
 }
