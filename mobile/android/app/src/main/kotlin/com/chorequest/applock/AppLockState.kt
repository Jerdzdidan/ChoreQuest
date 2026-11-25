package com.chorequest.applock

/**
 * What App Lock holds in memory only (AL-3, rule 9): which locked app is
 * open now, for whom, and until when. Shared by the watcher, the lock screen
 * and the Flutter channel; every change goes through this object's lock.
 *
 * Nothing here is saved. If Android stops ChoreQuest, every open locked app
 * locks again, which is the safe way to fail.
 */
object AppLockState {
    /** The lock screen was asked for, over [pkg]. */
    data class LockRequest(val pkg: String, val reason: String, val at: Long)

    /**
     * A child spending earned minutes on [pkg]. The server has paid until
     * [paidUntil]; [balanceAfter] is what the child has left beyond it.
     * [more] turns false once the server says there are no more minutes, or
     * cannot be reached, and then [endReason] says which.
     */
    class ChildSession(
        val pkg: String,
        val token: String,
        var paidUntil: Long,
        var balanceAfter: Int,
    ) {
        var more = balanceAfter > 0
        var requesting = false
        var endReason = REASON_TIME_UP
        var warned = false
    }

    /**
     * A grown-up opened [pkg] with their PIN or password. It stays open
     * while it is in front, and locks again once it has been away for a
     * little while.
     */
    class GrownUpPass(val pkg: String, val grantedAt: Long) {
        var lastInFront = 0L
    }

    const val REASON_LOCKED = "locked"
    const val REASON_TIME_UP = "time_up"
    const val REASON_OFFLINE = "offline"

    /** Read by the lock screen when ChoreQuest opens over a locked app. */
    var pending: LockRequest? = null
    var child: ChildSession? = null
    var grownUp: GrownUpPass? = null

    /** Why each app last locked, for a moment, so the lock screen can say "Time's up". */
    val endedBecause = HashMap<String, Pair<String, Long>>()
}
