<?php

namespace App\Http\Controllers\Api;

use App\Domain\Allocation\LedgerService;
use App\Http\Controllers\Controller;
use App\Models\Child;
use App\Models\LedgerEntry;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class LedgerController extends Controller
{
    public function __construct(private readonly LedgerService $ledger)
    {
    }

    /**
     * What the child sees: how many minutes they have, and how much room is
     * left before today's and this week's limits stop them earning more.
     */
    public function balance(Request $request): JsonResponse
    {
        $child = $request->user();
        $rule = $child->rule();
        $today = now();

        $earnedToday = $this->ledger->earnedOn($child, $today);
        $earnedThisWeek = $this->ledger->earnedInWeekOf($child, $today);

        return response()->json([
            'balance_minutes' => $this->ledger->balance($child),
            'earned_today' => $earnedToday,
            'earned_this_week' => $earnedThisWeek,
            'daily_cap_minutes' => $rule->daily_cap_minutes,
            'weekly_cap_minutes' => $rule->weekly_cap_minutes,
            'daily_remaining' => max(0, $rule->daily_cap_minutes - $earnedToday),
            'weekly_remaining' => max(0, $rule->weekly_cap_minutes - $earnedThisWeek),
            'minutes_per_point' => $rule->minutes_per_point,
        ]);
    }

    /**
     * Spend screen time. The server decides how much is actually taken, so a
     * tampered client cannot spend minutes that were never earned.
     */
    public function consume(Request $request): JsonResponse
    {
        $data = $request->validate([
            'minutes' => ['required', 'integer', 'min:1', 'max:1440'],
        ]);

        $child = $request->user();
        $entry = $this->ledger->consume($child, $data['minutes'], 'Screen time used');

        return response()->json([
            'requested_minutes' => $data['minutes'],
            'consumed_minutes' => abs($entry->minutes),
            'balance_minutes' => $this->ledger->balance($child),
        ]);
    }

    /**
     * The parent's screen-time report for one child: the running ledger and
     * the totals behind it.
     */
    public function report(Request $request, Child $child): JsonResponse
    {
        abort_unless($child->user_id === $request->user()->id, 404);

        $entries = LedgerEntry::where('child_id', $child->id)
            ->with('submission.assignment.template')
            ->orderByDesc('id')
            ->limit(200)
            ->get();

        $rule = $child->rule();
        $today = now();

        return response()->json([
            'child' => ['id' => $child->id, 'name' => $child->name],
            // The server's today, which is what for_date and the daily limit
            // are counted in. A phone's own date can differ from it.
            'today' => $today->toDateString(),
            'balance_minutes' => $this->ledger->balance($child),
            'earned_today' => $this->ledger->earnedOn($child, $today),
            'earned_this_week' => $this->ledger->earnedInWeekOf($child, $today),
            'daily_cap_minutes' => $rule->daily_cap_minutes,
            'weekly_cap_minutes' => $rule->weekly_cap_minutes,
            'totals' => [
                'earned' => (int) LedgerEntry::where('child_id', $child->id)->where('entry_type', LedgerEntry::EARNED)->sum('minutes'),
                'consumed' => abs((int) LedgerEntry::where('child_id', $child->id)->where('entry_type', LedgerEntry::CONSUMED)->sum('minutes')),
                'reversed' => abs((int) LedgerEntry::where('child_id', $child->id)->where('entry_type', LedgerEntry::REVERSAL)->sum('minutes')),
                'forfeited' => (int) LedgerEntry::where('child_id', $child->id)->sum('minutes_forfeited'),
            ],
            'entries' => $entries->map(fn (LedgerEntry $e) => [
                'id' => $e->id,
                'type' => $e->entry_type,
                'minutes' => $e->minutes,
                'points' => $e->points,
                'minutes_gross' => $e->minutes_gross,
                'minutes_forfeited' => $e->minutes_forfeited,
                'for_date' => $e->for_date->toDateString(),
                'note' => $e->note,
                'chore' => $e->submission?->assignment?->template?->name,
                'at' => $e->created_at->toIso8601String(),
            ])->all(),
        ]);
    }
}
