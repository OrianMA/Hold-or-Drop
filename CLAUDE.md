# Development Philosophy

## Architecture Reference

* **Always read `ARCHITECTURE.md` before working on this project.** It documents the game
  systems, service boot order, event catalog, data flow, and tuning constants.
* Keep `ARCHITECTURE.md` in sync: when you add/change a service, event, system, or data
  flow, update the relevant section in the same change.

## Workspace Inspection (Roblox Studio)

* The `.rbxl` place file is **not** checked in — Workspace geometry (PlayerZones, rooms,
  models, GUIs, properties) lives only in Studio. When code needs to reference a scene
  instance, **inspect Studio first** (via the `Roblox_Studio` MCP: `list_roblox_studios`,
  `set_active_studio`, `search_game_tree`, `inspect_instance`, `execute_luau`) to verify
  actual names, classes, hierarchy, and properties before assuming anything from chat.
* You are **free to rename, restructure, or fix Studio instances** (via `execute_luau` or
  similar) when you spot inconsistencies — typos, mismatched names between package
  instances, missing properties (e.g. `ResetOnSpawn`), etc. Report what you changed in
  the response.
* When code expects a specific instance name/path, the names in code and the names in
  Studio must agree. If they drift, fix whichever side is wrong rather than guessing.

## Project Environment

* The project uses Roblox-TS (TypeScript for Roblox).
* Prefer TypeScript patterns and conventions.
* Use strong typing whenever practical.
* Avoid unnecessary use of `any`.
* Respect existing project structure and conventions.

## Core Principles

* Prefer simple and readable solutions over complex architectures.
* Prioritize maintainability and clarity.
* Avoid over-engineering.
* Keep files focused on a single responsibility.
* Separate systems into different files when it improves readability.
* Optimize for a solo developer workflow.

## Refactoring Rules

* Do not rewrite entire systems unless explicitly requested.
* Modify only the code required to solve the problem.
* Preserve existing behavior whenever possible.
* Avoid introducing new patterns, frameworks, or abstractions without clear benefit.
* Never replace a working system just because a different architecture exists.

## Code Style

* Prioritize readability over cleverness.
* Use descriptive names.
* Keep functions reasonably small.
* Minimize nesting.
* Prefer explicit logic over hidden abstractions.

## Problem Solving

* Focus on the exact task requested.
* Do not expand scope unnecessarily.
* Do not redesign unrelated systems.
* Keep solutions practical and production-oriented.

## Response Format

* Explain the issue briefly.
* Explain the proposed solution.
* Provide only the modified code when possible.
* Avoid repeating context already present in project files.
* Minimize token usage.

## Roblox Specific

* Consider performance.
* Consider mobile players by default.
* Keep client and server responsibilities separated.
* Avoid unnecessary RemoteEvents and RemoteFunctions.
* Use patterns commonly found in successful Roblox games.
* Prefer practical game development solutions over enterprise-style architectures.
