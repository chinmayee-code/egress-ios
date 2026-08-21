# Egress: Complete Project and Implementation Guide

> Code-backed reference for the product, simulation engine, mathematics, Apple technologies, user interface, testing, and presentation.

## 1. Document Status

This document describes the code that is currently present in the repository. It is intended to be the single project reference for:

- understanding the app phase by phase;
- explaining the implementation to judges or teammates;
- building presentation slides and speaker notes;
- tracing a feature to the file that implements it;
- distinguishing deterministic simulation from generative AI;
- identifying current limitations without overstating the product.

The implementation is the source of truth. Older planning documents under `docs/design/` describe ideas and targets, but some of those ideas were changed or not implemented. Where a comment, plan, and executable code disagree, this guide follows the executable code.

### Product safety boundary

Egress is an educational crowd-evacuation simulator. It is not certified fire, building-code, architectural, or engineering software. Its scores and thresholds are product rules used to make simulations understandable; they must not be presented as approval for a real venue.

### Current repository scale

At the time of this audit, the project contains:

- a pure-Swift `EgressEngine` package;
- an iPhone SwiftUI application;
- more than 100 application and engine Swift source files;
- 32 engine test files, one app-level deterministic test file, and placeholder UI tests;
- local visual and sound assets;
- no third-party runtime package dependency.

---

## 2. Product in One Sentence

**Egress lets a user draw or choose a venue, simulate how a mixed crowd escapes through hazards and bottlenecks, and receive a deterministic safety result plus validated on-device coaching.**

### The problem

Floor plans do not make crowd behavior easy to understand. A route can look open while still creating congestion, exposing people to hazards, or leaving part of a room unreachable. Static diagrams also do not show the time-dependent interaction between people, exits, obstacles, fire, and density.

### Who it helps

The current product is framed for education, demonstrations, early design exploration, and safety awareness. It helps a user ask questions such as:

- Can everyone reach an exit?
- Where does the worst crowd density form?
- Does panic make a narrow exit slower?
- What happens when fire blocks a route?
- Would a wider exit, another exit, or a moved obstacle improve the result?

### What makes the implementation distinct

- The venue is editable, not a prerecorded animation.
- Navigation and physics are deterministic for the same venue, configuration, and seed.
- Hundreds of characters are generated and rendered procedurally in Swift.
- Safety metrics, scores, verdicts, and geometry fixes come from code, not an LLM.
- Apple Foundation Models is optional and is restricted to explaining verified facts.
- Simulation, persistence, coaching, sound, and rendering operate on device.

---

## 3. End-to-End User Journey

```text
Landing
  -> Spaces or Learn
  -> Choose a preset, case study, or blank venue
  -> Draw/edit walls, exits, obstacles, water, and fire
  -> Configure crowd count and deterministic seed
  -> Validate that enough floor is reachable
  -> Run the simulation
  -> Watch routes, density, hazards, agents, and escalations
  -> Receive metrics, score, verdict, reasons, and RALLY coaching
  -> Apply a deterministic geometry fix
  -> Rerun with the same crowd and seed
  -> Compare before and after
  -> Save and share the local run report
```

### Phase 1: Create

The editor converts touch input into metre-based geometry. A SwiftUI `Canvas` draws the scene. A transparent UIKit bridge recognizes one-finger drawing and selection plus two-finger pan and pinch gestures. `EditorModel` stores the venue as observable state and converts authoring coordinates to engine coordinates when the simulation starts.

### Phase 2: Compute

The pure-Swift engine rasterizes the venue into a 0.25 m grid, marks blocked and exterior cells, computes a multi-source shortest-path flow field, spawns a deterministic mixed crowd, and advances agents with fixed-step social-force physics. Fire and smoke advance on a separate fixed hazard clock.

### Phase 3: Bring to life

An immutable `SimulationSnapshot` crosses from the engine to the SwiftUI app. `TimelineView` schedules visual updates and `Canvas` renders scenery, density, hazards, casualties, and procedurally generated pixel characters. Sound, haptics, VoiceOver announcements, camera controls, and live status are app-layer concerns.

### Phase 4: Understand

The engine resolves metrics, Safety Score, verdict reasons, and a feasible fix. The app persists a versioned report. If Apple Foundation Models is available, RALLY asks it for concise structured wording, validates every generated number and geometry reference, and falls back to deterministic canned wording if any check fails.

---

## 4. Complete Architecture

```text
CREATE                         COMPUTE                         BRING TO LIFE
SwiftUI editor                Pure-Swift EgressEngine         SwiftUI visual system

Canvas                         Venue rasterization             TimelineView
UIKit gestures       --->      Flat 1D grids          --->     Canvas + GraphicsContext
@Observable state              Multi-source BFS                Procedural characters
VenueModel                     Social-force physics            Density/fire/smoke layers
                               Spatial hashing                 Sound + haptics
                               Fire cellular automaton
                               Metrics and event log

                                      |
                                      v

UNDERSTAND
Deterministic metrics -> Safety Score -> PASS/WARN/FAIL -> feasible geometry fix
                                                            |
                                                            v
                                      Apple Foundation Models, when available
                                      explains validated facts in plain language
```

### Core design rule

**The engine computes truth. The model communicates it.**

There are two different kinds of intelligence:

```text
Navigation intelligence = deterministic breadth-first search
Language intelligence   = optional Apple Foundation Models generation
```

The language model does not:

- move agents;
- calculate routes;
- spread fire;
- calculate density or clearance;
- assign PASS, WARN, or FAIL;
- calculate the Safety Score;
- invent an exit, obstacle identifier, or safety number;
- directly mutate the venue.

### Layer boundaries

| Layer | Responsibility | Important boundary |
|---|---|---|
| `EgressEngine` | Geometry, pathfinding, hazards, physics, metrics, verdicts, fixes | No SwiftUI, UIKit, SwiftData, AVFoundation, or Foundation Models |
| App state/controllers | Convert user actions to models and drive the engine | Main-actor UI ownership |
| Rendering | Draw immutable snapshots | Does not change simulation state |
| Feedback | Sound, haptics, announcements | Does not affect deterministic results |
| Persistence | Save a stable report snapshot locally | Does not own engine logic |
| AI coaching | Generate optional wording from engine facts | Output is constrained, validated, and replaceable |

---

## 5. Project Structure

```text
Egress/
|- Config/                       Shared Xcode configuration
|- EgressEngine/                 Standalone deterministic Swift package
|  |- Sources/EgressEngine/      Engine implementation
|  `- Tests/EgressEngineTests/   Swift Testing suites
|- Egress/
|  |- Egress.xcodeproj/          iPhone app project
|  |- Egress/                    Application source and resources
|  |- EgressTests/               App-level tests
|  `- EgressUITests/             UI test target
|- docs/                         Plans, scripts, and this code-backed guide
|- bin/                          Development setup scripts
`- README.md                     Toolchain and setup summary
```

### Build model

- `EgressEngine` is a local Swift package with no package dependencies.
- The app links the local package product.
- `EGRESS_FM_COACH` conditionally compiles the Foundation Models path.
- The app is iPhone-only and does not support Mac Catalyst.
- Project settings use generated Info.plist values and automatic signing.
- `PrivacyInfo.xcprivacy` declares no tracking or collected data and declares the `UserDefaults` required-reason API use.

### Configuration note

The repository currently contains inconsistent version declarations:

- `README.md` says Xcode 27, Swift 6.4, iOS 27 SDK, and iOS 26 deployment.
- `Config/Shared.xcconfig` sets Swift 6.0 and iOS 26.0.
- the app target in `project.pbxproj` overrides the deployment target to 26.5 and reports `SWIFT_VERSION = 5.0`, while the project-level xcconfig enables strict Swift concurrency.

Before release or a judged reproducibility claim, these values should be aligned and verified using Xcode's resolved build settings.

---

## 6. Engine Data Model and Units

### Coordinate system

- World positions and dimensions are measured in metres.
- Time is measured in seconds.
- Velocity is metres per second.
- Acceleration is metres per second squared.
- Density is people per square metre (`p/m^2`).
- The grid cell size is `0.25 m`, so one cell covers `0.0625 m^2`.

### SIMD vectors

`Vec2` is a type alias for `SIMD2<Double>`:

```swift
public typealias Vec2 = SIMD2<Double>
```

This gives the engine a compact two-component value for positions, velocities, forces, wall normals, and dimensions. Swift SIMD operations express vector arithmetic directly:

```text
position + velocity * dt
desiredVelocity - currentVelocity
dot(relativeVelocity, tangent)
length(vector) = sqrt(x*x + y*y)
```

The `Vec2` extension adds length, squared length, distance, dot product, and safe normalization. Normalization returns zero for a nearly zero vector, preventing division by zero and non-finite physics values.

### Flat one-dimensional grids

Although a venue is conceptually two-dimensional, engine fields are not stored as `[[Value]]`. They use one contiguous one-dimensional array with row-major indexing:

```text
index(x, y) = y * width + x
x(index)    = index % width
y(index)    = index / width
```

This representation is used by navigation cost, density, fire, smoke, and related cell fields. Advantages include:

- one allocation instead of one allocation per row;
- contiguous memory and better cache locality;
- cheap index conversion;
- simpler copying for immutable snapshots;
- no nested-array bounds and indirection overhead.

This is a storage optimization; the algorithms still reason in `(x, y)` grid coordinates.

### Grid conversion

World positions are mapped to cells with floor division:

```text
cellX = floor(worldX / 0.25)
cellY = floor(worldY / 0.25)
```

The world-space center of a cell is:

```text
centerX = (cellX + 0.5) * 0.25
centerY = (cellY + 0.5) * 0.25
```

### Value and concurrency design

Venue models, snapshots, metrics, hazards, and most engine records are value types conforming to `Sendable`. The mutable `Simulation` is a plain final class and is deliberately independent of the main actor. The app's `SimulationController` is `@MainActor` and owns the engine instance. This keeps UI mutation serialized while preserving a reusable UI-free engine.

---

## 7. Venue Geometry and Rasterization

### Venue model

`VenueModel` contains:

- stable identity and name;
- venue type;
- rectangular world geometry;
- wall line segments;
- exit segments with stable integer identifiers and widths;
- rectangular obstacles;
- water zones;
- explicitly blocked cells;
- non-blocking decor.

### Obstacle classes

| Class | Blocks movement | Can RALLY relocate it |
|---|---:|---:|
| Structural | Yes | No |
| Relocatable | Yes | Yes |
| Decor | No | No geometry change needed |

The visual `kind` of a prop is an editor/rendering concern. The engine primarily uses geometry and obstacle class.

### Area

```text
grossArea = width * height
netArea   = grossArea - exteriorBlockedArea - obstacleAreas
```

Water is intentionally not subtracted from `netArea` in the current implementation, even though it blocks movement. Overlapping obstacles can also be double-counted by the simple area subtraction. Therefore, `netArea` is an approximate reporting value, not a constructive solid geometry union.

### Rasterizing geometry

- Wall segments are converted to grid cells with Bresenham line traversal.
- Obstacles and water use half-open rectangular cell ranges.
- Exit spans are sampled at half-cell intervals and clamped to the venue grid.
- Explicitly blocked cells are unioned with derived barriers.
- Decor is excluded from movement blocking.

### Discovering the room interior

Free-form walls make a plain rectangular room assumption insufficient. `RoomEnclosure`:

1. rasterizes walls and exits as temporary barriers;
2. starts a four-neighbor flood fill from grid-border cells;
3. marks every reached cell as outside;
4. treats unreached non-barrier cells as the enclosed interior;
5. restores exit cells as traversable route targets.

If the drawing does not create a closed interior, the helper returns no exterior mask and the full rectangular grid remains available. The editor caches enclosure results using a geometry signature to avoid recalculating them for every visual frame.

### Water

Water is a static no-go area. It does not spread, injure agents, change friction, or participate in fire/smoke mathematics.

---

## 8. Shortest-Path Navigation

### Why multi-source breadth-first search

Every exit cell is inserted into one BFS queue at cost zero. Search then expands through each traversable cell's four orthogonal neighbors. For a uniform grid, each move has equal cost, so BFS computes the exact minimum number of cell steps from every reachable cell to its nearest exit.

```text
for exit in exits:
    cost[exit] = 0
    queue.push(exit)

