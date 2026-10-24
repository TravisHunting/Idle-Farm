extends Node
## Net (autoload): two-player "join world" over ENet (see MULTIPLAYER.md).
## The host runs the game as usual; the guest's game runs in puppet mode (Game.puppet) and only
## shows what the host streams to it, sending its own actions back as commands (Commands.submit).
##   host -> guest  _welcome  the whole world once (Game + World incl. actors)
##                  _state    Game + World without actors, when it changed (checked every second)
##                  _actors   actor deltas + one-shot effects, ~5x a second
##                  _reject
##   guest -> host  _hello {protocol, version, pid, name}, _cmd {command}
##   either way     _bye: leaving on purpose (the other side doesn't have to wait for a timeout)
## When the host goes, the guest keeps the farm as its own world (main.host_left); when the guest
## goes, the host carries on and the guest's hand waits in the save for them to come back.
## Only Net's own node path is used for RPCs, so it is the same on both machines.

signal status_changed(text: String)
signal peer_joined(pid: String)
signal peer_left(pid: String)

const PORT := 24680
const PROTOCOL := 1
const STATE_EVERY := 1.0
const ACTORS_EVERY := 0.2
const KEYFRAME_EVERY := 10.0      # resend every actor in full now and then
const HELLO_TIMEOUT := 5.0
const PEER_TIMEOUT_MS := 5000
## Actor timers that tick down on the guest too: only sent when they go up.
const DECAYING := ["bubble_t", "hurt_t"]

var main: Node                    # main.gd, registers itself
var mode := "offline"             # offline / hosting / joining / guest
var status := ""
var guest_pid := ""               # host: who is visiting
var guest_peer := 0
var join_slot := 1                # guest: where the shared world is kept
var last_exit := ""               # why the other side went: "bye" (on purpose) or "lost" (dropped / timed out)
var stats := {"sent": 0, "received": 0, "states": 0, "actors": 0}
var verbose := false

var _peer: ENetMultiplayerPeer
var _state_t := 0.0
var _actors_t := 0.0
var _key_t := 0.0
var _last_state_hash := 0
var _state_now := false
var _sent := {}                   # host: uid -> values last sent (actor deltas)
var _fx: Array = []               # host: effects to replay on the guest
var _hello_wait := {}             # host: peer id -> seconds left to say hello


func _ready() -> void:
	verbose = "net_verbose" in OS.get_cmdline_user_args()
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


func game_version() -> String:
	return str(ProjectSettings.get_setting("application/config/version", "dev"))


func is_guest() -> bool:
	return mode == "guest"


## Hosting with a guest in the world: record effects for them.
func live_host() -> bool:
	return mode == "hosting" and guest_peer != 0


func _set_status(t: String) -> void:
	status = t
	if verbose:
		print("[net] ", t)
	status_changed.emit(t)


# ---------------------------------------------------------------- host
func host(port: int = PORT) -> Error:
	stop()
	if main == null or not Game.running or Game.puppet:
		return ERR_UNAVAILABLE
	_peer = ENetMultiplayerPeer.new()
	var err := _peer.create_server(port, 1)
	if err != OK:
		_peer = null
		_set_status("Couldn't open port %d (%s)." % [port, error_string(err)])
		return err
	_peer.host.compress(ENetConnection.COMPRESS_ZSTD)
	multiplayer.multiplayer_peer = _peer
	mode = "hosting"
	_set_status("Hosting on port %d." % port)
	return OK


func _on_peer_connected(id: int) -> void:
	if mode == "hosting":
		_hello_wait[id] = HELLO_TIMEOUT
		_peer.get_peer(id).set_timeout(0, PEER_TIMEOUT_MS / 2, PEER_TIMEOUT_MS)


func _on_peer_disconnected(id: int) -> void:
	_hello_wait.erase(id)
	if mode == "hosting" and id == guest_peer:
		last_exit = "lost"
		var pid := guest_pid
		guest_peer = 0
		guest_pid = ""
		Game.present.erase(pid)
		Game.add_log("%s left the farm." % Game.player_name(pid))
		_set_status("Your friend left.")
		peer_left.emit(pid)


