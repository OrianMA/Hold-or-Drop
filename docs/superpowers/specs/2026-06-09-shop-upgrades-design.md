# Shop Upgrades — Design Spec

> Date: 2026-06-09
> Status: Approved (design), pending implementation plan
> Scope: 3 player upgrades sold from the Shop (cash purchases only). Robux buttons
> are explicitly **out of scope** for this spec.

## 1. Goal

Wire the existing Shop UI (`Workspace/Shop` prompt → `MainUI/ShopMenu`) so the player
can spend in-game **Money** to permanently upgrade three button stats. All upgrades are
stored per-player and restored on reconnect.

The three upgrades, surfaced as four shop buttons:

| Shop button (Studio frame) | Upgrade | Effect |
|----------------------------|---------|--------|
| `AButtonMoney`  | BaseCash +1   | +1 level of BaseCash |
| `BX5ButtonMoney`| BaseCash +5   | +5 levels of BaseCash in one click |
| `CMultiplier`   | Multiplier +1 | +1 level of Multiplier |
| `DSafety`       | Safety +1     | +1 level of Safety (risk reduction) |

`BaseCash +1` and `BaseCash +5` drive the **same** underlying `BaseCashLevel`; the `+5`
button is a convenience shortcut, nothing more.

## 2. Data model — levels are the source of truth

`PlayerProgressionService` switches from storing **values** to storing **levels** (integers
≥ 0). The effective values are derived from the levels by a pure formula and mirrored to
player attributes so the existing game loop reads them unchanged.

| Stored (DataStore) | Mirrored attribute | Derived value formula |
|--------------------|--------------------|-----------------------|
| `BaseCashLevel`   | `BaseCash`           | `floor(100 * 1.1^level)` |
| `MultiplierLevel` | `Multiplier`         | `0.1 * 1.1^level` |
| `SafetyLevel` (0..10) | `AdditionalSecurity` | `level * 0.05` (capped at 0.5) |

The **levels are also mirrored as attributes** (`BaseCashLevel`, `MultiplierLevel`,
`SafetyLevel`) so the client can compute the next price/stat and render "Lvl N" without a
network round-trip.

Why levels-as-source: the pricing/value curves can be retuned later with **zero migration** —
every player keeps their level and simply lands on the new curve. The UI can also show levels.

**Default levels** are all `0`, which reproduces today's defaults exactly:
`BaseCash=100`, `Multiplier=0.1`, `AdditionalSecurity=0`.

### Store version bump

`PlayerProgression_v1` → `PlayerProgression_v2`. The persisted schema changes shape
(values → levels). With the `resetData` cheat currently `true`, this has no dev impact; the
bump guarantees a clean transition the day `resetData` is turned off for ship. `Money`
lives in `PlayerData_v1` and is untouched.

## 3. Pricing

A single deterministic formula, computed identically on client and server:

```
priceFor(level) = floor(startPrice * 1.5^level)   -- cost to go from `level` → `level+1`
```

`BaseCash +5` price = strict sum of the next five level prices (no discount):

```
priceForFive(level) = Σ  priceFor(level + i)   for i in 0..4
```

| Item | startPrice | L0→1 | L1→2 | L4→5 | Notes |
|------|-----------|------|------|------|-------|
| BaseCash   | 25   | 25   | 37   | 126  | `+5` from L0 = 328 |
| Multiplier | 100  | 100  | 150  | 506  | |
| Safety     | 2000 | 2000 | 3000 | 10125| cap at L10 (76 886 for L9→10) |

Determinism note: both sides run Luau, so `floor(start * 1.5^level)` yields the same integer.
At very high levels the price is astronomically large (effectively unreachable) but never
diverges between client and server.

## 4. Effective-value curves (reference)

| Level | BaseCash (`×1.1`) | Multiplier (`×1.1`) | Safety |
|-------|-------------------|---------------------|--------|
| 0   | 100      | 0.1   | 0%  |
| 10  | 259      | 0.259 | 50% (cap) |
| 50  | 11 739   | 11.7  | — |
| 100 | 1.38M    | 1 378 | — |

BaseCash and Multiplier are intentionally near-infinite (the `×1.1` value curve plus the
`×1.5` price curve). `FormatNumber` (K → Vg, 10^63) already covers the display range.

## 5. Files (separation of concerns)

| File | Role | Status |
|------|------|--------|
| `shared/ShopConfig.ts` | Single source of truth: `ShopItemId`, item table (target stat, quantity, startPrice, cap), and pure helpers `priceFor`, `priceForFive`, `valueFor`. Imported by both sides. | new |
| `server/services/ShopService.ts` | Purchase authority: handles `ShopPurchaseEvent`, re-validates Money, deducts, increments level, recomputes value. | new |
| `server/services/PlayerProgressionService.ts` | Extended: store the 3 levels, derive values at load, expose `getLevel` / `addLevel`. | modified |
| `client/behaviors/ShopBehavior.ts` | Open/close + auto-close on distance. **Unchanged.** | existing |
| `client/behaviors/ShopItemsController.ts` | Binds the 4 frames: shows current→next stat + price, listens to attributes, handles cash-button clicks. | new |