while queue is not empty:
    current = queue.popFront()
    for neighbor in current.fourNeighbors:
        if neighbor is open and unvisited:
            cost[neighbor] = cost[current] + 1
            queue.push(neighbor)
```

Blocked and unreachable cells retain `Int.max`.

### Why one flow field serves the entire crowd

Running a separate path search for each agent would repeat almost the same work. The reverse, multi-source field computes routes once for the venue. Every agent samples the local cost gradient:

```text
gx = cost(right) - cost(left)
gy = cost(down)  - cost(up)
direction = normalize(-(gx, gy))
```

The negative gradient points toward decreasing cost and therefore toward an exit.

### Mathematical model

For open cell `c`, the discrete cost satisfies:

```text
C(c) = 0                                      if c is an exit
C(c) = 1 + min(C(n)) for n in N4(c)          otherwise
C(c) = infinity                              if unreachable
```

`N4` is the Von Neumann neighborhood: left, right, up, and down. Diagonal movement is not a BFS edge, although continuous physics can produce diagonal world-space motion while following the field.

### Complexity

For `V` grid cells and at most four edges per cell:

```text
time  = O(V + E), which is O(V) on this fixed-degree grid
space = O(V)
```

### Dynamic hazard rerouting

Active fire cells are added to the blocked set. The engine rebuilds the flow field only when that active set changes. Agents then sample the new field and route around the hazard when another reachable path exists.

### Wall field

A separate multi-source flood starts from blocked cells and records the nearest blocked source. It provides approximate metric distance and an outward normal for wall repulsion. Venue boundaries are not automatically hard walls because an exit may lie on an edge; authored barriers and bounds handling control movement.

---

## 9. Crowd Creation and Agent State

### Deterministic random generator

The engine uses a seeded SplitMix64 generator. The same venue, configuration, and seed reproduce spawn selection, mobility assignment, and fire randomness.

This is central to before/after comparisons: applying a fix and rerunning with the same seed changes geometry while preserving the stochastic sequence.

### Spawning

The spawner:

1. collects traversable cells that can reach an exit;
2. excludes exit cells;
3. shuffles candidates with the seeded generator;
4. chooses distinct cells;
5. caps the requested crowd at the number of available cells.

No two agents initially occupy the same grid cell.

### Mobility classes

| Mobility | Base desired speed | Visual identity |
|---|---:|---|
| Adult | 1.3 m/s | Adult body variants |
| Child | 0.9 m/s | Shorter silhouette |
| Elderly | 0.7 m/s | Gray hair and cane |
| Wheelchair | 0.8 m/s | Seated body and wheel |
| Staff | 1.3 m/s | Cap and vest |

The default deterministic mix is weighted toward adults: five adult entries plus one entry each for child, elderly, wheelchair, and staff.

### Status

An agent is `active`, `evacuated`, `injured`, or `dead`. Injured and dead agents both count as casualties. Downed agents remain represented in the physical/density population, so they can continue to affect crowding.

### Emotion and arousal

The current rule set is local and deterministic:

- density below 1.8: calm;
- density from 1.8 to below 5.0: uneasy;
- density at or above 5.0: panicked;
- occupying an active fire cell: panicked.

Arousal multiplies desired speed:

| State | Arousal multiplier |
|---|---:|
| Calm | 1.0 |
| Uneasy | 1.1 |
| Panicked | 1.5 by default |

The source variable named `nearFire` currently checks the agent's fire cell, not a radius around the fire.

### Emotes

Emotes are observation-only visual signals; they never feed back into physics. Rules detect first panic, unease, stalling, crowding, fire, exit proximity, and staff supporting nearby panicked agents. Emotes live for 1.6 seconds and the renderer displays only the highest-priority subset when characters are large enough on screen.

---

## 10. Social-Force Crowd Physics

The engine uses a simplified social-force formulation inspired by pedestrian dynamics. Each agent receives a desired-motion force, repulsion/contact from nearby agents, and repulsion/contact from nearby walls.

### Fixed time step

- App controller step: `1/60 s`.
- Internal physics substep: `1/120 s`.
- Maximum accepted frame delta: `1/30 s`.
- Hazard update: fixed `1/15 s`.

Fixed stepping makes the result depend on simulation steps rather than display-frame timing.

### Desired velocity

For base speed `v0`, arousal `a`, and normalized flow direction `e`:

```text
vDesired = v0 * a * e
```

The relaxation acceleration drives current velocity `v` toward the desired velocity over `tau = 0.5 s`:

```text
aDrive = (vDesired - v) / tau
```

### Pedestrian interaction

For agents `i` and `j`:

```text
d       = ||position_i - position_j||
n       = normalize(position_i - position_j)
overlap = radius_i + radius_j - d
t       = (-n.y, n.x)
```

The soft social repulsion is:

```text
fSocial = A * exp(overlap / B) * n
```

with `A = 12` and `B = 0.20 m`.

If bodies overlap, physical compression is added:

```text
fBody = k * overlap * n
```

with `k = 60`.

Tangential friction opposes sliding relative motion:

```text
relativeTangent = dot(v_j - v_i, t)
fFriction       = kappa * overlap * relativeTangent * t
```

with `kappa = 40`.

Only neighbors within `1.2 m` are evaluated after spatial-hash candidate lookup.

### Wall interaction

The wall field provides wall distance and normal. The engine applies the same categories of soft repulsion, body compression, and tangential friction, with wall social strength `8` and falloff `0.20 m`. A wall is stationary, so relative tangential velocity comes from the agent.

### Numerical integration

Total acceleration is clamped to `20 m/s^2`. Semi-implicit Euler integration is used:

```text
vNext = clampMagnitude(v + acceleration * dt, 2.5 m/s)
xNext = x + vNext * dt
```

Semi-implicit Euler updates velocity before position. It is inexpensive and generally more stable for this interactive fixed-step model than updating position from the old velocity.

### Hard collision slide

Soft forces are not the final wall guarantee. If the proposed position enters a blocked cell, the engine tries each axis separately. A permitted axis is kept and a blocked axis has its velocity component canceled. The resulting position is clamped into world bounds. This creates a wall-slide behavior and prevents tunneling through rasterized barriers at the configured speed and step size.

### Order independence

Each substep reads all force inputs from a start-of-step copy and writes new states separately. This Jacobi-style update avoids an earlier agent receiving a different physical result simply because another agent was updated first.

### Faster-is-slower effect

Panic increases desired speed, but at a constrained exit this also increases contact, compression, and tangential friction. Therefore, a more urgent crowd can form a stronger arch or jam and clear more slowly. The test suite includes both:

- a constrained bottleneck where higher panic creates worse clearance;
- an uncrowded case where the panic multiplier does not create a false slowdown.

This is emergent from the interaction rules and parameters; it is not implemented as a direct "panic makes the run slower" condition.

---

## 11. Spatial Hash Optimization

A naive interaction loop compares every pair of agents:

```text
N * (N - 1) / 2 comparisons = O(N^2)
```

The engine instead divides world space into uniform bins whose size matches the interaction range. Each active or downed body is inserted into one bin. An agent queries its own and neighboring bins, then performs an exact distance check on the returned candidates.

```text
binX = floor(position.x / binSize)
binY = floor(position.y / binSize)
```

### Complexity statement

- Building the hash is `O(N)`.
- Queries are local and are near constant cost when occupancy per bin stays bounded.
- A typical full interaction pass is therefore near `O(N)`.
- Worst-case behavior can still approach `O(N^2)` if every agent is packed into the same small set of bins.

The presentation-safe claim is **"spatial hashing avoids routine all-pairs checks and gives near-linear behavior for normally distributed crowds"**, not an unconditional `O(N)` guarantee.

---

## 12. Density, Metrics, and Bottlenecks

### Density grid

Body positions are first counted in 0.25 m cells. The engine then applies a separable box blur with radius:

```text
round(0.75 / 0.25) = 3 cells
```

The complete neighborhood is therefore `7 x 7` cells. Its physical area is:

```text
(7 * 0.25)^2 = 3.0625 m^2
```

Density is the neighborhood count divided by this fixed physical area. The implementation uses horizontal and vertical running sums instead of recomputing the full square for every cell.

At grid edges, missing outside cells contribute zero while the divisor remains the full kernel area, so edge density can read lower than an equivalent interior cluster.

### Density policy thresholds

| Meaning | Threshold |
|---|---:|
| Comfortable reference | 1.8 p/m^2 |
| Congested reference | 2.0 p/m^2 |
| At-risk threshold | 5.0 p/m^2 |
| Crush threshold | 7.0 p/m^2 |

An agent becomes "at risk" after accumulating at least 3 seconds at or above 5.0 p/m^2.

### Visual bands are separate

The current renderer/HUD colors use 2, 4, and 6 p/m^2 breakpoints. These are visual bands, not the exact verdict policy thresholds above. They should be described as rendering bands unless the code is aligned later.

### Metrics tracked

- configured/spawned crowd;
- elapsed time;
- active, evacuated, injured, dead, and casualty counts;
- clearance time;
- current and peak density;
- peak-density cell and timestamp;
- each agent's time above the at-risk threshold;
- fraction of agents classified at risk;
- trapped active agents when the run does not clear.

Clearance is captured on the first frame where no active agents remain. The safety target comes from venue type. The engine's hard simulation-time cap is `clamp(3 * target, 300, 600)` seconds.

### Venue-type educational targets

| Venue type | Target |
|---|---:|
| Office | 150 s |
| Nightclub | 120 s |
| Concert hall | 180 s |
| Retail | 150 s |
| Transit | 240 s |
| Classroom | 180 s |
| Stadium | 240 s |

These are app defaults. The repository does not currently contain a formal bibliography or jurisdiction-specific code mapping that would support presenting them as certified standards.

---

## 13. Fire and Smoke

### Fire cellular automaton

Each grid cell has one of four states:

```text
unburnt -> igniting -> burning -> burnt
```

For spread rate `lambda`, time step `dt`, and a neighboring burning cell, the continuous-time rate is converted into a discrete ignition probability:

```text
p = 1 - exp(-lambda * dt)
```

The cardinal spread rate is `0.35 / s`. Diagonal spread uses `0.7 * lambda`. Cells remain igniting for 1 second and burning for 20 seconds. Iteration order and random draws are deterministic for the seed.

### Why `1 - exp(-lambda * dt)`

This is the probability of at least one event from a Poisson process over interval `dt`. Unlike the approximation `lambda * dt`, it remains bounded by 1 and behaves consistently when the step size changes.

### Movement and injury

- Igniting and burning cells are considered active fire.
- Active fire cells become navigation blockers.
- Entering an active fire cell immediately changes an active agent to injured and zeroes velocity.
- An injured agent changes to dead after 2 seconds of injury simulation time.
- The casualty metric increments once when injury occurs.

If no active agents remain, the simulation is complete. Consequently, a run can finish with injured agents before enough additional simulation time elapses to relabel all of them as dead. Reporting correctly groups both states as casualties.

### Smoke diffusion

Burning cells produce smoke at `0.5 / s`. At each 15 Hz hazard update, every cell reads the previous smoke field and computes:

```text
sNext = s + D * (mean4 - s) - decay * s * dt
```

where:

- `D = 0.25` per hazard tick;
- `mean4` is the mean of orthogonal neighbors;
- `decay = 0.01 / s`;
- the result is clamped to `[0, 1]`.

Reading from the previous field is a Jacobi update, so cell traversal order does not bias diffusion.

### Current smoke boundary

Smoke is currently rendered, but it does not reduce speed, visibility, route preference, health, or scoring. Any presentation statement that agents "react to smoke" would be inaccurate for the current build.

---

## 14. Simulation Clock and App Controller

`SimulationController` turns irregular display timestamps into fixed `1/60 s` engine calls. Each engine call internally performs `1/120 s` physics substeps.

### Accumulator

```text
accumulator += clampedDisplayDelta

