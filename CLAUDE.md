# ChoreQuest

Undergraduate thesis project. A CNN-assisted, rule-based Android application that
converts a child's verified household chore into a parent-defined amount of
recreational screen time. Children aged 4-10. Researchers: Gondayao, Mercado,
Tanqui-on.

The application is evaluated against six ISO/IEC 25010:2023 characteristics:
functional suitability, performance efficiency, interaction capability,
reliability, security, maintainability.

## Stack — pinned, do not substitute

| Layer    | Choice                              | Why it is fixed |
|----------|-------------------------------------|-----------------|
| API      | Laravel 12 + Sanctum                | Laravel 13 needs PHP ^8.3; this machine has PHP 8.2.12 (XAMPP) |
| Database | MySQL / MariaDB 10.4 (XAMPP)        | Named in the manuscript |
| Mobile   | Flutter + Riverpod                  | Named in the manuscript |
| Model    | MobileNetV2 → TensorFlow Lite, int8 | On-device inference is the privacy argument |
| Training | Python 3.13 + TensorFlow 2.21       | TF 2.21 ships a cp313 Windows wheel |

Changing any of these means editing the manuscript, so raise it before doing it.

## Architectural rules — these are load-bearing

These are the commitments the paper actually argues for. Do not relax them for
convenience, especially late in the project when a shortcut looks cheap.

1. **Allocation is authoritative in Laravel.** The Dart copy of the rules exists
   only to render a balance instantly and to work offline. It never writes a
   balance the server did not compute. This is what stops a child from editing
   their own point total by tampering with the app.

2. **`ledger_entries` is append-only.** Earning writes `+minutes`; consuming
   writes `-minutes`. Balance is always `SUM(minutes)`. Never add a `balance`
   column to any table. Never `UPDATE` or delete a past ledger row. A replayable
   ledger is the reliability evidence.

3. **Verification returns three states, never two:** `auto_approved`,
   `pending_review`, `auto_rejected`. The middle state — abstention — is the
   ethical core of the study. A model that is unsure must be allowed to say so
   and defer to the parent.

4. **Both confidence thresholds live in `allocation_rules`, per child.** Never
   hard-code them. They must be tunable from the parent settings screen without
   a rebuild — that is the maintainability evidence.

5. **A submission keeps both the model's original guess and the parent's final
   decision.** Chapter 4 computes false-approval and false-rejection rates from
   that pair. Overwriting the model's guess destroys the data.

6. **Child authentication is PIN-through-household, never email.** A child picks
   an avatar within their parent's household and enters a 4-digit PIN. Tokens
   carry an ability, `parent` or `child`, and child tokens are refused on every
   parent route.

7. **Chore photos are never publicly reachable.** They are images of minors
   inside their homes. Store outside the public root; serve only through an
   authenticated, authorised route.

## Scope — what NOT to do

- **Do not write tests.** The research team writes all tests themselves.
- **Do not write documentation files** (`.md`, ERDs, API contracts, READMEs).
  The team writes all of it for the manuscript.
- **Do not regenerate or edit existing migrations** once data is seeded. Add a
  new migration instead. Never run `migrate:fresh` without being asked.
- **Do not refactor outside the current slice.** If a change seems needed
  elsewhere, say so and wait.

## How the work is structured

One slice per session. Branch per slice (`slice/1.3-submissions`), merge to
`main` when the slice is done.

When a slice touches the schema or the allocation engine, plan before building.

### Verification — team decision, 6 September 2026

The team does not use an HTTP client and has chosen to **skip verification gates
on the backend slices (1.2, 1.3, 1.4)**. Nothing exercises the API until the
Flutter client reaches it in Phase 3. Do not ask them to run curl or install a
REST client; do not write gate scripts unless they ask.

From Phase 3 on, the team runs the app on a device themselves. Before handing a
mobile slice over, make sure `flutter analyze` is clean and a debug APK builds.

Two consequences that shape how backend code must be written:

1. **Keep the allocation engine pure and isolated** — no I/O, no clock reads, no
   randomness inside it, dependencies passed in. When a wrong balance shows up in
   Phase 3, that isolation is what makes it possible to exercise the engine on
   its own and settle whether the bug is in the engine or the client.

