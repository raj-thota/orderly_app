# Manual Add — structured fields + contacts import

Date: 2026-07-21
Status: approved

## Problem

The FAB (`main.dart` `Icons.add`) opens `CaptureSheet`. Its **Manual Entry**
source is a single free-text box wired to `CaptureController.setText()` →
`CaptureDraft.fromText()`. Name is only extracted by a chat-oriented regex
(`capture_draft.dart:84`):

```
(?:this is|i am|i'm|from)\s+([A-Z][a-z]+)|^([A-Z][a-z]+):
```

Hand-typed manual input (`Rahul 98765... 2 chairs`) matches nothing, so
`draft.name` stays null and `review_confirm_screen.dart:112` renders
`draft.name ?? 'Unknown'`. AI refine can backfill but is nullable/unreliable, so
manually-added customers "always show Unknown".

Second ask: let the user add a customer from phone contacts.

## Decisions (approved)

1. Manual Entry becomes a **structured form** (Name / Phone / What they want).
   Paste / Screenshot / Voice keep the AI parser — correct there.
2. **"Pick from Contacts"** button lives on the manual form.
3. Contacts v1 = **name + primary phone prefill** only.

## Design

### 1. Structured Manual Entry (root fix for "Unknown")

Replace the `manual` branch of `_InputArea` in `capture_sheet.dart` with three
fields bound directly to the controller:

| Field | Binds to | Effect |
|---|---|---|
| Name | `setName(v)` | sets `manualName` → `draft.name`; AI-guarded |
| Phone | `setPhone(v)` | sets `manualPhone`; normalized |
| What they want (optional) | `setText(v)` | existing path; drives items/intent + AI refine on the description only |

Name/phone become `manualName`/`manualPhone`, which the AI merge already refuses
to overwrite (`capture_provider.dart:190,196`). So the description can still be
AI-parsed for items without clobbering the hand-typed identity.

- Review button `hasContent`: enable when name OR phone OR description non-empty.
- Controller tweak: `setName`/`setPhone` early-return on empty
  (`capture_provider.dart:242,250`), so a cleared field can't un-set the manual
  value. Allow empty to clear `manualName`/`manualPhone` so the form is
  authoritative. Dialog-edit callers (`capture_screen.dart`) only submit
  non-empty, so they are unaffected.

### 2. Import from Contacts

- New dep `fluttercontactpicker` — purpose-built native-picker-only plugin.
  `FlutterContactPicker.pickPhoneContact()` opens the OS chooser and returns a
  single `PhoneContact{ fullName, phoneNumber }`. No address-book enumeration.
- Picked contact → prefill Name + phone into the form fields (editable).
- Wrapped behind a thin `ContactsService` interface (provider-injected) so it is
  mockable and the native picker is never invoked in tests. A pure
  `contactToPrefill(PhoneContact)` helper does name/phone extraction +
  `normalizePhone` — this is the unit-tested part.
- Platform permissions (per plugin docs):
  - **iOS / Android ≤10:** none — native picker is system-mediated.
  - **Android 11+ / Xiaomi:** requires `READ_CONTACTS`. Add
    `<uses-permission android:name="android.permission.READ_CONTACTS"/>` to
    `AndroidManifest.xml`; the plugin requests it at runtime
    (`pickPhoneContact(askForPermission: true)`). This is the minimal permission
    for native contact picking on modern Android and is declared for Play data
    safety.

### Data flow (downstream unchanged)

`form fields → controller (manualName/manualPhone/draft) → Review & Confirm →
save() → createOrLink(name, phone)`. Name non-null → no "Unknown";
`customers.name` correct.

## Testing

- Unit (`capture_controller_test.dart`): `setName('')` clears `manualName`;
  `setName('Rahul')` then `setText(description)` keeps `draft.name == 'Rahul'`.
- `ContactsService` interface has a fake; picker not hit in tests.
- Manual widget smoke deferred (optional).

## Out of scope (v1)

Bulk import, contact sync, multi-number chooser, editing an existing customer
from contacts.
