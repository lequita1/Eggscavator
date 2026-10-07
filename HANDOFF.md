\# Eggscavator — Session Handoff



\## Current Session



Session: Initial repository setup

Date: 2026-10-07



\## Current Objective



Set up Eggscavator as a persistent multi-session development project so different Claude sessions can continue the work from the same repository without losing context.



\## Current Project Phase



Repository and source-code migration.



\## Completed



\* Saved `Eggscavator\_Main.rbxl` locally.

\* Saved `Eggscavator\_Old.rbxl` locally.

\* Initialized Git repository.

\* Created `.gitignore`.

\* Created initial Git commit.

\* Created GitHub repository.

\* Connected local repository to GitHub.

\* Pushed the initial place backup to GitHub.

\* Synchronized ServerScriptService source to `src/server`.

\* Synchronized StarterPlayerScripts source to `src/client`.

\* Synchronized ReplicatedStorage.Shared source to `src/shared`.

\* Created `CLAUDE.md`.

\* Created `PROJECT\_STATE.md`.



\## Current Repository Structure



```text

Eggscavator/

├── Eggscavator\_Main.rbxl

├── Eggscavator\_Old.rbxl

├── CLAUDE.md

├── PROJECT\_STATE.md

├── ScriptNames.md

├── game.md

├── .gitignore

└── src/

&#x20;   ├── client/

&#x20;   ├── server/

&#x20;   └── shared/

```



\## Important Source



\### Server



Located under:



```text

src/server/ServerScriptService/

```



Important services:



\* EggService

\* InventoryService

\* PieceService

\* PlayerDataService

\* RoundService

\* ShopService

\* StationTeleportService

\* ToolService



\### Client



Located under:



```text

src/client/StarterPlayerScripts/

```



Includes:



\* ClientMain

\* HatchCutscene

\* ReleaseCutscene

\* DinoLife

\* MotherHider

\* LayerHUD

\* EggProgress

\* FirstPerson

\* ViewModel

\* SellFly

\* ClimbController

\* ShopTags

\* EggMonster

\* Controllers

\* UI



\### Shared



Located under:



```text

src/shared/Shared/

```



Includes:



\* GameConfig

\* ToolDefinitions

\* EggDefinitions

\* ItemDefinitions

\* Curator

\* DinoAnimator

\* HatchlingProp

\* Util



\## Important Existing Game Flow



```text

Lobby

→ Round

→ Egg Arena

→ Excavate Egg

→ Collect Materials

→ Sell

→ Earn Money

→ Upgrade Tools

→ Excavate Deeper

→ Break Egg

→ Hatchling Reveal

→ Hatchling Delivery

→ Mama Reunion

→ Repeat

```



\## Work In Progress



The repository migration is not completely finished.



The following still need to be addressed:



\* persistent task tracking

\* decision log

\* changelog

\* remaining relevant project documentation

\* asset migration strategy

\* full inspection of the actual source code

\* revamp planning

\* revamp implementation



\## Known Issues / Warnings



\* `DevMoney` is development-only and should not remain enabled for production.

\* The older place file must be preserved.

\* Do not delete existing assets simply because they appear unused until their purpose is understood.

\* Documentation generated inside the Roblox project may describe intended architecture rather than actual implementation.

\* The actual code must always be treated as more authoritative than old analysis notes.



\## Current Next Task



Create:



```text

TASKS.md

DECISIONS.md

CHANGELOG.md

```



Then commit the persistent project documentation.



After that, inspect the current source code and determine what should actually be revamped before making large changes.



\## What the Next Session Should Do



Read:



1\. `CLAUDE.md`

2\. `PROJECT\_STATE.md`

3\. `HANDOFF.md`

4\. `TASKS.md`

5\. `DECISIONS.md`



Then check:



```text

git status

git log --oneline -5

```



Verify the documented state against the actual repository before making changes.



Do not restart the project from scratch.



\## GitHub



Repository:



`https://github.com/lequita1/Eggscavator`



Branch:



`main`



\## Handoff Rule



Before ending a meaningful session, update this file with:



\* what was completed

\* what is currently in progress

\* what is broken

\* important discoveries

\* files changed

\* exact next task



The next Claude session must be able to continue without needing the previous conversation.



