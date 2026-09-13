<?php

namespace App\Domain\Verification;

/**
 * Applies the two confidence thresholds to one model result.
 *
 * A pure function: same inputs, same outcome, no I/O and no clock. The
 * thresholds arrive as arguments because they are configured per child and
 * must stay tunable without a rebuild.
 */
final class ConfidenceRouter
{
    /**
     * @param  string|null  $label  'done' or 'not_done'; null when no model ran
     * @param  float|null   $confidence  the model's confidence in $label, 0..1
     */
    public function route(?string $label, ?float $confidence, float $high, float $low): string
    {
        // No model verdict at all -- either the chore has no trained class, or
        // inference failed on the device. Either way a person decides.
        if ($label === null || $confidence === null) {
            return Routing::PENDING_REVIEW;
        }

        // Normalise to a single axis: how confident are we that this chore IS
        // finished. A confident 'not_done' is a confident rejection, so it has
        // to be folded onto the same scale rather than treated separately.
        $confidenceDone = $label === 'done' ? $confidence : 1.0 - $confidence;

        if ($confidenceDone >= $high) {
            return Routing::AUTO_APPROVED;
        }

        if ($confidenceDone <= $low) {
            return Routing::AUTO_REJECTED;
        }

        return Routing::PENDING_REVIEW;
    }

    public function statusFor(string $routing): string
    {
        return match ($routing) {
            Routing::AUTO_APPROVED => Decision::APPROVED,
            Routing::AUTO_REJECTED => Decision::REJECTED,
            default => Decision::PENDING,
        };
    }
}
