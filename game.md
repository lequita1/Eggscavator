--[[
================================================================================
                     COMPLETE GAME ANALYSIS — EGG BREAKING SIMULATOR
================================================================================

┌──────────────────────────────────────────────────────────────────────────────┐
│                              1. HIGH-LEVEL FLOW                              │
└──────────────────────────────────────────────────────────────────────────────┘

The game is an EGG BREAKING / MINING SIMULATOR with round-based gameplay,
tool upgrades, an economy, a shop, inventory, and a cooperative climb rig.

PLAYER LOOP (what a player does each session):
  1. Join → PlayerDataService loads/saves data (money, inventory, tools).
  2. Spawn into the lobby area with stations (Sell, Shop, teleport pads).
  3. A Round starts (RoundService) → players are teleported to the egg arena.
  4. Players use their Tools to break Egg Layers (mining-style).
  5. Breaking egg pieces yields Eggshells / Items collected into Inventory.
  6. Players can climb the Climb Rig (cooperative team mechanic).
  7. Round ends → players teleport back → sell items at Sell Station for money.
  8. Money is used at the Shop Station to buy better Tools and upgrades.
  9. Better tools break harder layers → access deeper egg content → more value.
  10. Data saves on leave (PlayerDataService).

================================================================================
│                              2. ARCHITECTURE OVERVIEW                         │
================================================================================

CLIENT-SERVER MODEL:
  • Server (Scripts in ServerScriptService) = single source of truth.
    - Handles: data persistence, economy, tool logic, shop, inventory,
      round management, egg HP, piece spawning, teleportation, climb rig.
  • Client (LocalScripts in StarterPlayerScripts) = input + visuals.
    - Handles: tool swinging animation, pickup prompts, egg rendering,
      atmosphere effects, React UI, climb intent sending.
  • Shared (ReplicatedStorage.Shared) = definitions both sides use.
    - Item definitions, tool definitions, egg layer data, economy constants.

COMMUNICATION:
  • RemoteEvents / RemoteFunctions in ReplicatedStorage bridge client↔server.
  • Client fires intent (e.g. "I want to swing", "I want to climb") to server.
  • Server validates and applies authoritative changes, replicates results.

================================================================================
│                          3. SERVER SERVICES (DETAILED)                        │
================================================================================

─── 3.1 PlayerDataService (ServerScriptService) ───
  PURPOSE: Load and persist player data across sessions.
  MECHANICS:
    • On PlayerAdded: attempts to load from DataStore (pcall + retry).
    • Data structure includes: Money (in cents), Inventory items, owned Tools,
      currently equipped tool, upgrades applied.
    • On PlayerRemoving: saves data back to DataStore.
    • Handles edge cases: DataStore failures, session locking, retries.
  CONNECTIONS:
    • Provides data to ShopService (check balance, deduct money),
      InventoryService (add/remove items), ToolService (equip/upgrade tools),
      EggService (reward money for breaking egg pieces).

─── 3.2 EggService (ServerScriptService) ───
  PURPOSE: Manages the egg — the central object players break apart.
  MECHANICS:
    • Egg has multiple LAYERS (outermost first). Each layer has:
      - Hardness: determines which tool Power level is needed to damage it.
      - HP per patch: how many hits to break a piece of that layer.
      - Value in cents: reward for breaking a piece.
    • Egg pieces (patches) are spawned as parts in the Workspace.
    • When a tool hits a piece (Touched event via ToolService), EggService
      reduces that piece's HP. When HP reaches 0, the piece is destroyed.
    • Broken pieces may drop items (Eggshell Flakes, etc.) into the player's
      inventory via InventoryService.
    • Money reward is added via PlayerDataService.
    • When all pieces of a layer are destroyed, the next inner layer is
      revealed/exposed for breaking.
  CONNECTIONS:
    • Works with ToolService (tool hit → damage calculation).
    • Rewards through PlayerDataService (money) and InventoryService (items).
    • RoundService controls when the egg is active/reset.

─── 3.3 ToolService (ServerScriptService) ───
  PURPOSE: Manages tool ownership, equipping, upgrades, and hit processing.
  MECHANICS:
    • Tool definitions (from Shared) include:
      - DPS = Damage / AttackInterval (damage per second).
      - Power = the hardest layer the tool can break (tier gating).
      - Upgrade kinds: "Hold" (and possibly others) that improve the tool.
    • When a player equips a tool, ToolService validates ownership and sets
      the active tool for that player.
    • On tool swing/hit (triggered by client via RemoteEvent):
      - Server validates the hit (range, cooldown, rate limiting).
      - Calculates damage based on tool's Damage stat.
      - Checks if tool's Power >= target piece's layer Hardness.
      - If yes → applies damage to the egg piece (delegates to EggService).
      - If no → hit bounces (no damage, possibly visual feedback).
    • Upgrades: players can upgrade tools (e.g., "Hold" upgrade) to increase
      stats. Upgrade state stored in player data via PlayerDataService.
  CONNECTIONS:
    • Reads tool defs from ReplicatedStorage.Shared.
    • Applies damage via EggService.
    • Checks/deducts upgrade costs via ShopService + PlayerDataService.
    • Client-side swinging handled by ToolController (StarterPlayerScripts).

─── 3.4 ShopService (ServerScriptService) ───
  PURPOSE: Handles purchases — buying new tools, upgrades, and items.
  MECHANICS:
    • Shop has categories: Tools, Upgrades.
    • On purchase request (RemoteEvent from client):
      - Validates player has enough money (PlayerDataService).
      - Deducts money from player data.
      - Grants the purchased item/tool/upgrade.
      - Updates inventory (InventoryService) or tool data (ToolService).
    • Prices are in cents (e.g., $1.00 = 100 cents).
  CONNECTIONS:
    • Depends on PlayerDataService (balance check & deduction).
    • Grants tools via ToolService, items via InventoryService.
    • UI rendered on client via ReactController.

─── 3.5 RoundService (ServerScriptService) ───
  PURPOSE: Manages the round-based gameplay loop.
  MECHANICS:
    • Round phases: Intermission → Active → Round End → Reset.
    • During Intermission: players are in the lobby/station area.
    • Round Start: teleports players to the egg arena (StationTeleportService).
    • During Active: players break the egg using tools.
    • Round End: based on timer or egg fully destroyed.
    • Reset: egg is rebuilt/reinstanced, players return to lobby.
    • Economy scaling: rewards scale by player count (x0.25, x0.5, x0.75, x1).
      This means fewer players = less reward, more players = full reward.
      Each player earns approximately $265 per match at full scale.
  CONNECTIONS:
    • Uses StationTeleportService to move players between lobby and arena.
    • Triggers EggService to reset/spawn the egg at round start.
    • Awards end-of-round money via PlayerDataService.

─── 3.6 InventoryService (ServerScriptService) ───
  PURPOSE: Manages player inventories (collected items/materials).
  MECHANICS:
    • Stores item quantities per player (e.g., Eggshell Flake x42).
    • Items can be added (from breaking egg pieces) or removed (from selling).
    • Item definitions come from ReplicatedStorage.Shared (name, value, etc.).
    • Selling: at the Sell Station, items are converted to money.
  CONNECTIONS:
    • Receives items from EggService (egg piece → item drop).
    • Converts items to money at Sell Station (via ShopService or direct).
    • Data persisted through PlayerDataService.

─── 3.7 PieceService (ServerScriptService) ───
  PURPOSE: Manages the individual egg pieces/patches in the world.
  MECHANICS:
    • Spawns and tracks individual breakable pieces that compose the egg.
    • Each piece has its own HP, layer assignment, and value.
    • Handles piece destruction and cleanup.
    • May handle visual updates (cracks, damage states) as pieces take damage.
  CONNECTIONS:
    • Called by EggService to spawn/damage/destroy pieces.
    • Works with ToolService for hit detection on specific pieces.

─── 3.8 StationTeleportService (ServerScriptService) ───
  PURPOSE: Handles player teleportation between stations and arena.
  MECHANICS:
    • Stations: Sell Station, Shop Station, Arena (round start), and others.
    • Teleport pads/triggers in the Workspace detect player proximity.
    • 1.5-second cooldown between teleports to prevent spam.
    • On teleport: moves player's character to the target station's position.
  CONNECTIONS:
    • Used by RoundService (arena teleport at round start/return at end).
    • Players use teleport pads manually (Sell, Shop) during intermission.
    • Client-side: PickupController may show prompts near stations.

─── 3.9 ClimbService (ServerScriptService) ───
  PURPOSE: Manages the cooperative Climb Rig — a team-shared climbing mechanic.
  MECHANICS:
    • The Climb Rig is a shared object that multiple players cooperate on.
    • Server owns the rig's state (position, progress, who's climbing).
    • Client sends "climb intent" (e.g., "start climbing", "move up") via
      RemoteEvent to the server.
    • Server validates and applies the climbing movement authoritatively.
    • The rig progresses as players climb together (cooperative element).
  CONNECTIONS:
    • Receives climb intents from client (via RemoteEvent).
    • May tie into RoundService (climb available during active round).
    • Client-side handled by a climb controller (sends intents).

─── 3.10 DevMoney (ServerScriptService) ───
  PURPOSE: Temporary testing helper — gives $50 on player join.
  STATUS: Marked for deletion before publishing.
  MECHANICS:
    • On PlayerAdded: adds $50 (5000 cents) to the player's money.
    • Used for testing shop purchases and upgrades during development.
  WARNING: Remove before production to avoid giving all players free money.

================================================================================
│                          4. CLIENT CONTROLLERS (DETAILED)                     │
================================================================================

─── 4.1 ToolController (StarterPlayerScripts) ───
  PURPOSE: Handles tool swinging and hit detection on the client.
  MECHANICS:
    • Listens for player input (mouse click / tap) to trigger tool swing.
    • Plays swing animation locally for instant feedback.
    • On hit: sends a RemoteEvent to the server (ToolService) with target info.
    • Does NOT apply damage client-side — server validates and applies.
    • Handles tool equip/unequip visuals (show/hide tool in character's hand).

─── 4.2 PickupController (StarterPlayerScripts) ───
  PURPOSE: Handles item pickup prompts and interactions.
  MECHANICS:
    • Detects when player is near a pickup-able item or station.
    • Shows a UI prompt (e.g., "Press E to Sell", "Press E to pick up").
    • On player confirmation: fires RemoteEvent to server for processing.
  CONNECTIONS:
    • Interacts with StationTeleportService (station proximity).
    • Interacts with InventoryService (item pickups).

─── 4.3 EggView (StarterPlayerScripts) ───
  PURPOSE: Client-side rendering and visual management of the egg.
  MECHANICS:
    • Displays the egg and its layers to the player.
    • May handle visual effects: cracks, particle bursts on hit, layer
      transitions when outer layers are destroyed.
    • Optimizes rendering (only show relevant layers/pieces).

─── 4.4 EggAtmosphere (StarterPlayerScripts) ───
  PURPOSE: Manages atmospheric effects around the egg/arena.
  MECHANICS:
    • Controls lighting, fog, particle ambiance in the egg arena.
    • May intensify effects as players break deeper layers (drama scaling).
    • Purely cosmetic — no gameplay impact.

─── 4.5 ReactController (StarterPlayerScripts) ───
  PURPOSE: Root controller for all React-based UI.
  MECHANICS:
    • Uses the ReactLua package (ReplicatedStorage or packages folder).
    • Mounts the main UI tree (Shop UI, Inventory UI, Money display, etc.).
    • React components subscribe to game state (money, inventory, round phase)
      and re-render when state changes.
    • UI actions (buy, sell, equip) fire RemoteEvents to server services.
  CONNECTIONS:
    • Shop UI → ShopService (purchase requests).
    • Inventory UI → InventoryService (view/sell items).
    • Money display → PlayerDataService (balance).
    • Round info → RoundService (timer, phase).

================================================================================
│                          5. SHARED DEFINITIONS                                │
================================================================================

─── ReplicatedStorage.Shared ───
  Contains definitions used by both client and server:

  • ITEM DEFINITIONS:
    - Name, display name, value (in cents), rarity/category.
    - Example item: "Eggshell Flake" — a basic crafting/sell material.
    - Used by InventoryService (what items exist) and EggService (drops).

  • TOOL DEFINITIONS:
    - Tool name, Damage, AttackInterval, Power (layer tier), UpgradeKinds.
    - DPS = Damage / AttackInterval (calculated or stored).
    - Power determines which egg layers the tool can damage.
    - UpgradeKinds: "Hold" and potentially others.
    - Used by ToolService (server) and ToolController (client display).

  • EGG LAYER DATA:
    - Layer order (outermost = layer 1, innermost = last).
    - Hardness per layer (min tool Power to damage).
    - HP per patch (durability of each piece in that layer).
    - Value per piece (cents reward for breaking).
    - Used by EggService and PieceService.

  • ECONOMY CONSTANTS:
    - Everything stored in CENTS internally ($1.00 = 100 cents).
    - Round reward base: ~$265 per match.
    - Player count scaling multipliers: x0.25, x0.5, x0.75, x1.
    - Used by RoundService and ShopService.

================================================================================
│                          6. ECONOMY SYSTEM                                    │
================================================================================

CURRENCY:
  • Internal: cents (integer). Display: dollars (cents / 100).
  • Player money stored in PlayerDataService data.

INCOME SOURCES:
  1. Breaking egg pieces → immediate money reward (per piece value).
  2. Selling inventory items at Sell Station → converts items to money.
  3. End-of-round reward → ~$265 scaled by player count.

EXPENSES:
  1. Buying new tools at Shop Station (higher Power/DPS tools cost more).
  2. Upgrading existing tools (e.g., "Hold" upgrade).
  3. Potentially buying items or consumables (if shop supports it).

FLOW:
  Break egg → earn money + collect items → sell items for more money →
  buy better tools → break harder layers → earn even more → repeat.

================================================================================
│                          7. ROUND FLOW (DETAILED)                             │
================================================================================

  ┌─────────────┐    ┌─────────────┐    ┌─────────────┐    ┌─────────────┐
  │ INTERMISSION │───►│ ROUND START  │───►│  ACTIVE      │───►│ ROUND END   │
  └─────────────┘    └─────────────┘    └─────────────┘    └─────────────┘
        ▲                                                            │
        │                                                            ▼
  ┌─────────────┐                                            ┌─────────────┐
  │   RESET      │◄───────────────────────────────────────────┤  TELEPORT    │
  │ (egg rebuilt)│                                            │  (to lobby)  │
  └─────────────┘                                            └─────────────┘

  INTERMISSION:
    • Players in lobby. Can visit Sell Station, Shop Station.
    • Timer counts down to round start.

  ROUND START:
    • StationTeleportService teleports all players to egg arena.
    • EggService spawns the egg with all layers.
    • EggAtmosphere activates arena ambiance.

  ACTIVE:
    • Players swing tools at egg (ToolController → ToolService → EggService).
    • Egg pieces take damage, break, drop items + money.
    • Players can use Climb Rig (cooperative climbing).
    • Players progress through layers (outer → inner).

  ROUND END:
    • Triggered by: timer expiry OR egg fully destroyed.
    • End-of-round money awarded (scaled by player count).
    • Players teleported back to lobby.

  RESET:
    • Egg rebuilt/reinstanced for next round.
    • Player inventories and money persist (not reset).

================================================================================
│                          8. TOOL PROGRESSION SYSTEM                           │
================================================================================

TOOL STATS:
  • Damage: raw damage per hit.
  • AttackInterval: seconds between hits (lower = faster).
  • DPS = Damage / AttackInterval (overall effectiveness metric).
  • Power: tier number — must be >= layer Hardness to damage that layer.

PROGRESSION:
  Starter Tool (low Power, low DPS)
    → Buy better tool at Shop (higher Power, higher DPS)
    → Upgrade tool (e.g., "Hold" upgrade improves a stat)
    → Break harder layers → earn more → buy even better tools
    → Repeat until all egg layers are accessible.

UPGRADE KINDS:
  • "Hold": Improves the tool in some way (likely hold-to-attack or
    sustained damage, or a stat boost). Exact effect defined in tool defs.

================================================================================
│                          9. EGG BREAKING MECHANICS                             │
================================================================================

EGG STRUCTURE:
  • The egg is composed of multiple concentric LAYERS.
  • Each layer contains multiple PIECES (patches).
  • Layer 1 (outermost) → Layer N (innermost).

BREAKING A PIECE:
  1. Player swings tool at a piece (client input → server validation).
  2. Server checks: tool Power >= piece's layer Hardness?
     - NO → hit bounces, no damage. Visual feedback to client.
     - YES → proceed to damage.
  3. Server calculates damage (tool Damage stat, possibly upgrade modifiers).
  4. Piece HP reduced by damage. If HP <= 0:
     a. Piece is destroyed (removed from Workspace).
     b. Money reward added to player (piece value in cents).
     c. Item(s) may be added to player's inventory (e.g., Eggshell Flake).
  5. When all pieces in a layer are destroyed, inner layer becomes accessible.

LAYER PROGRESSION:
  Outer layers: low Hardness, low HP, low value. Starter tools can handle.
  Inner layers: high Hardness, high HP, high value. Need upgraded tools.
  This creates the progression loop: better tools → deeper layers → more reward.

================================================================================
│                          10. CLIMB RIG MECHANICS                              │
================================================================================

CONCEPT:
  • A cooperative climbing mechanic shared among players.
  • The Climb Rig is a physical structure/object in the arena.

HOW IT WORKS:
  1. Players approach the Climb Rig.
  2. Client sends "climb intent" to server (RemoteEvent).
  3. Server (ClimbService) validates and moves the player on the rig.
  4. Multiple players can climb simultaneously (team-shared).
  5. Progress is server-authoritative — client only sends intent.
  6. Climbing may provide access to higher egg layers or vantage points.

WHY IT EXISTS:
  • Adds cooperative gameplay beyond just hitting the egg.
  • May be required to reach certain parts of the egg.
  • Encourages team play during rounds.

================================================================================
│                          11. STATION SYSTEM                                   │
================================================================================

STATIONS IN THE GAME:
  • Sell Station: Convert inventory items to money.
  • Shop Station: Buy new tools and upgrades.
  • Arena Teleport: Round-based teleport to egg arena.
  • (Possibly others: Climb Rig entry, special shops, etc.)

TELEPORTATION:
  • Managed by StationTeleportService.
  • 1.5-second cooldown between teleports.
  • Triggered by stepping on teleport pads (proximity detection).
  • PickupController may show interaction prompts near stations.

================================================================================
│                          12. DATA PERSISTENCE                                 │
================================================================================

  PlayerDataService handles all save/load:

  SAVED DATA:
    • Money (cents) — total currency.
    • Inventory — items and quantities.
    • Tools — owned tools and their upgrade states.
    • Equipped tool — which tool is currently active.
    • (Possibly stats: total broken, layers cleared, etc.)

  SAVE TRIGGERS:
    • On PlayerRemoving (player leaves game).
    • Possibly periodic auto-save during gameplay.
    • On round end (checkpoint save).

  LOAD TRIGGERS:
    • On PlayerAdded (player joins game).

  RESILIENCE:
    • Uses pcall + retries for DataStore calls.
    • Handles DataStore outages gracefully.
    • Session locking to prevent duplicate sessions.

================================================================================
│                          13. HOW EVERYTHING CONNECTS                          │
================================================================================

  ┌──────────────────┐
  │  PlayerDataService │ ◄──► DataStore (save/load)
  └────────┬─────────┘
           │ provides/updates money, inventory, tools
           ▼
  ┌──────────────────┐         ┌──────────────────┐
  │   EggService      │◄────────►│  ToolService     │
  │                   │         │                  │
  │ Manages egg layers│         │ Manages tools,   │
  │ Spawns pieces     │         │ hit processing,  │
  │ Tracks piece HP   │         │ upgrades, Power  │
  │ Rewards on break  │         │ checks           │
  └────────┬─────────┘         └────────┬─────────┘
           │ drops items                │ validates hits
           ▼                            │
  ┌──────────────────┐         ┌────────┴─────────┐
  │ InventoryService  │         │  PieceService     │
  │                  │         │                  │
  │ Tracks items     │         │ Spawns/tracks    │
  │ Add on break     │         │ individual egg   │
  │ Remove on sell   │         │ pieces in world  │
  └────────┬─────────┘         └──────────────────┘
           │ sell items
           ▼
  ┌──────────────────┐         ┌──────────────────┐
  │   ShopService     │◄────────►│ StationTeleport   │
  │                  │         │   Service          │
  │ Buy tools/upgrades│        │ Moves players      │
  │ Check/deduct money│        │ Sell/Shop/Arena    │
  │ Grant items/tools │        │ 1.5s cooldown     │
  └────────┬─────────┘         └────────┬─────────┘
           │                            │
           ▼                            ▼
  ┌──────────────────────────────────────────────────┐
  │                  RoundService                      │
  │  Intermission → Start → Active → End → Reset      │
  │  Teleports players, resets egg, awards money       │
  │  Scales rewards by player count                    │
  └──────────────────────────────────────────────────┘
           │
           ▼
  ┌──────────────────┐
  │  ClimbService     │  (cooperative climbing during active round)
  │  Server-authoritative rig movement                 │
  │  Client sends climb intent                         │
  └──────────────────┘

CLIENT SIDE:
  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐
  │ToolController│  │PickupController│  │  EggView      │
  │ swing input  │  │ station prompts│  │ egg rendering │
  │ hit → server │  │ pickup → server│  │ layer visuals │
  └──────────────┘  └──────────────┘  └──────────────┘

  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐
  │ EggAtmosphere│  │ReactController│  │ Climb (client)│
  │ ambiance/FX  │  │ all UI (React) │  │ sends intent  │
  └──────────────┘  └──────────────┘  └──────────────┘

SHARED:
  ┌──────────────────────────────────────────────────┐
  │           ReplicatedStorage.Shared                │
  │  Item Defs | Tool Defs | Egg Layer Data | Economy │
  └──────────────────────────────────────────────────┘

================================================================================
│                          14. KEY GAMEPLAY LOOP SUMMARY                        │
================================================================================

  1. JOIN → Load data (money, tools, inventory).
  2. ROUND START → Teleport to arena. Egg spawns.
  3. SWING TOOL → Server validates hit → Egg piece takes damage.
  4. PIECE BREAKS → Earn money + collect items.
  5. LAYER CLEARED → Inner layer exposed (needs better tool).
  6. CLIMB RIG → Cooperative climbing for access/vantage.
  7. ROUND END → Teleport to lobby. Award round money.
  8. SELL STATION → Convert items to money.
  9. SHOP STATION → Buy better tools / upgrades.
  10. REPEAT → Break deeper layers, earn more, upgrade further.

================================================================================
│                          15. NOTES & OBSERVATIONS                              │
================================================================================

  • DevMoney script gives $50 on join — REMOVE before publishing.
  • Economy is in cents internally (avoids floating-point issues).
  • Player count scaling (x0.25 to x1) balances rewards for different
    server sizes — prevents inflation in low-population servers.
  • ReactLua is used for all UI, providing a modern component-based approach.
  • The climb rig adds a cooperative dimension beyond simple mining.
  • Tool Power gating ensures progression — you can't skip to deep layers
    without investing in better tools.
  • Station teleport cooldown (1.5s) prevents exploit spam.
  • The game has a clear core loop: Mine → Sell → Upgrade → Mine Deeper.

================================================================================
                          END OF GAME ANALYSIS
================================================================================
]]

