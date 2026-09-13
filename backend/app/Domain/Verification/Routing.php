<?php

namespace App\Domain\Verification;

/**
 * The three-state verification outcome.
 *
 * The middle state is the point of the design: a model that is unsure is
 * allowed to say so and hand the decision to a person, rather than being
 * forced to guess. Collapsing this to two states would remove the parent from
 * the loop, which the study argues against explicitly.
 */
final class Routing
{
    public const AUTO_APPROVED = 'auto_approved';
    public const PENDING_REVIEW = 'pending_review';
    public const AUTO_REJECTED = 'auto_rejected';
}
