# QuietPass — Full Regression Checklist (Post-Redesign)

Run this **before** trusting the redesign, store screenshots, or anything else in this phase — this is the real gate, not the assets. Test every item in **both light and dark theme** unless noted otherwise; toggle via Profile → Appearance.

## Auth

- [ ] Sign up with a new phone number (light theme)
- [ ] Sign up with a new phone number (dark theme)
- [ ] OTP verification succeeds
- [ ] Sign in with an existing phone number
- [ ] Sign out, then sign back in — lands on the correct house list, not a stale one

## House membership

- [ ] Create a new house
- [ ] Join a house via invite code
- [ ] Copy invite code (confirm it's actually copied — paste it somewhere to check)
- [ ] Share invite code via the native share sheet
- [ ] View housemates list — names, roles, avatars (or initials fallback) all correct
- [ ] As admin: promote a member to admin
- [ ] As admin: demote an admin to member
- [ ] As admin: remove a member from the house
- [ ] Leave a house voluntarily
- [ ] **Confirm departure cleanup**: before leaving, create a recurring booking as the departing member; after leaving, confirm (from another account) that slot is actually freed and rebookable — not just hidden

## Status

- [ ] Set status to Open to Chat (no timer)
- [ ] Set status to Deep Focus with a duration
- [ ] Set status to In Call with a duration
- [ ] Set status to Sleeping Early with a duration
- [ ] Set status to Away with a duration
- [ ] Confirm status badge shows the correct end time on your own row and housemates' rows
- [ ] Confirm status reverts to Open to Chat automatically once the timer lapses (or on next refresh)

## Dinner headcount

- [ ] Mark "Home for dinner" — count and your name update live
- [ ] Mark "Staying out" — count updates, no duplicate entry
- [ ] Confirm live update on a second device when a housemate changes their response
- [ ] Confirm "FINAL AT 5 PM" label appears after the cutoff, and the toggle still works
- [ ] Confirm the tally resets the next calendar day

## Spaces — booking

- [ ] Book a space (one-off), confirm it appears in the list
- [ ] Confirm the chore pass sheet appears right after booking
- [ ] Mark a chore done
- [ ] Attempt to book an overlapping/too-close slot — confirm it's rejected with a clear message

## Spaces — recurring bookings

- [ ] Create a recurring weekly series (2+ weekdays)
- [ ] Confirm the result sheet shows booked occurrences (and any skipped-due-to-conflict ones, if applicable)
- [ ] Confirm "Your recurring bookings" section shows the series with correct days/time
- [ ] **Cancel a single occurrence** — confirm only that one slot disappears, the series and other occurrences remain
- [ ] **Cancel the whole series** — confirm every future occurrence disappears, past occurrences (if any) are untouched
- [ ] Confirm the weekly cap (3 slots/user/week) is enforced — try to exceed it, confirm rejection

## Urgent access request

- [ ] As a non-holder, send an "Ask for 5 min" request on a currently-active booking
- [ ] Confirm the holder receives a push notification
- [ ] Confirm the holder sees the in-app banner live if the app is open
- [ ] Confirm the booking itself is untouched (not cancelled/modified)
- [ ] Confirm sending a second request too soon is rate-limited

## Admin-cancel

- [ ] As admin, cancel another member's booking — confirm the cancel action is visible and works
- [ ] Confirm the affected member gets a push notification
- [ ] Confirm self-cancelling your own booking sends no notification to yourself

## Nudges

- [ ] Send each preset nudge (package arrived, door unlocked, sink full)
- [ ] Send a custom nudge
- [ ] Confirm nudges appear with no sender identity shown anywhere
- [ ] Confirm push notification arrives on a backgrounded device

## House agreements

- [ ] As admin, add an agreement (title + content)
- [ ] As admin, edit an agreement
- [ ] As admin, remove an agreement
- [ ] As a non-admin member, confirm you can view but have no add/edit/remove controls
- [ ] Confirm live update on a second device

## Guest Wi-Fi / QR portal

- [ ] As admin, set Wi-Fi SSID/password
- [ ] Confirm the QR code renders correctly
- [ ] Scan the QR with a **different phone's stock camera app** (not QuietPass) — confirm it prompts to join that network
- [ ] Confirm the "scan with your own camera, app doesn't auto-connect" disclaimer is visible
- [ ] As a non-admin, confirm you can view the QR but not edit the Wi-Fi details
- [ ] Confirm the house rules section below the QR shows the same items as the Agreements screen

## Profile & avatar

- [ ] Upload a profile photo — confirm it appears correctly sized, not stretched/cropped oddly
- [ ] Confirm the uploaded photo appears in the housemates list for other members
- [ ] Remove the profile photo — confirm it reverts to the coloured-initial fallback everywhere (profile, housemates list)
- [ ] Edit display name — confirm it updates everywhere it's shown
- [ ] Toggle theme (System/Light/Dark) — confirm every screen you've already tested still looks correct after switching

## Account deletion

- [ ] Delete account — confirm the confirmation sheet appears with accurate copy
- [ ] Confirm deletion actually removes the account (attempt to sign in again with the same number — should be treated as a new account)
- [ ] Confirm housemates in a shared house see you removed from the member list live

## Icon & splash

- [ ] Confirm the new house+Q icon appears correctly on the home screen launcher
- [ ] Confirm the dark splash screen with the teal mark appears briefly on cold app launch
- [ ] Confirm no stretching/distortion of the icon in the app switcher/recents view

## Narrow-width / overflow check

- [ ] On your smallest/narrowest test device, confirm no screen overflows horizontally, especially the group header and any card with a long house name or long display name
