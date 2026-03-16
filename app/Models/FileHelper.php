<?php

namespace App\Models;

interface FileHelper
{
    public function uploadFile($fullPath, $folder, $customName);
    public function uploadAndPublishFile($fullPath, $folder, $customName);
    public function createFolder($name, $parentId);

    public function shareReadWithAll($fileId);

}
