<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * One row per photograph a child submits.
     *
     * The column layout is driven by what Chapter 4 has to compute. A
     * false-approval rate is the proportion of submissions the model approved
     * on its own that a parent later judged incomplete -- which is only
     * calculable if the model's original verdict survives the parent's
     * decision instead of being overwritten by it. So the two are held in
     * separate columns that never touch:
     *
     *   routing          what the confidence thresholds decided. Written once
     *                    at intake and never modified.
     *   parent_decision  what a person decided, or null if no one has looked.
     *
     *   false approval  = routing 'auto_approved' AND parent_decision 'rejected'
     *   false rejection = routing 'auto_rejected' AND parent_decision 'approved'
     *
     * That second figure only exists if a parent can overturn an automatic
     * rejection, and the first only exists if a parent can overturn an
     * automatic approval. Both are therefore reviewable, not just the
     * uncertain ones -- which is also what Chapter 2 promises when it says the
     * parent may confirm, override, or reject ANY classification.
     */
    public function up(): void
    {
        Schema::create('submissions', function (Blueprint $table) {
            $table->id();
            $table->foreignId('child_id')->constrained()->cascadeOnDelete();
            $table->foreignId('assignment_id')->constrained()->cascadeOnDelete();

            $table->string('photo_path');

            // ---- what the model said. Immutable. ----
            $table->string('model_label', 20)->nullable();
            $table->decimal('model_confidence', 4, 3)->nullable();
            $table->string('model_version', 40)->nullable();

            // Capture-to-result on the handset, for the performance
            // efficiency criterion. Recorded per submission so the figure
            // reported in Chapter 4 comes from real devices in real homes
            // rather than one timing run on one phone.
            $table->unsignedInteger('inference_ms')->nullable();

            // ---- what the thresholds decided. Immutable. ----
            $table->string('routing', 20);

            // ---- what a person decided. Null until someone looks. ----
            $table->string('parent_decision', 20)->nullable();
            $table->timestamp('parent_decided_at')->nullable();
            $table->foreignId('parent_user_id')->nullable()->constrained('users')->nullOnDelete();

            // Effective state: 'approved', 'rejected' or 'pending'. Derived
            // from the two above and stored so the review queue and the
            // ledger can be queried directly.
            $table->string('status', 20);

            // Which day this counts against for the daily cap. Fixed at
            // intake so a submission cannot drift to another day by being
            // reviewed late.
            $table->date('for_date');

            // Set by the client so a retried upload from the offline queue in
            // slice 3.5 lands once rather than twice.
            $table->uuid('client_token')->nullable()->unique();

            $table->timestamps();

            $table->index(['child_id', 'for_date']);
            $table->index(['status', 'child_id']);
            $table->index(['assignment_id', 'for_date']);
            $table->index('routing');
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('submissions');
    }
};
