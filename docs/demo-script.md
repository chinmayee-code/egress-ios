# Egress — Hackathon Demo Script (IndeHub 2026)

A ~3.5-minute screen recording script, plus deep-dive talking points, a rubric
coverage map, and a shot list. Record with voiceover (and picture-in-picture if
you can). Everything below is backed by the real implementation.

---

## The one-line pitch (say this if you only have 10 seconds)

> "Egress is a pocket crowd-evacuation lab. Draw a room, fill it with people,
> light a fire — and watch, in real physics, whether everyone gets out. It runs
> entirely on-device, with no internet, and it dresses hard safety engineering
> in a pixel-arcade skin so anyone will actually use it."

---

## PRIMARY SCRIPT (≈3 min 30 s)

Format: **[ON SCREEN]** = what to show · **VO** = what to say.

### 0:00 – 0:20 · Hook / the problem  *(Criterion 1)*
**[ON SCREEN]** Landing screen. Tap **Start Your Simulation**.
> **VO:** "Every year, crowds die not because a building is unsafe, but because a
> layout is — one exit too few, a corridor too tight. Professional evacuation
> software costs thousands and lives on a desktop. So the people who need it
> most — a café owner, a teacher, an event organizer — never get to ask the one
> question that matters: *if this goes wrong, does everyone get out?* Egress
> answers that question, on a phone, offline."

### 0:20 – 0:45 · The gallery + the game skin  *(Criteria 4, 5)*
**[ON SCREEN]** Spaces tab. Slowly scroll the preset carousel.
> **VO:** "This is Spaces. Each card is a real, playable venue — an office, a
> classroom, a packed nightclub — rated LITE, STANDARD or PRO like difficulty
> levels. The little resident on every card even *matches* that difficulty:
> calm and confident on an easy room, visibly alarmed on a hard one. That's the
> whole idea — we wrapped a serious safety tool in a warm, pixel-arcade skin so
> it feels like a game you *want* to poke at, not an engineering report you're
> afraid to open."

### 0:45 – 1:35 · The core journey — run a bad room  *(Criteria 2, 6)*
**[ON SCREEN]** Open **The Vault** (nightclub · 150 people · 1 exit · PRO). Start
the simulation. Let the crowd flow. Point the camera at the exit as it jams.
> **VO:** "Let's stress-test the worst case: a hundred and fifty people, one
> exit. When I run it, every one of these dots is an independent person, steered
> by real crowd physics. Watch the exit. The heat-map goes red as density
> climbs, and the app escalates on its own — *congestion… bottleneck… crush.*"
**[ON SCREEN]** Drop a fire near the exit. Crowd visibly reroutes; a banner fires.
> **VO:** "Now I'll add fire. The flames spread cell by cell, and — this is the
> important part — the crowd *reroutes live* around them. The room can't drain
> fast enough."

### 1:35 – 2:05 · The verdict + the coach  *(Criteria 1, 2, 3)*
**[ON SCREEN]** Results sheet: **FAIL**, Safety Score animates to a low number.
RALLY coach card appears.
> **VO:** "Verdict: **FAIL.** A Safety Score of forty-something, and it tells me
> *why* — density and casualties, not a vague grade. And RALLY, our on-device
> coach, doesn't just scold: it diagnoses *where* the jam formed and proposes a
> concrete fix — *add a second exit to split the flow.* No numbers it can't
> justify, no internet, nothing leaves the phone."

### 2:05 – 2:40 · Close the loop — fix it, prove it  *(Criteria 2, 6 — the money shot)*
**[ON SCREEN]** Open the editor on that venue. Add a second exit. Re-run. Crowd
now drains smoothly. Results: **PASS**, Safety Score jumps high.
> **VO:** "So I take RALLY's advice — one more exit — and run the *exact same*
> crowd again. Same seed, same people. And now" *(let the PASS land)* "…everyone's
> out, comfortably under target. That's the loop: **design, simulate, fail,
> understand, fix, pass.** In sixty seconds I turned an unsafe room into a safe
> one — and I can prove the difference."

