---
target: "BetterMeets full UI/UX review: idle, live, paused, settings and source workflows"
total_score: 24
max_score: 40
na_heuristics: 
p0_count: 0
p1_count: 3
timestamp: 2026-09-25T21-07-11Z
slug: sources-meetstage-workspaceview-swift
---
Method: dual-agent (A: /root/design_assessment · B: /root/evidence_assessment), supplemented by a native live-app walkthrough.

**BetterMeets has a coherent native foundation, but it is not yet polished enough for a presenter to operate without hesitation.** Its biggest opportunity is confidence: make the current source, audience-facing output, and next action unmistakable. Preserve the quiet materials, system typography, and source-led layout.

The review covered your three screenshots, the SwiftUI/AppKit implementation, and the running app. Image #2 is only a source-tile crop, so I also inspected a complete live App Store capture. No application code changed; the app was returned to idle with its original tool settings.

Three things already work well:

- A stable stage preserves window geometry and source aspect ratio while sources change.
- App thumbnails, icons, persistent shortcut slots, and Space previews support fast recognition.
- Native controls, explicit accessible names/states, short transitions, 0.96 press feedback, and accessibility preference handling provide a strong foundation.

**These are the five priorities, in implementation order.** HIGH/P1 means a misleading or disruptive interaction; MEDIUM/P2 means a substantial usability or craft improvement. No P0 issue was established.

| Severity | Location | Before | After | Why |
|---|---|---|---|---|
| **HIGH · P1 — Audience visibility** | [StageView.swift:101](/Users/leo/Developer/meet-stage/Sources/MeetStage/StageView.swift:101), [WorkspaceView.swift:38](/Users/leo/Developer/meet-stage/Sources/MeetStage/WorkspaceView.swift:38) | Setup says choose a source, then share BetterMeets. Stage Only is an unlabeled rectangle. Restoring controls puts the sidebar and other window thumbnails back into the shared window. Some copy implies an audience is receiving local capture. | Make **Stage Only** a labeled action. Teach the complete sequence: choose source → Stage Only → share BetterMeets in the meeting app. Explain once that reopening controls makes them visible in that window share. Use “On stage” for local capture status. | Someone following the current instructions can show the controller workspace unintentionally. Local capture does not establish meeting transmission. |
| **HIGH · P1 — Capture controls** | [WorkspaceView.swift:57](/Users/leo/Developer/meet-stage/Sources/MeetStage/WorkspaceView.swift:57), [StageStatusBar.swift:22](/Users/leo/Developer/meet-stage/Sources/MeetStage/StageStatusBar.swift:22), [ControlSourcePickerViews.swift:82](/Users/leo/Developer/meet-stage/Sources/MeetStage/ControlSourcePickerViews.swift:82), [StageActionsView.swift:44](/Users/leo/Developer/meet-stage/Sources/MeetStage/StageActionsView.swift:44) | Pause sits top-right; Stop bottom-right; status bottom-left. Clicking the selected tile pauses it. Its play glyph communicates live state even though its action is Pause. The source widget contains effects but no capture controls. | Group **source · Pause/Resume · Clear Stage** together. Give the source widget Pause/Resume and a return path. Prefer selection that keeps the current source live; if the repeat-click toggle is retained, visibly reveal its Pause/Resume action on hover and focus. | Live testing confirmed that a second selection blanks the stage. The emergency control should be obvious beside the state it changes. “Clear Stage” also distinguishes the action from stopping the meeting app’s share. |
| **HIGH · P1 — Settings focus** | [StageActionsView.swift:107](/Users/leo/Developer/meet-stage/Sources/MeetStage/StageActionsView.swift:107), [MeetStageApp.swift:174](/Users/leo/Developer/meet-stage/Sources/MeetStage/MeetStageApp.swift:174) | Gear opens a popover; ⌘, opens a separate Settings window. In the popover, Tab moved focus to a background source; Space dismissed Settings and opened that source preview. | Route full Settings through one native window, or explicitly manage popover focus: enter its controls on open, prevent background source shortcuts while interacting there, and restore focus on dismissal. | This is a reproduced interaction defect. The next keyboard action must affect the visible task. |
| **MEDIUM · P2 — Source browsing** | [ControlView.swift:71](/Users/leo/Developer/meet-stage/Sources/MeetStage/ControlView.swift:71), [WorkspaceView.swift:126](/Users/leo/Developer/meet-stage/Sources/MeetStage/WorkspaceView.swift:126), [WindowHoverPreview.swift:48](/Users/leo/Developer/meet-stage/Sources/MeetStage/WindowHoverPreview.swift:48) | A fixed 176pt sidebar places six tools above the source list. Your screenshot fully shows only four of six sources; scrollbars are hidden. App/title labels often repeat, while the distinguishing title remains truncated even in the enlarged preview. | Add a compact density for short windows and a resizable sidebar. Respect system scroll indicators. Deduplicate identical app/title text and show the full distinguishing title in previews. Give source choice more space while idle. | The central task should remain easy with more windows, smaller displays, and several documents from the same app. |
| **MEDIUM · P2 — Recovery** | [StageView.swift:119](/Users/leo/Developer/meet-stage/Sources/MeetStage/StageView.swift:119), [CaptureManager+Callbacks.swift:136](/Users/leo/Developer/meet-stage/Sources/MeetStage/CaptureManager+Callbacks.swift:136), [ControlView.swift:147](/Users/leo/Developer/meet-stage/Sources/MeetStage/ControlView.swift:147), [ControlSourcePickerViews.swift:3](/Users/leo/Developer/meet-stage/Sources/MeetStage/ControlSourcePickerViews.swift:3) | Permission failures and capture failures reuse “Nothing is on stage.” System error codes can reach the stage. Allow Access and Restart appear together. An unavailable pinned tile has no local Unpin action. | Use specific presenter-facing headings and the appropriate **Retry**, **Choose Another Window**, or permission action. Keep diagnostics in details/logs; show Restart when needed. Add Unpin directly to unavailable slots. Keep audience-facing output brief. | Recovery deserves the clearest hierarchy because it happens at the most stressful moment. |

