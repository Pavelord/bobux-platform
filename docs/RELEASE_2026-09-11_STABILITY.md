# September 11 stability release

Prepared Windows 0.1.38/build 43 and Android 0.1.30-mobile/build 31.
Publication is performed by the Bobux Release workflow; confirm its result and
public manifests before calling this release live.

## Player and session fixes

- Lobby thumbnail requests stop when the lobby leaves the tree. Pending Lua
  starts, sleeping tasks, and callbacks tolerate deleted character contexts.
  Main stops its scripts before disconnect and during scene destruction.
- The escape menu uses CanvasLayer 900, above inventory and imported GUI.
  Backpack input and player controls are blocked while it is open. Reset uses
  the character's authoritative respawn request and timeout recovery.
- Main's 26 RPC declarations match the previous stable schema. Optional tool
  damage has a separate node and is enabled by the server's join capability.
- Removed forced falling/prone poses. Rounded collision radius is 0.7 studs;
  overlap recovery no longer resets its timer on solver jitter. Jump reaches
  roughly 7.2 studs. Only the complete old 24/31/1.25 movement preset is migrated;
  explicit version 2 settings and Lua JumpPower remain literal.
- Home uses available width: fixed 148 px cards, square covers, inset text, one
  deduplicated Recommended row. Window resize changes the visible card count.

## Validation before packaging

PASS: Lua compatibility, Main script teardown with sleeping tasks and deleted
contexts, real local WebSocket join → authoritative Reset → Leave, GUI clicks
through the system menu above inventory and a full-screen imported GUI,
mobile Studio layout, humanoid states, narrow corridor, rotated concave wall,
ceiling and automatic escape from an engulfing block with solver-like jitter.
GPU row checks: 6 cards at 1280, 10 at 1920, 2 at 480, all square and unique.
API tests cover AI response validation, wallet/commerce, private messages/votes.

Server Toolbox audit: all 2,065 packages checked, 1,598 models and 467 sounds;
package hashes and dependency hashes match. Godot loaded 50 models and 50 sounds
from the public server cache. A physical Android device was not connected;
APK export and mobile layout checks do not substitute for device testing.

## Deployment constraints

API requires node:sqlite (Node 22.13+). A verified Node 22 runtime was installed
at /opt/bobux-runtime/node; deploy selects it as the API's PM2 interpreter.
Deployment excludes private databases/storage from rsync deletion, preserves
existing AI provider secrets, and stops publication on Godot parse failures.
Real commerce remains disabled until the owner configures a payment provider.