while accumulator >= 1/60 and steps < 8:
    engine.step(1/60)
    accumulator -= 1/60
```

The eight-step catch-up budget prevents a long frame from creating an endless update spiral. Excess backlog is dropped. As a result:

- a run is deterministic for the fixed steps that actually execute;
- dropped backlog can make wall-clock completion take longer;
- it does not inject a large, unstable physics step.

### History and scrubbing

Snapshots are decimated to roughly 20 frames per second and retained for timeline scrubbing. Scrubbing is a visual history operation; it does not reverse the mutable engine. Returning to live resumes forward stepping.

### Camera and following

The simulation has UIKit-backed pan, pinch, and tap input. Tapping near an active agent can enter follow mode when zoom is sufficient. Camera changes affect only projection, never engine coordinates.

### Thermal state

The UI watches `ProcessInfo.thermalState` and can show a performance notice for serious conditions or frame-budget pressure. Current code does not actually lower character detail or change physics based on thermal state, despite wording that may imply detail is being capped.

---

## 15. Events and Live Escalation

### Event log

`RunEventLog` stores monotonically identified, Codable events. The vocabulary includes alarm, ignition, hazard spread, exit blocked, flow recomputation, density threshold, jam, injury, death, progress, and simulation end.

The current `Simulation` emits:

- alarm;
- ignition;
- flow-field recomputation;
- density escalations;
- exit blocked;
- agent injured;
- agent killed;
- simulation ended.

`hazardSpread`, `jam`, and `progress` cases exist in the vocabulary but are not currently emitted directly.

### Escalation bands

| Band | Trigger |
|---|---:|
| Congestion | density >= 4 p/m^2 |
| Bottleneck | density >= 5 p/m^2 |
| Crush | density >= 7 p/m^2 |
| Exit blocked | active fire occupies an exit |
| First casualty | first injury/death event |

Priority is casualty, crush, exit blocked, bottleneck, then congestion. At most one escalation is selected at a time. A 6-second cooldown limits repetition and a band must remain clear for 10 seconds before it can rearm. A higher density band suppresses lower-density messages.

### Run summary

The log can derive counts, injuries, deaths, worst jam, alarm/end status, and duration. This summary is available in the engine but is not currently passed into `FoundationModelsCoach`; AI coaching uses the final `RunResult` and `CoachFacts` instead.

---

## 16. Safety Score and Verdict

### Score formula

The Safety Score starts from 100 and subtracts four penalties:

```text
casualtyPenalty = min(60, 25 * casualties)

densityRatio    = clamp((peakDensity - 1.8) / (7.0 - 1.8), 0, 1)
densityPenalty  = densityRatio * 25

riskPenalty     = atRiskFraction * 20

timeRatio       = clamp((clearance - target) / target, 0, 1)
timePenalty     = timeRatio * 15

