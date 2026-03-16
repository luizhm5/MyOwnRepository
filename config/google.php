<?php
return [
    /*
    |--------------------------------------------------------------------------
    | Your Google APIs credentials
    |--------------------------------------------------------------------------
    */

    'credentials_json' => storage_path('app/' . env('GOOGLE_CREDENTIALS', 'google/credentials.json')),
    'credentials_json_alt' => storage_path('app/' . env('GOOGLE_CREDENTIALS_ALT', 'google/credentials_alt.json')),
    'file_open_url' => env('GOOGLE_FILE_OPEN_URL'),
    'file_download_url' => env('GOOGLE_FILE_DOWNLOAD_URL'),
    'history_export_folder' => env('GOOGLE_HISTORY_EXPORT_FOLDER_ID')
];
