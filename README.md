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
| Interview prep | Describe the interview. Recap finds the most relevant days by meaning, not just keywords, and writes 3–5 STAR stories, a "how to say it" script for each, and tips. Results are grouped by project, so one project's whole story becomes one answer. You can limit stories to a single project, and speak your request instead of typing it. Past preps are saved and shareable. |

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
    Services/
      RecapRecorder.swift          Microphone + on-device speech-to-text
      ReminderScheduler.swift      Daily notification
      ProjectStore.swift           Add, rename, merge, ignore, and inactivity for projects
      ProjectPulse.swift           Weekly project pulse notification
      AppSettings.swift            Engine choice, Keychain storage for the API key
      AI/
        Summaries.swift            Shared prompts and data shapes
        AppleIntelligence.swift    On-device model (Foundation Models)
        Claude.swift               Anthropic Messages API client + JSON schemas
        Coordinators.swift         Engine picking, on-device semantic search, interview coach
    Views/
      Components/AdaptiveSplitView.swift   NavigationSplitView wrapper used by every tab
      Components/ProjectComponents.swift   New-project card, project tags, text export
      JournalView, ProjectsView, RecapRecorderView, GoalsView, InterviewPrepView, SettingsView
```

All data is stored on the device with SwiftData.

## Ideas for next steps

- iCloud sync and backup
- A home-screen widget and lock-screen shortcut to start a recap
- Weekly and monthly roll-ups ("what did I do this quarter?") for performance reviews
- Practice mode: Recap asks you an interview question and gives feedback on your spoken answer