score = round(clamp(
    100 - casualtyPenalty - densityPenalty - riskPenalty - timePenalty,
    0,
    100
))
```

Maximum penalties are:

- casualties: 60 points;
- peak density: 25 points;
- at-risk fraction: 20 points;
- delayed clearance: 15 points.

The components can total more than 100, so the final score is clamped.

### Verdict rules

The verdict is not just a color chosen from score. Safety conditions have authority:

**FAIL** if any is true:

- casualties are greater than zero;
- score is below 50;
- at least one active agent is trapped.

**WARN** if no FAIL condition exists and any is true:

- peak density is at least 5 p/m^2;
- at-risk fraction is at least 15%;
- clearance exceeds the venue target;
- score is at least 50 but below 80.

**PASS** otherwise.

An exact score of 50 does not fail from score alone because the code uses `< 50`; it can still fail for casualty or trapped-agent reasons.

### Explainability

The engine creates structured `VerdictReason` values containing:

- metric key;
- observed value;
- threshold;
- unit;
- human-readable text.

This makes a verdict auditable before any language model is called.

---

## 17. RALLY Fix Planning and Before/After Comparison

### Deterministic coach

`RallyCoach` creates no geometry fix for PASS. For WARN or FAIL, it first identifies an exit near the peak jam, with a narrow-exit fallback, and proposes a wider exit. The requested width is:

```text
max(1.2 m, currentWidth + 0.7 m)
```

If that exact proposal is not feasible, it attempts the minimum 1.2 m form. The broader planner also supports adding an exit and relocating a movable obstacle.

### Fix types

```text
widenExit(exitID, newWidth)
addExit(wallSide, centerOffset, width)
relocateObstacle(obstacleID, newCenter)
```

### Feasibility gates

- referenced exit or obstacle identifier must exist;
- exit width must meet the 1.2 m minimum;
- new geometry must remain in room bounds;
- only relocatable obstacles may move;
- planned placements avoid walls, exits, water, and other obstacles with a body-radius margin.

`FixPlanner` scans candidate positions on a deterministic grid. Obstacle relocation uses a step of `max(2 cells, 0.25 m)`, which is 0.5 m with the current grid. It favors positions away from the peak jam and exits. New-exit planning samples wall positions at 0.25 m and favors separation from existing exits while rejecting obstructed wall strips.

The base `Fix.isFeasible` checks identity, dimensions, movability, and bounds, while collision-aware placement belongs to `FixPlanner`. A caller constructing an arbitrary `Fix` should not assume the base check performs the full planner overlap search.

### Apply and rerun

A fix creates a new `VenueModel`; it does not mutate the prior run result. The app reruns the new venue with the same simulation configuration and seed, then records baseline score/casualties and displays the delta. This is a controlled comparison, not an AI-generated prediction.

---

## 18. Apple Foundation Models and RALLY

### Which Apple LLM is used

The app uses Apple's `FoundationModels` framework and `SystemLanguageModel.default`. It does not bundle a named third-party model, call OpenAI, or choose a downloadable model identifier in the source. The system framework decides the available on-device Apple language model.

The feature is compiled only when both are true:

```swift
#if EGRESS_FM_COACH && canImport(FoundationModels)
```

At runtime, the app also checks `SystemLanguageModel.default.availability`. If compilation support or runtime availability is missing, RALLY uses `CannedCoach`.

### Why wording exists in `CannedCoach.swift`

Hardcoded text is the guaranteed deterministic fallback. It ensures that every supported device receives useful coaching even when:

- Apple Intelligence is unavailable;
- the Foundation Models framework is unavailable in the SDK/build;
- the model session throws;
- generation exceeds 20 seconds;
- the generated output fails validation.

The model's value is flexible plain-language diagnosis and summary, not the creation of the underlying safety answer.

### Structured generation

The Foundation Models path uses:

- `LanguageModelSession`;
- `@Generable` output schemas;
- `@Guide` constraints;
- separate WARN/FAIL and PASS structures;
- constrained enums for action and wall side.

For a non-pass result, the model can propose an intent such as widen, add, or move. The app maps that intent to engine-owned geometry and validates feasibility. For PASS, a separate schema allows a light joke field; injury-related joke vocabulary is rejected.

### Facts supplied to the model

`CoachFacts` packages engine-owned values such as:

- score and verdict;
- clearance and target time;
- peak density and policy thresholds;
- crowd, casualty, trapped, and survivor counts;
- at-risk fraction;
- room dimensions and precomputed area per person;
- exit identifiers, widths, wall sides, and offsets;
- obstacle identifiers, sizes, positions, and movability;
- deterministic engine fix information.

The prompt explicitly tells the model not to do arithmetic or invent values.

### Numeric grounding

Every ASCII decimal token found in generated prose is checked against `CoachFacts.approvedFigures`. That allowlist is built from engine facts, identifiers, dimensions, thresholds, percentages, and other exact values supplied to the session.

Example:

```text
Engine says peak density = 5.8 p/m^2
Generated text says 5.8  -> allowed
Generated text says 6.3  -> rejected unless 6.3 is another approved fact
```

This does not prove that every sentence is semantically perfect, but it prevents unsupported numeric claims from reaching the user.

### Geometry validation

For a generated fix intent, validation checks:

- action belongs to the structured enum;
- identifier exists;
- referenced obstacle is movable when required;
- dimensions and offsets are grounded;
- mapped engine fix is feasible;
- diagnosis/headline/summary are present and bounded;
- PASS humor does not use injury vocabulary.

If generated prose is acceptable but its fix is not, the app can retain the wording while using the deterministic engine fix. If broader validation fails, the whole response falls back to `CannedCoach`.

### Correct judge answer

**Question:** How do we know the AI is not inventing the safety result?

**Answer:** The complete safety pipeline runs before the language model. The engine computes routes, crowd motion, hazards, metrics, score, verdict, reasons, and a feasible fix. The model receives those facts through a structured schema and is limited to wording and a constrained fix intent. Numbers, identifiers, dimensions, and feasibility are validated. Any unavailable, timed-out, erroneous, or ungrounded response is replaced by deterministic coaching.

---

## 19. SwiftUI Editor

### State model

`EditorModel` is `@MainActor @Observable`. SwiftUI views read the state directly and refresh only when observed properties change. It owns:

- selected tool group and tool;
- walls, exits, props, water, and ignition point;
- current selection and in-progress draft;
- camera;
- crowd count, seed, and venue type;
- validation and cached room enclosure.

### Tools

Tool groups are Build, Props, and Hazards. Specific interactions include:

- select and move;
- draw wall;
- draw exit;
- erase;
- place structural, relocatable, or decor props;
- place fire;
- draw water.

### Touch model

`CanvasInputView` is a transparent `UIViewRepresentable`. UIKit gesture recognizers provide touch-count control that the selected SwiftUI drawing gesture did not expose cleanly:

- one finger: draw, tap, select, or move according to the armed tool;
- two fingers: pan;
- pinch: zoom around an anchor;
- tap: selection, point placement, or erase.

The editor and renderer share projection mathematics so screen coordinates map consistently to world metres.

### Snapping and constraints

- coordinate snap: 0.25 m;
- minimum drawn wall: 0.5 m;
- minimum editor exit drag: 0.5 m;
- minimum box dimension: 0.5 m;
- erase radius: 0.6 m;
- selection radius: 0.9 m;
- keyboard/accessibility nudge: 0.5 m;
- exit width stepper: 0.1 m.

The editor permits an exit narrower than the engine's 1.2 m recommended minimum so the simulator can demonstrate a poor design and report it.

### Free-form authoring and normalization

The editor allows content beyond the initial rectangular floor. It computes the union of the base floor and authored content, snaps outward to the 0.25 m grid, then translates all elements into a non-negative engine coordinate system. This separates a flexible drawing workspace from the engine's `[0, width] x [0, height]` venue model.

### Prop library

Structural examples include a bar, stage, turnstile, lockers, pillar, and seating. Relocatable examples include an object, high table, speaker, desk, bench, and equipment rack. A planter is available as decor. In the editor these props can be selected and moved; their engine obstacle class determines whether RALLY is permitted to relocate them automatically.

### Validation

The editor checks basic geometry and requires at least 50% of candidate floor cells to be reachable before enabling simulation. This is a permissive educational gate: a venue with exactly half its floor unreachable can still pass editor validation and later produce a poor simulation result.

### Accessible alternative

Because freehand canvas drawing is not a complete VoiceOver authoring experience, the app provides presets and configuration controls for exit width, crowd, seed, object movement/removal, and hazard clearing. Canvas content also exposes accessibility summaries and the app honors Reduce Motion in animated UI paths.

---

## 20. Rendering Pipeline

### Snapshot boundary

`SimulationSnapshot` is immutable and `Sendable`. It contains:

- simulation time;
- lightweight `AgentRender` values;
- fire and smoke snapshot data;
- density grid;
- live metrics.

The renderer consumes the snapshot without reaching into mutable engine internals.

### Timeline and Canvas

`TimelineView(.animation(paused:))` schedules view refreshes. SwiftUI `Canvas` supplies a `GraphicsContext` for immediate-mode drawing. A normal frame renders layers in a stable order:

1. grid and exterior;
2. water;
3. obstacles and decor;
4. walls;
5. density overlay;
6. fire and smoke;
7. exits;
8. casualties;
9. live crowd and emotes.

The editor and simulator share `VenueScenery` so the same wall, exit, obstacle, water, and decorative language appears before and during a run.

### Density accessibility

Density does not rely only on hue. Optional patterns use dots, diagonal marks, and crosses to distinguish bands for color-vision accessibility.

### Fire visual

Fire flicker, glow, ember, and smoke visuals are generated from simulation time and stable cell hashes. They do not consume the simulation RNG and therefore cannot perturb physics determinism.

---

## 21. Procedural Character Generator

### No sprite animation dependency

The live simulation characters are assembled in Swift from small vector-pixel cells. Their identity is generated from the agent's stable identifier instead of loading a frame animation.

### Stable identity

A deterministic hash chooses:

- body silhouette;
- skin tone;
- hair color/style;
- top color;
- trouser color;
- class-specific details.

The same agent ID therefore keeps the same appearance across frames and deterministic reruns.

### Five mobility representations

- adults have male/female silhouette variants;
- children are shorter;
- elderly characters use gray hair and a cane;
- wheelchair users include a seated silhouette and wheel;
- staff use a cap and safety vest.

### Motion

Character motion is derived from engine state:

```text
cadence = (2.4 + speed * 2.2) * panicMultiplier
```

Walk animation alternates foot lift. Horizontal velocity controls lean. Speed controls bob. Panic can add jitter, raised hands, expression changes, and an aura. These are visual consequences of state, not physics forces.

### Batched Canvas rendering

Each sprite is represented by material cells such as hair, face, skin, top, trousers, body, cane, and wheelchair. Instead of issuing a separate fill operation for every pixel of every person, the renderer combines cells of the same color across the crowd into shared `Path` objects and fills each batch together.

This reduces hundreds or thousands of tiny draw submissions to a much smaller set of color-batch fills.

### Level of detail

- faces appear only when projected cell size is at least 4 points;
- emotes appear only from 5 points;
- at most 12 emotes are selected by priority;
- character unit size is bounded by zoom/projection rules so details do not resize layout controls.

Casualties currently use the bundled coffin visual in the simulation. Older corpse silhouette maps remain in `AgentSprites` but are not the active casualty rendering path.

### PixelText

`PixelText` is not a system text renderer. `PixelFont` stores a small 5-by-7 bitmap pattern for each supported glyph. SwiftUI `Canvas` draws a square for every active bit:

```text
glyph row "10101"
           ^ ^ ^ -> draw three pixel rectangles
