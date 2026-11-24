<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Support\Carbon;

/**
 * One locked app on one phone (AL-1). An app with no rule is Open. See the
 * migration.
 *
 * @property int $user_id
 * @property string $device_key
 * @property string $package
 * @property string $setting
 * @property int|null $set_by
 * @property Carbon $updated_at
 */
class AppRule extends Model
{
    /** "Earned time": a child's earned minutes, or a grown-up's PIN. */
    public const EARNED_TIME = 'earned_time';

    /** "Grown-ups only": a grown-up only; children's faces show dimmed. */
    public const GROWN_UPS_ONLY = 'grown_ups_only';

    /** What a parent may choose. Open removes the rule. */
    public const OPEN = 'open';

    public const SETTINGS = [self::OPEN, self::EARNED_TIME, self::GROWN_UPS_ONLY];

    protected $fillable = ['user_id', 'device_key', 'package', 'setting', 'set_by'];

    public function household(): BelongsTo
    {
        return $this->belongsTo(User::class, 'user_id');
    }

    public function setter(): BelongsTo
    {
        return $this->belongsTo(User::class, 'set_by');
    }

    /** @return array{package: string, setting: string, set_by: ?int, updated_at: string} */
    public function toPayload(): array
    {
        return [
            'package' => $this->package,
            'setting' => $this->setting,
            'set_by' => $this->set_by,
            'updated_at' => $this->updated_at->toIso8601String(),
        ];
    }
}
