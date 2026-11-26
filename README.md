# Recap

A goal-tracking journal for iPhone you **talk to** instead of typing, built to work properly on the **iPhone Duo** foldable.

At the end of each day, Recap reminds you to talk through what you did. It turns your voice into text, has AI summarize it (wins, challenges, skills, goal progress), and saves it. Later, when you have an interview coming up, you describe the interview and Recap searches every day you've recorded and writes **STAR stories** (Situation, Task, Action, Result) you can actually tell, built only from things you really did, with the dates they came from.

## What's in this first version

| Feature | How it works |
|---|---|
| End-of-day reminder | A daily notification at the time you pick. Tap it and the recorder opens. |
| Voice recap | Live speech-to-text on your iPhone. Long recaps and pauses are fine. You can fix mistakes in the text, or add more, before saving. |
| AI summary | Headline, summary, accomplishments, challenges, skills, and progress on each of your goals. |
| Goals | Add goals, and each recap is checked against them. Each goal shows a timeline of the days you worked on it. |
| Journal | Every day, searchable, grouped by month. |
| Projects | Recap spots ongoing projects in your recaps and asks before adding them (Add, Rename, Merge, or Ignore). Each project gets an AI overview, highlights (wins, skills, solved blockers), a weekly activity chart, and a day-by-day timeline. Projects you haven't mentioned in 21 days are marked inactive with a "Still working on this?" prompt. There's an optional weekly "Project pulse" notification, and you can share a project as text. |
| Competencies | Each recap is tagged with the FYI / Korn Ferry Leadership Architect competencies you showed (38, in four groups), with the moment and how strongly (strong, solid, or light). You can browse and search them by meaning, see your evidence for each, find gaps in Coverage, export your best example for each, and fix tags by hand. Recaps from before this feature can be tagged with "Re-tag my past recaps". Tap the ⓘ on any competency to see what employers look for: skilled, less skilled, and overused behaviors, what interviewers listen for, and common questions. Found in the Interview tab under **Competencies**. |
| Interview prep | Describe the interview. Recap finds the most relevant days by meaning, not just keywords, and writes 3–5 STAR stories, a "how to say it" script for each, and tips. Results are grouped by project, so one project's whole story becomes one answer. You can limit stories to a single project, and speak your request instead of typing it. In competency mode you pick competencies (or paste a job posting, or let Recap find them in your description), and you get one story per competency with a "why this example" line, likely follow-up questions, and an honest note when you don't have a strong example yet. Past preps are saved and shareable. |

Your recap is always saved *before* it's summarized, so a failed summary never loses what you said. You can retry from the journal.

## iPhone Duo support

Recap follows Apple's "Prepare your app for iPhone Duo" guidance:

- **System navigation instead of custom layouts.** Each tab uses `NavigationSplitView`, which Apple calls fully adaptive on iPhone Duo. Folded, it shows one column and you tap through. Unfolded, it shows your list and the selected day, goal, or prep side by side. The `TabView` adapts on its own too, and shows vertically on the inner screen.
- **Size classes, not screen measurements.** The outer screen is compact width and the unfolded inner screen is regular width, like an iPad. Any layout decision (such as the recorder putting prompts beside the transcript) reads `horizontalSizeClass`. There are no hand-picked widths and no device checks.
- **The system handles safe areas.** Safe areas on the Duo are often uneven (camera, status bar, vertical toolbars), so Recap leaves them to the system and never overrides them.
- **Folding or unfolding never loses your place.** The recording and transcript live at the app level, and the selected item is held above the layout. If you fold mid-sentence, it keeps recording.
- All orientations and Split View multitasking are supported.

For the full inner-screen experience, where toolbars run vertically under the status bar and the app reaches the screen edge, Apple says to build with **Xcode 27.1 or later**.

## AI: Apple Intelligence and Claude

You choose the engine for each job in Settings:

