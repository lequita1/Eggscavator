\# Eggscavator — Changelog



This file records meaningful changes to the Eggscavator project.



Do not record every tiny edit.



Record major:



\* gameplay changes

\* architecture changes

\* story changes

\* UI changes

\* asset changes

\* bug fixes

\* migrations

\* important project milestones



\---



\## 2026-10-07 — Repository \& Source Migration



\### Added



\* Created local Eggscavator project repository.

\* Preserved `Eggscavator\_Main.rbxl`.

\* Preserved `Eggscavator\_Old.rbxl`.

\* Created Git repository.

\* Created GitHub repository.

\* Connected local repository to GitHub.

\* Added `.gitignore`.

\* Synchronized server source from Roblox Studio.

\* Synchronized client source from Roblox Studio.

\* Synchronized shared source from Roblox Studio.



\### Added Project Documentation



\* `CLAUDE.md`

\* `PROJECT\_STATE.md`

\* `HANDOFF.md`

\* `TASKS.md`

\* `DECISIONS.md`



\### Revamp Direction Established



The project direction was refined around:



\* story-driven excavation

\* three initial chapters

\* Chicken Egg

\* Dinosaur Egg

\* Alien Egg

\* story-driven selling

\* A.R.C.

\* Dr. Vale

\* player trust choices

\* chapter intro cutscenes

\* chapter loading flow

\* hatchling discoveries

\* delivery and reunion sequences

\* excavation journal

\* improved egg layer/material presentation



\### Asset Pipeline Decision



Established:



```text

Primary:

Claude → Blender Python script → Blender → Roblox



Alternative:

Claude → Gemini image prompt → Gemini reference image

→ Meshy Image-to-3D → Roblox

```



Claude should not be treated as the final 3D asset-generation system.



\### Current Development Stage



Planning and existing-game audit.



No major gameplay rewrite has been approved yet.