### 2:40 – 3:05 · Learn + why it's real  *(Criteria 1, 4)*
**[ON SCREEN]** Learn tab: daily quiz, real case-study rows.
> **VO:** "Beyond the sandbox, Learn turns real evacuation disasters into short
> case studies and a daily quiz — so the app teaches the principles, not just
> the scores. Every threshold Egress uses — the density bands, the exit widths —
> comes from published crowd-safety standards, not numbers we made up."

### 3:05 – 3:30 · The close  *(Criteria 3, 5)*
**[ON SCREEN]** Toggle airplane mode ON in Control Center, then run a sim again to
prove it still works. End on the app icon / title.
> **VO:** "And it all runs *here* — airplane mode on, no server, deterministic
> physics, private by construction. Native SwiftUI, an on-device simulation
> engine, Core Haptics you can feel, and Apple's on-device Foundation Models for
> the coach. Egress: crowd safety you can hold in your hand. Thanks for watching."

---

## DEEP-DIVE TALKING POINTS
*(Use these to stretch to ~5 min, for Q&A, or in the written submission's technical section. Keep spoken versions to one sentence each.)*

### The algorithms & concepts (the "how")
- **Helbing Social Force Model** — every person is a particle under a *driving
  term* (accelerate toward desired velocity, relaxation time τ) plus a *soft
  exponential repulsion* from neighbours and walls, and *body-compression +
  tangential-friction* contact forces once bodies overlap. Integrated with
  **semi-implicit Euler** in fixed **120 Hz substeps**, using a start-of-step
  snapshot so the update is **order-independent (Jacobi)** → reproducible.
- **Emergent "faster-is-slower"** — panic *raises* desired speed, which *raises*
  compression and friction at a throat, which *lowers* collective flow. The
  bottleneck death-spiral isn't scripted; it emerges from the physics. This is
  the app's core scientific claim.
- **Multi-source BFS flow field** — shortest walking distance to the *nearest*
  exit for every cell. Unit edge costs collapse Dijkstra to BFS, so the field is
  **exact and free of local minima**: step downhill and you always reach an exit
  if one is reachable. Rebuilt live when fire changes what's passable.
- **Spatial hash** — the social force only needs neighbours within ~1.2 m, so we
  bin agents on a uniform grid for **O(N) neighbour queries instead of O(N²)** —
  what lets ~200 agents hit frame rate on a phone.
- **Fire cellular automaton** — cells cycle unburnt → igniting → burning → burnt;
  each tick a burning cell ignites flammable neighbours with probability
  **p = 1 − e^(−λΔt)** (diagonals at 0.7×). Runs on its own 15 Hz clock,
  decoupled from physics. Smoke is a separate **diffusion field** that blinds but
  never blocks.
- **Fruin Level-of-Service density bands** — 1.8 / 2.0 / 5.0 / 7.0 persons·m⁻²
  (comfortable → congested → at-risk → crush). Real, citable crowd-science
  thresholds; the coach quotes them verbatim.
- **Safety Score (0–100)** — `100 − C − D − R − T`: penalties for **c**asualties,
  peak **d**ensity, at-**r**isk dwell, and **t**ime overrun past the egress
  target. A transparent, deterministic formula — not a black box.
- **Determinism** — one seeded RNG stream drives spawn + hazard spread, so *the
  same seed reproduces a run exactly.* That's what makes the before/after
  comparison honest and the whole thing testable.

### Apple technologies (the "with what")  *(Criterion 3)*
- **SwiftUI** — the entire UI; `@Observable` state, `NavigationStack`, environment
  injection. Zero storyboards.
- **SwiftUI `Canvas` + `TimelineView`** — the real-time crowd renderer: agents,
  fire, smoke and the density heat-map are all vector-drawn every frame. No game
  engine, no Metal shaders needed.
- **Swift Package (`EgressEngine`)** — the whole simulation is a pure, UIKit-free
  Swift package: unit-testable in isolation, and it swaps a `MockSimulation` for
  the real one behind one protocol.
- **SwiftData** — `@Model` run records persisted locally and surfaced with
  `@Query`; your history lives on-device.
- **Core Haptics** — three *hand-authored* signature patterns (alarm klaxon, a
  rising crush swell, a sombre FAIL) via `CHHapticEngine`, plus standard Taptic
  feedback — with a budget/intensity system and engine-restart discipline. Every
  haptic has a sound and visual twin, so it's never the only channel.
- **Foundation Models (on-device LLM)** — the RALLY coach uses `@Generable` /
  `@Guide` **structured generation** through `LanguageModelSession`, gated by an
  8-check validator (V1–V8) so the model can *never* emit a number it can't
  ground or reference an element that doesn't exist. **Honest limitation:** this
  path is behind a build flag pending on-device verification; the shipping
  default is a deterministic templated coach, so *every* device gets a coherent,
  fully-offline experience. (This fallback design is itself a Criterion-3 asset.)
- **AVFoundation** — original sound effects. **UIKit appearance** bridged for the
  warm cream chrome.
- **Accessibility** — VoiceOver labels/hints/traits throughout, **Reduce Motion**,
  **Dynamic Type**, and **Reduce Haptic Intensity** all respected; nothing relies
  on colour or sound alone.

### Why it matters in real life — and *offline*  *(Criterion 1)*
- **The user:** small-venue owners, teachers, event and community organizers who
  will never buy MassMotion / Pathfinder or hire a $10k consultant.
- **The value:** a credible, standards-grounded "does everyone get out?" sanity
  check that turns an invisible risk into a thing you can *see* and *fix*.
- **Offline by design:** the engine is pure local computation, the AI is
  on-device, persistence is local. It works in airplane mode — which is exactly
  where evacuation planning is needed: a basement venue with no signal, a field
  site, a disaster zone. No network also means **private by construction** — your
  floor plans never leave the phone.

### The game skin — why a serious tool looks like an arcade  *(Criteria 4, 5)*
- Pixel-art chrome (chunky pixel borders, pixel type), a warm cream palette, and
  springy "arcade-button" press animations.
- Difficulty **tiers** (LITE / STD / PRO) and pixel-art residents whose **emotion
  matches the difficulty** make the stakes legible at a glance.
- A **Daily Quiz** mini-game with coins turns learning into a habit.
- The point isn't decoration: a friendly, re-playable skin is what gets a
  non-expert to *run the simulation a second time* — and the second run is where
  the safety insight lives.

---

## RUBRIC COVERAGE MAP
*(Say the recording is deliberately built to touch all six.)*

| Criterion (pts) | Where the demo earns it |
|---|---|
| Problem & user value (20) | Hook (0:00), verdict framing (1:35), Learn + real standards (2:40), offline real-world (3:05) |
| Working product & technical execution (25) | Full core loop run (0:45→2:40), live reroute, **honest** Foundation-Models-vs-fallback note (2:05) |
| Apple-platform craft (20) | Close (3:05) + deep-dive; Canvas/TimelineView, SwiftData, Core Haptics, Foundation Models, Swift Package |
| Experience design & accessibility (15) | Game-skin segment (0:20), escalation banners, and a spoken line on VoiceOver / Reduce Motion / non-colour cues |
| Originality & product judgment (10) | "Serious tool as an arcade" framing + deliberate scope (one flag off, deterministic fallback shipped) |
| Demonstration evidence (10) | The fix-and-re-run **before/after** (2:05→2:40) and the airplane-mode proof (3:05) — judges *see* it work |

---

## SCREEN DEEP-DIVE: the live simulation ("Startup Floor", t + 0.0s)
*Use when narrating the sim canvas itself. Two beats — characters, then physics.
≈75–90 s in full; trim either half. Backed by `AgentSprites.swift` + the engine.*

### Beat A — The characters (the gamey vibe)
**[ON SCREEN]** Pinch-zoom into one cluster so the detail reads.
> "Look closely — these aren't dots. Every person is a hand-drawn, chunky pixel
> human, and every one is *different*: skin tone, hair, shirt, trousers — all
> generated from that person's ID with a hash, so nobody's random and the same
> person looks the same every frame and every replay. We made them readable *by
> shape, not colour* — an accessibility choice: a broad adult, a small child, a
> hunched elderly figure with a cane, someone seated in a wheelchair with its
> wheel, a staff marshal in a flat cap and plum vest. You can tell who's who in
> pure greyscale."

**[ON SCREEN]** Run for a second so they walk, then pause.
> "They actually *walk* — an alternating-foot step cycle that speeds up with
> movement, and they lean into their direction so the crowd visibly flows toward
> the exits. When someone panics they throw their arms overhead, their face
> changes — calm, worried, wide-eyed — and a ring plus a little symbol badge
> appear above them, every cue a shape, never just colour. Why go this far for a
> safety tool? Because you *care* about these little people. Watching a pixel
> human you recognise get stuck at a door turns an abstract density number into
> something you feel. That's how we made crowd engineering feel like a game."

### Beat B — The physics underneath
**[ON SCREEN]** Point to the HUD (55 AGENTS · t+0.0s · COMFORTABLE · 1.6 p/m²),
then the teal exit bars and brown desks.
> "It's a real simulation, not an animation. We're frozen at t plus zero — the
> alarm just sounded, everyone at their desk, velocity zero. Underneath, each
> person is a particle in the **Helbing social-force model**: they accelerate
> toward the nearest exit, push apart for personal space, push off walls, and —
> when packed — grind together with body compression and friction. They find the
> door with a **flow field**: a breadth-first search out from every exit gives
> each tile its exact shortest distance to safety, so each person walks
> 'downhill' and routes around those desks automatically, no dead-ends. The teal
> bars are the exits. That readout — **1.6 people per square metre, COMFORTABLE**
> — is a real crowd-science threshold, the Fruin bands; as people bunch it
> climbs, the badge turns, and panic makes them *slower* — emergent
> 'faster-is-slower', never scripted. And in the corner: **60 FPS** with 55
> fully-detailed people, because every pixel of one colour across the whole crowd
> fills in a single pass. All on the phone, no server."

### One-liner
> "Every dot is a unique, hand-drawn pixel person — readable by shape for
> accessibility — walking under a real Helbing social-force model toward a BFS
> flow field, with live Fruin density bands up top. Crowd physics turned into
> characters you root for, at 60 FPS, entirely on-device."

---

## SHOT LIST / RECORDING TIPS
1. **Rehearse the fix-and-re-run.** The FAIL → add exit → PASS arc is your single
   strongest 30 seconds. Same seed both times so the only variable is your fix.
2. **Slow down on the jam and the verdict.** Let the heat-map redden and the
   Safety Score animate — don't talk over the payoff.
3. **Prove offline for real.** Toggle airplane mode on camera, then run a sim.
   That one action makes the "no internet" claim undeniable (Criterion 6).
4. **Show one accessibility toggle** (e.g. Reduce Motion or VoiceOver reading a
   card) for two seconds — it's cheap and directly scores Criterion 4.
5. **Keep the physics claims to one sentence each on camera;** park the depth in
   the written submission and the deep-dive above.
6. **State limitations plainly** near the end ("the Foundation-Models coach is
   pending on-device verification, so we ship the deterministic coach as the
   default") — the rubric explicitly rewards honesty.
7. **Length:** aim for 3–4 minutes. If a track/format needs shorter, cut the
   Learn segment (2:40) first; never cut the before/after.
```
