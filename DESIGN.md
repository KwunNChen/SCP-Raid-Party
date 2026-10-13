# Working title: HALDEN BREACH (factions vs. the Authority)

> Supersedes the earlier "Terminus" and "Low Clearance" docs. Existing code in `src/` is reused where noted.

## 1. Pitch

Several hostile factions want something locked inside **Site Halden**, a containment site run by the **Vesper Containment Authority (VCA)**, an original SCP-style organization. Each run, 2-3 factions raid the same site at once. You can go in **quiet** (Stealth Raid) or **loud** (Hostile Raid). The Authority fights back with AI security and, when the server is full enough, human **Site Command** players. Every raid makes the site's containment less stable, so things get out.

## 2. Factions (original)

| Faction | Wants | Playstyle / signature tools |
|---|---|---|
| **Gray Ledger** | Files and artifacts to sell | Forged keycards, disguises, data siphons |
| **The Open Hand** | Entities freed | Breach charges, lures, cell overrides |
| **Ember Syndicate** | Valuables, fast | Smoke, vault tools, speed gadgets |

All three start with sidegrade kits (different tools, not stronger ones). More factions come with seasons. Each faction has its own reputation track, cosmetics and lore thread.

## 3. The two raid modes

**Stealth Raid (build this first)**
- Quiet infiltration. Guards patrol with vision cones, cameras scan, noise and light matter.
- A global **Alert level (0-3)** rises as you're detected. Level 3 = lockdown.
- Goal: reach the vault, take the objective, extract.
- Score includes a **ghost bonus** for staying undetected. A caught raid collapses into a mini hostile mode.
- This is the Entry Point-style loop: planning, tension, a small mistake spiraling.

**Hostile Raid (stage 3)**
- Alert starts at maximum. Timed assault with response teams, locked doors, and objectives to breach and hold.
- Combat is deliberately limited: **stun batons, breaching charges, and a limited-ammo sidearm with server-validated hits**, using **downed/revive** instead of death. This keeps it out of the saturated shooter lane and is much cheaper to balance and build.
- **This is the biggest build in the game.** Do not start it until Stealth Raid has players.

## 4. How factions contest each other

- Factions enter from different points. There is **one primary prize** that only one team can extract. Other teams get secondary objectives.
- Rivals can **sabotage** each other non-lethally: jam doors, trip alarms, steal a keycard.
- **Temporary truce:** two factions may team up to open a vault and then betray at extraction. This is the clip machine.
- **Population fallback:** if a server has too few players, missing factions are filled by **AI rival crews**. This is how the game works with 4 players or 24.

## 5. The Authority side (mixed)

- **AI security (always on):** patrols, cameras, door logic and response teams. Built with PathfindingService.
- **Site Command (player roles, optional):** when enough players are present, 1-2 players can take over cameras, doors, lockdown and guard dispatch from a terminal UI. It is mostly interface work, which suits a scripter, and it needs no animation.
- **Containment instability:** raid actions raise a hidden Instability meter. Past thresholds, `AnomalySpawner` events fire (blackouts, entities, rule shifts) and hit **everyone**, which is the "everything goes wrong" beat.

## 6. Progression (never maxes out)

- **Faction reputation:** unlocks tools, cosmetics and lore, per faction.
- **Notoriety / site hardening:** the more a server's players raid, the harder the site gets (more cameras, new patrol routes), so difficulty is endless.
- **Contracts:** daily and weekly objectives.
- **Seasons:** a new site wing, a new faction or tool set, a new lore arc, and a ladder reset.
- **Currency:** Credits buy tool sidegrades and cosmetics. No pay-to-win, and this matters more here because PvP exposes any imbalance immediately.

## 7. Monetization

Faction cosmetics and uniforms, tool skins, VIP (cosmetics and lobby perks, no stat or XP edge), a season pass (cosmetic track). Check current DevEx rules before planning income.

## 8. IP

The Authority, Site Halden and all factions are original, in SCP's style only (clearance levels, containment procedures, case-file tone). SCP's named factions (Chaos Insurgency, Serpent's Hand and others) are SCP-wiki content under CC BY-SA 3.0, with attribution and share-alike obligations. Avoid them. (I'm not a lawyer.)

## 9. What carries over from the existing code

| Module | New role |
|---|---|
| `DataService` | Unchanged, with per-faction reputation added to the template |
| `ShiftManager` | Becomes the raid state machine (lobby, planning, raid, extraction, results) |
| `ObjectiveTracker` | Heist objectives (hack, steal, reach, hold) |
| `AnomalySpawner` | Instability events that hit everyone |
| `RuleDirector` | Optional: site protocols posted on terminals. May be cut if it doesn't fit |

New systems needed: guard AI (patrol, vision, detection), alert-level manager, faction kits, Site Command UI, and AI rival crews.

## 10. Build for a scripter with no modeling or animation

- Guards use default rigs with uniforms set through HumanoidDescription, and Roblox's default walk/idle animations. No custom animation.
- Detection, cameras and alarms are scripts and lighting.
- Site Command is UI.
- The site is a modular kit from the Creator Store. **Free models can contain malicious scripts, so inspect everything you import.**
- Use Studio's generative tools for placeholders, if your version has them.

## 11. Honest scope and staging

The full vision is a 4-6 month project for one scripter. The slice that ships fast:

| Stage | Time | Contents |
|---|---|---|
| **0: slice** | Weeks 1-2 | One corridor: a patrolling guard with vision cone, detection meter, one vault, extraction |
| **1: MVP** | Weeks 3-6 | Stealth Raid vs AI security, one team, 2 faction kits, Instability events, saves and rewards. **Publish this.** |
| **2** | Months 2-3 | Contesting factions (human or AI crews), the first Site Command role |
| **3** | Month 4+ | Hostile Raid mode, seasons, shop, pass |

## 12. Risks

1. **Population:** contested PvP feels empty at low player counts. The AI-crew fallback is the mitigation.
2. **Guard AI:** pathfinding and detection tuning are where most scripting time goes. Do this first.
3. **Exploiters:** competitive games attract them. Every remote must be validated on the server.
4. **Content rules:** keep it stylized and non-graphic, with downed states instead of death.
5. **Scope creep:** Hostile Raid and Site Command are the tempting additions. Both wait until after the MVP is out.
