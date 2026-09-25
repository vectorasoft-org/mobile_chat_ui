# VSChatWidget — Mobile Developer Guide

`vs_chat_flutter` is a **one-shot chat plugin** for Flutter apps. You declare
your chat API and your look **once**. The package provides the rest: the
conversation list, starting a chat, the room, attachments, voice notes,
live messages, reconnects, and a Telegram-style Media / Files / Members panel.

It is the Flutter twin of the web widget (`vschat.js`). Both talk to the same
host API and the same chat-service, so a room opened on the web and one opened
in the app are the **same room**.

> **Design rule: the package is generic.** It does not know what a "parcel",
> "payout" or "merchant" is. Your backend (the *host*) decides what a chat is
> about and who is in it. The package only shows what the host returns. The
> same widget serves delivery support, a helpdesk, internal staff rooms or an
> AI assistant.

---

## 1. How it fits together

```
 ┌──────────── your app ────────────┐
 │  VSChatWidget / VSChatButton     │
 │            │                      │
 │        VSChat (facade)            │
 └────┬─────────────────────┬────────┘
      │ HTTPS + your login   │ Socket.IO (api key + one-time token)
      ▼                      ▼
 ┌─────────────┐      ┌───────────────┐
 │  Host API   │─────▶│  chat-service │   the host holds the app secret;
 │ (e.g. DMS)  │secret│  (generic)    │   the phone never sees it
 └─────────────┘      └───────────────┘
```

| Concern | Who does it |
|---|---|
| What a chat is about (topic), who is in it (members), may this user open it | **Host API** |
| Minting the one-time socket token for this user | **Host API** (with the app secret) |
| Storing uploads, serving file bytes to members only | **Host API**, which proxies chat-service |
| Messages, history, live delivery, deletes | **chat-service** over the socket |
| Every screen and interaction | **This package** |

The phone never asserts who it is. The host derives the user from the
login token on every call, and chat-service verifies the socket token the
host minted.

---

## 2. Install

`pubspec.yaml`:

```yaml
dependencies:
  vs_chat_flutter:
    git:
      url: https://github.com/vectorasoft-org/mobile_chat_ui.git
      ref: <pinned commit>   # pin a commit; move all apps together
```

To work on the package locally, use a git-ignored `pubspec_overrides.yaml`.
Never put a `path:` in `pubspec.yaml`.

```yaml
dependency_overrides:
  vs_chat_flutter:
    path: ../../Packages/mobile_chat_ui
```

