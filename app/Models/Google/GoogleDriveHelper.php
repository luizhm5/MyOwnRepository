<?php
namespace App\Models\Google;

use App\Exceptions\CustomException;
use App\Models\FileHelper;
use Google\Client;
use Google\Service\Drive;
use Google_Exception;
use Google_Service_Drive;
use Illuminate\Support\Facades\Log;
use Throwable;

class GoogleDriveHelper implements FileHelper {

    protected $client;
    protected $driveService;
    const credentialKeys = [
        'google.credentials_json',
        'google.credentials_json_alt',
    ];

    public function __construct($scopes = Google_Service_Drive::DRIVE, $serviceClass = Google_Service_Drive::class, $credentialKey = null)
    {
        $this->client = new Client();
        $config = config($credentialKey ?: 'google.credentials_json');
        try {
            $this->client->setAuthConfig($config);
            $this->client->setScopes($scopes);
            $this->driveService = new Drive($this->client);
        } catch (\Google\Exception $e) {
            Log::error($e);
            throw new CustomException($e->getMessage());
        }
    }

    public function uploadAndPublishFile($fullPath, $folder = '', $customName = ''): string {
        try {
            $fileId = $this->uploadFile($fullPath, $folder, $customName);
            return $this->shareReadWithAll($fileId);
        } catch (CustomException $e) {
            Log::error("Unable to upload file and share file ".$e->getMessage());
            throw $e;
        }
    }
    public function uploadFile($fullPath, $folder = '', $customName = ''): string
    {
        try {
            Log::info(sprintf("Starting file %s upload to google folder %s", $customName, $folder));
            if (!$customName) {
                $customName = basename($fullPath);
            }
            $fileSettings = array('name' => $customName);
            if($folder) {
                $fileSettings['parents'] = array($folder);
            }
            $fileMetadata = new Drive\DriveFile($fileSettings);
            $content = file_get_contents($fullPath);
            $file = $this->driveService->files->create($fileMetadata, array(
                    'data' => $content,
                    'mimeType' => mime_content_type($fullPath),
                    'uploadType' => 'multipart',
                    'fields' => 'id',
                    'supportsAllDrives'=>true
                )
            );
            Log::info("Upload file with id: ".$file->id);
            return $file->id;
        } catch(\Exception $e) {
            Log::error($e);
           throw new CustomException($e->getMessage());
        }
    }

    function shareReadWithAll($fileId): string
    {
        Log::info("Sharing file with id: ".$fileId);
        $permission = new Drive\Permission();
        $permission->setType('anyone');
        $permission->setRole('reader');
        try {
            $this->driveService->permissions->create($fileId, $permission, array('supportsAllDrives'=>true));
            $placeHolder = env('GOOGLE_FILE_DOWNLOAD_URL', 'https://drive.google.com/uc?export=download&id=%s');
            $downloadUrl = sprintf($placeHolder, $fileId);
            Log::info("File shared, download link: ".$downloadUrl);
            return $downloadUrl;
        } catch (\Exception $e) {
            Log::error($e);
            throw new CustomException($e);
        }
    }

    /**
     * @param string $fileId
     * @return string|bool
     * @throws Google_Exception
     */
    public function hasAccessToGoogleFile(string $fileId): string|bool
    {
        foreach (static::credentialKeys as $credentialKey) {
            try {
                $this->driveService->files->get($fileId, ['fields' => 'name,parents,version,createdTime']);

                return $credentialKey;
            } catch (Throwable $e) {
                return false;
            }
        }
        return false;
    }

    function createFolder($name, $parentId=''): string
    {
        try {
            $fileMetadata = new Drive\DriveFile(array(
                'name' => $name,
                'mimeType' => 'application/vnd.google-apps.folder'));
            $fileSettings = [
                'fields' => 'id'
            ];
            if($parentId) {
                $fileSettings['parents'] = $parentId;
            }
            $file = $this->driveService->files->create($fileMetadata, $fileSettings);
            Log::info("Folder ID: " . $file->id);
            return $file->id;

        }catch(\Exception $e) {
            Log::error($e);
            throw new CustomException($e->getMessage());
        }
    }

    public static function getGoogleLogin(): string
    {
        $result = [];
        foreach (static::credentialKeys as $credentialKey) {
            $credentialFile = config($credentialKey);
            $googleCredential = json_decode(file_get_contents($credentialFile), true);
            $result[] = $googleCredential['client_email'];
        }

        return implode(', ', $result);
    }

    public static function getFileIdByUrl(string $url): string
    {
        preg_match('/[_0-9a-z\-]{44}/i', $url, $match);

        return $match[0] ?? '';
    }

}
