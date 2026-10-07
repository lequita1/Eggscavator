\# Eggscavator — Design \& Architecture Decisions



This file records important decisions made for the Eggscavator project.



Future Claude sessions must read this file before making major architectural or design changes.



\---



\## D-001 — Preserve the Existing Patch-Based Egg Excavation



\### Decision



Keep the existing smooth egg + individual patch/layer excavation mechanic.



The player aims at a specific patch, the patch highlights, the player breaks it, and a deeper layer becomes visible.



\### Reason



The existing excavation mechanic is already a strong part of the game's identity and does not need to be replaced.



The revamp should improve its presentation and storytelling rather than replacing the fundamental gameplay.



\---



\## D-002 — Story Is Built Around Excavation and Selling



\### Decision



Do not create a completely separate story game on top of the simulator.



The story should emerge from the existing gameplay loop.



Primary relationship:



```text

Excavate

→ Discover

→ Sell

→ Investigate

→ Discover More

→ Hatchling

→ Deliver

→ Reunion

```



\### Reason



This keeps the game recognizable as Eggscavator while giving the existing systems a stronger purpose.



Selling should become one of the main ways the world reacts to the player's discoveries.



\---



\## D-003 — Initial Story Scope Is Three Eggs



\### Decision



The first major story revamp focuses on:



1\. Chicken

2\. Dinosaur

3\. Alien



\### Reason



Three distinct chapters are large enough to establish the game's new identity while keeping the first revamp achievable.



Additional eggs will be considered after the first three are polished.



\---



\## D-004 — Chicken Egg Is the Normal Introduction



\### Decision



The Chicken Egg should initially feel ordinary.



It establishes the normal excavation, selling, and progression loop before the larger mystery begins.



\### Reason



The later mystery will be more effective if the player first understands what "normal" looks like.



The Chicken chapter ends with a subtle indication that the eggs may not actually be normal.



\---



\## D-005 — Dinosaur Egg Is the First Major Mystery



\### Decision



The Dinosaur Egg is where the player first encounters strong evidence that something unusual is happening.



This chapter introduces:



\* unusual materials

\* outside interest

\* A.R.C.

\* Dr. Vale

\* player trust choices

\* evidence of living creatures inside the eggs



\### Reason



The Dinosaur Egg provides a natural escalation from the ordinary Chicken chapter.



\---



\## D-006 — Alien Egg Expands the Mystery



\### Decision



The Alien Egg confirms that the previous anomaly was not an isolated event.



It should expand the mystery without explaining the entire universe.



\### Reason



The player should have questions after each chapter, not receive a complete explanation.



\---



\## D-007 — A.R.C. Is an Original Organization



\### Decision



Use the original organization name:



\*\*A.R.C. — Anomaly Research \& Containment\*\*



The visual concept may include professional black-suited agents, vehicles, communication devices, and containment equipment.



\### Reason



The organization needs its own identity and lore rather than directly copying an existing fictional organization.



\---



\## D-008 — Dr. Vale Is the Player's Investigation Contact



\### Decision



Use Dr. Vale as the working name for a knowledgeable researcher/advisor.



\### Reason



The player needs someone who can provide context and guidance without directly explaining the complete mystery.



\---



\## D-009 — A.R.C. Choices Are Relationship Choices



\### Decision



The A.R.C. choice should not simply be:



```text

YES = good

NO = bad

```



Instead, the choice affects:



\* trust

\* dialogue

\* information

\* opportunities

\* future interactions

\* possible rewards



\### Reason



This provides meaningful player agency without requiring two completely separate story campaigns.



\---



\## D-010 — Selling Must Stay Convenient



\### Decision



The selling system should remain fast and useful for the normal economy.



Story events should trigger around meaningful discoveries rather than every ordinary sale.



\### Reason



Constant dialogue interruptions would make the simulator frustrating.



The player should still be able to excavate and sell smoothly.



\---



\## D-011 — Each Egg Has a Distinct Visual Material Progression



\### Decision



Keep the smooth overall egg shape, but redesign the internal patches/layers so they feel intentional to each egg.



\### Reason



The current visual structure can be preserved while making the excavation much more detailed and meaningful.



Chicken, Dinosaur, and Alien should each communicate their identity through their layers.



\---



\## D-012 — Every Chapter Gets an Intro Cutscene



\### Decision



Each chapter begins with:



```text

Lobby

→ Teleport

→ Loading

→ Chapter Intro Cutscene

→ Gameplay

```



The intro cutscene should teach the basic game flow while establishing the chapter's specific story and tone.



\### Reason



The player should understand both:



\* what this chapter is about

\* what they are supposed to do



without requiring a large traditional tutorial.



\---



\## D-013 — Four-Player Chapter Sessions



\### Decision



The chapter gameplay session supports a maximum of four players.



\### Reason



The game is intended to preserve a cooperative multiplayer feel while keeping the excavation area readable and manageable.



\---



\## D-014 — Chapter Loading Should Reduce Asset Pop-In



\### Decision



