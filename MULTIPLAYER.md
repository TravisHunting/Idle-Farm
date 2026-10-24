# Multiplayer — design & implementation plan

> **Picking this up?** Read "Status" first, then work the first unchecked box in "Tasks", in order.
> Tick a box only when it is done *and* verified (headless test green, or noted how it was checked).
> Add a line to "Log" at the bottom whenever you finish a task, and to the TODO.md Changelog when a
> whole phase is done. Keep `tests/sim_test.gd` green after every task: single player must never break.

## Status
- **Current phase:** 2 (leaving, forking, rejoining). Phases 0 and 1 are done (2026-10-24).
- **Last done:** 1.8 bandwidth check (`tests/run_net_test.sh` passes: two copies on localhost).
- **Next task:** 2.1 guest slot (most of it already happens, see the Phase 1 notes), then 2.2 (the
  guest is currently left frozen in puppet mode when the host goes away).
- **Known blockers:** none.
- **Multiplayer test:** `bash tests/run_net_test.sh` (~45s) starts a headless host and a guest
  (`profile=2`) on localhost and must pass on both sides. For a look at the guest's screen, run the
  guest without `--headless` and add `shot=<file.png>` (see `tests/net_runner.gd`).
- **Test baseline:** `sim_test` was flaky before multiplayer work started: even with a fixed `seed=N`, a few
  faction checks fail at random ("rabbit caught in a web", "aliens cataclysm wipes them out", "the
  wild comes back", "locust swarm takes off", "creep survives a reload", "the hatchling lives", "the egg hatched", "the colony grew", "the
  aliens' share of power moved", "the farm comes back"; the untouched code failed 4/4
  runs on seed 1). Results vary from run to run with the same seed, so something non-seeded feeds the sim. Treat
  "green" as: no `SCRIPT ERROR`, every multiplayer check passes, and only those known faction checks
  may fail. Use `days=4` or more (`days=3` is too short for some checks).

## The model (agreed with the user)
- The only multiplayer action is **"join world"**: a guest joins the world a host is running.
  Two players at most (one host, one guest).
- **Host-authoritative.** The host runs the full simulation exactly as in single player. The guest
  runs **no simulation** ("puppet mode"): it shows state streamed from the host and sends its
  actions as **commands**. No determinism / lockstep needed.
- Each player has **their own card box + stash** (their own pool of actions). Everything else
  (coins/chest, materials, weirdness, relics, factions...) is shared world state.
- **Nobody ever merges worlds.** When either player leaves, both keep a copy:
  - the host keeps running its world as before;
  - the guest's game drops out of puppet mode and keeps running the last state it received as its
    **own solo world** (a fork, saved in the slot the guest chose when joining).
  - Either copy can later be joined by the other player. Works the same in reverse.
- Transport: **ENet** (`ENetMultiplayerPeer`) + **UPnP** to open the port, **join by IP:port**.
  No servers, no signalling, no relay. If UPnP fails, the host forwards the port manually or
  the players use LAN.

## Decisions & defaults (change here if the user decides otherwise)
| Topic | Default |
|---|---|
| Port | UDP `24680`, editable in settings. |
| Player id | Random 16-hex `pid`, generated once, stored in `user://settings.json`. Display name optional (defaults "FRIEND"). |
| World id | `world_id` (random) saved in the slot; a guest fork gets a new id + `forked_from`. |
| Hands | `Game.hands = {pid: {box, stash, card_timer}}`; `Game.owner_pid` = whose world it is. |
| Guest hand when absent | Stays in the world's save, **frozen** (no drip while away); restored when that pid rejoins. A new pid gets an empty hand. |
| Cards pushed by the world (alien/brood envoys, follow-ups, delayed effects) | Into the hand of the player whose action caused it if known, else the **owner's** box. |
| Card cadence, game speed, debug keys | World rules: host only. Greyed out for the guest. |
| Offline progress | Only when the **owner** loads a save (unchanged). Never on join. |
| Snapshot encoding | `var_to_bytes` of the existing `to_dict()` output (never `bytes_to_var_with_objects`), ZSTD via `ENetConnection.compress`. |
| Guest's slot | Chosen before connecting; overwritten with the shared world (confirm if not empty); autosaved every 20s while joined. |
| Two copies on one PC (testing) | Command-line `-- profile=N` gives each copy its own settings/pid/slot files. |