@rpc("any_peer", "call_remote", "reliable")
func _hello(info: Dictionary) -> void:
	var id := multiplayer.get_remote_sender_id()
	if mode != "hosting":
		return
	_hello_wait.erase(id)
	var reason := ""
	var pid := String(info.get("pid", ""))
	if int(info.get("protocol", -1)) != PROTOCOL or String(info.get("version", "")) != game_version():
		reason = "Different game versions (host %s, you %s)." % [game_version(), String(info.get("version", "?"))]
	elif main == null or not Game.running or Game.puppet:
		reason = "The host isn't on a farm right now."
	elif guest_peer != 0:
		reason = "Someone is already visiting."
	elif pid.length() != 16 or pid == Game.my_pid:
		reason = "Same player id as the host (a second copy on one PC needs -- profile=2)."
	if reason != "":
		_reject.rpc_id(id, reason)
		_kick_later(id)
		return
	guest_peer = id
	guest_pid = pid
	var h := Game.hand(pid)
	var nm := String(info.get("name", "")).strip_edges().substr(0, 12).to_upper()
	if nm != "":
		h["name"] = nm
	Game.present[pid] = true
	_sent = {}
	_fx = []
	_key_t = 0.0
	Game.add_log("%s joined the farm!" % Game.player_name(pid))
	var d := {"game": Game.to_dict(), "world": main.world.to_dict(), "speed": Game.time_scale}
	_send(id, "_welcome", var_to_bytes(d))
	_state_now = true
	_set_status("%s is here." % Game.player_name(pid))
	peer_joined.emit(pid)


func _kick_later(id: int) -> void:
	await get_tree().create_timer(0.5).timeout
	if _peer and mode == "hosting":
		_peer.disconnect_peer(id)


@rpc("any_peer", "call_remote", "reliable")
func _cmd(cmd: Dictionary) -> void:
	var id := multiplayer.get_remote_sender_id()
	if mode != "hosting" or id != guest_peer or main == null:
		return
	if main.commands.execute(guest_pid, cmd):
		_state_now = true


## Called by the game for one-shot visuals ("puff", "float", "strike", "beam", "meteor", "shake").
func fx(kind: String, args: Array) -> void:
	if live_host() and _fx.size() < 200:
		_fx.append([kind, args])


func _process(delta: float) -> void:
	for id in _hello_wait.keys():
		_hello_wait[id] -= delta
		if _hello_wait[id] <= 0.0:
			_hello_wait.erase(id)
			if _peer:
				_peer.disconnect_peer(id)
	if not live_host() or main == null or main.world == null:
		return
	_state_t -= delta
	if _state_t <= 0.0 or _state_now:
		_state_t = STATE_EVERY
		_state_now = false
		var d := {"game": Game.to_dict(), "world": main.world.to_dict(false), "speed": Game.time_scale}
		var b := var_to_bytes(d)
		var h := hash(b)
		if h != _last_state_hash:
			_last_state_hash = h
			_send(guest_peer, "_state", b)
			stats["states"] += 1
	_actors_t -= delta
	_key_t -= delta
	if _actors_t <= 0.0:
		_actors_t = ACTORS_EVERY
		var full := _key_t <= 0.0
		if full:
			_key_t = KEYFRAME_EVERY
		_send(guest_peer, "_actors", var_to_bytes(_actors_packet(full)))
		stats["actors"] += 1


## [entries, gone, fx]: entries are [uid, kind, caste, {field index: value}] with only the fields
## that changed since they were last sent.
func _actors_packet(full: bool) -> Array:
	var world: World = main.world
	var entries: Array = []
	var here := {}
	var actors: Array = [world.farmer] if world.farmer else []
	actors.append_array(world.animals)
	for a in actors:
		var fields: Array = a.net_fields()
		var last: Array = _sent.get(a.uid, [])
		var delta := {}
		for i in fields.size():
			var v: Variant = a.get(fields[i])
			if full or last.is_empty() or _changed(fields[i], v, last[i]):
				delta[i] = v
				if not last.is_empty():
					last[i] = v
		if last.is_empty():
			last = []
			for f in fields:
				last.append(a.get(f))
			_sent[a.uid] = last
		here[a.uid] = true
		if not delta.is_empty():
			var caste: String = a.caste if (a is Alien or a is Insect) else ""
			entries.append([a.uid, "farmer" if a == world.farmer else a.kind, caste, delta])
	var gone: Array = []
	for u in _sent.keys():
		if not here.has(u):
			gone.append(u)
			_sent.erase(u)
	var out := [entries, gone, _fx]
	_fx = []
	return out