Platform permissions (microphone, camera, photos, location) are listed in the
package [README](../README.md#platform-setup).

Import everything from one place:

```dart
import 'package:vs_chat_flutter/vs_chat_flutter.dart';
```

---

## 3. Quick start (three touch points)

### 3.1 Declare once, at app start

```dart
void initAppChat() => VSChat.init(
      VSChatOptions(
        api: apiDio,                                   // your authenticated Dio
        authorization: () => XAuth.instance.authorization,
        theme: ChatTheme.brand(const Color(0xFFEC1D27)),
        language: () => currentLanguageCode,           // 'en' | 'km'
      ),
    );
```

Call `initAppChat()` in `main()` before `runApp`. Calling `VSChat.init` again
later replaces the options, for example after a language or brand change.

### 3.2 The Chat page (menu item, tab or drawer)

```dart
Get.to(() => const VSChatWidget());          // or Navigator.push(...)
```

### 3.3 A chat icon on a row (a parcel, an order, a payout)

```dart
VSChatButton(topic: 'package', subjectId: parcel.id.toString())
// or, from your own icon:
onTap: () => VSChat.start(context, topic: 'package', subjectId: id),
```

### 3.4 A tapped push notification ("someone is waiting in chat")

```dart
VSChat.reopen(context, data['channel_id']);
```

That is the whole integration. The reference is a single file of about 50
lines in each app (`app_chat.dart` in hou-driver-v5 and hou-merchant-v5).

---

## 4. Modes, entry points and presentation

### 4.1 Two ways to start a chat

| Mode | "New chat" does | Use for |
|---|---|---|
| `VSChatMode.topics` *(default)* | Topic list → the topic's prompt (if any) → match → Yes/No → room | Apps with several kinds of chat (a parcel, a payout, general) |
| `VSChatMode.direct` | Yes/No → room for `topic` straight away | One-tap support line, helpdesk, AI assistant |

```dart
const VSChatWidget();                                          // drill-down
const VSChatWidget(mode: VSChatMode.direct, topic: 'general'); // click to chat
```

**Topic drill-down in detail.** The host's topic list says which topics need a
subject. For example, "Chat about a package" asks for *the QR code* **or**
*the receiver phone + pickup date*. The package renders those fields,
asks the host to find matches, and handles each outcome:

- no match → a message;
- one match → straight to Yes/No;
- several → a pick list.

### 4.2 What the widget shows

| `VSChatWidget` parameter | Default | Effect |
|---|---|---|
| `mode` | `topics` | See above |
| `topic`, `subjectId` | – | Required for `direct` (`subjectId` optional) |
| `showConversations` | `true` | Lists the user's rooms: newest first, pull to refresh, search appears after 6 rooms, a **New chat** button. `false` shows only the way to start one |
| `showAppBar` | `true` | `false` when you embed it under your own app bar or in a tab |
| `title` | the `title` text | App bar title |
| `presentation` | options default | Page or sheet for rooms opened from here |

### 4.3 Page or bottom sheet

```dart
VSChatOptions(..., presentation: VSChatPresentation.sheet, sheetInitialSize: 0.6)
VSChat.start(context, topic: 'package', subjectId: id,
             presentation: VSChatPresentation.sheet);   // per call
```

- **page:** full screen, with the platform back gesture.
- **sheet:** the room slides up over the current screen at `sheetInitialSize`
  of its height. Drag the handle **up** for full screen or **down** to close.
  This works well for a quick question about the row the user is looking at,
  without losing their place.

### 4.4 The Yes/No before a room opens

Opening a room **notifies every member**, so `VSChat.start` asks first.
Turn it off with `confirmStart: false`. Plug in your house dialog with
`confirm:` (and your error dialog with `notify:`):

```dart
confirm: (context, message) => showConfirmDialog(context: context, message: message, ...),
notify:  (context, message) async => showInfoDialog(context: context, message: message, ...),
```

`VSChat.reopen` never asks, because nobody new is notified.

---

## 5. Inside the room

| Feature | Notes |
|---|---|
| Live messages | Socket.IO. Messages appear as they are sent, with no refresh |
| Reconnect | Automatic. Every reconnect fetches a **fresh** token from the host (tokens are single-use) and re-joins the room |
| Text, emoji, copy, delete own message | Long-press a message |
| Photos, videos, files (multi-select) | Uploaded through the host; a ghost bubble shows progress |
| Voice notes | Hold to record, slide to cancel |
| Location | Sends the current position (see §8 for map thumbnails) |
| **Header tap → shared panel** | Telegram-style profile: big header with the room name and member count, then tabs **Media** (3-column grid, tap to view or play), **Files** (icon, size, date, tap to download) and **Members** (initials, role, a "You" chip) |
| Media button in the app bar | Opens the panel on the Media tab |
| "Load older" in Media/Files | Pages back through history; the room's list gains them too |
| Info button | Theme choice, cache/downloads cleanup |

Media and Files come from the history the room has loaded, so nothing is
fetched twice.

---

## 6. Theming

```dart
theme: ChatTheme.brand(const Color(0xFF0D6EFD)),   // one colour themes everything
theme: ChatTheme.houExpress(),                      // = brand(#EC1D27)
theme: ChatTheme.brand(c).copyWith(messageReceivedBackground: Colors.white),
```

`ChatTheme` exposes about 40 colours: bubbles, input bar, recorder, audio
player and more. `brand()` derives a consistent set from one colour. Use
`copyWith` for anything else.

---

## 7. Text and languages

The package ships **English and Khmer** for every text it shows
(`lib/chat/services/chat_strings.dart`), so an app needs no copy of them.

- `language: () => 'km'` is read on every text, so a language switch applies
  on the next screen with no re-init.
- Override any text per language:

```dart
strings: const {
  'en': {'title': 'Support', 'newChat': 'Ask us'},
  'km': {'title': 'ជំនួយ'},
},
```

- **Topic prompt fields** are labelled by the host's `label`. To translate
  them, add `field_<key>` overrides. DMS's are `field_qr_code`,
  `field_receiver_phone`, `field_pickup_date` and `field_payment_date`.
- Topic names come from the host, so adding a topic needs no app release.

Your own code can read any text with `VSChat.t('key')`.

---

## 8. The host API contract

All routes are relative to your `api` Dio's base URL (DMS:
`{host}/api/driver/v2`, `{host}/api/merchant/v2`) and are called with the
user's login. Responses use the envelope `{status: 'OK', data}` or
`{status: 'Error', error_message}`. Rename any route with
`endpoints: VSChatEndpoints(...)`.

