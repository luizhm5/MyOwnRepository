<?php

return [
    'clientId' => env('BOX_CLIENTID'),
    'clientSecret' => env('BOX_CLIENTSECRET'),
    'enterpriseId' => env('BOX_ENTERPRISEID'),
    'jwtPrivateKey' => env('BOX_PRIVATEKEYFILE'),
    'jwtPrivateKeyPassword' => env('BOX_PRIVATEKEYPASSWORD'),
    'jwtPublicKeyId' => env('BOX_PUBLICKEYID')
];
