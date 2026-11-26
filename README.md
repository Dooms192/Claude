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
| Interview prep | Describe the interview. Recap finds the most relevant days by meaning, not just keywords, and writes 3–5 STAR stories, a "how to say it" script for each, and tips. Past preps are saved and shareable. |

Your recap is always saved *before* it's summarized, so a failed summary never loses what you said. You can retry from the journal.

## iPhone Duo support

Apps break on new devices when they assume a fixed screen size. Recap doesn't:

- **Folded (5.4" outer screen):** a normal one-column iPhone layout.
- **Unfolded (7.6" inner screen):** two columns. Your list is on the left and the selected day, goal, or interview prep is on the right. The recorder puts the prompts and controls on the left and the live transcript on the right, and STAR stories show their four parts in a 2×2 grid.
- **The switch is based on the actual width the app has** (`Views/Components/AdaptiveSplitView.swift`), not the device model, so it works however iOS labels each screen, in Split View, and on future devices.
- **Folding or unfolding never loses your place.** The recording and transcript live at the app level, and the selected item is held above the layout. If you unfold while reading a day, it opens on the right. If you fold, it stays open full-screen. If you fold mid-sentence, it keeps recording.
- All orientations and multitasking are supported.

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

You need Xcode 26 or later and an iPhone running iOS 26 or later. Apple Intelligence also needs a supported device with Apple Intelligence turned on.

1. Clone this repo on your Mac and open `Recap/Recap.xcodeproj`.
2. Click the **Recap** project, then the **Recap** target, then **Signing & Capabilities**. Choose your **Team** (a free Apple ID works for your own phone), and change the **Bundle Identifier** from `com.example.recap` to something unique, like `com.yourname.recap`.
3. Plug in your iPhone Duo, pick it as the run destination, and press **Run** (⌘R).
4. On the phone, allow the microphone and speech recognition when asked. If iOS says the developer isn't trusted, go to Settings → General → VPN & Device Management and trust your Apple ID.

To check the Duo layouts without the phone, run on an iPhone Duo simulator if your Xcode has one. Otherwise use an iPad mini simulator: full-screen shows the unfolded layout, and a narrow Split View shows the folded one.

## Project layout

```
Recap/
  Recap.xcodeproj
  Recap/
    RecapApp.swift                 App entry, tab routing, notification handling
    Models/                        SwiftData models: DayEntry, Goal, PrepSession (+ STAR types)
    Services/
      RecapRecorder.swift          Microphone + on-device speech-to-text
      ReminderScheduler.swift      Daily notification
      AppSettings.swift            Engine choice, Keychain storage for the API key
      AI/
        Summaries.swift            Shared prompts and data shapes
        AppleIntelligence.swift    On-device model (Foundation Models)
        Claude.swift               Anthropic Messages API client + JSON schemas
        Coordinators.swift         Engine picking, on-device semantic search, interview coach
    Views/
      Components/AdaptiveSplitView.swift   The Duo fold/unfold layout
      JournalView, RecapRecorderView, GoalsView, InterviewPrepView, SettingsView
```

All data is stored on the device with SwiftData.

## Ideas for next steps

- iCloud sync and backup
- A home-screen widget and lock-screen shortcut to start a recap
- Weekly and monthly roll-ups ("what did I do this quarter?") for performance reviews
- Practice mode: Recap asks you an interview question and gives feedback on your spoken answer