## 6. Networking — one new RemoteEvent

Per `CLAUDE.md` (minimize RemoteEvents), only **one** event is added:

- **`ShopPurchaseEvent` (C→S)** — arg: `ShopItemId` string
  (`"BaseCash"` | `"BaseCashX5"` | `"Multiplier"` | `"Safety"`).

Everything else flows over **auto-replicated attributes**:
- `Money` (existing, `PlayerDataService`)
- `BaseCashLevel` / `MultiplierLevel` / `SafetyLevel` (new, mirrored)

The client refreshes its UI from `GetAttributeChangedSignal` on those attributes — **no
server→client response event needed**.

Failure (race/desync only, since the client pre-checks) reuses the existing
**`InformationTextEvent`** to flash "Pas assez d'argent".

## 7. Purchase flow

```
Click cash button
  └─ client pre-check: Money >= price ?
       ├─ no  → local denied feedback (greyed button), no network
       └─ yes → fire ShopPurchaseEvent(itemId)
                  └─ ShopService (server):
                       1. resolve item from ShopConfig
                       2. read current level (+ cap check for Safety)
                       3. compute price (priceFor / priceForFive)
                       4. re-validate Money >= price  → else InformationTextEvent, abort
                       5. PlayerDataService.add(player, "Money", -price)
                       6. PlayerProgressionService.addLevel(player, stat, qty)
                          → recomputes & sets the value attribute
                       → attributes replicate → client UI updates
```

Server is authoritative on every field; the client pre-check is UX-only.

## 8. Safety wiring into the game loop

`AdditionalSecurity` is currently *stored but not wired* (ARCHITECTURE.md §6.6). This spec
wires it. In `ButtonInGameModule.startButtonGame`, read safety **once** at session start
(alongside `baseCash` / `multiplierPerSecond`, ~line 109):

```ts
const safety = PlayerProgressionService.get(player, "AdditionalSecurity"); // 0..0.5
```

Then apply multiplicatively where the risk roll is computed (~line 155):

```ts
const risk = getRisk(timeHeld) * (1 - safety);
```

This preserves the existing risk curve shape, just scaled down. At 50% safety the effective
risk ceiling drops from `MAX_RISK` 0.8 to 0.4. `getRisk`'s signature is unchanged.

## 9. UI binding (per frame)

Each of the 4 frames (`ShopMenu/Body/<frame>`) is wired by `ShopItemsController`:

- `BoostLyout/BoostTitleText` ← `"+1 Boost"` / `"+5 Boost"` per item.
- `BoostLyout/CurrentStatFrame/CurrentStatText` ← current value (`FormatNumber`).
- `BoostLyout/NextStatFrame/NextStatText` ← value after purchase (`FormatNumber`).
- Cash button (`ButtonsLayout` → the TextButton holding `TextLabel`) ← price (`FormatCash`);
  greyed when `Money < price`.
- **Safety at cap (level 10):** show `"MAX"`, disable the cash button.
- **Robux button** (the TextButton holding `GainQuantityText` / `RobuxQuantityText`): left
  as-is, **not wired** in this spec.

The controller refreshes on `Money` and the relevant level attribute changing.

### Studio cleanup (done as part of implementation)

In all 4 frames the "next" label is currently named `CurrentStatText` (duplicate of the
"current" one inside `NextStatFrame`). Rename the one under `NextStatFrame` to `NextStatText`
so the controller can target it unambiguously.

## 10. Boot order

`ShopService` is inserted into `services/index.ts` after `PlayerDataService` and
`PlayerProgressionService` (it needs both). It only registers a RemoteEvent handler, so it
has no dependency on rooms and can sit right after `PlayerProgressionService`.

Client: `initShopItems()` is added to `main.client.ts` alongside the existing `initShopMenu()`.

## 11. Out of scope

- Robux / Developer Product purchases (the second button per frame).
- Prestige / rebirth systems.
- Any change to Money earning (game loop payout math) beyond the Safety risk scaling.

## 12. Touch list

- `shared/Event.ts` — add `ShopPurchaseEvent`.
- `shared/ShopConfig.ts` — new.
- `server/services/ShopService.ts` — new.
- `server/services/PlayerProgressionService.ts` — levels-as-source refactor + `getLevel`/`addLevel`, store `_v2`.
- `server/services/index.ts` — register `ShopService`.
- `server/modules/ButtonInGameModule.ts` — read safety once, scale risk.
- `client/behaviors/ShopItemsController.ts` — new.
- `client/main.client.ts` — `initShopItems()`.
- `ARCHITECTURE.md` — new "Shop" section + event catalog row + progression note update.
- Studio: rename `NextStatFrame/CurrentStatText` → `NextStatText` ×4.
