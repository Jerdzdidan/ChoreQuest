<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Support\Carbon;

/**
 * A locked app opened from the lock screen (AL-1, rule 10). Append-only:
 * there is no updated_at and no update path. See the migration.
 *
 * @property int $user_id
 * @property string $device_key
 * @property string $package
 * @property string $method
 * @property int|null $child_id
 * @property int|null $parent_id
 * @property Carbon $created_at
 */
class AppUnlock extends Model
{
    /** A child's earned minutes opened an Earned time app. */
    public const CHILD_MINUTES = 'child_minutes';

    /** A grown-up opened it with their PIN. */
    public const PARENT_PIN = 'parent_pin';

    /** A grown-up opened it with their password, their PIN being off. */
    public const PARENT_PASSWORD = 'parent_password';

    public const UPDATED_AT = null;

    protected $fillable = ['user_id', 'device_key', 'package', 'method', 'child_id', 'parent_id'];

    protected function casts(): array
    {
        return [
            'created_at' => 'datetime',
        ];
    }

    public function household(): BelongsTo
    {
        return $this->belongsTo(User::class, 'user_id');
    }

    public function child(): BelongsTo
    {
        return $this->belongsTo(Child::class);
    }

    public function parent(): BelongsTo
    {
        return $this->belongsTo(User::class, 'parent_id');
    }

    /** @return array{id: int, device_key: string, package: string, method: string, child: ?array, parent: ?array, at: string} */
    public function toPayload(): array
    {
        return [
            'id' => $this->id,
            'device_key' => $this->device_key,
            'package' => $this->package,
            'method' => $this->method,
            'child' => $this->child ? ['id' => $this->child->id, 'name' => $this->child->name] : null,
            'parent' => $this->parent ? ['id' => $this->parent->id, 'name' => $this->parent->name] : null,
            'at' => $this->created_at->toIso8601String(),
        ];
    }
}
