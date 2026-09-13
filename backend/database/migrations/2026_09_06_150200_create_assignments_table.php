<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('assignments', function (Blueprint $table) {
            $table->id();
            $table->foreignId('child_id')->constrained()->cascadeOnDelete();
            $table->foreignId('chore_template_id')->constrained()->cascadeOnDelete();

            // Copied from the template at assignment time, then owned by the
            // parent. Editing a template later must not silently repoint the
            // value of work a child has already been promised.
            $table->unsignedSmallInteger('points');

            $table->time('due_time')->nullable();

            // 'daily' recurs every day; 'once' happens on scheduled_date only.
            // Weekly recurrence is deliberately not modelled yet.
            $table->string('recurrence', 10)->default('daily');
            $table->date('scheduled_date')->nullable();

            $table->boolean('is_active')->default(true);
            $table->timestamps();

            $table->index(['child_id', 'is_active']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('assignments');
    }
};