## Protocol (sketch)
Autoload `Net` (`scripts/net.gd`), the same node path on both sides, so RPCs just work.
- Channel 0 (reliable): `hello`/`welcome`/`reject`, `cmd` (guest -> host), `state` (host -> guest:
  full Game + World without animals, sent when changed, checked 1x/s, and right after every command),
  `fx` one-shot events, `bye`.
- Channel 1 (reliable, as built): `actors` at ~5 Hz: `[entries, gone, fx]`. An entry is
  `[uid, kind, caste, {field index: value}]` with only the `net_fields()` that changed since the
  last send (a full keyframe every 10s); `gone` = uids that disappeared; `fx` = one-shot effects.
  The guest interpolates positions. (The plan said unreliable; deltas need reliable delivery.)
- `hello {protocol, game_version, pid, name}` -> host replies `welcome {owner_pid, world_id, state}`
  or `reject {reason}` (version mismatch, world full, host not in a game).
- `cmd {type, args}`: the host sets `pid` from the sending peer (never trust the guest's), checks
  bounds, runs `Commands.execute`.

## Tasks

### Phase 0: prep refactors (single player only, no networking yet)
- [x] **0.1 Player identity + profiles.** `Game.my_pid` (generate + persist in settings.json).
  Parse `-- profile=N` in `Game._ready`: suffix settings + slot paths (`settings_p2.json`,
  `slot_p2_1.json`) so two copies on one PC don't collide.
- [x] **0.2 Per-player hands.** Replace `Game.box`/`stash`/`card_timer` with `Game.hands[pid]` +
  `Game.owner_pid`; keep `box`/`stash` as accessors for the local player so HUD code barely
  changes. `add_card`/`take_card`/`move_card`/`card_at` take an optional `pid` (default: local).
  Card drip runs for every **present** pid. Save version 4: migrate the old `box`/`stash` into the
  owner's hand. Implement the "pushed cards" routing rule (see Decisions). Callers: `cards.gd:94,96,451`,
  `colony.gd:1187,1209`, `swarm.gd:1114,1118`, `main._offline_progress`.
- [x] **0.3 Command layer.** New `scripts/commands.gd` (class `Commands`) with
  `submit(cmd)`, which runs locally when solo/host or is sent to the host by a guest, and
  `execute(pid, cmd)`, which validates and applies. Commands: `choose(where, i, which)`,
  `move_card(from, fi, to, ti)`, `set_card_minutes(n)`, `debug(key)`. Route the HUD
  (`hud.gd:191, 234, 262, 273-280`) and the debug keys (`main._unhandled_input`) through it.
  Log lines name the player when there is more than one ("FRIEND chose: ...").
- [x] **0.4 Stable actor ids.** `uid: int` on Farmer and every Animal, from a counter saved in
  World; kept across save/load. Needed to match actors in the stream.
- [x] **0.5 World id.** `world_id` + `forked_from` in the save (`Game.to_dict`); new on `new_farm`.
- [x] **0.6 Puppet mode.** `Game.puppet := false`. When true, every simulation loop is off:
  `Game._process` (clock/day/buffs/drip), `world._process` sim parts (growth, `farmer.update`,
  `animals.update`, weeds), `cards`, `director`, `colony`, `swarm`, `tides`, offline progress.
  Cosmetic parts stay on (`_anim_t`, particles, weather_fx, HUD). Audit `create_timer`/tweens/
  `await` that change state.
- [x] **0.7 Tests.** Extend `tests/sim_runner.gd`: commands for two pids (fake guest hand), save/
  reload keeps hands, uids and world_id, and N seconds of puppet mode leave the state unchanged
  (compare `var_to_bytes(to_dict())`).

### Phase 1: net core (`scripts/net.gd`, autoload `Net`)
- [x] **1.1 Net autoload + states** OFFLINE / HOSTING / JOINING / GUEST, signals
  (`peer_joined`, `peer_left`, `status_changed(text)`). `host(port)`: `create_server(port, 1)`;
  `join(ip, port)`: `create_client`; ZSTD compression; ENet peer timeout ~5 s. Register in
  project.godot autoloads (after Game).
- [x] **1.2 Handshake**: hello/welcome/reject + `PROTOCOL_VERSION` and game version check; clear
  reject messages.
- [x] **1.3 Commands over RPC**: `Commands.submit` on the guest -> `rpc_id(1, "_cmd", ...)`; the
  host maps sender peer -> pid, validates, executes, marks the state dirty.
- [x] **1.4 State snapshots**: the host serializes `Game.to_dict()` + `world.to_dict()` without animals,
  sending when the hash changes (checked 1x/s) and right after a command. The guest applies them in puppet
  mode **without** touching local-only state (settings, `my_pid`, speed, the open card modal, HUD
  hover). Split `World.from_dict` so grid/fields/land can be reloaded without rebuilding actors.
- [x] **1.5 Actor stream** (~5 Hz, channel 1): add `net_state()` / `net_apply()` to Animal/Farmer
  (only what drawing needs). The guest spawns/despawns by uid and lerps positions; derive walk
  animation/facing from movement.
- [x] **1.6 FX forwarding**: when hosting, record one-shot visuals (world puffs/floating text, speech
  bubbles, `director.shake`, lightning flash, card-arrival/trash animations) and replay them on
  the guest. Find the spawner functions in world.gd / director.gd / hud.gd first.
- [x] **1.7 Guest clock smoothing**: advance `time_of_day` locally between snapshots (cosmetic only,
  no `new_day` signals in puppet mode).
- [x] **1.8 Bandwidth check**: debug-log bytes/s each way and snapshot size; target < 20 KB/s.
  Optimize (diff the grid, lower rates) only if needed.

### Phase 2: leaving, forking, rejoining
- [ ] **2.1 Guest slot**: the guest picks the target slot before joining; while joined it autosaves
  the received world there every 20s and on disconnect (keep `owner_pid` = host).
- [ ] **2.2 Host gone** (bye or timeout) on the guest: save, set `puppet = false`, new `world_id`
  (`forked_from` = old), `owner_pid = my_pid`, rebuild actors from the last stream, keep playing
  solo. Log: "Your friend left. The farm carries on with you."
- [ ] **2.3 Guest gone** on the host: keep running; the guest hand stays in `hands`, frozen.
- [ ] **2.4 Rejoin**: a pid already in `hands` gets its hand back; a new pid gets an empty hand.
  Works on either copy (the old host can join the guest's fork).
- [ ] **2.5 Clean exits**: quitting, going to the menu or `stop_hosting` sends `bye` first; tear
  down the peer when the game tree is torn down (`main.back_to_menu`, F5).

### Phase 3: connectivity
- [ ] **3.1 UPnP** in a `Thread` (discover blocks for ~2s): `discover()`, `add_port_mapping(port, port,
  "IdleFarm", "UDP")`, `query_external_address()`; remove the mapping on stop/quit. Report each
  outcome through `status_changed`.
- [ ] **3.2 Address to share**: external `IP:port` when UPnP worked, plus LAN addresses
  (`IP.get_local_addresses()`, IPv4 private ranges); a copy button (`DisplayServer.clipboard_set`).
- [ ] **3.3 Fallback text** when UPnP fails: "forward UDP 24680 to this PC, or play on the same
  network". Note that Windows Firewall asks to allow the game the first time it hosts.
- [ ] **3.4 Guest errors**: connect timeout (~8s), bad address, rejected (show the reason), lost
  connection.

### Phase 4: UI (pixel font, built in code like the rest)
- [ ] **4.1 Text entry widget** for `IP:port` (digits, `.`, `:`, backspace, Ctrl+V paste), reusable.
- [ ] **4.2 Welcome screen "JOIN FRIEND"**: address -> pick slot for the copy (confirm overwrite)
  -> "connecting..." -> in game. Back button cancels.
- [ ] **4.3 Hosting from the game**: settings panel "INVITE FRIEND" -> starts server + UPnP, shows
  the address + copy button + status; "STOP" closes it.
- [ ] **4.4 HUD indicator** in the top bar: hosting / friend here / connecting / lost; log lines
  on join/leave.
- [ ] **4.5 Guest restrictions**: card cadence + speed greyed out, debug keys only on the host.
- [ ] **4.6 Slot summary** on the welcome screen shows "shared" / "fork" when relevant (optional).

### Phase 5: verification & docs
- [ ] **5.1 `tests/net_test.gd` + `net_runner.gd`**: start two headless copies on localhost
  (`profile=1 role=host`, `profile=2 role=guest`); the guest joins, plays a card via a command, and
  the host state shows it; the guest receives state + actors; kill the host -> the guest goes solo
  and its slot file exists; the old host joins the guest's fork and gets its hand back. Exit
  non-zero on failure.
- [ ] **5.2 Two windows on one PC** (standalone runs with profiles): visual check of smoothness,
  card play feel, leave/fork.
- [ ] **5.3 Internet test with UPnP** between two real networks (needs the user).
- [ ] **5.4 Docs**: TODO.md architecture rows (`net.gd`, `commands.gd`), How to run (two
  instances, profiles, port), Gotchas, Changelog; one line in CLAUDE.md / AGENTS.md.

### Phase 0 notes (what exists now)
- `Game.my_pid` (settings `pid`), `Game.profile` (`-- profile=N` -> `settings_pN.json`, `slot_pN_K.json`),
  `Game.new_id()`.
- `Game.hands[pid] = {box, stash, card_timer[, name]}`, `Game.owner_pid`, `Game.present` (not saved;
  only present pids drip), `Game.acting_pid` (set by `cards.choose` and when a delayed effect fires; `pending`
  entries carry `pid`). `Game.box/stash/card_timer` are properties for the local hand. `add_card/
  take_card/move_card/card_at/card_count/draw_card` take an optional `pid`; `Game.card_target()` routes
  cards nobody asked for; `Game.player_name(pid)` ("PLAYER 1" = owner, "PLAYER 2"). `draw_requested`
  now carries a pid. Save version 4 (`hands`, `owner_pid`, `world_id`, `forked_from`, `next_uid`).
- `scripts/commands.gd` (`Commands`, node in GameRoot, `main.commands`, `hud.commands`): `submit(cmd)` /
  `execute(pid, cmd)`; types `choose`, `move_card`, `card_minutes`, `speed`, `debug` (keys in
  `Commands.DEBUG`). Owner-only rules are enforced in `execute`. Debug keys F1-F4, F6-F11 go through it; F5 stays local.
- `uid` on Farmer/Animal from `World.new_uid()`; saved; `World.next_uid` restored as max+1.
- `Game.world_id`, `Game.forked_from`, `Game.fork()`. `main.load_game` forks any slot whose
  `owner_pid` isn't us.
- `Game.puppet` + `Game.simulating()`: gates `Game/director/cards/colony/swarm/tides._process` and
  `World._simulate()` (cosmetic `_anim_t`/particles/redraw keep running). Farmer clicks don't change mood in
  puppet mode. Not yet covered: the guest clock (1.7) and the actors' own animation timers (1.5).
- Not verified in a windowed run yet: the HUD paths now call `commands.submit` (compiles, and the same
  code runs in the headless test, but no clicks have been made).

### Phase 1 notes (what exists now)
- `scripts/net.gd` (autoload **Net**, registered after Game). `Net.host(port)`, `Net.join(ip, port, slot)`,
  `Net.stop()`, `Net.mode` (offline/hosting/joining/guest), `Net.status` + `status_changed`,
  `peer_joined/peer_left(pid)`, `Net.stats` (payload bytes) and `Net.wire()` (bytes on the wire),
  `-- net_verbose` prints status lines. `PORT` 24680, `PROTOCOL` 1, version from
  `application/config/version` (unset -> "dev").
- Host: a hello must arrive within 5s; rejects a protocol/version mismatch, no game running, a second guest, or the
  host's own pid. On accept: `Game.hand(pid)` (+ `name`), `Game.present[pid]`, log "X joined", sends `_welcome`
  (Game + World incl. actors + speed). `_cmd` -> `main.commands.execute(guest_pid, cmd)` and an immediate
  snapshot. State check every 1s (hash of `var_to_bytes`), actors every 0.2s.
- Guest: `main.start_guest(slot, d)` builds the game tree in puppet mode, loads the welcome and saves it to
  the slot (the normal 20s autosave keeps saving it; `owner_pid` stays the host's, so opening that slot
  later forks it, see 0.5). `_state` -> `Game.from_dict` + `World.load_grid` (actors untouched), then
  `cards_changed`, `card_arrived` for new cards in our box, `log_added`. `Game.time_scale` follows the host.
- Actors: `net_fields()` on Animal (+Alien, +Insect) and Farmer (`net_tool` wraps `task.tool`); `net_tick(d)` runs
  instead of `update()` on a guest (anim, bubble/hurt timers, glide to `net_to`, snap if >48px off).
  Missing actors are created from `kind`/`caste`; `gone` removes them.
- FX: `World.puff/float_text`, `WeatherFx.strike/beam/meteor` and `main.shake` call `Net.fx()` (no-op unless
  hosting with a guest); the guest replays them. `director.shake` now connects to `main.shake` (no lambda).
- `World.to_dict(with_actors)`, `World.load_grid(d)` / `load_actors(d)` (`from_dict` = both).
- `main.back_to_menu`, `save_and_quit` and F5 call `Net.stop()` (no goodbye message yet: 2.5).
- Measured (localhost, 21 actors, 15s steady): payload 23.7 KB/s, **wire 6.0 KB/s** (ZSTD), mostly the 1/s
  state snapshot (~20 KB raw). Joining + a card round trip takes ~2.5s. Good enough; diffing the grid
  can wait.
- Known rough edges for later phases: the log says "PLAYER 2 chose..." on both screens (names are 4.x);
  a guest whose host leaves stays frozen (2.2); nothing restricts the guest's settings panel yet (4.5,
  the host rejects those commands anyway).

## Risks / gotchas to keep in mind
- `World.from_dict` rebuilds actors: never call it per snapshot on the guest (task 1.4 split).
- Anything that mutates state from a timer/tween/await bypasses the puppet gate: audit in 0.6.
- Snapshot application emits signals (`cards_changed`, `weather_changed`). Make sure HUD
  reactions are idempotent and don't replay arrival animations every snapshot.
- Guest card modal: the open card may vanish/move after a snapshot (e.g. trashed); the HUD
  already re-checks `card_at(open_where, open_i) == open_id` (hud.gd:92). Keep that behaviour.
- `can_choose` on the guest uses streamed state; the host re-validates and may refuse, so give a
  small "couldn't play that" feedback.
- CGNAT / UPnP-disabled routers cannot host; that's accepted for this transport.

## Log
- 2026-10-24: plan written.
- 2026-10-24: phase 0 done (0.1-0.7). New `scripts/commands.gd`; game/cards/main/hud/world/animal/
  farmer/director/colony/swarm/tides touched; 27 new checks in `tests/sim_runner.gd`, passing on seeds 1-3.
  Found that sim_test was already flaky (see Status).
- 2026-10-24: phase 1 done (1.1-1.8). New `scripts/net.gd` (autoload), `tests/net_test.gd`,
  `tests/net_runner.gd`, `tests/run_net_test.sh`; actor `net_fields/net_tick`, `World.load_grid`,
  `main.start_guest`, FX hooks. Two-copy localhost test passes on both sides; guest screenshot looks right;
  sim_test's multiplayer checks pass (the puppet check now leaves out the guest's ticking clock).
