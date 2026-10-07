\# Eggscavator — Project State



\## Current Status



The existing Roblox game has been exported from Roblox Studio and its source scripts are now synchronized to the local filesystem.



The repository is connected to GitHub:



`https://github.com/lequita1/Eggscavator`



Current branch:



`main`



\## Local Project



```text

E:\\Projects\\Self\\Eggscavator

```



\## Place Files



```text

Eggscavator\_Main.rbxl

Eggscavator\_Old.rbxl

```



`Eggscavator\_Main.rbxl` is the current/main place.



`Eggscavator\_Old.rbxl` is the older version and should be preserved as a reference/backup.



\## Current Source Structure



```text

src/

├── client/

│   └── StarterPlayerScripts/

│       ├── ClientMain.local.luau

│       ├── ClimbController.local.luau

│       ├── DinoLife.local.luau

│       ├── EggMonster.local.luau

│       ├── EggProgress.local.luau

│       ├── FirstPerson.local.luau

│       ├── HatchCutscene.local.luau

│       ├── LayerHUD.local.luau

│       ├── MotherHider.local.luau

│       ├── ReleaseCutscene.local.luau

│       ├── SellFly.local.luau

│       ├── ShopTags.local.luau

│       ├── ViewModel.local.luau

│       ├── Controllers/

│       └── UI/

│

├── server/

│   └── ServerScriptService/

│       ├── ClimbService.legacy.luau

│       ├── DevMoney.legacy.luau

│       ├── EggSim.legacy.luau

│       ├── EggSweepTest.legacy.luau

│       ├── Main.legacy.luau

│       ├── WorldCheck.legacy.luau

│       └── Services/

│           ├── EggService.luau

│           ├── InventoryService.luau

│           ├── PieceService.luau

│           ├── PlayerDataService.luau

│           ├── RoundService.luau

│           ├── ShopService.luau

│           ├── StationTeleportService.luau

│           └── ToolService.luau

│

└── shared/

&#x20;   └── Shared/

&#x20;       ├── Curator.luau

&#x20;       ├── DinoAnimator.luau

&#x20;       ├── EggDefinitions.luau

&#x20;       ├── GameConfig.luau

&#x20;       ├── HatchlingProp.luau

&#x20;       ├── ItemDefinitions.luau

&#x20;       ├── ToolDefinitions.luau

&#x20;       └── Util.luau

```



\## Existing Game Concept



Eggscavator is an egg excavation/mining simulator.



Core loop:



```text

Join

→ enter lobby

→ round starts

→ teleport to egg arena

→ excavate egg

→ collect shells/materials

→ sell materials

→ earn money

→ buy/upgrade tools

→ excavate deeper

→ break the egg

→ reveal hatchling

→ deliver hatchling

→ hatchling reunites with mama

→ continue progression

```



\## Existing Major Systems



\### Server



\* Main

\* WorldCheck

\* EggSim

\* EggSweepTest

\* ClimbService

\* DevMoney

\* InventoryService

\* EggService

\* PlayerDataService

\* ToolService

\* ShopService

\* RoundService

\* StationTeleportService

\* PieceService



\### Client



\* ClientMain

\* HatchCutscene

\* DinoLife

\* ReleaseCutscene

\* MotherHider

\* LayerHUD

\* EggProgress

\* FirstPerson

\* ViewModel

\* SellFly

\* ClimbController

\* ShopTags

\* EggMonster

\* ToolController

\* ReactController

\* EggView

\* EggAtmosphere

\* PickupController



\### UI



The game currently uses ReactLua.



Current UI source includes:



\* App

\* Theme

\* Store

\* Kit

\* Journal

\* Hotbar

\* ShopPanel

\* SellPopup

\* Notifications

\* Results

\* LootFeed

\* Announcer

\* Sounds

\* Effects

\* ShopStage

\* Button

\* Label

\* Panel

\* related story modules



\## Existing Game Assets



Important existing assets are currently inside the Roblox place:



\* egg models

\* egg patches

\* yolk mesh

\* dinosaur rig

\* hatchling-related assets

\* tools

\* map decorations

\* sell station

\* tool shop

\* delivery spot

\* hatch stage

\* climb rig

\* game sounds

\* other world assets



These have not all been converted into filesystem assets yet.



\## Current Revamp Goal



The game is being substantially redesigned and polished.



The intended identity is:



> A polished excavation/discovery adventure with simulator progression.



The most important emotional sequence is:



```text

Find egg

→ excavate

→ struggle/progress

→ finally break egg

→ discover hatchling

→ deliver hatchling

→ watch hatchling reunite with mama

```



The revamp should preserve the discovery and emotional payoff instead of becoming a generic simulator.



\## Important Existing Notes



There is a large design/game analysis stored inside the Roblox project as documentation.



It describes:



\* server/client architecture

\* egg layers

\* egg pieces

\* tools and power

\* inventory

\* economy

\* shop

\* round system

\* cooperative climbing

\* hatchling

\* delivery

\* mama reunion

\* ReactLua UI



These notes are useful references but must be verified against the actual source code.



\## Known Development Items



`DevMoney` is a development/testing helper that should eventually be removed or disabled for production.



There are also older/backup assets inside `ServerStorage`, including a `\_Removed` folder and dinosaur backup assets.



Do not delete these casually during the revamp.



\## Current Migration Status



Completed:



\* Main Roblox place saved locally

\* Old Roblox place saved locally

\* Git repository initialized

\* Initial place backup committed

\* GitHub remote configured

\* Place backup pushed to GitHub

\* Server source synchronized to `src/server`

\* Client source synchronized to `src/client`

\* Shared source synchronized to `src/shared`

\* `CLAUDE.md` created



Not yet completed:



\* Persistent task tracking

\* Session handoff system

\* Decision log

\* Changelog

\* Complete asset/source migration

\* Full revamp planning

\* Revamp implementation



\## Current Priority



Set up the persistent multi-session development system before beginning the major revamp.



The next documentation files to create are:



```text

HANDOFF.md

TASKS.md

DECISIONS.md

CHANGELOG.md

```



After that, inspect the actual source and existing game behavior before planning large rewrites.



\## Important Rule



This file must be updated whenever the actual project state changes significantly.



Never use this file to pretend something is completed when it has not been verified.



