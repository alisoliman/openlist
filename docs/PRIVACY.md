# Openlist for iPhone privacy policy

Updated 1 October 2026.

This policy covers the Openlist iPhone app, maintained by Ali Soliman. The
separate Mac app has additional features, including optional connections to AI
clients, described in the [project documentation](../README.md).

## Your library

Openlist stores your tasks, lists, notes, labels, attached content, activity
history and work sessions on your device. It works without a separate Openlist
account. App preferences stay on the device. Openlist's widgets use a local
snapshot of library and calendar information to display your tasks and agenda.

When iCloud is available, Openlist syncs its library through a private CloudKit
database in your Apple Account. This includes retained Trash and history records.
The developer cannot browse your private CloudKit records. Apple operates iCloud
under [Apple's privacy policy](https://www.apple.com/legal/privacy/).

Openlist does not send your library to a developer-operated server. The iPhone
app contains no advertising, analytics or third-party crash-reporting SDKs and
does not track your activity across other companies' apps or websites. iCloud
errors may be written to the device's system log. Apple may handle system
diagnostics according to your device settings and its own policies.

## Permissions and voice capture

- **Microphone:** used when you start voice capture. Speech recognition runs on
  your device using Apple's speech models. Where available, Apple's on-device
  language model helps turn your words into tasks. Required models may download
  from Apple. Openlist does not save an audio recording or a separate transcript;
  the task text you choose to add becomes part of your library. Voice capture
  defaults to review; choosing **After voice capture ▸ Save automatically** in
  Settings saves recognized tasks when listening finishes on that device.
- **Calendars:** with permission, Openlist reads calendar events to show busy
  time and plan around it. It does not change your calendar events. Calendar
  information is used locally, including in the agenda widget.
- **Notifications:** used for local task reminders and planning alerts. These
  can show task details on your screen. Apple also delivers background iCloud
  change notifications so the library can sync.

You can revoke microphone, calendar and notification permissions in iPhone
Settings. You can continue entering and managing tasks without granting these
permissions. iCloud access is controlled through your Apple Account settings;
Openlist's Settings shows the current sync status.

## Retention and deletion

Your library stays on your devices and, when syncing, in your private iCloud
database until you remove it. Moving an item to Trash retains it for restoration;
there is no automatic Trash expiry. In Openlist, open **Settings → Trash** to
restore items or hold the erase control to delete them permanently. These
deletions sync when iCloud transfers complete.

Erasing a task or list does not erase separate activity and work-history records,
which can contain its title. The iPhone app currently has no full-library reset.
If you also use Openlist on a Mac, **Settings → Data → Delete everything** removes
the library, including those history records, and syncs the deletions. Backups
and exported copies are separate and must be managed separately.

Deleting the iPhone app removes its local data but does not delete data already
stored in iCloud. Use your Apple Account's iCloud storage controls to manage
cloud data and backups. See Apple's guidance on
[deleting apps](https://support.apple.com/guide/iphone/remove-or-delete-apps-iph248b543ca/ios)
and [managing iCloud storage](https://support.apple.com/en-us/108922).

## Support and contact

Contact the maintainer through [GitHub Issues](https://github.com/alisoliman/openlist/issues)
for questions about Openlist or this policy. Issues are public: do not include
personal task content, credentials or private attachments. Information you
choose to post is visible to the developer and others and is managed through
GitHub's account and repository controls under
[GitHub's privacy statement](https://docs.github.com/en/site-policy/privacy-policies/github-general-privacy-statement).

Report security vulnerabilities privately using the process in
[SECURITY.md](../SECURITY.md). See [Support](SUPPORT.md) for troubleshooting.
