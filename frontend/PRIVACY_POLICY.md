# QuietPass Privacy Policy

**Last updated:** October 13, 2026

QuietPass ("the app", "we", "us") helps people living in a shared house coordinate day-to-day life: who's home, who's free to talk, who's using a shared space, and simple house logistics like dinner plans and Wi-Fi for guests. This page explains exactly what we collect, why, and how it's handled.

This policy covers the QuietPass mobile app and its backend. It does not cover third-party services you reach through links inside the app (for example, a phone call to a landlord's number you've saved).

## What we collect

### Your phone number
Used to sign you in via Firebase Authentication (OTP/SMS verification) and to identify your account. Your phone number is never shown to other members of your house — they see your display name only.

### Your display name
Shown to the other members of any house you join, so they know who's who. You can change it at any time from your profile.

### Your profile photo (optional)
If you choose to upload a profile photo, it's resized, compressed, and stripped of EXIF metadata (which can otherwise contain location and device information) on our server, then stored in Google Cloud Storage. The resulting photo is shown to other members of your house(s) wherever your name appears. You can remove your photo at any time, which deletes it from storage.

### House activity you generate
This is the core of what the app does, and all of it is created by you and visible only to members of the house(s) you belong to:
- **Live status** — "Open to Chat," "Deep Focus," "In Call," and similar, with an optional end time.
- **Dinner headcount** — whether you're home for dinner or staying out, for the current day.
- **House agreements** — pinned house rules, trash schedule, landlord contact, or notes an admin has added.
- **Wi-Fi details** — your house's guest Wi-Fi network name and password, if an admin has set them, used only to generate an in-app QR code. The app does not transmit this to anyone outside your house's membership.
- **Space bookings** — reservations for shared spaces (like a living room or desk), including recurring weekly bookings, and the clean-up "chore" tied to each booking.
- **Nudges** — short alerts sent to the house ("the sink is full," "a package arrived," or a custom message). Nudges are **anonymized**: the backend never records or transmits who sent a nudge, only its content and type. Nobody — including us — can see who sent a particular nudge after the fact, because that information is never stored.
- **Urgent access requests** — a polite, non-anonymous notification you can send to whoever currently holds a shared space you need briefly. Unlike nudges, this one identifies the requester to the holder, since it's a direct request about a specific booking, not a general house-wide signal.

### Push notification tokens
If you allow notifications, we store a device token (issued by Firebase Cloud Messaging) so we can deliver nudges, urgent access requests, and similar alerts to your device even when the app isn't open. This token identifies your device for push delivery purposes; it does not identify you personally beyond that.

### What we do *not* collect
We do not collect your precise location, your contacts, your browsing history, or any data unrelated to coordinating life in your house. We do not use your data for advertising, and we do not sell your data to anyone.

## How your data is used

All of the above is used for exactly one purpose: making the app work for you and the people in your house(s). Specifically:

- Your phone number and display name identify you to your housemates.
- Your status, dinner response, bookings, and agreements are shown to members of the same house so coordination actually works.
- Push tokens let us deliver real-time alerts (nudges, urgent access requests, booking changes) to your device.
- Your profile photo, if set, is shown alongside your name wherever your name appears to housemates.

We do not use any of this data to build an advertising profile, and we do not share it with third parties for marketing.

## Who can see your data

- **Other members of a house you belong to** can see your display name, status, dinner response, bookings, and profile photo (if set) — but only within that specific house. Someone in a different house you're not a member of cannot see any of this.
- **Nudges are anonymous even to other house members** — the content is visible, the sender is not, by design (the backend never records it).
- **QuietPass (us)** can access data as needed to operate, maintain, and debug the service, and to respond to legal requirements. We do not look at your data outside of these purposes.
- **No one outside your house(s)** — and no advertiser or data broker — has access to your activity data.

## Where your data is stored

- Account, house, and activity data is stored in a managed PostgreSQL database (Google Cloud SQL).
- Profile photos are stored in Google Cloud Storage.
- Authentication is handled by Firebase Authentication (Google).
- Push notifications are delivered via Firebase Cloud Messaging (Google).

All of the above run on Google Cloud infrastructure, in the same region, with access restricted to what the app's backend needs to function.

## Your choices and controls

- **Edit your display name** at any time from your profile.
- **Upload or remove your profile photo** at any time from your profile.
- **Delete your account** at any time from your profile. This permanently removes your account, your memberships in every house, your bookings, your chores, and your profile photo. This cannot be undone.
- **Leave a house** at any time, which removes your future bookings and recurring series in that house (so you're not holding a shared space you can no longer use) without affecting your account or your data in any other house.
- **Push notifications** can be disabled from your device's system settings at any time.

## Data retention

We keep your data for as long as your account exists. If you delete your account, your personal data (profile, display name, phone number, memberships, bookings, chores, profile photo) is permanently deleted. Nudge content is not retained beyond live delivery in any form that identifies a sender, since no sender is ever recorded.

## Children's privacy

QuietPass is intended for general audiences coordinating shared housing and is not directed at children. We do not knowingly collect data from children under 13 (or the relevant minimum age in your jurisdiction).

## Changes to this policy

If we make material changes to this policy, we'll update the "Last updated" date above. Continued use of the app after a change means you accept the updated policy.

## Contact

Questions about this policy or your data can be sent to the app's support contact listed on its store listing page.

---

*This document needs to be hosted at a stable, publicly reachable URL before store submission — both Google Play and Apple require a live privacy policy link in the store listing, not just an in-app or repository file.*
