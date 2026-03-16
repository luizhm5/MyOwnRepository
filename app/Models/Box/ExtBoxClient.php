<?php

namespace App\Models\Box;

use Box\Managers\BoxResourceManager;
use Box\Managers\BoxUsersManager;
use Box\Managers\BoxFoldersManager;
use Box\Managers\BoxFilesManager;
use Box\Config\BoxConstants;

class ExtBoxClient
{
    public $accessToken;

    public $headers;

    public $BoxConfig;

    public $resourceManager;

    public $usersManager;

    public $foldersManager;

    public $filesManager;

    public $extFilesManager;

    public function __construct($BoxConfig, $accessToken)
    {
        $this->accessToken = $accessToken;
        $this->headers     = [BoxConstants::HEADER_KEY_AUTH => sprintf(BoxConstants::HEADER_VAL_V2_AUTH_STRING, $accessToken)];
        $this->BoxConfig   = $BoxConfig;
        $this->initializeManagers();
    }

    private function initializeManagers()
    {
        $this->resourceManager = new BoxResourceManager($this);
        $this->usersManager    = new BoxUsersManager($this);
        $this->foldersManager  = new BoxFoldersManager($this);
        $this->filesManager    = new BoxFilesManager($this);
        $this->extFilesManager = new ExtBoxFilesManager($this);
    }
}