func _changed(field: String, v: Variant, last: Variant) -> bool:
	if typeof(v) != typeof(last):
		return true
	if field in DECAYING:
		return float(v) > float(last) + 0.05 or (float(v) <= 0.0 and float(last) > 0.0)
	match typeof(v):
		TYPE_FLOAT:
			return absf(v - last) > (1.0 if field == "age" else 0.05)
		TYPE_VECTOR2:
			return (v as Vector2).distance_to(last) > 0.25
	return v != last


# ---------------------------------------------------------------- guest
## Join a host; the shared world will be kept in save slot `slot`.
func join(ip: String, port: int = PORT, slot: int = 1) -> Error:
	stop()
	join_slot = slot
	_peer = ENetMultiplayerPeer.new()
	var err := _peer.create_client(ip, port)
	if err != OK:
		_peer = null
		_set_status("Can't connect to %s:%d (%s)." % [ip, port, error_string(err)])
		return err
	_peer.host.compress(ENetConnection.COMPRESS_ZSTD)
	multiplayer.multiplayer_peer = _peer
	mode = "joining"
	_set_status("Connecting to %s:%d..." % [ip, port])
	return OK


func _on_connected() -> void:
	if mode != "joining":
		return
	_peer.get_peer(1).set_timeout(0, PEER_TIMEOUT_MS / 2, PEER_TIMEOUT_MS)
	_hello.rpc_id(1, {"protocol": PROTOCOL, "version": game_version(), "pid": Game.my_pid,
		"name": String(Game.settings.get("name", ""))})
	_set_status("Connected, saying hello...")


func _on_connection_failed() -> void:
	_set_status("Couldn't reach the host.")
	stop()


func _on_server_disconnected() -> void:
	if mode == "closing":
		return
	if mode != "offline":
		last_exit = "lost"
	_host_gone()


## The host left (said bye, closed the game or timed out): a guest keeps the farm as its own.
func _host_gone() -> void:
	var was_guest := mode == "guest"
	if mode == "offline":
		return
	stop(false)
	if was_guest and main:
		main.host_left()
		_set_status("The host left. The farm is yours now.")
	else:
		_set_status("The host closed the connection.")


@rpc("any_peer", "call_remote", "reliable")
func _bye() -> void:
	var id := multiplayer.get_remote_sender_id()
	if mode == "guest" and id == 1:
		last_exit = "bye"
		_host_gone()
	elif mode == "hosting" and id == guest_peer:
		_on_peer_disconnected(id)
		last_exit = "bye"
		if _peer:
			_peer.disconnect_peer(id)


@rpc("authority", "call_remote", "reliable")
func _reject(reason: String) -> void:
	_set_status("The host said no: %s" % reason)
	stop()


@rpc("authority", "call_remote", "reliable")
func _welcome(b: PackedByteArray) -> void:
	stats["received"] += b.size()
	var d: Variant = bytes_to_var(b)
	if mode != "joining" or typeof(d) != TYPE_DICTIONARY or main == null:
		return
	mode = "guest"
	main.start_guest(join_slot, d)
	_set_status("Joined the farm.")


@rpc("authority", "call_remote", "reliable")
func _state(b: PackedByteArray) -> void:
	stats["received"] += b.size()
	stats["states"] += 1
	var d: Variant = bytes_to_var(b)
	if mode != "guest" or typeof(d) != TYPE_DICTIONARY or main == null or main.world == null:
		return
	var had: Array = Game.box.duplicate()
	var log_n := Game.log_lines.size()
	var last_log: String = Game.log_lines[-1] if log_n > 0 else ""
	Game.from_dict(d.get("game", {}))
	Game.time_scale = float(d.get("speed", 1.0))
	main.world.load_grid(d.get("world", {}))
	Game.cards_changed.emit()
	for id in Game.box:
		if id != "" and not id in had and not id in Game.stash:
			Game.card_arrived.emit(id)
	if Game.log_lines.size() > 0 and (Game.log_lines[-1] != last_log or Game.log_lines.size() != log_n):
		Game.log_added.emit(Game.log_lines[-1])


