<?php

use Illuminate\Support\Facades\Route;

/*
|--------------------------------------------------------------------------
| Web Routes
|--------------------------------------------------------------------------
|
| Here is where you can register web routes for your application. These
| routes are loaded by the RouteServiceProvider and all of them will
| be assigned to the "web" middleware group. Make something great!
|
*/

Route::get('/error', function () {
    return view('500');
});

Route::get("/process", [\App\Http\Controllers\ProcessController::class, "__invoke"]);
Route::post("/salesforce_canvas", [\App\Http\Controllers\SalesforceController::class, "__invoke"]);