The capture-control and focus recommendations follow the native principles of orienting people through toolbar actions and supporting predictable keyboard interaction. [Apple toolbar guidance](https://developer.apple.com/design/human-interface-guidelines/toolbars), [Apple accessibility guidance](https://developer.apple.com/design/human-interface-guidelines/accessibility).

**Your three states should have distinct jobs.**

| State | Presenter experience | Stage output |
|---|---|---|
| Nothing selected | “Choose a window” with immediate access to sources and the short sharing setup sequence. | Quiet neutral placeholder. |
| Source live | “On stage · App / Window” beside Pause and Clear Stage; a clear Open Source App action explains where interaction happens. | The selected source, with enabled presentation effects. |
| Paused | “Stage paused · App / Window” beside a prominent Resume action. Explain that the source image is hidden, not frozen. | A calm “Presentation paused” message; operator instructions belong with presenter controls. |

This is a presentation specification, not evidence that a remote meeting was tested. The current pause implementation clears the image and shows a placeholder.

Several smaller details will compound once those priorities are resolved:

| Severity | Location | Before | After | Why |
|---|---|---|---|---|
| MEDIUM · P2 | [ControlSettingsView.swift:17](/Users/leo/Developer/meet-stage/Sources/MeetStage/ControlSettingsView.swift:17) | Spotlight → Focus, Annotate → Draw, Keystrokes → Keys, Auto Polish → Stage. | Use the same feature names across tools, settings, menus, and help. | Recognition should survive navigation. |
| MEDIUM · P2 | [ControlSettingsView.swift:197](/Users/leo/Developer/meet-stage/Sources/MeetStage/ControlSettingsView.swift:197), [StageView.swift:137](/Users/leo/Developer/meet-stage/Sources/MeetStage/StageView.swift:137) | Stage settings preview the backdrop/logo even when Auto Polish is off; the live stage gates both on Auto Polish. | Show the governing On/Off state with an Enable action beside the preview. | A successful preference change should not appear to be ignored. |
| MEDIUM · P2 | [ControlComponents.swift:70](/Users/leo/Developer/meet-stage/Sources/MeetStage/ControlComponents.swift:70), [StageActionsView.swift:123](/Users/leo/Developer/meet-stage/Sources/MeetStage/StageActionsView.swift:123) | Per-tool settings depend on right-click. Enabled effects can be waiting for a source, with that distinction only in tooltips. | Reveal a small settings affordance on hover/focus; use a shared “Ready for the next source” hint when appropriate. | Keep useful preconfiguration while making its effect understandable. |
| MEDIUM · P2 | [ControlView.swift:131](/Users/leo/Developer/meet-stage/Sources/MeetStage/ControlView.swift:131) | Every keyboard focus change springs the source to the center over 0.3s. | Scroll only enough to reveal offscreen focus, immediately for keyboard input. | Repeated navigation should preserve position and feel direct. |
| LOW · P3 | [ControlSourcePickerViews.swift:231](/Users/leo/Developer/meet-stage/Sources/MeetStage/ControlSourcePickerViews.swift:231), [ControlSourcePickerViews.swift:248](/Users/leo/Developer/meet-stage/Sources/MeetStage/ControlSourcePickerViews.swift:248) | Small app/title text competes with a strong black shortcut badge over the thumbnail. | Strengthen the identifying text and quiet the keycap; retain the visible shortcut. | The window’s identity should win the first glance. |
| LOW · P3 | [ControlSourcePickerViews.swift:99](/Users/leo/Developer/meet-stage/Sources/MeetStage/ControlSourcePickerViews.swift:99) | Paused tiles mix blue selection fill with orange border/keycap. | Compare a neutral selection fill with one coordinated orange paused treatment, retaining the pause symbol. | An opportunity for visual cohesion; the current state already has non-color cues. |

Keep the existing press feedback and restrained motion. Avoid adding bouncy transitions or staggered entrances to frequently used presentation controls. Automatic 450ms hover previews deserve a rapid-browsing check, but flicker was not established and should not be reported as a defect. Likewise, the faint inner stage boundary warrants visual cleanup only if it is a redundant frame rather than the captured source’s own edge.

**Design health: 24/40.** This is a heuristic judgment from the reviewed evidence. The independent design review scored 25/40; the confirmed Settings focus problem lowers User Control by one point.

| Heuristic | Score / 4 | Main assessment |
|---|---|---|
| System status | 3 | Distinct local states; meeting/output meaning needs clarity. |
| Real-world language | 3 | Familiar core concepts; inconsistent feature names. |
| User control and freedom | 2 | Capture exits work; Settings focus escapes its task. |
| Consistency and standards | 2 | Native foundation, inconsistent settings entry points and state/action symbols. |
| Error prevention | 2 | Share setup and repeat-selection behavior permit avoidable surprises. |
| Recognition over recall | 2 | Mode discovery, contextual settings, and long titles need work. |
| Efficiency | 3 | Strong shortcuts and pins; source density and repeated scrolling interfere. |
| Aesthetic restraint | 3 | Coherent native identity; hierarchy needs refinement. |
| Error recovery | 2 | Recovery exists but lacks specific, adjacent actions in several states. |
| Help | 2 | Tooltips and README exist; essential guidance belongs in the flow. |
| **Total** | **24/40** | **Acceptable foundation; interaction refinement needed.** |

Cognitive load is moderate: grouping works, but tool prominence, terminology changes, and remembering Stage Only add effort. Six source windows are one recognizable collection; there is no reason to hide valid choices merely to satisfy an arbitrary option-count rule.

The emotional high point is the first source appearing on the stable stage. The weak points are setting up the audience view, finding controls after moving into the source app, and recovering from failure. Those moments deserve the most design attention.

- **First-time presenter:** can follow setup literally and show the controller; may try interacting with the stage image before discovering Open App.
- **Power presenter:** benefits from global slots, but the floating widget lacks capture controls and keyboard browsing repeatedly recenters the list.
- **Keyboard/low-vision presenter:** benefits from accessible names and state values; the confirmed popover focus problem and small, truncated window identifiers remain barriers.

The proposed work maps to Impeccable clarify/onboard for the sharing flow, shape for grouped capture controls, harden for Settings focus and recovery, adapt/layout for source browsing, then polish for the visual details. Two later product choices deserve deliberate review: whether to retain repeat-click pause, and whether the source widget should become a complete presentation remote.

**Verification and verdict:** Live source selection, repeat-click pause, shortcut resume, Stage Only, Escape restoration, all six Settings panes, keyboard preview, Settings entry points, and Stop were exercised. Accessibility names and values were inspected. Permission denial, timeout/failure recovery, unavailable pins, and motion policy were reviewed in source.

Still unverified: an actual remote meeting view; VoiceOver speech and asynchronous announcements; light mode and accessibility display settings; minimum-size/many-window layouts; floating-widget placement; 10%-speed motion playback and frame-time performance. No contrast failure or performance regression is claimed without measurement. No build/tests were run because this was a review with no implementation changes.

**Verdict: Block polish sign-off until the three HIGH interaction issues are resolved.** The app’s underlying capture flow worked in the live walkthrough. Preserve its native identity and fix those interaction gaps before fine-tuning decoration.