After teleporting into a chapter, the game should use an intentional loading sequence before giving control to the player.



Critical assets should be prepared before the chapter begins.



\### Reason



The current game can feel laggy or visually incomplete when players initially spawn.



The loading sequence should hide unavoidable initialization and reduce visible asset pop-in.



\---



\## D-015 — Do Not Pretend Loading Progress Is Exact



\### Decision



Do not create a fake loading percentage that claims to represent exact loading progress unless the implementation can measure it reliably.



\### Reason



A visually accurate loading experience is more trustworthy than a fake 0–100% progress bar.



\---



\## D-016 — Intro Cutscenes Are Chapter-Specific



\### Decision



All chapters teach the same core gameplay concepts, but the actual cinematic presentation should be different for each egg.



\### Reason



The player should feel that they entered a new chapter rather than replaying the same tutorial with a different egg model.



\---



\## D-017 — Hatchlings Are Story Characters



\### Decision



Hatchlings are not merely rewards or inventory items.



Each hatchling receives:



\* unique reveal

\* unique behavior

\* unique sound

\* unique delivery sequence

\* unique parent

\* unique reunion



\### Reason



The hatchling is the emotional payoff of completing the egg.



\---



\## D-018 — The Journal Becomes Story Evidence



\### Decision



Use the existing Journal as a foundation for tracking discoveries.



\### Reason



The player needs a persistent place to remember:



\* eggs

\* materials

\* characters

\* discoveries

\* clues

\* chapter progress



It also lets the mystery build without forcing exposition into gameplay.



\---



\## D-019 — Do Not Rebuild Working Systems Unnecessarily



\### Decision



Existing systems such as:



\* tools

\* tool progression

\* inventory

\* economy foundations

\* rounds

\* DataStore

\* networking

\* ReactLua

\* patch excavation



should be preserved unless the audit identifies a specific reason to change them.



\### Reason



The goal is a focused revamp, not a destructive rewrite.



\---



\## D-020 — Blender Python Is the Primary Custom 3D Asset Method



\### Decision



Claude should NOT directly attempt to generate final 3D models as the primary method.



When practical, Claude should provide a Blender Python script that creates the requested asset.



\### Reason



Procedural Blender generation provides greater control and repeatability over geometry, proportions, materials, naming, and technical structure.



\---



\## D-021 — Gemini → Meshy Is the Alternative 3D Pipeline



\### Decision



When Blender procedural modeling is not the best method, use:



```text

Claude

→ Gemini image-generation prompt

→ User generates concept/reference image in Google Gemini

→ User sends image to Meshy

→ Meshy Image-to-3D

→ User reviews/refines result

→ Roblox integration

```



\### Reason



Some organic or visually complex hero assets are better approached from a concept image and then converted into 3D.



Claude's responsibility is to define the asset accurately and provide the required prompts/specifications.



\---



\## D-022 — Claude Must Request Missing Assets Explicitly



\### Decision



Claude must not silently invent low-quality final assets when a real asset is required.



Claude should clearly tell the project owner:



\* what asset is needed

\* why it is needed

\* recommended creation method

\* required dimensions

\* rigging requirements

\* animation requirements

\* required output

\* where it will be used



\### Reason



This keeps the development process deliberate and prevents placeholder assets from accidentally becoming permanent.



\---



\## D-023 — The First Three Chapters Do Not Reveal the Full Mystery



\### Decision



Chicken, Dinosaur, and Alien should each reveal more of the world while leaving larger unanswered questions.



\### Reason



The long-term mystery is part of the game's replay and progression motivation.



The player should constantly have a reason to ask:



> "What connects these eggs?"



\---



\## D-024 — Avoid Generic Simulator Bloat



\### Decision



Do not automatically add:



\* rebirths

\* unnecessary currencies

\* unrelated pets

\* excessive quests

\* meaningless rarity systems

\* excessive UI

\* dialogue spam



\### Reason



The game's identity should remain focused on:



> \*\*Excavate → Discover → Sell → Investigate → Deliver → Progress\*\*



\---



\## D-025 — Repository Is the Persistent Project Memory



\### Decision



GitHub, project documentation, and synchronized source files are the persistent shared memory between AI sessions.



\### Reason



Different Claude accounts/sessions cannot depend on the previous conversation remaining available.



The repository must contain enough information for another session to continue independently.



\---



\## D-026 — Audit Before Major Implementation



\### Decision



The first implementation phase is an audit of the current game.



Claude must inspect the existing code and determine:



\* what already works

\* what can be reused

\* what needs extension

\* what needs refactoring

\* what actually needs replacement

\* what external assets are required



\### Reason



The revamp should be integrated into the existing game rather than blindly rewritten.



\---



\# Decision Review Rule



When a future change conflicts with one of these decisions:



1\. Identify the conflict.

2\. Explain why the existing decision may no longer be suitable.

3\. Update this document if the project owner changes the decision.

4\. Do not silently override an established decision.



This document records intentional project direction, not temporary implementation details.