```

It is used for compact score, verdict, and game-like statistical labels. The relevant Swift technology is SwiftUI `Canvas` and `GraphicsContext`; the bitmap font itself is custom project code.

---

## 22. Sound, Haptics, and Accessibility Feedback

### AVFoundation audio

`SoundPlayer` owns one `AVAudioEngine` and a small pool of player nodes. The audio session is ambient and mixes with other audio, respecting the silent switch. Bundled MP3s cover theme, controls, ambience, alarm, death variants, success, and fail.

The implementation also has generated fallbacks:

- short 8-bit style effects if a bundled effect cannot load;
- brown-noise-like crowd ambience fallback;
- procedural fire crackle.

Crowd murmur volume follows active population and density. Fire ambience follows active fire count. Death sounds are queued with at least 0.12 seconds between playback and a capped queue. Background music loops from a rotated entry point and fades rather than cutting abruptly.

### Core Haptics

Three signature custom patterns are hand authored:

- alarm/klaxon;
- crush warning;
- FAIL verdict.

Other interactions use UIKit feedback generators. Ordinary haptics are budgeted to roughly one per 0.5 seconds, while important signature, casualty, and score cues have separate handling. If Core Haptics hardware is unavailable, custom feedback becomes a safe no-op or uses simpler fallback behavior.

### Reduced feedback

User settings can disable sound and reduce audio/haptic intensity. Reduced haptics simplify the crush pattern. App lifecycle handling stops or fades feedback when backgrounded and resumes appropriate music after returning.

### VoiceOver and motion

- live escalations can post spoken accessibility announcements;
- controls have accessibility labels;
- patterns supplement density colors;
- Reduce Motion is observed in UI/animation decisions;
- presets and parameter controls provide a more accessible route than freehand drawing.

---

## 23. Persistence and Sharing

### SwiftData

`RunRecord` is a SwiftData `@Model`. The model container is local-only with CloudKit disabled. A record stores searchable stable fields plus a JSON-encoded versioned report:

- UUID and date;
- venue name/type;
- score and raw verdict;
- clearance, occupancy, and seed;
- `RunReportSnapshot` JSON.

### Report snapshot

Version 1 captures the simulation configuration, venue details, metrics, verdict reasons, fix, before/after deltas, and coaching. The engine result is saved promptly; asynchronous AI coaching can patch its text into the persisted report later.

### Spaces history

Spaces shows summary statistics, presets, and the latest ten runs. Selecting a run opens the complete static report.

### Share image

The report uses SwiftUI `ImageRenderer` at scale 3 to render a self-contained branded image. `ShareLink` presents the system share sheet. The share card includes the educational safety disclaimer so a detached image does not imply certified advice.

---

## 24. App Features Outside the Engine

### Landing

The landing screen is the first-launch gate on every app launch. It presents the EGRESS identity, an offline/private/precise value statement, and a direct start action. It uses the `landing_hero` asset when available. A fallback `LandingDiorama` can render a procedural isometric scene in `Canvas` using a 2:1 projection:

```text
screenX = (gridX - gridY) * tile * 0.5
screenY = (gridX + gridY) * tile * 0.25
```

The fallback includes Bezier routes, animated path dashes, buildings, crowd marks, and smoke.

### Spaces

Spaces is the main working library. It contains:

- preset venue cartridges;
- local aggregate stats;
- recent SwiftData run history;
- navigation to complete run reports;
- settings and replayable tours.

Current presets are a startup office, nightclub, amphitheatre, transit platform, and lecture room. Presets provide a fast, accessible path into simulation.

### Learn

Learn includes a daily quiz and case studies.

The quiz currently has:

- ten questions;
- 120 seconds;
- three lives;
- `50 + 10 * (streak - 1)` points for a correct answer;
- one-life loss for a wrong answer or timeout;
- local session state rather than persisted daily completion history.

One playable atrium case is fictional and opens in the editor. A real-incident station platform learning entry is read-only. The current learning copy includes code-like and incident claims without a precise bibliography, so external citations and jurisdiction labels should be added before treating it as authoritative course material.

### Onboarding tours

The tour system uses SwiftUI anchor preferences to locate live controls, a reverse-mask spotlight, a guide mascot, typewriter text, optional sound blips, and `UserDefaults` flags for seen/replay state. There are separate tours for Spaces, editor, and simulation.

### Settings

Settings controls feedback, accessibility options, and tutorial replay and explains scoring and the educational disclaimer. The privacy claim is supported by the absence of network integrations in app source, local-only SwiftData configuration, the on-device Foundation Models API, and the privacy manifest. A release privacy audit should still be repeated whenever a dependency or capability is added.

---

## 25. UI Theme and Design System

### Product theme

The interface combines a warm editorial control shell with a dark simulation canvas and a procedural pixel-world visual language. It is intentionally not a generic blue or purple dashboard.

The visual split communicates mode:

- warm light surfaces: creation, navigation, learning, and reports;
- dark canvas: live simulation and spatial inspection;
- sage/green: safe or positive state;
- amber/gold: caution and congestion;
- terracotta/brick: hazard, failure, and casualty;
- teal/pink/plum: supporting categorical accents.

### Color tokens

| Token | Hex | Use |
|---|---|---|
| Ground | `#F4E8D0` | Main warm background |
| Surface raised | `#FBF4E4` | Controls and cards |
| Surface sunken | `#EADFC7` | Inset areas |
| Outline | `#2B2622` | Strong borders and dark canvas |
| Separator | `#CBB899` | Low-emphasis structure |
| Text primary | `#2B2622` | Main text |
| Text secondary | `#5A4D40` | Supporting text |
| Text tertiary | `#9E8E73` | Metadata |
| Sage | `#8DA85A` | Positive state |
| Deep sage | `#738A4A` | Strong positive state |
| Teal | `#4F9691` | Informational accent |
| Gold | `#D6A63C` | Warning/caution |
| Terracotta | `#C65D32` | Hazard |
| Brick | `#9E3521` | Failure/severe state |
| Pink | `#F3B6C0` | Supporting accent |
| Plum | `#8A5E74` | Supporting accent |
| Canvas raised | `#4C4239` | Dark-scene structure |
| Canvas separator | `#5A4D40` | Dark-scene lines |
| Canvas text | `#F4E8D0` | Text on dark canvas |

### Typography

The design maps roles to Apple's native font designs:

- display: New York/system serif;
- body: SF Rounded;
- data: SF Mono;
- micro labels: condensed system styling;
- accent: heavy system monospaced fallback.

Older plans mention DSEG and Press Start faces, but those custom fonts are not bundled in the current repository. Presentation materials should say "system serif/rounded/monospaced typography plus a custom bitmap font," not claim those external faces ship in the app.

### Pixel chrome

`PixelCornerRect` creates a stair-stepped rounded shape by quantizing a quarter-circle profile. It is used to give controls and panels a consistent retro-digital edge without relying on image slices.

### Layout tokens

- spacing follows a 4-point base family: 1, 2, 4, 8, 12, 16, 24, and 32;
- corner radii include 8, 12, 16, 20, 26, and 28;
- the minimum intended touch target is 44 points;
- fixed canvas controls and score elements use stable dimensions to prevent layout movement.

### Motion

Motion constants centralize springs and reveal durations. Score reveal lasts about 1.2 seconds and caps haptic ticks at eight. Reduce Motion is used to simplify animated behavior.

### Symbols

Buttons use SF Symbols through a registry with runtime fallback where a newer symbol is unavailable. The app avoids embedding custom SVG icons for standard controls.

---

## 26. Apple Technologies Used

