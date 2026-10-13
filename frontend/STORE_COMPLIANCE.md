# Store Compliance Notes — Data Safety (Google Play) & Privacy Labels (Apple)

Based on what QuietPass actually collects (see PRIVACY_POLICY.md). Fill the console forms from this list — it's scoped to this app's real data flows, not a generic template.

## ⚠️ Flagged as sensitive — declare carefully

- **Phone number** — collected at sign-up (Firebase Auth), used for account identification. Not shared with third parties beyond Firebase/Google (the auth processor itself).
- **Profile photos** — optional, user-uploaded, stored in Google Cloud Storage, visible to housemates. This is "Photos" under both forms' sensitive-category data types — declare it explicitly, don't lump it into generic "User content."

## Google Play Data Safety form

Answer "Does your app collect or share any of the required user data types?" → **Yes**, and declare:

| Data category | Data type | Collected? | Shared with third parties? | Purpose |
|---|---|---|---|---|
| Personal info | Phone number | Yes | No (processed by Firebase Auth only, not shared onward) | Account creation, authentication |
| Personal info | Name | Yes | No | Shown to housemates within the app |
| Photos | Photos | Yes (optional) | No | Profile photo shown to housemates |
| App activity | App interactions | Yes | No | Status, bookings, nudges, agreements — all functional app data |
| Device or other IDs | Device ID | Yes | No | FCM push token, for delivering notifications |

For each: mark **"Data is encrypted in transit"** → Yes (HTTPS/TLS throughout). Mark **"You provide a way to request data deletion"** → Yes (account deletion in-app removes everything immediately; also note this in the form's data-deletion field).

**Data collection is not optional for core functionality** except the profile photo, which should be marked as optional/user-initiated.

**None of this data is used for advertising or sold to third parties** — answer the relevant Data Safety questions accordingly (no, to both).

## Apple App Store Privacy (Nutrition) Labels

Under **App Privacy → Data Used to Track You**: answer **No** — nothing here is used for cross-app/cross-site tracking or ad targeting.

Under **Data Linked to You** (data tied to the user's identity), declare:

| Category | Apple's data type | Linked to user? |
|---|---|---|
| Contact Info | Phone Number | Yes |
| Contact Info | Name | Yes |
| User Content | Photos or Videos | Yes (profile photo) |
| User Content | Other User Content | Yes (status, bookings, nudges, agreements) |
| Identifiers | Device ID | Yes (push token) |

Under **Data Not Linked to You**: none applies here — every data type above is tied to an identified account, nothing is anonymized/aggregated before storage (nudges are anonymous in display to *other users*, but the record of who sent one isn't even stored at all server-side — so there's no "linked but anonymized" bucket to declare either; it's simply never collected).

## One nuance worth stating plainly in both forms

**Nudges are not anonymous to the backend because they're anonymized — they're anonymous because the sender is never recorded in the first place.** There's no "we store it but hide it from other users" distinction to make; the data literally doesn't exist. If either form has a field for "data retained but not shown to other users," this does not apply — don't declare nudge-sender identity as collected data at all.

## Account deletion requirement (both stores now require this)

QuietPass already has in-app account deletion (Profile → Delete account), which immediately and permanently removes: account, phone number, display name, profile photo, all house memberships, all bookings/chores, and push tokens. Both Google Play and Apple require this capability to exist and be reachable without contacting support — confirm this still works in the regression pass below, and reference it directly in the Data Safety form's deletion-request field.
