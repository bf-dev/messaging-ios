# Messaging Server iOS Simulator QA Checklist

Use this checklist when validating the refreshed Messaging Server iOS flow in Simulator.

## Recommended setup

- Open `Telegram/Telegram.xcodeproj` in Xcode.
- Pick the Messaging Server app scheme used for the custom iOS build.
- Recommended simulators:
  - iPhone 16
  - iPhone 16 Pro
  - iPhone SE (3rd generation)
- Validate once in Light Mode and once in Dark Mode.
- If possible, test on both a fresh install and an upgrade build that already has a saved session.

## Pre-flight

- Confirm the app launches to the new welcome screen when there is no saved session.
- Confirm the app launches directly into Chats when a valid saved session exists.
- Confirm there are no Auto Layout warnings in the Xcode console.
- Confirm no obvious flicker happens when switching roots after login or logout.

## 1. Welcome + login flow

### Fresh onboarding

- Launch with no saved session.
- Verify the welcome screen layout:
  - icon, headline, server card, feature cards, and primary CTA are visible
  - spacing looks balanced on small and large phones
  - content scrolls if Dynamic Type or small screens reduce vertical space
- Tap **Get Started**.
- Verify the login screen matches the new Telegram-style flow.

### Successful connect

- Enter a valid API key.
- Leave the default server URL or enter a known-good server.
- Tap **Connect**.
- Verify:
  - button enters loading state immediately
  - duplicate taps do nothing while loading
  - app transitions to the authenticated tabs after success
  - saved session persists after relaunch

### Failed connect

- Enter an invalid API key.
- Tap **Connect**.
- Verify:
  - loading ends cleanly
  - a user-visible error appears
  - the screen remains interactive afterward
  - the app does not hang

### Timeout handling

- Point the app to an unreachable server URL.
- Tap **Connect**.
- Verify:
  - request times out in about 10 seconds
  - loading stops automatically
  - an error is shown
  - Connect can be tapped again immediately

### Background cancellation

- Start a connect attempt against a slow or unreachable server.
- Send the app to background before completion.
- Return to the app.
- Verify:
  - connection attempt is cancelled
  - loading state is reset
  - the app shows the cancellation toast/message
  - the screen is usable without force closing

### Edit connection safety

- Start from a valid saved session.
- Go to **Settings -> Edit Connection**.
- Enter invalid credentials.
- Verify failed validation does **not** wipe the previous working session.
- Relaunch the app and verify it still opens with the last known-good session.

## 2. Chat list validation

- Verify the Chats tab opens with the summary card and live connection badge.
- Confirm rows show:
  - avatar or initials
  - chat title
  - latest preview text
  - secondary platform/account text
  - timestamp
  - unread badge when unread count is non-zero
- Confirm unread chats look visually stronger than read chats.
- Pull to refresh and verify the list updates without layout glitches.
- Confirm search filters by title, preview, account, and participant names.
- Confirm filter sheet works for:
  - platform
  - account
  - clear filters
- Confirm the empty state looks correct when:
  - there are no chats at all
  - filters remove all results
  - search returns no matches
- If realtime events are available, verify the list refreshes after new inbound activity.
- Confirm chats remain sorted by newest activity.

## 3. Conversation screen validation

- Open a busy chat and verify:
  - title/subtitle render correctly
  - bubble spacing feels consistent
  - outgoing and incoming bubbles are visually distinct
  - media previews load when available
  - attachment filename fallback appears when preview is unavailable
- Open an empty or low-traffic chat and verify the empty state.
- Scroll long conversations and confirm there is no jumpy layout behavior.
- Open the keyboard and verify:
  - composer stays above the keyboard
  - list remains readable
  - bottom scrolling still works
- Type long text and verify the composer grows without breaking layout.
- Confirm the placeholder hides when text exists and returns when cleared.
- Add and remove attachments and verify the pill row updates correctly.
- Tap suggested replies and verify they populate the composer correctly.

### Pending approval bubbles

- Send a message that requires approval.
- Verify an optimistic pending bubble appears immediately.
- Verify pending/approved/sending/failed states update in place.
- Use bubble actions to approve, deny, or edit when supported.
- Confirm failed states remain visible and do not silently disappear.

### Read state

- Open a chat with unread messages.
- Scroll through the latest visible messages.
- Return to the chat list and verify unread state decreases or clears as expected.

## 4. Settings validation

- Verify the new summary card at the top of Settings.
- Confirm Connection section shows:
  - server URL
  - masked API key
  - connected account count
- Confirm Platform Status section:
  - loads successfully
  - shows empty-state copy when nothing is configured
  - opens detail alerts for configured rows
- Confirm Actions section:
  - Edit Connection opens the updated login flow
  - Refresh Server Status updates the section without issues
  - Log Out clears the session and returns to onboarding

## 5. Visual polish pass

Check these quickly in both Light and Dark Mode:

- button states: normal, pressed, disabled, loading
- input fields: idle, focused, error alert shown after failed connect
- card borders/shadows feel subtle and not muddy
- avatar initials remain readable across colors
- timestamps and unread badges align correctly
- long titles and long preview text truncate gracefully
- layout still looks acceptable with larger text sizes
- no clipped content on iPhone SE width

## 6. Regression notes

Record the following after QA:

- simulator/device name and iOS version
- app scheme/build used
- server URL used for validation
- which login scenarios passed: success / failure / timeout / background cancel
- which messaging scenarios passed: search / filters / send / pending approval / logout
- screenshots for any layout issue or console warning

## Suggested bug report format

- **Area:** Login / Chats / Conversation / Settings
- **Device:** e.g. iPhone 16 Simulator, iOS 18.x
- **Steps:** numbered reproduction steps
- **Expected:** concise expected result
- **Actual:** concise actual result
- **Evidence:** screenshot, screen recording, console log