| | Apple Intelligence | Claude |
|---|---|---|
| Cost | Free | Pay-as-you-go API, a few cents per use |
| Privacy | Never leaves your phone | The text for that request is sent to Anthropic |
| Daily summaries | **Recommended.** It handles one day well. | Works, slightly better writing |
| Interview prep | Reads only your top 6 days | **Recommended.** Reads your 25 most relevant days, including what you said |

If the engine you picked isn't available, Recap uses the other one.

**Claude Pro does not cover this.** Apps use the Anthropic API, which is billed separately. To turn on Claude, get a key at [console.anthropic.com](https://console.anthropic.com/settings/keys), add a few dollars of credit, and paste the key into Recap's Settings. The key is stored in the iPhone Keychain. You can set a monthly spending limit in the console.

## Backups

Recap backs up to a folder you choose. CloudKit isn't needed, so it works on a free Apple developer account.

- **Set it up:** Settings → Backups → **Choose backup folder**. Pick a folder in **iCloud Drive** (for example iCloud Drive → Recap Backups), which works with the free iCloud storage. Settings warns you if the folder is inside the app (deleted along with it) or isn't in iCloud Drive.
- **Automatic:** a backup is written about 5 seconds after any change, and when the app goes to the background with unsaved changes. Each backup is one JSON file, like `Recap-Backup-2026-11-26-2130.json`. It's written to a temporary file and renamed into place, so it's never half-written. Recap keeps the newest 5, 10, or 30, and only ever deletes its own `Recap-Backup-` files.
- **What's included:** all recaps (transcripts, summaries, project notes, competency tags), goals, projects (overviews, colors, icons, status), interview preps, ignored project names, and your settings. Never the Claude API key.
- **Restore:** Settings → **Restore from backup…** shows a preview, then **Replace everything** or **Merge** (adds what's missing, matched by ID, with no duplicates). A safety backup of your current data is saved first. On a fresh install, picking your backup folder offers to restore the newest backup.
- **Shortcuts:** a "Back up Recap" action, for example for a nightly automation at 10 PM.
- **If the folder goes missing** (iCloud signed out, folder deleted), Settings shows "Backups paused: choose your folder again". The app keeps working, and saving a recap never waits on a backup.
- **Format versions:** every file has a `formatVersion`. New fields are added as optional, so old backups keep restoring, and `BackupFile.decode` is where future versions upgrade older files.

**Test it once:** back up, delete the app, reinstall, choose the same backup folder, and accept "Restore it?". Then check that project timelines, goal progress, and competency evidence all came back.

## Building it (on a Mac)

You need Xcode 26 or later (Xcode 27.1 or later is recommended for the best iPhone Duo inner-screen layout) and an iPhone running iOS 26 or later. Apple Intelligence also needs a supported device with Apple Intelligence turned on.

1. Clone this repo on your Mac and open `Recap/Recap.xcodeproj`.
2. Click the **Recap** project, then the **Recap** target, then **Signing & Capabilities**. Choose your **Team** (a free Apple ID works for your own phone), and change the **Bundle Identifier** from `com.example.recap` to something unique, like `com.yourname.recap`.
3. Plug in your iPhone Duo, pick it as the run destination, and press **Run** (⌘R).
4. On the phone, allow the microphone and speech recognition when asked. If iOS says the developer isn't trusted, go to Settings → General → VPN & Device Management and trust your Apple ID.

To check the Duo layouts without the phone, use the iPhone Duo simulator in Xcode 27.1's Device Hub. It has buttons to open, close, and rotate the device. Also test Split View by dragging the app by its home indicator to either side of the inner screen.

## Project layout

```
Recap/
  Recap.xcodeproj
  Recap/
    RecapApp.swift                 App entry, tab routing, notification handling
    Models/                        SwiftData models: DayEntry, Goal, Project, PrepSession (+ STAR types)
      Competencies.swift           The 38 competencies with definitions and signals. Edit this to match your edition of FYI.
    Services/
      RecapRecorder.swift          Microphone + on-device speech-to-text
      ReminderScheduler.swift      Daily notification
      ProjectStore.swift           Add, rename, merge, ignore, and inactivity for projects
      ProjectPulse.swift           Weekly project pulse notification
      Backup/                      Backup file format, automatic backups and restore, Shortcuts action
      AppSettings.swift            Engine choice, Keychain storage for the API key
      AI/
        Summaries.swift            Shared prompts and data shapes
        AppleIntelligence.swift    On-device model (Foundation Models)
        Claude.swift               Anthropic Messages API client + JSON schemas
        Coordinators.swift         Engine picking, on-device semantic search, interview coach
        CompetencyAI.swift         Competency tagging, detection, and one-story-per-competency prep
    Views/
      Components/AdaptiveSplitView.swift   NavigationSplitView wrapper used by every tab
      Components/ProjectComponents.swift   New-project card, project tags, text export
      JournalView, ProjectsView, RecapRecorderView, GoalsView, InterviewTab, InterviewPrepView, CompetenciesView, SettingsView
```

All data is stored on the device with SwiftData.

## Updates

Newest first.

### Major updates

- **Competency info buttons:** a ⓘ on each competency shows what employers look for: skilled, less skilled, and overused behaviors, what interviewers listen for, and common interview questions. Competency stories now use this to show the right behaviors.
- **Automatic backups:** backups go to a folder you choose, such as one in iCloud Drive, with no paid account or CloudKit. Includes restore (Replace or Merge), a safety copy before restoring, a restore offer on a fresh install, and a "Back up Recap" Shortcuts action.
- **Competencies (FYI / Korn Ferry Leadership Architect):** 38 competencies in four groups. Recaps are tagged with the ones you showed. You can browse and search them, see your evidence and coverage gaps, and fix tags by hand. Interview Prep can build one STAR story per competency, from ones you pick or from a pasted job posting.
- **STAR explainer for everyone:** "What's a STAR story?" now appears in the Interview Prep list on every iPhone, not just the unfolded Duo.
- **Projects:** ongoing projects are detected from your recaps. Each gets an AI overview, highlights, a weekly activity chart, a day-by-day timeline, and an inactive prompt after 21 days. Interview Prep can tell a project's whole story or use stories from one project.
- **Goal deadlines and voice input:** deadlines you mention in a recap become a goal's target date. Interview Prep has a mic, so you can speak your request.
- **iPhone Duo layout rebuilt on Apple's guidance:** every tab uses the system split view and size classes instead of a custom layout.
- **Goal suggestions:** goals you mention in a recap are suggested with one-tap "Add goal" instead of being silently dropped.
- **First version:** daily voice recaps, AI summaries (Apple Intelligence or Claude), goals, journal, end-of-day reminder, and STAR interview prep.

### Bug fixes

- **Slow typing in competency search:** each keystroke reloaded Apple's language model on the main thread. The model now loads once in the background, and searches run off the main thread after a short pause in typing.
- **Slow first launch and first unfold:** the microphone's speech recognizer and audio engine are now created when you first tap a mic, not every time a screen is built. Launch housekeeping (inactive projects, weekly summaries, backup folder) now runs after the first screen appears.
- **Mic warning:** the audio system no longer switches into recording mode on the main thread, which caused an Xcode warning about possible freezes. A quick double-tap on the mic also can't start recording twice.
- **Competencies wouldn't open:** tapping a competency did nothing. It now opens like every other list.
- **Squeezed left column on the unfolded Duo:** fixed by switching to the system split view.
- **Journal overlap:** the "Record today's recap" card no longer overlaps the "No recaps yet" message.
- **Wrapped text:** "Record today's recap" and "Prepare my stories" no longer wrap onto extra lines.

### Known issues

- **Sidebar swipe:** on the unfolded Duo, hiding the list and swiping it back in doesn't resize the layout correctly. The show/hide button works fine.

## Ideas for next steps

- iCloud sync and backup
- A home-screen widget and lock-screen shortcut to start a recap
- Weekly and monthly roll-ups ("what did I do this quarter?") for performance reviews
- Practice mode: Recap asks you an interview question and gives feedback on your spoken answer
