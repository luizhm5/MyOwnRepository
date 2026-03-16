<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * Run the migrations.
     */
    public function up(): void
    {
        //
        $tableName = config('constants.BILLING_EXPORT_TMP_TABLE');
        if (!Schema::hasTable($tableName)) {
            Schema::create($tableName, function ($table) {
                $table->integer('taskId')->primary()->increments();
                $table->string('view_id', 700)->default('');
                $table->string('view_name', 700)->default('');
                $table->string('proposal_id', 700)->default('');
                $table->tinyInteger('long_name')->unsigned()->default(0);
                $table->string('user_id', 40);
                $table->string('user_email', 40);
                $table->timestamp('access_date')->default(DB::raw('CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP'));;
                $table->smallInteger('state')->default(1);
                $table->tinyInteger('progress')->default(0);
                $table->text('file_url');
                $table->string('error_msg', 255);
                $table->text('log');

                $table->engine = 'InnoDB';
            });
        }

        $tableName = config('constants.HISTORY_EXPORT_TMP_TABLE');
        if (!Schema::hasTable($tableName)) {
            Schema::create($tableName, function ($table) {
                $table->integer('taskId')->primary()->increments();
                $table->string('view_id', 700)->default('');
                $table->string('view_name', 700)->default('');
                $table->string('proposal_id', 700)->default('');
                $table->tinyInteger('long_name')->unsigned()->default(0);
                $table->string('user_id', 40);
                $table->string('user_email', 40);
                $table->timestamp('access_date')->default(DB::raw('CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP'));;
                $table->smallInteger('state')->default(1);
                $table->tinyInteger('progress')->default(0);
                $table->text('file_url');
                $table->string('error_msg', 255);
                $table->text('log');

                $table->engine = 'InnoDB';
            });
        }

        $tableName = config('constants.PFX_EXPORT_TMP_TABLE');
        if (!Schema::hasTable($tableName)) {
            Schema::create($tableName, function ($table) {
                $table->integer('taskId')->primary()->increments();
                $table->string('view_id', 700)->default('');
                $table->string('view_name', 700)->default('');
                $table->string('proposal_id', 700)->default('');
                $table->tinyInteger('long_name')->unsigned()->default(0);
                $table->string('user_id', 40);
                $table->string('user_email', 40);
                $table->timestamp('access_date')->default(DB::raw('CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP'));;
                $table->smallInteger('state')->default(1);
                $table->tinyInteger('progress')->default(0);
                $table->text('file_url');
                $table->string('error_msg', 255);
                $table->text('log');

                $table->engine = 'InnoDB';
            });
        }
    }

    /**
     * Reverse the migrations.
     */
    public function down(): void
    {
        Schema::dropIfExists(config('constants.BILLING_EXPORT_TMP_TABLE'));
        Schema::dropIfExists(config('constants.HISTORY_EXPORT_TMP_TABLE'));
        Schema::dropIfExists(config('constants.PFX_EXPORT_TMP_TABLE'));
    }
};
