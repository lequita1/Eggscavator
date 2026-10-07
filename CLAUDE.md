\# Eggscavator — Project Instructions



\## Project Identity



\*\*Eggscavator\*\* is a Roblox egg excavation simulator being substantially revamped.



Core fantasy:



> Excavate → Discover → Deliver → Progress



The player excavates eggs using tools, collects materials, sells them, upgrades tools, eventually breaks deeper egg layers, discovers a hatchling, delivers the hatchling, and watches it reunite with its mama.



The hatch/reunion sequence is an important part of the game's identity and should not be casually removed.



\---



\## Source of Truth



The repository is the persistent memory shared between different Claude sessions.



Never assume the current conversation contains the entire project history.



Before making changes:



1\. Read `PROJECT\_STATE.md`.

2\. Read `HANDOFF.md`.

3\. Read `TASKS.md`.

4\. Read `DECISIONS.md`.

5\. Inspect the actual source code.

6\. Verify documentation against the implementation.



The actual Roblox place files are:



\* `Eggscavator\_Main.rbxl` — current/main place

\* `Eggscavator\_Old.rbxl` — older reference/backup place



Do not delete or overwrite either place unless explicitly instructed.



\---



\## Current Source Layout



Script Sync currently mirrors Roblox Studio source code into:



```text

src/

├── client/

├── server/

└── shared/

```



Current important areas:



```text

src/server/ServerScriptService/

src/server/ServerScriptService/Services/



src/client/StarterPlayerScripts/

src/client/StarterPlayerScripts/Controllers/

src/client/StarterPlayerScripts/UI/



src/shared/Shared/

```



Do not arbitrarily rename or restructure these paths while Script Sync is being used.



\---



\## Architecture



The game uses a client/server Roblox architecture.



\### Server



The server is authoritative for important gameplay state.



Important systems currently include:



\* PlayerDataService

\* EggService

\* ToolService

\* ShopService

\* RoundService

\* InventoryService

\* PieceService

\* StationTeleportService

\* ClimbService



Important gameplay, economy, rewards, progression, and ownership decisions must remain server-authoritative.



Never trust the client to award money, items, progression, or ownership.



\### Client



The client handles input, presentation, animation, effects, and UI.



Important client systems include:



\* ToolController

\* ReactController

\* EggView

\* EggAtmosphere

\* PickupController

\* HatchCutscene

\* ReleaseCutscene

\* DinoLife

\* ClientMain

\* UI modules



\### Shared



Shared definitions currently live under:



```text

src/shared/Shared/

```



Important modules include:



\* GameConfig

\* ToolDefinitions

\* EggDefinitions

\* ItemDefinitions

\* Util

\* Curator

\* DinoAnimator

\* HatchlingProp



\---



\## Existing UI



The game already uses ReactLua for UI.



Existing UI source is under:



```text

src/client/StarterPlayerScripts/UI/

```



Do not replace the UI architecture just because a different UI technology is popular.



Improve the existing architecture when practical.



\---



\## Development Philosophy



This is a \*\*revamp\*\*, not an excuse to blindly rewrite everything.



Before replacing an existing system:



1\. Understand it.

2\. Determine what currently works.

3\. Determine what is weak or broken.

4\. Preserve useful behavior.

5\. Replace only what actually needs replacement.



Avoid unnecessary rewrites.



Avoid generic simulator mechanics that do not strengthen the game's core identity.



Do not add features merely because other simulator games have them.



\---



\## Debugging



When a problem appears:



1\. Reproduce or inspect the problem.

2\. Find the root cause.

3\. Fix the correct system.

4\. Verify the fix.

5\. Document important discoveries.



Do not stack random patches.



\---



\## Git



GitHub is the shared synchronization layer between Claude sessions.



Before meaningful work:



```text

git status

git log --oneline -5

```



After meaningful work:



\* review the diff

\* update project documentation

\* create a logical commit when appropriate

\* push the changes



Never discard another session's work without understanding it first.



\---



\## Multi-Session Continuity



Multiple Claude sessions may work on this repository.



A session must never leave important knowledge only inside its conversation.



Important discoveries and project state must be written to:



\* `PROJECT\_STATE.md`

\* `TASKS.md`

\* `DECISIONS.md`

\* `HANDOFF.md`



