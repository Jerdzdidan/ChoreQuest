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