2. **State assumptions in the commit message**, especially the ones nobody
   checked: week boundaries, timezone handling, what "today" means, concurrency
   on approval. Unverified assumptions that are written down can be found later;
   unverified assumptions that are not written down cannot.

When a Phase 3 bug appears, hit the API directly with curl at that moment to
bisect it. The team does not need to install anything for that.

## Conventions

- Laravel: business rules live in `app/Domain/`, not in controllers. The
  allocation engine is a pure function — no I/O, no clock, no randomness — so
  the same inputs always produce the same minutes.
- API routes are plural and resourceful: `/api/children`, `/api/submissions`.
- Flutter: folder per feature under `lib/features/`, plumbing in `lib/core/`,
  widgets used by more than one feature in `lib/shared/`.
- Flutter: Riverpod 3 for state and Flutter's own `Navigator` for routing — not
  go_router, which moved to the separate `material_ui` package while the SDK
  still ships `material.dart`. The `MaterialApp` is keyed by the signed-in
  identity, so signing in or out discards the whole navigation stack. Keep it
  that way rather than popping routes by hand.
- Flutter: every API failure is a sealed `ApiException` carrying a message fit
  to show. Switches over it, and over dio's `DioExceptionType`, stay exhaustive
  with no default case, so a new failure type breaks the build instead of a
  screen.
- Flutter: cleartext http is allowed in `android/app/src/debug` only.
- Migrations are additive and named for what they do.

## Running locally

MySQL runs from the XAMPP Control Panel (Apache is not needed). The `mysql`
client is at `C:\xampp\mysql\bin\mysql.exe` and is not on PATH.

```
cd backend
php artisan serve --host 0.0.0.0 --port 8000
```

`--host 0.0.0.0` matters for the emulator and for a phone on Wi-Fi: the default
binds to 127.0.0.1 only. It is not needed with `adb reverse`, below.

```
cd mobile
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8000/api
```

Inside an Android emulator, `10.0.2.2` is the host machine. `localhost` is the
emulator itself.

On a real phone over USB, prefer `adb reverse tcp:8000 tcp:8000` with
`API_BASE_URL=http://127.0.0.1:8000/api`. The phone's port 8000 is carried over
the cable, so no firewall rule is involved. That matters on this machine: its
Wi-Fi uses the Public network profile, where Windows Firewall blocks inbound
connections, so reaching the PC's LAN address from a phone needs an admin to
change the profile or add a rule.

### Android builds on this machine — required setting

Toolchain: Flutter 3.47.2 at `C:\src\flutter`, Android SDK at `C:\Android\Sdk`,
and Android Studio's bundled JDK 25, which `flutter config --jdk-dir` points at.
The user folder `C:\Users\A S U S` contains spaces; none of the toolchain lives
under it. The project itself does, and that builds fine.

Gradle fails within seconds with `java.io.IOException: Unable to establish
loopback connection` unless every JVM involved is given a pipe directory
outside the user profile:

```
JAVA_TOOL_OPTIONS=-Djdk.net.unixdomain.tmpdir=C:\Windows\Temp
```

Cause, confirmed from stack traces on both sides of the connection: the Gradle
client and its daemon each call `Selector.open()`, and on Windows JDK 25 backs
that with an AF_UNIX socket file in the temp directory. Under
`C:\Users\A S U S\...` that socket fails with "Invalid argument: connect".

`GRADLE_OPTS` is not enough, despite an earlier note here saying it was: it
reaches only the client, and a daemon started without the property dies on its
first connection with "A new daemon was started but could not be connected
to". `JAVA_TOOL_OPTIONS` reaches the client, the daemon and the Kotlin compiler
daemon alike; each JVM then prints a harmless "Picked up JAVA_TOOL_OPTIONS"
line. `C:\Windows\Temp` exists on every Windows install, so there is no folder
to keep alive.

If it is not set in the user environment, set it for the command:
`JAVA_TOOL_OPTIONS='-Djdk.net.unixdomain.tmpdir=C:/Windows/Temp' flutter ...`
in Bash, or `$env:JAVA_TOOL_OPTIONS = '-Djdk.net.unixdomain.tmpdir=C:\Windows\Temp'`
first in PowerShell. Do not work around it by moving TEMP, setting JAVA_HOME,
or moving the project.
