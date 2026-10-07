--[[
	Game Structure Overview — 'before revamp almost finish.rbxl'
	Auto-generated inventory of all scripts, modules, and key objects.

═══════════════════════════════════════════════════════════════
  ServerScriptService
═══════════════════════════════════════════════════════════════
ServerScriptService
├── Main                         (Script)
├── WorldCheck                   (Script)
├── EggSim                       (Script)
├── EggSweepTest                 (Script)
├── ClimbService                 (Script)
├── DevMoney                     (Script)
└── Services                     (Folder)
    ├── InventoryService         (ModuleScript)
    ├── EggService               (ModuleScript)
    ├── PlayerDataService        (ModuleScript)
    ├── ToolService              (ModuleScript)
    ├── ShopService              (ModuleScript)
    ├── RoundService             (ModuleScript)
    ├── StationTeleportService   (ModuleScript)
    └── PieceService             (ModuleScript)

═══════════════════════════════════════════════════════════════
  ReplicatedStorage
═══════════════════════════════════════════════════════════════
ReplicatedStorage
├── Remotes                     (Folder — currently empty)
├── Shared                      (Folder)
│   ├── Util                    (ModuleScript)
│   ├── GameConfig              (ModuleScript)
│   ├── ToolDefinitions         (ModuleScript)
│   ├── EggDefinitions          (ModuleScript)
│   ├── ItemDefinitions         (ModuleScript)
│   ├── Curator                 (ModuleScript)
│   ├── DinoAnimator            (ModuleScript)
│   └── HatchlingProp           (ModuleScript)
├── Packages                    (Folder)
│   └── ReactLua               (Folder)
│       ├── React              (ModuleScript)
│       ├── ReactCache         (ModuleScript)
│       ├── ReactDebugTools    (ModuleScript)
│       ├── ReactDevtoolsExtensions (ModuleScript)
│       ├── ReactDevtoolsShared(ModuleScript)
│       ├── ReactIs            (ModuleScript)
│       ├── ReactReconciler    (ModuleScript)
│       ├── ReactRoblox        (ModuleScript)
│       ├── ReactShallowRenderer(ModuleScript)
│       ├── ReactTestRenderer  (ModuleScript)
│       ├── RoactCompat        (ModuleScript)
│       ├── Scheduler          (ModuleScript)
│       ├── Shared             (ModuleScript)
│       └── node_modules       (Folder — 7 subfolders)
├── GameSounds                 (Folder — 20+ Sound instances)
├── DinoRig                    (Model — rigged dino mesh + bones)
├── EggPatches                 (Folder)
│   └── Stonehatch             (Folder — patch mesh parts)
└── EggYolk                    (MeshPart)

═══════════════════════════════════════════════════════════════
  StarterPlayer
═══════════════════════════════════════════════════════════════
StarterPlayer
├── StarterCharacterScripts    (empty — no children)
└── StarterPlayerScripts
    ├── ClientMain             (LocalScript)
    ├── HatchCutscene          (LocalScript)
    ├── DinoLife               (LocalScript)
    ├── ReleaseCutscene        (LocalScript)
    ├── MotherHider            (LocalScript)
    ├── LayerHUD               (LocalScript)
    ├── EggProgress            (LocalScript)
    ├── FirstPerson            (LocalScript)
    ├── ViewModel              (LocalScript)
    ├── SellFly                (LocalScript)
    ├── ClimbController        (LocalScript)
    ├── ShopTags               (LocalScript)
    ├── EggMonster             (LocalScript)
    ├── Controllers            (Folder)
    │   ├── ToolController      (ModuleScript)
    │   ├── ReactController    (ModuleScript)
    │   ├── EggView            (ModuleScript)
    │   ├── EggAtmosphere      (ModuleScript)
    │   └── PickupController    (ModuleScript)
    └── UI                     (Folder)
        ├── App               (ModuleScript)
        ├── Theme             (ModuleScript)
        ├── Store             (ModuleScript)
        ├── Kit               (ModuleScript)
        ├── Journal           (ModuleScript)
        ├── Hotbar            (ModuleScript)
        ├── ShopPanel         (ModuleScript)
        ├── SellPopup         (ModuleScript)
        ├── Notifications     (ModuleScript)
        ├── Results           (ModuleScript)
        ├── LootFeed          (ModuleScript)
        ├── Announcer         (ModuleScript)
        ├── Sounds            (ModuleScript)
        ├── Effects            (ModuleScript)
        ├── ShopStage         (ModuleScript)
        ├── Components        (Folder)
        │   ├── Button        (ModuleScript)
        │   ├── Label         (ModuleScript)
        │   └── Panel         (ModuleScript)
        └── Stories           (Folder)
            ├── Button.story  (ModuleScript)
            ├── Label.story   (ModuleScript)
            └── Panel.story   (ModuleScript)

═══════════════════════════════════════════════════════════════
  ServerStorage
═══════════════════════════════════════════════════════════════
ServerStorage
├── Assets                     (Folder)
│   ├── Eggs                   (Folder)
│   │   └── Stonehatch         (Model)
│   ├── Tools                 (Folder)
│   │   ├── Drill1            (Tool)
│   │   ├── IcePick1          (Tool)
│   │   ├── Pickaxe1          (Tool)
│   │   ├── IcePick           (Tool)
│   │   ├── Pickaxe           (Tool)
│   │   ├── Drill             (Tool)
│   │   ├── Brush             (Tool)
│   │   └── Vacuum             (Tool)
│   └── Twin Drillers        (Model)
├── DecorTemplates            (Folder)
│   ├── Realistic Tree       (Model)
│   ├── Tree                 (Model)
│   └── Bush                 (Model)
├── DinoBackups              (Folder)
│   ├── DinoPreview_132712   (LocalScript)
│   ├── HatchlingProp_132712(ModuleScript)
│   └── ReleaseCutscene_132712 (LocalScript)
├── _Removed                 (Folder)
│   ├── ClimbSpike           (Script)
│   ├── EggRamps            (Folder — 80 parts)
│   ├── Pickaxe_before_Meshy(Tool)
│   ├── Drill_before_Meshy  (Tool)
│   ├── Decor_Stage4_Tools  (Folder — many parts)
│   ├── Stonehatch_OLD_tiles(Folder)
│   └── Stonehatch_V1_tiles (Folder)
└── Brushtool2_Plugin_Storage (Folder)
    ├── SOLO_BrushtoolBrushObjects (Folder)
    ├── SOLO_BrushtoolStampObjects (Folder)
    ├── SOLO_BrushtoolReferences   (Folder)
    └── SOLO_BrushtoolTable        (Folder)

═══════════════════════════════════════════════════════════════
  StarterGui
═══════════════════════════════════════════════════════════════
StarterGui
└── (empty — no children)

═══════════════════════════════════════════════════════════════
  Workspace
═══════════════════════════════════════════════════════════════
Workspace
├── Note                     (Script — design notes)
├── GameAnalysis             (ModuleScript)
├── ScriptNames              (Script — this file)
├── Baseplate               (Part)
├── Terrain                 (Terrain)
├── Camera                  (Camera)
├── Map                     (Folder)
│   ├── EggField           (Folder — egg pads)
│   ├── Paths             (Folder)
│   ├── SpawnSign         (Folder)
│   ├── SellStation       (Folder)
│   ├── ToolShop          (Folder)
│   ├── Spawn             (SpawnLocation)
│   └── DeliverySpot      (Model)
├── Eggs                   (Folder)
├── Decor                  (Folder)
│   ├── Stage4            (Folder)
│   ├── Stage3            (Folder)
│   ├── Stage5            (Folder)
│   ├── Stage6            (Folder)
│   ├── Stage8            (Folder)
│   ├── Stage9            (Folder)
│   ├── Stage10           (Folder)
│   ├── Mesh             (Model)
│   ├── Mesh             (Model)
│   └── camp map         (Model)
├── HatchStage            (Model — rocks, pillars, egg prop, hatchling)
└── Dino                  (Model)

═══════════════════════════════════════════════════════════════
  Summary
═══════════════════════════════════════════════════════════════
  Server Scripts (Script):       6   (Main, WorldCheck, EggSim, EggSweepTest, ClimbService, DevMoney)
  Server Modules (ModuleScript):  8   (InventoryService, EggService, PlayerDataService, ToolService, ShopService, RoundService, StationTeleportService, PieceService)
  Client Scripts (LocalScript):  13   (ClientMain + 12 others in StarterPlayerScripts)
  Client Modules (ModuleScript): 24   (5 Controllers + 15 UI + 3 Components + 1 Store + ...)
  Shared Modules (ModuleScript):  8   (Util, GameConfig, ToolDefinitions, EggDefinitions, ItemDefinitions, Curator, DinoAnimator, HatchlingProp)
  ReactLua Modules:             13   (React, ReactCache, ReactRoblox, Scheduler, etc.)
  Workspace Scripts:             3   (Note, GameAnalysis, ScriptNames)
  ServerStorage Backups:         3   (DinoPreview, HatchlingProp, ReleaseCutscene)
  _Removed Scripts:              1   (ClimbSpike)
]]

-- This script is documentation-only. It does not run any logic.
-- Open it in Studio to read the full game structure tree above.