| Apple technology | Exact role in Egress | Main implementation |
|---|---|---|
| Swift | Entire app and engine; value semantics, protocols, Codable, concurrency | All source |
| Swift SIMD | `SIMD2<Double>` positions, velocities, forces, dimensions | `Geometry/Vec2.swift` |
| Swift Package Manager | Separate reusable `EgressEngine`, no third-party package dependency | `EgressEngine/Package.swift` |
| SwiftUI | App structure, editor/results/learning UI, controls, layouts | `Egress/Egress/**/*.swift` |
| SwiftUI Canvas | Editor, simulation, procedural visuals, bitmap text | editor, rendering, landing, quiz art |
| `GraphicsContext` and `Path` | Immediate-mode batched vector-pixel drawing | `AgentSprites`, renderer, scenery |
| `TimelineView` | Animation-clock rendering for simulation and characters | simulation and pixel characters |
| Observation | `@Observable` models for editor, simulation, quiz, and feedback settings | model/controller files |
| UIKit | Multi-touch recognizers, haptic fallbacks, app appearance, touch indicators | input bridges, app entry, feedback |
| `UIViewRepresentable` | Transparent bridge from SwiftUI to UIKit gestures | `CanvasInputView`, `SimCanvasInputView` |
| Swift Concurrency | async coach calls, timeout race, main-actor UI ownership | AI and controllers |
| Foundation Models | Optional on-device structured RALLY wording | `AI/FoundationModelsCoach.swift` |
| SwiftData | Local run persistence | `Persistence/RunRecord.swift`, app dependencies |
| AVFoundation | Music, sound effects, mixed ambience, procedural audio fallback | `Feedback/SoundPlayer.swift` |
| Core Haptics | Three custom safety/verdict tactile signatures | `Feedback/Haptics.swift` |
| Accessibility APIs | VoiceOver labels/announcements and Reduce Motion paths | simulation/UI views |
| `ImageRenderer` | Off-screen run-report share image | `RunReportView.swift` |
| `ShareLink` | System share sheet for the report image | `RunReportView.swift` |
| `UserDefaults` / `@AppStorage` | Feedback and tutorial preferences | feedback, settings, tours |
| `ProcessInfo.thermalState` | Performance warning state | `SimulateRootView.swift` |
| SF Symbols | Standard control iconography | `DesignSystem/Symbols.swift` |
| Asset catalogs | App icon, hero, mascot, report/stat art, casualty image | `Assets.xcassets` |
| Privacy manifest | No tracking/collection declaration and UserDefaults reason | `PrivacyInfo.xcprivacy` |

### Technologies mentioned in old plans but not used by current app source

The current source does not import or implement Core Motion, PDFKit, Charts, TipKit, Metal APIs, or Accelerate. Xcode contains normal Metal compiler build settings, but that is not evidence of a custom Metal rendering pipeline. Canvas is the implemented renderer.

---

## 27. Determinism, Performance, and Memory Choices

### Determinism

- seeded SplitMix64 randomness;
- fixed physics and hazard clocks;
- stable iteration order for fire;
- start-of-step/Jacobi reads for agents and smoke;
- immutable render snapshots;
- visual random-looking effects use stable hashes instead of engine RNG;
- same-seed apply/rerun comparisons.

### Performance

- one reverse BFS rather than one search per agent;
- flat 1D row-major fields;
- SIMD vector values;
- spatial hashing rather than routine all-pairs checks;
- separable density blur;
- flow field rebuild only when active fire blockers change;
- batched character paths by color;
- zoom-based detail gates;
- decimated history snapshots;
- capped catch-up steps;
- bounded emote count and death-sound queue.

### Important claim boundary

The physics loop runs at 120 Hz, while Canvas redraws at display cadence. Therefore the correct statement is **"120 Hz fixed-step physics with display-speed Canvas rendering,"** not "the entire app renders at 120 FPS."

---

## 28. Tests and Verification

### Engine coverage map

| Area | Test files |
|---|---|
| Geometry and grid | `GeometryTests`, `BlockedCellsTests`, `RoomEnclosureTests`, `VenueTests` |
| Navigation | `FlowFieldTests`, `WallFieldTests` |
| Agents and RNG | `AgentSpawnerTests`, `SeededRNGTests`, `EmoteTrackerTests` |
| Spatial/density | `SpatialHashTests`, `DensityGridTests` |
| Hazards | `FireAutomatonTests`, `SmokeFieldTests`, `HazardFieldTests` |
| Simulation | `SimulationTests`, `SimulationPanicTests`, `FasterIsSlowerTests` |
| Metrics and standards | `MetricsTests`, `SafetyStandardsTests`, `SafetyScoreTests` |
| Verdicts | `VerdictRulesTests` |
| Events | `RunEventTests`, `RunEventLogTests`, `EscalationTrackerTests`, `SimulationEventsTests`, `SimulationEscalationTests` |
| Fixes | `FixTests`, `FixPlannerTests`, `RallyCoachTests`, `ApplyRerunTests` |
| Presets and test seam | `VenuePresetTests`, `MockSimulationTests` |

The tests exercise deterministic repeatability, finite/in-bounds simulation, collision/contact behavior, fire spread and casualties, panic, the faster-is-slower case, score/verdict boundaries, fix feasibility, and same-seed before/after reruns.

### App tests

`EgressTests.swift` verifies that `SimulationController` produces the same clearance and score under irregular display pacing when no catch-up backlog is dropped. The UI target currently contains Xcode template launch and launch-performance tests rather than complete journey assertions.

### Audit result

The engine suite was executed while preparing this guide:

```text
162 tests in 32 suites passed
```

This verifies the current package on the local macOS Swift toolchain. It does not replace iOS app, simulator, accessibility, or physical-device testing.

### Commands

From the repository root:

```bash
swift test --package-path EgressEngine
```

For the application, use the available iPhone simulator/device destination in Xcode or `xcodebuild`, for example:

```bash
xcodebuild \
  -project Egress/Egress.xcodeproj \
  -scheme Egress \
  -destination 'platform=iOS Simulator,name=<installed iPhone>' \
  test
```

Device testing remains necessary for Core Haptics feel, audio-session behavior, and Foundation Models availability.

---

## 29. File-by-File Source Guide

Paths in this section are relative to the repository root.

### Engine: geometry, standards, and venue

| File | Responsibility |
|---|---|
| `EgressEngine/Sources/EgressEngine/Geometry/Vec2.swift` | `SIMD2<Double>` alias and safe vector mathematics. |
| `EgressEngine/Sources/EgressEngine/Geometry/Grid.swift` | Hashable grid coordinate, four-neighbor traversal, and flat row-major indexing. |
| `EgressEngine/Sources/EgressEngine/Geometry/GridGeometry.swift` | Conversion between metres and grid cells. |
| `EgressEngine/Sources/EgressEngine/Standards/SafetyStandards.swift` | Cell/body size, density references, and minimum dimensions. |
| `EgressEngine/Sources/EgressEngine/Standards/SimConstants.swift` | Physics, density, fire, smoke, and timing constants. |
| `EgressEngine/Sources/EgressEngine/Standards/VerdictConstants.swift` | Score and verdict boundary constants. |
| `EgressEngine/Sources/EgressEngine/Venue/VenueElements.swift` | Walls, exits, obstacle classes, obstacles, water, and decor value types. |
| `EgressEngine/Sources/EgressEngine/Venue/VenueModel.swift` | Complete venue aggregate, gross/net area, and geometry ownership. |
| `EgressEngine/Sources/EgressEngine/Venue/VenueType.swift` | Venue categories and educational target times. |
| `EgressEngine/Sources/EgressEngine/Venue/VenuePreset.swift` | Built-in preset venue definitions and catalog. |

### Engine: rasterization and navigation

| File | Responsibility |
|---|---|
| `EgressEngine/Sources/EgressEngine/Navigation/BlockedCells.swift` | Rasterizes authored geometry into movement blockers. |
| `EgressEngine/Sources/EgressEngine/Navigation/RoomEnclosure.swift` | Border flood-fill that distinguishes free-form room interior from exterior. |
| `EgressEngine/Sources/EgressEngine/Navigation/FlowField.swift` | Multi-source BFS cost field and local route gradient. |
| `EgressEngine/Sources/EgressEngine/Navigation/WallField.swift` | Nearest-wall distance/source field for collision forces. |

### Engine: agents and spatial lookup

| File | Responsibility |
|---|---|
| `EgressEngine/Sources/EgressEngine/Agent/AgentKinds.swift` | Mobility, emotion, and status enums plus speed/radius behavior. |
| `EgressEngine/Sources/EgressEngine/Agent/Agent.swift` | Mutable per-person engine state. |
| `EgressEngine/Sources/EgressEngine/Agent/AgentSpawner.swift` | Seeded mixed-mobility spawning on distinct reachable cells. |
| `EgressEngine/Sources/EgressEngine/Agent/Emote.swift` | Observation rules and lifetime tracking for visual emotes. |
| `EgressEngine/Sources/EgressEngine/Spatial/SpatialHash.swift` | Uniform-bin local-neighbor lookup for crowd forces. |

### Engine: hazards

| File | Responsibility |
|---|---|
| `EgressEngine/Sources/EgressEngine/Hazards/FireAutomaton.swift` | Seeded cellular fire state and probabilistic spread. |
| `EgressEngine/Sources/EgressEngine/Hazards/SmokeField.swift` | Emission, four-neighbor diffusion, decay, and clamping. |
| `EgressEngine/Sources/EgressEngine/Hazards/HazardField.swift` | Coordinates 15 Hz fire/smoke updates and exposes active blockers. |

### Engine: simulation and metrics