@rpc("authority", "call_remote", "reliable", 1)
func _actors(b: PackedByteArray) -> void:
	stats["received"] += b.size()
	stats["actors"] += 1
	var p: Variant = bytes_to_var(b)
	if mode != "guest" or typeof(p) != TYPE_ARRAY or main == null or main.world == null:
		return
	var world: World = main.world
	var by_uid := {}
	for a in world.animals:
		by_uid[a.uid] = a
	for e in p[0]:
		var uid := int(e[0])
		var kind := String(e[1])
		var delta: Dictionary = e[3]
		var a: Variant = world.farmer if kind == "farmer" else by_uid.get(uid)
		var fresh := false
		if a == null:
			var at: Vector2 = delta.get(0, Vector2(-40, -40))
			if kind == "alien":
				a = Alien.new(world, String(e[2]), at)
			elif kind == "insect":
				a = Insect.new(world, String(e[2]), at)
			else:
				a = Animal.new(world, kind, at)
			world.animals.append(a)
			by_uid[uid] = a
			fresh = true
		a.uid = uid
		var fields: Array = a.net_fields()
		for i in delta:
			var f: String = fields[int(i)]
			if f == "pos":
				a.net_to = delta[i]
				if fresh or (a.pos as Vector2).distance_to(delta[i]) > 48.0:
					a.pos = delta[i]
			else:
				a.set(f, delta[i])
	for u in p[1]:
		var g: Variant = by_uid.get(int(u))
		if g:
			world.animals.erase(g)
	for f in p[2]:
		_replay(String(f[0]), f[1])


func _replay(kind: String, args: Array) -> void:
	var world: World = main.world
	match kind:
		"puff":
			world.callv("puff", args)
		"float":
			world.callv("float_text", args)
		"strike", "beam", "meteor":
			if main.weather_fx:
				main.weather_fx.callv(kind, args)
		"shake":
			main.shake(float(args[0]))


## Guest: send an action to the host.
func send_command(cmd: Dictionary) -> void:
	if mode == "guest":
		var b := var_to_bytes(cmd)
		stats["sent"] += b.size()
		_cmd.rpc_id(1, cmd)


# ---------------------------------------------------------------- both
## Bytes that actually crossed the network (compressed, with ENet overhead) since connecting.
func wire() -> Dictionary:
	if _peer and _peer.host:
		stats["wire_sent"] = int(stats.get("wire_sent", 0)) + int(_peer.host.pop_statistic(ENetConnection.HOST_TOTAL_SENT_DATA))
		stats["wire_received"] = int(stats.get("wire_received", 0)) + int(_peer.host.pop_statistic(ENetConnection.HOST_TOTAL_RECEIVED_DATA))
	return {"sent": int(stats.get("wire_sent", 0)), "received": int(stats.get("wire_received", 0))}


func _send(id: int, method: String, b: PackedByteArray) -> void:
	stats["sent"] += b.size()
	rpc_id(id, method, b)


## Close the connection; with `bye`, tell the other side first (and let it arrive, up to ~0.3s)
## so it knows we left on purpose instead of waiting for a timeout.
func stop(bye: bool = true) -> void:
	var was_hosting := mode == "hosting"
	if _peer and bye and (mode == "guest" or (was_hosting and guest_peer != 0)):
		var to := 1 if mode == "guest" else guest_peer
		_bye.rpc_id(to)
		var pp := _peer.get_peer(to)
		mode = "closing"   # our own disconnect events below are not news
		if pp:
			pp.peer_disconnect_later()
		for i in 30:
			_peer.poll()
			if pp == null or pp.get_state() == ENetPacketPeer.STATE_DISCONNECTED:
				break
			OS.delay_msec(10)
	if _peer:
		_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	_peer = null
	if was_hosting and guest_pid != "":
		Game.present.erase(guest_pid)
	mode = "offline"
	guest_peer = 0
	guest_pid = ""
	_hello_wait = {}
	_sent = {}
	_fx = []
	_last_state_hash = 0
