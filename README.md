# ChoreQuest

## Running locally

The API runs on port **8001**, not Laravel's usual 8000, because other
projects on the team's machines already use 8000. `backend/.env` sets it with
`SERVER_PORT=8001`, so no flag is needed:

```
cd backend
php artisan serve --host 0.0.0.0
```

The app points at `http://10.0.2.2:8001/api` by default, which is the host
machine as seen from an Android emulator. For a phone over USB:

```
adb reverse tcp:8001 tcp:8001
flutter run --dart-define=API_BASE_URL=http://127.0.0.1:8001/api
```

An existing `backend/.env` made before this change needs the
`SERVER_PORT=8001` line copied in from `.env.example`.

## Testing

A demo household with three weeks of approved quests, so every badge,
story chapter and unlockable can be seen without doing chores first. It is
created by the normal local seeding (`php artisan db:seed`), or on its own:

```
cd backend
php artisan db:seed --class=DemoAccountSeeder
```

| Who | Sign in with |
|---|---|
| Demo parent | `demo.parent@chorequest.test` / `demo-parent-2026` |
| Demo child | household code shown by the seeder (and on the demo parent's home screen), child **Demo Hero**, PIN `2468` |

Running it again adds nothing. Local and testing environments only.
Team Player and story chapter 4 stay locked until a family quest is done.