| File | Responsibility |
|---|---|
| `EgressEngine/Sources/EgressEngine/Simulation/SimulationRunning.swift` | Configuration and protocol seam shared by real/mock simulation. |
| `EgressEngine/Sources/EgressEngine/Simulation/Simulation.swift` | Main deterministic clock, physics, routing, hazards, casualty, metric, and event integration. |
| `EgressEngine/Sources/EgressEngine/Simulation/SimulationSnapshot.swift` | Immutable app/render transfer objects. |
| `EgressEngine/Sources/EgressEngine/Simulation/DensityGrid.swift` | Flat density field and separable neighborhood estimator. |
| `EgressEngine/Sources/EgressEngine/Simulation/Metrics.swift` | Clearance, peak density, dwell risk, casualty, trapped, and live metric accumulation. |
| `EgressEngine/Sources/EgressEngine/Simulation/SeededRNG.swift` | SplitMix64 deterministic random generator. |
| `EgressEngine/Sources/EgressEngine/Simulation/MockSimulation.swift` | Test/demonstration implementation of the simulation protocol. |

### Engine: events, verdicts, and fixes

| File | Responsibility |
|---|---|
| `EgressEngine/Sources/EgressEngine/Events/RunEvent.swift` | Typed event record and event vocabulary. |
| `EgressEngine/Sources/EgressEngine/Events/RunEventLog.swift` | Ordered log and derived summary. |
| `EgressEngine/Sources/EgressEngine/Events/EscalationTracker.swift` | Priority, cooldown, suppression, and rearm logic for live warnings. |
| `EgressEngine/Sources/EgressEngine/Verdict/SafetyScore.swift` | Reproducible 0-100 penalty formula. |
| `EgressEngine/Sources/EgressEngine/Verdict/Verdict.swift` | PASS/WARN/FAIL and structured reason types. |
| `EgressEngine/Sources/EgressEngine/Verdict/VerdictRules.swift` | Rule-authoritative verdict resolution. |
| `EgressEngine/Sources/EgressEngine/Rally/Fix.swift` | Geometry fix values, basic feasibility, and application to a venue. |
| `EgressEngine/Sources/EgressEngine/Rally/FixPlanner.swift` | Collision-aware deterministic search for obstacle/new-exit placement. |
| `EgressEngine/Sources/EgressEngine/Rally/RallyCoach.swift` | Deterministic primary recommendation from final engine results. |

### App entry and composition

| File | Responsibility |
|---|---|
| `Egress/Egress/EgressApp.swift` | SwiftUI app entry, appearance, dependencies, model container, and lifecycle feedback handling. |
| `Egress/Egress/App/AppDependencies.swift` | Live dependency and local SwiftData container construction. |
| `Egress/Egress/App/AppRoot.swift` | Landing gate, app navigation, modal editor/simulation routes, and dark canvas host. |
| `Egress/Egress/App/EgressTabBar.swift` | Spaces/Learn tab bar and central create action. |

### Design system

| File | Responsibility |
|---|---|
| `Egress/Egress/DesignSystem/Color+Tokens.swift` | Warm shell, dark canvas, semantic verdict, and accent colors. |
| `Egress/Egress/DesignSystem/Typography.swift` | Native display/body/data/micro/accent font roles. |
| `Egress/Egress/DesignSystem/Layout.swift` | Spacing, radius, touch-size, and layout constants. |
| `Egress/Egress/DesignSystem/Materials.swift` | Reusable surface/material styling. |
| `Egress/Egress/DesignSystem/Motion.swift` | Central animation/reveal timing and Reduce Motion choices. |
| `Egress/Egress/DesignSystem/PixelChrome.swift` | Stair-step shapes, Canvas bitmap text, glyph data, and stat glyphs. |
| `Egress/Egress/DesignSystem/Symbols.swift` | SF Symbol registry and availability fallback. |
| `Egress/Egress/DesignSystem/EgressButtonStyle.swift` | Branded sound-aware button behavior. |
| `Egress/Egress/DesignSystem/MarkdownText.swift` | Styled rendering for limited rich copy. |
| `Egress/Egress/DesignSystem/TypewriterText.swift` | Progressive text used by guided experiences. |
| `Egress/Egress/DesignSystem/TouchIndicators.swift` | Optional passive UIKit touch visualization for demos. |

### Editor

| File | Responsibility |
|---|---|
| `Egress/Egress/Editor/EditorModel.swift` | Complete editor state machine, validation, normalization, selection, and venue conversion. |
| `Egress/Egress/Editor/EditorCamera.swift` | World rectangle and pan/zoom/fit camera mathematics. |
| `Egress/Egress/Editor/EditorProp.swift` | Editor-facing prop metadata and conversion. |
| `Egress/Egress/Editor/CanvasInputView.swift` | UIKit one/two-finger and pinch gesture bridge. |
| `Egress/Egress/Editor/EditorCanvasView.swift` | SwiftUI Canvas editor rendering and input overlay. |
| `Egress/Egress/Editor/EditorPropLibrarySheet.swift` | Categorized prop chooser. |
| `Egress/Egress/Editor/EditorRootView.swift` | Complete editor screen, tools, property/config sheets, and run action. |

### Simulation UI and controller

| File | Responsibility |
|---|---|
| `Egress/Egress/Features/Simulate/SimulationController.swift` | Main-actor fixed-step driver, snapshots, history, camera, result, and apply/rerun state. |
| `Egress/Egress/Features/Simulate/RunResult.swift` | App result aggregate connecting engine result and coaching. |
| `Egress/Egress/Features/Simulate/SampleVenue.swift` | Small sample venue helper used by app/test contexts. |
| `Egress/Egress/Features/Simulate/SimulateRootView.swift` | Simulation composition, lifecycle, persistence, feedback, and result presentation. |
| `Egress/Egress/Features/Simulate/SimCanvasView.swift` | Timeline-driven Canvas and interaction overlay. |
| `Egress/Egress/Features/Simulate/SimCanvasRenderer.swift` | Projection and ordered scenery/density/hazard/crowd draw passes. |
| `Egress/Egress/Features/Simulate/SimCanvasInputView.swift` | UIKit simulation pan/pinch/tap bridge. |
| `Egress/Egress/Features/Simulate/SimHUD.swift` | Live time, evacuation, density, and status chips. |
| `Egress/Egress/Features/Simulate/SimTransport.swift` | Timeline, play/pause, stepping, scrubbing, and live controls. |
| `Egress/Egress/Features/Simulate/SimZoomControls.swift` | Camera zoom control. |
| `Egress/Egress/Features/Simulate/EscalationBanner.swift` | Priority live warning presentation. |
| `Egress/Egress/Features/Simulate/RallyLiveCard.swift` | RALLY mascot and live contextual card. |
| `Egress/Egress/Features/Simulate/ResultsSheet.swift` | Score/verdict/reasons/fix/coach UI and apply action. |
| `Egress/Egress/Features/Simulate/SimulateStateViews.swift` | Empty, loading, background-pause, and performance-notice states. |

### Rendering

| File | Responsibility |
|---|---|
| `Egress/Egress/Rendering/VenueScenery.swift` | Shared editor/simulation drawing for venue elements. |
| `Egress/Egress/Rendering/AgentSprites.swift` | Procedural character materials, silhouettes, animation, batching, expressions, and emotes. |
| `Egress/Egress/Rendering/PixelCharacter.swift` | Timeline-driven reusable character view and stable string seed. |

### AI coaching

| File | Responsibility |
|---|---|
| `Egress/Egress/AI/Coach.swift` | Coach protocol, advice value, and source badge. |
| `Egress/Egress/AI/CoachFacts.swift` | Engine fact serialization and approved numeric grounding set. |
| `Egress/Egress/AI/CannedCoach.swift` | Deterministic guaranteed coaching templates. |
| `Egress/Egress/AI/DeviceCapabilities.swift` | Compile/runtime Foundation Models availability check. |
| `Egress/Egress/AI/FoundationModelsCoach.swift` | Structured session, timeout, prompts, grounding, validation, and fallback. |
| `Egress/Egress/AI/CoachProvider.swift` | Chooses Foundation Models or canned execution path. |

### Feedback and persistence

| File | Responsibility |
|---|---|
| `Egress/Egress/Feedback/FeedbackSettings.swift` | Observable sound/haptic/accessibility preferences backed by defaults. |
| `Egress/Egress/Feedback/FeedbackServices.swift` | Coordinates sound and haptics for app events. |
| `Egress/Egress/Feedback/SoundPlayer.swift` | AVAudioEngine graph, assets, procedural fallback, ambience, queueing, and lifecycle. |
| `Egress/Egress/Feedback/Haptics.swift` | Core Haptics patterns, UIKit fallbacks, budgeting, and lifecycle. |
| `Egress/Egress/Persistence/RunRecord.swift` | SwiftData model and versioned Codable report snapshot. |

### Landing, Spaces, Learn, onboarding, and settings

