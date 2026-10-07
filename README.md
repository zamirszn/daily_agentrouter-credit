# Daily Login Runner

An Android app that signs in to https://agentrouter.org with your GitHub accounts, one after
another, every day at 6:30pm by default to claim the daily $25 credit.
For each account it: logs in, waits 10s, logs out, pauses, then moves to the next one.
You can add as many accounts as you want.

## Build

Local: `flutter pub get` then `flutter build apk --release`.
The APK is at `build/app/outputs/flutter-apk/app-release.apk`.

GitHub Actions: push the repo, open Actions -> "Build APK", download the artifact.

## How to use the app

The app has four tabs: **Home**, **Accounts**, **Run** and **History**.

### 1. First launch
Allow notifications and exact alarms when asked. Without them the 6:30pm reminder will not fire.
On Home, the "Daily run at 6:30pm" card should say it is scheduled.

### 2. Add your accounts (Accounts tab)
1. Tap **Add**, type a name, tap **Add**. Repeat for as many accounts as you need.
2. For each account tap **Set up**. A browser opens on github.com/login.
3. Log in to that GitHub account by hand (including any 2FA), then tap **Save session**.
   The chip changes to "Session saved".
4. First time only for each account: tap the login icon in the top bar to open agentrouter,
   tap **Continue with GitHub** and approve GitHub's "Authorize" page if it shows. Then tap
   **Save session** once more.
5. Use the pencil to rename an account and the bin to remove it (this also deletes its saved session).

Tip: set up one account at a time. Each setup starts from a clean browser, so sessions do not mix.

### 3. Settings (Home tab)
- **Wait between accounts**: pause after one account logs out before the next one starts
  (0-120s, default 15s). Increase it if the site rate-limits or the next login fails.

### 4. Test before trusting it (Home tab, Test card)
- Tick the accounts to test. Turn on **Quick waits** for a faster run
  (3s before logout, 3s between accounts, 40s login timeout).
- **Run now** starts immediately and switches to the Run tab.
- **Test in 30s** schedules a notification in 30 seconds. Try it with the app open, in the
  background, and closed. Tapping the notification opens the app and starts the run once.
- After a test, the line "Registered notification ids" should still include `0`
  (the daily schedule).
- Test runs are marked "(test)" in History.

### 5. The daily run
At 6:30pm you get a notification. **Tap it**: the app opens and the run starts by itself, using
all your accounts with the normal waits (10s before logout, your chosen gap between accounts).
Keep the phone on and unlocked while it runs. The run needs the app in the foreground.
When it finishes you get a "X/Y done" notification.

### 6. Run tab
Shows the live browser and a step log. Do not touch the page while a run is going.

### 7. History tab
Every run with a per-account result and the step it reached. Tap a run to expand it.

## Statuses
- **success**: logged in, waited, logged out.
- **timeout**: login (60s) or logout (30s) took too long.
- **failed**: something broke, e.g. the GitHub button was not found. The note says what.
- **relogin**: the saved GitHub session no longer works. Go to Accounts and use **Re-login**
  for that account. The app does not retry in a loop.

A failed account never stops the run; the next account still goes.

## How the GitHub button is clicked
The page loads with JavaScript, so the app waits for it to render, then sends a full tap
(press and release). If the page has not moved to GitHub within 6s it taps again, up to 6 times.
The log lines show "click had no effect, retrying" when that happens.

## Troubleshooting
- **Notification never appears**: Android settings -> Apps -> Daily Login Runner -> allow
  notifications and "Alarms & reminders". Disable battery optimisation for the app.
- **"Needs re-login"**: redo Set up for that account (steps 2-3 above).
- **Logout used fallback** (History note): the logout menu item was not found, so the app cleared
  the site's storage and cookies instead. The result is still a logged-out state.
- **Build fails on `proguard-android.txt`**: Android Gradle Plugin 9 vs the inappwebview plugin.
  Change `proguard-android.txt` to `proguard-android-optimize.txt` in the plugin's
  `android/build.gradle` inside your pub cache.

## Security
Cookies are stored only in encrypted secure storage on the phone. No passwords are stored,
cookie values are never logged, and Android cloud backup is off.
