<?php

namespace App\Models\Box;

use Box\Config\BoxConstants;
use Box\Managers\BoxFilesManager;
use Box\Models\Request\BoxFileRequest;
use Box\Exceptions\BoxSdkException;


class ExtBoxFilesManager extends BoxFilesManager
{

    function __construct($boxClient)
    {
        parent::__construct($boxClient);
    }

    public function getFileSharedLink($id, $options, $additionalHeaders = null, $runAsync = false)
    {
        $urlParams = $this->keepNonEmptyParams([BoxConstants::QUERY_PARAM_FIELDS => "shared_link"]);
        $uri       = parent::createUri(BoxConstants::FILES_ENDPOINT_STRING . $id, $urlParams);
        $request   = parent::alterBaseBoxRequest($this->getBaseBoxRequest(), BoxConstants::PUT, $uri, $additionalHeaders,  json_encode($options));
        return parent::requestTypeResolver($request, [], $runAsync);
    }

    // public function uploadFileVersion($id, BoxFileRequest $fileRequest, $file, $additionalHeaders = null, $runAsync = false)
    public function uploadFileVersion(BoxFileRequest $fileRequest, $file, $id, $additionalHeaders = null, $runAsync = false)
    {
        if (!($fileRequest instanceof BoxFileRequest)) {
            throw new BoxSdkException('The first argument supplied must be a BoxFileRequest');
        }

        // Prepare file hash for verification
        $this->getFileHashHeader($file, $additionalHeaders);

        // Prepare file
        $options = $this->createFileUploadOption($fileRequest, $file);

        $uri     = parent::createUri(sprintf(BoxConstants::FILES_NEW_VERSION_ENDPOINT_STRING, $id));
        $request = parent::alterBaseBoxRequest($this->getBaseBoxRequest(), BoxConstants::POST, $uri, $additionalHeaders);
        return parent::requestTypeResolver($request, $options, $runAsync);
    }

}
