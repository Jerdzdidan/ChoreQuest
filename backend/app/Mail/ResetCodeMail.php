<?php

namespace App\Mail;

use App\Models\PasswordResetCode;
use Illuminate\Mail\Mailable;
use Illuminate\Mail\Mailables\Content;
use Illuminate\Mail\Mailables\Envelope;

/**
 * "Your ChoreQuest code" (PA-3): the 6-digit code that resets a forgotten
 * password, sent from the project's mail account. Sent at once rather than
 * queued, since no queue worker runs beside the API.
 */
class ResetCodeMail extends Mailable
{
    public function __construct(public readonly string $code) {}

    public function envelope(): Envelope
    {
        return new Envelope(subject: 'Your ChoreQuest code');
    }

    public function content(): Content
    {
        return new Content(
            view: 'mail.reset-code',
            text: 'mail.reset-code-text',
            with: ['code' => $this->code, 'minutes' => PasswordResetCode::LIFETIME_MINUTES],
        );
    }
}