| Route | Request | `data` | Notes |
|---|---|---|---|
| `POST /chat/topics` | – | `[{topic, name, description?, prompt?}]` | `prompt = {fields:[{key,label,type:text\|phone\|date}], any_of:[[key,…],…]}` |
| `POST /chat/find-subject` | `{topic, <field>: value…}` | `[{subject_id, label}]` | Only subjects this user may chat about |
| `POST /chat/open-channel` | `{topic, subject_id?}` | **session** | Resolves members, notifies them |
| `POST /chat/open-conversation` | `{channel_id}` | **session** | Member-only; also used for every reconnect token |
| `POST /chat/conversations` | – | `[{channel_id, name, channel_type, context, last_opened_at}]` | `context` values become the row's subtitle |
| `POST /chat/members` | `{channel_id}` | `[{user_code, user_class}]` or `[{official_code, name, role}]` | Member-only |
| `POST /chat/resource` | multipart `{channel_id, file}` | `{object:{full_path,…}, file}` | Stores as the **caller**; never trusts a client user id |
| `GET /chat/resource/{full_path}` | – | file bytes | Member-only proxy (uploads need the storage secret) |
| `GET /chat/location/get-thumbnail?lat&lon` | – | PNG | *Optional.* Without it, location messages show a placeholder |

**Session** = `{base_url, api_key, channel_id, user_id, token, name?, members?}`.
`base_url` and `api_key` are chat-service's public socket address and app key.
`token` is a one-time socket token for `user_id`. If `members` is included,
the Members tab uses it without an extra call.

**Rules every host must keep:**
1. Take the user **only** from the login token. Ignore any user id in a request.
2. Check membership on `open-conversation`, `members` and `resource`.
3. Keep the chat-service secret on the server.
4. A room id must never be shared by accident: include the topic in the id,
   and never leave its tail empty.

---

## 9. AI assistants

Nothing special is needed. An assistant is **a member of a room**:

1. Give it a topic on the host (for example `assistant`) whose member rules
   add a bot user.
2. Open it from the app like any chat, for example
   `const VSChatWidget(mode: VSChatMode.direct, topic: 'assistant')`.
3. A server-side worker listens for new messages in those rooms and replies
   as the bot, through chat-service's server API. Its answers arrive in the
   app over the socket like anyone else's, including attachments.

Because the package renders whatever the room contains, adding an assistant
needs no app release.

---

## 10. Lower-level use (without the facade)

`VSChat` is a thin layer over `ChatPage` + `ChatConfig`. Hosts that follow the
package's original contract (`/chat/sign-jwt` + `/chat/create-channel`) can
still build a `ChatConfig` with a `channelType` and no `session`. The service
then signs a token and creates the channel itself. `ChatConfig.session`,
`tokenProvider`, `requestHeaders` and `membersProvider` are the seams
`VSChat` uses.

---

## 11. Troubleshooting

| Symptom | Cause |
|---|---|
| `Call VSChat.init() first.` | `VSChat.init` did not run before the first chat screen |
| Room opens, no history, no live messages | The socket was refused: the token was already spent, or `base_url`/`api_key` is wrong. Check the host's session |
| Images/voice notes do not load | `GET /chat/resource/{path}` refused. Check the user is a member, and that `requestHeaders` carries everything your API middleware needs (e.g. `X-App-Version`) |
| "Could not open the chat" | The host returned an error; its `error_message` is shown as is |
| Members tab empty | The host has no `/chat/members` route and the session carried no `members` |
| Location shows a placeholder | The host has no `/chat/location/get-thumbnail` |