When approaching a context or usage limit, update `HANDOFF.md` before stopping.



The next session must be able to continue without asking the user to re-explain the whole project.



\---



\## Session Start



At the beginning of a session:



```text

1\. Read CLAUDE.md

2\. Read HANDOFF.md

3\. Read PROJECT\_STATE.md

4\. Read TASKS.md

5\. Read DECISIONS.md

6\. Inspect Git status

7\. Inspect recent commits

8\. Verify the documented state against the actual code

9\. Continue from the highest-priority unfinished task

```



\---



\## Session End



Before stopping after meaningful work:



```text

1\. Verify the implementation

2\. Update PROJECT\_STATE.md

3\. Update TASKS.md

4\. Update HANDOFF.md

5\. Update DECISIONS.md when an important decision was made

6\. Update CHANGELOG.md when appropriate

7\. Review git diff

8\. Commit when appropriate

9\. Push when appropriate

```



Never claim unfinished work is complete.



\---



\## Important Existing Development Notes



The old project analysis identifies:



\* round-based egg excavation

\* layered egg progression

\* tool power gating

\* tool upgrades

\* inventory and selling

\* player data persistence

\* cooperative climbing

\* hatchling reveal

\* hatchling delivery

\* mama reunion

\* ReactLua UI



These notes are useful starting information, but they are \*\*not automatically authoritative\*\*.



Always verify claims against the actual implementation.


# SESSION CONTINUATION / CONTEXT LIMIT PROTOCOL

A Claude session may reach a conversation, context, usage, or execution limit while a task is only partially complete.

A limit is NOT considered a completed task.

Before stopping because of a limit, the current session MUST persist enough information for another Claude session to continue.

## Before Stopping

The session must:

1. Save all completed work.
2. Save all important discoveries.
3. Update `PROJECT_STATE.md`.
4. Update `TASKS.md`.
5. Update `HANDOFF.md`.
6. Update `DECISIONS.md` if a meaningful decision was made.
7. Review `git diff`.
8. Commit the work.
9. Push the commit to GitHub.

## HANDOFF.md Must Explain

* what the session was trying to accomplish
* what has been completed
* what is currently in progress
* the exact point where work stopped
* files that were changed
* files that still need changes
* known bugs
* known risks
* important discoveries
* decisions that were made
* what should happen next
* the exact recommended first action for the next session

Do NOT write vague handoffs such as:

> "Continue the revamp."

Instead write a precise continuation point such as:

> "EggService layer-generation refactor is 70% complete. Layer 1 and Layer 2 now use the new patch metadata structure. Layer 3 is not migrated yet. Do not modify ToolService. Next: finish the Layer 3 conversion in EggService.lua, then run the existing egg-break test."

## Next Session Protocol

A new Claude session MUST assume that the previous session may have stopped unexpectedly.

Before doing new work:

1. Read `CLAUDE.md`.
2. Read `HANDOFF.md`.
3. Read `PROJECT_STATE.md`.
4. Read `TASKS.md`.
5. Read `DECISIONS.md`.
6. Run `git status`.
7. Run `git log --oneline -5`.
8. Inspect the latest commit.
9. Verify the handoff against the actual code.
10. Continue from the documented stopping point.

Do NOT ask the project owner to repeat the previous session's work unless the repository is genuinely missing the required information.

## Repository Is the Source of Continuity

The previous Claude conversation is NOT the source of truth.

GitHub + repository files are the source of truth.

A new Claude session must be able to continue from the repository even when the previous conversation is unavailable.

## Never Claim Partial Work Is Complete

If a session is interrupted during a task:

* mark it `[~]` in `TASKS.md`
* document exactly what remains in `HANDOFF.md`
* do not mark it `[x]`

## Push Before Handoff

A handoff that exists only in the local working directory is NOT sufficient.

The current session should push the handoff commit to GitHub whenever practical before stopping.

The next session should always begin from the latest pushed repository state.



\---



\## Known Development Item



There is a development-only money helper:



```text

DevMoney

```



It must not remain enabled in the production version unless intentionally redesigned.



\---



\## General Rule



Think like one engineer in a continuous team.



Do not start the project from scratch every time a new Claude session starts.



Inherit the repository state, verify it, improve it, document it, and leave it ready for the next engineer.