| File | Responsibility |
|---|---|
| `Egress/Egress/Features/Landing/LandingView.swift` | Brand entry, CTA, hero asset, and procedural isometric fallback. |
| `Egress/Egress/Features/Spaces/SpacesRootView.swift` | Presets, statistics, recent local runs, settings, and report navigation. |
| `Egress/Egress/Features/Spaces/PresetCard.swift` | Cartridge-style preset card and generated venue thumbnail. |
| `Egress/Egress/Features/Spaces/RunReportView.swift` | Full saved report, ImageRenderer share card, and ShareLink. |
| `Egress/Egress/Features/Learn/CaseStudy.swift` | Case-study/quiz source content and playable venue model. |
| `Egress/Egress/Features/Learn/CaseStudyDetailView.swift` | Case-study explanation and playable/read-only action. |
| `Egress/Egress/Features/Learn/LearnRootView.swift` | Learn library and quiz entry. |
| `Egress/Egress/Features/Learn/Quiz.swift` | Quiz question value model/content. |
| `Egress/Egress/Features/Learn/QuizGameModel.swift` | Observable timer, life, streak, answer, and score state machine. |
| `Egress/Egress/Features/Learn/QuizGameView.swift` | Complete interactive quiz UI and result states. |
| `Egress/Egress/Features/Learn/QuizArt.swift` | Procedural mascot, heart, bubble, and pixel-plus art. |
| `Egress/Egress/Features/Onboarding/TourModels.swift` | Tour IDs, steps, legends, and anchor preference keys. |
| `Egress/Egress/Features/Onboarding/Tours.swift` | Spaces/editor/simulation tour content. |
| `Egress/Egress/Features/Onboarding/TourHost.swift` | Tour state, seen flags, sequencing, and overlay attachment. |
| `Egress/Egress/Features/Onboarding/TourOverlay.swift` | Spotlight, guide, arrows, copy, and tour controls. |
| `Egress/Egress/Features/Settings/SettingsSheet.swift` | Feedback/accessibility/tutorial settings, score explanation, privacy, and disclaimer. |

### Tests and support files

| Location | Responsibility |
|---|---|
| `EgressEngine/Tests/EgressEngineTests/*.swift` | 32 focused Swift Testing suites for engine algorithms and integration. |
| `Egress/EgressTests/EgressTests.swift` | App controller fixed-step determinism under irregular timestamps. |
| `Egress/EgressUITests/EgressUITests.swift` | Basic launch and launch-performance tests; feature journeys remain to be added. |
| `Egress/EgressUITests/EgressUITestsLaunchTests.swift` | Launch screenshot/test template. |
| `Egress/Egress/PrivacyInfo.xcprivacy` | Privacy declarations and required-reason API declaration. |
| `Config/Shared.xcconfig` | Deployment, Swift concurrency, identity defaults, and AI compile flag. |
| `Config/Debug.xcconfig` / `Release.xcconfig` | Configuration includes and debug/release specialization. |

---

## 30. Assets and Resources

### Image assets

- `AppIcon`: application identity;
- `landing_hero`: main landing artwork;
- `guide_mascot`: onboarding guide;
- `cartridge_frame`: preset visual frame;
- `coffin`: current casualty visual;
- `stat_runs`, `stat_best`, `stat_last`: Spaces statistic art;
- `sprite_1` through `sprite_31`: bundled visual sprite assets used by branded UI/art contexts.

Live crowd animation still comes from `AgentSprites.swift`; the existence of bundled sprite assets does not change the procedural simulation-character pipeline.

### Sound assets

```text
background_theme.mp3
button_tap.mp3
crowd_murmur.mp3
death_female.mp3
death_impact.mp3
death_male.mp3
popup.mp3
sim_fail.mp3
sim_success.mp3
start_sim.mp3
warning_alarm.mp3
```

---

## 31. Known Limitations and Honest Claim Boundaries

1. **Educational, not certified.** Thresholds and targets require domain validation and jurisdiction-specific references before real safety use.
2. **No formal source bibliography.** Code comments refer to pedestrian-density concepts, but the repository does not provide enough primary references to support regulatory claims.
3. **Smoke is visual only.** It does not affect health, route choice, visibility, speed, or score.
4. **Water is static blocking only.** It has no hazard evolution or physical effect beyond no-go cells.
5. **Rectangular obstacle area is approximate.** Overlaps can be double-subtracted and water is not subtracted from net area.
6. **Four-neighbor BFS.** Route cost has Manhattan-grid discretization; it is not navmesh/A* with continuous travel-time weighting.
7. **Simplified crowd model.** Agents do not learn, communicate, form family groups, remember obstacles, stumble, or make probabilistic decisions.
8. **Current fire injury is immediate.** There is no heat-dose or smoke-inhalation model.
9. **Completion can preserve `injured`.** A run can stop when no active agents remain before every injured agent ages to `dead`.
10. **Visual and policy density bands differ.** UI uses 2/4/6 while scoring/verdict logic uses 1.8/5/7 references.
11. **Some event cases are unused.** `hazardSpread`, `jam`, and `progress` are defined but not emitted by the current main loop.
12. **Event summary is not used by AI.** Coaching is based on final facts, not a narrative analysis of the full event log.
13. **Thermal handling is notification-only.** The UI warns, but rendering detail is not dynamically reduced by the current code.
14. **Foundation Models availability varies.** Canned coaching is a first-class path, not an error screen.
15. **Generated prose validation has scope.** It strongly grounds numbers and geometry references but does not mathematically prove every natural-language implication.
16. **UI tests are incomplete.** Engine coverage is substantial, but end-to-end XCUITest journeys are not yet implemented.
17. **Learning content needs citations.** Building-code-like quiz claims and the real incident entry need exact authoritative sources.
18. **Build settings are inconsistent.** README, xcconfig, and target overrides should be aligned before release.
19. **Custom display font plans changed.** DSEG/Press Start are not bundled; native and custom bitmap rendering are used.
20. **No custom Metal pipeline.** SwiftUI Canvas is the renderer.

---

## 32. Presentation-Ready Technical Summary

### Architecture slide headline

**From a finger stroke to a living crowd.**

### Visible slide content

```text
CREATE              COMPUTE              BRING TO LIFE         UNDERSTAND
SwiftUI Editor  ->  Pure-Swift Engine -> Canvas Characters -> Verdict + RALLY

Canvas + UIKit      Flat SIMD grids       TimelineView          Deterministic result
@Observable         BFS + social forces   Batched Paths         Foundation Models wording
                    Fire automaton
```

Bottom line:

**Pure Swift | Deterministic | Fully on device | No game engine | No cloud**

### 35-second speaker script

> The experience begins in our SwiftUI editor. Canvas renders the venue, while UIKit gestures translate drawing, pinching, and panning into a simulation-ready model. The pure-Swift engine converts that geometry into flat quarter-metre grids, computes one shortest-path field for every exit, and advances the crowd with 120-hertz social-force physics, spatial hashing, and a separate fire cellular automaton. Each immutable snapshot returns to TimelineView and Canvas, where Swift generates and batches hundreds of pixel characters. Finally, deterministic code calculates the metrics, score, verdict, and feasible geometry fix. Apple's on-device Foundation Model only turns those verified results into clear coaching.

### High-value technical one-liners

- **Geometry becomes data:** touch-authored metres become flat 0.25 m fields.
- **One search guides everyone:** multi-source BFS computes the nearest reachable exit for every cell.
- **Urgency can create delay:** social-force contact and friction produce faster-is-slower bottlenecks.
- **Local neighbors, not every pair:** spatial hashing avoids routine `O(N^2)` checks.
- **Hazards have their own clock:** fire and smoke update deterministically at 15 Hz.
- **Characters are generated, not replayed:** stable IDs create mobility-aware people and walking poses.
- **The engine decides; AI explains:** score, verdict, and feasible geometry remain deterministic.

---

## 33. Glossary

| Term | Meaning in this project |
|---|---|
| Agent | One simulated person. |
| Arousal | Emotional-state multiplier applied to desired walking speed. |
| BFS | Breadth-first search; exact shortest cell-step search on an unweighted grid. |
| Cellular automaton | A grid process where a cell's next state depends on its current state and neighbors. |
| Density | Smoothed nearby body count divided by a fixed physical neighborhood area. |
| Deterministic | Same inputs and seed produce the same sequence of engine results. |
| Flow field | Per-cell route cost and direction toward the nearest reachable exit. |
| Foundation Models | Apple's framework used here for optional on-device structured wording. |
| Jacobi update | Compute every next value from one unchanged previous snapshot. |
| RALLY | The app's coaching layer and mascot; deterministic facts with optional model wording. |
| SIMD | Compact vector type used for two-dimensional numeric operations. |
| Social-force model | Desired motion plus interpersonal and wall repulsion/contact forces. |
| Spatial hash | Uniform grid bins used to find nearby agents efficiently. |
| Snapshot | Immutable render-facing copy of current simulation state. |
| Verdict | Deterministic PASS, WARN, or FAIL result from explicit rules. |

---

## 34. Recommended Next Engineering Actions

1. Align toolchain and deployment settings across README, xcconfig, and target overrides.
2. Add a primary-source bibliography and label every educational threshold by source/jurisdiction.
3. Decide whether visual density bands should exactly match policy thresholds.
4. Add smoke exposure/visibility behavior only if it can be tested and clearly explained.
5. Wire useful event-log summaries into coaching facts if temporal narrative is desired.
6. Implement actual render-detail degradation or revise the thermal notice wording.
7. Add XCUITests for preset -> run -> result -> apply -> rerun -> report.
8. Add device test records for Foundation Models, sound session, and Core Haptics.
9. Audit stale comments and old plan documents so presentation claims follow shipped code.

This guide should be updated whenever an algorithm, constant, Apple framework, or user-facing claim changes.
