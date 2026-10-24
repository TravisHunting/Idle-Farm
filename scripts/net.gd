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
## Hosting also asks the router to forward the port (UPnP, in a thread); `share_address()` is what
## the friend types in. Without UPnP the host forwards the port by hand, or both play on one network.

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
const JOIN_TIMEOUT := 8.0         # no welcome by then: give up
const UPNP_WAIT_MS := 2000        # how long discover() listens for the router
const UPNP_LEASE := 7200          # seconds: the router drops the mapping by itself if we crash (0 = forever)
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
var use_upnp := true              # ask the router to forward the port when hosting (tests turn it off)
var host_port := 0
var upnp_state := ""              # "" (not tried) / "working" / "open" / "failed"
var upnp_why := ""                # why it failed, for the help text
var external_ip := ""             # from the router, when UPnP worked
var upnp_lease := 0               # seconds the router keeps the mapping (0 = until removed)
var upnp_fake := {}               # tests: pretend the router answered this ({ok, ip} or {ok: false, why})

var _peer: ENetMultiplayerPeer
var _state_t := 0.0
var _actors_t := 0.0
var _key_t := 0.0
var _last_state_hash := 0
var _state_now := false
var _sent := {}                   # host: uid -> values last sent (actor deltas)
var _fx: Array = []               # host: effects to replay on the guest
var _hello_wait := {}             # host: peer id -> seconds left to say hello
var _join_t := 0.0                # guest: seconds left to get in
var _join_addr := ""
var _upnp_thread: Thread
var _upnp: UPNP                   # the router we mapped the port on (to unmap it again)


func _ready() -> void:
	verbose = "net_verbose" in OS.get_cmdline_user_args()
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


func _exit_tree() -> void:
	if _upnp_thread:
		_unmap(_upnp_thread.wait_to_finish().get("upnp"))
		_upnp_thread = null


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
	host_port = port
	var my_name := String(Game.settings.get("name", "")).strip_edges().to_upper()
	if my_name != "":
		Game.hand()["name"] = my_name
	if use_upnp:
		_start_upnp(port)
	else:
		upnp_state = ""
		_set_status("Hosting. Your friend joins at %s." % share_address())
	return OK


# ---------------------------------------------------------------- the router (UPnP) + addresses
func _start_upnp(port: int) -> void:
	if _upnp_thread:
		_unmap(_upnp_thread.wait_to_finish().get("upnp"))   # an earlier attempt still running
		_upnp_thread = null
	upnp_state = "working"
	upnp_why = ""
	external_ip = ""
	_set_status("Hosting. Asking your router to open port %d..." % port)
	_upnp_thread = Thread.new()
	_upnp_thread.start(_upnp_job.bind(port, upnp_fake.duplicate()))


## Runs in a thread: find the router, forward the UDP port, ask for the internet address.
func _upnp_job(port: int, fake: Dictionary) -> Dictionary:
	if not fake.is_empty():
		return fake
	var u := UPNP.new()
	var err := u.discover(UPNP_WAIT_MS, 2, "InternetGatewayDevice")
	if err != UPNP.UPNP_RESULT_SUCCESS:
		return {"ok": false, "why": "no router answered (UPnP may be off on the router, or Windows calls this a Public network)" if err == UPNP.UPNP_RESULT_NO_DEVICES else "no UPnP router found (%d)" % err}
	var gw := u.get_gateway()
	if gw == null or not gw.is_valid_gateway():
		return {"ok": false, "why": "the router doesn't do UPnP"}
	var lease := UPNP_LEASE
	err = u.add_port_mapping(port, port, "IdleFarm", "UDP", lease)
	if err != UPNP.UPNP_RESULT_SUCCESS:
		lease = 0   # some routers only take permanent mappings
		err = u.add_port_mapping(port, port, "IdleFarm", "UDP", 0)
	if err != UPNP.UPNP_RESULT_SUCCESS:
		return {"ok": false, "why": "the router said no (%d)" % err}
	return {"ok": true, "ip": u.query_external_address(), "upnp": u, "lease": lease}


func _finish_upnp() -> void:
	var r: Dictionary = _upnp_thread.wait_to_finish()
	_upnp_thread = null
	if mode != "hosting":
		_unmap(r.get("upnp"))   # stopped hosting while we waited
		return
	if r.get("ok", false):
		upnp_state = "open"
		_upnp = r.get("upnp")
		external_ip = String(r.get("ip", ""))
		upnp_lease = int(r.get("lease", 0))
		_set_status("Port open! Your friend joins at %s." % share_address())
	else:
		upnp_state = "failed"
		upnp_why = String(r.get("why", "unknown"))
		_set_status("Hosting, but the router wouldn't open the port (%s). Same network: %s" % [upnp_why, share_address()])


func _unmap(u: Variant) -> void:
	if u is UPNP and host_port > 0:
		(u as UPNP).delete_port_mapping(host_port, "UDP")


## This machine's addresses on the local network (IPv4, private ranges).
func lan_addresses() -> Array:
	var out: Array = []
	for a in IP.get_local_addresses():
		if a.begins_with("10.") or a.begins_with("192.168."):
			out.append(a)
		elif a.begins_with("172."):
			var b := int(a.get_slice(".", 1))
			if b >= 16 and b <= 31:
				out.append(a)
	return out


## What the friend should type: the internet address if the router opened the port, else this
## PC's address on the local network.
func share_address() -> String:
	var port := host_port if host_port > 0 else PORT
	if upnp_state == "open" and external_ip != "":
		return "%s:%d" % [external_ip, port]
	var lan := lan_addresses()
	return "%s:%d" % [lan[0] if not lan.is_empty() else "127.0.0.1", port]


func copy_address() -> void:
	DisplayServer.clipboard_set(share_address())


## Lines for the hosting panel: what to share, and what to do if the router didn't play along.
func help_lines() -> Array:
	var lines: Array = []
	match upnp_state:
		"working":
			lines.append("Asking your router to open the port...")
		"open":
			lines.append("Friend types: %s" % share_address())
			var lan := lan_addresses()
			if not lan.is_empty():
				lines.append("On the same network: %s:%d" % [lan[0], host_port])
		_:
			lines.append("Same network: %s" % share_address())
			if upnp_state == "failed":
				lines.append("Router: %s." % upnp_why)
			lines.append("Over the internet: forward UDP port %d to this PC in your router." % host_port)
	lines.append("Windows may ask to let the game through the firewall: allow it.")
	return lines


## "1.2.3.4:5678" / "host.name" / "[::1]:5678" -> ["1.2.3.4", 5678] (default port), [] if it's no address.
static func parse_address(text: String) -> Array:
	var t := text.strip_edges()
	if t == "" or " " in t:
		return []
	var ip := t
	var port := PORT
	if t.begins_with("["):   # [ipv6]:port
		var close := t.find("]")
		if close < 0:
			return []
		ip = t.substr(1, close - 1)
		var rest := t.substr(close + 1)
		if rest != "":
			if not rest.begins_with(":") or not rest.substr(1).is_valid_int():
				return []
			port = int(rest.substr(1))
	elif t.count(":") == 1:
		ip = t.get_slice(":", 0)
		var p := t.get_slice(":", 1)
		if not p.is_valid_int():
			return []
		port = int(p)
	elif t.count(":") > 1:
		ip = t   # a bare IPv6 address
	if ip == "" or port < 1 or port > 65535:
		return []
	if ip.is_valid_ip_address():
		return [ip, port]
	# a host name: letters, digits, dots and dashes
	for ch in ip:
		if not (ch == "." or ch == "-" or (ch >= "a" and ch <= "z") or (ch >= "A" and ch <= "Z") or (ch >= "0" and ch <= "9")):
			return []
	if ip.split(".").size() == 4 and ip.replace(".", "").is_valid_int():
		return []   # looks like an IPv4 address but isn't one (999.1.1.1)
	return [ip, port]


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
	main.world.ensure_friend(pid)   # their own farmer, hut and mailbox
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
	elif String(cmd.get("type", "")) != "poke":   # a missed click needs no telling off
		var why := "That card can't be played right now." if String(cmd.get("type", "")) == "choose" else "Only the host can change that."
		_refused.rpc_id(id, why)


@rpc("authority", "call_remote", "reliable")
func _refused(why: String) -> void:
	_set_status(why)


## Called by the game for one-shot visuals ("puff", "float", "strike", "beam", "meteor", "shake").
func fx(kind: String, args: Array) -> void:
	if live_host() and _fx.size() < 200:
		_fx.append([kind, args])


func _process(delta: float) -> void:
	if _upnp_thread and not _upnp_thread.is_alive():
		_finish_upnp()
	if mode == "joining":
		_join_t -= delta
		if _join_t <= 0.0:
			stop(false)
			_set_status("No answer from %s. Is your friend's game open and hosting? Check the address and port." % _join_addr)
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
	if world.friend:
		actors.append(world.friend)
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
			var kind: String = "farmer" if a == world.farmer else ("friend" if a == world.friend else a.kind)
			entries.append([a.uid, kind, caste, delta])
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
	_join_t = JOIN_TIMEOUT
	_join_addr = "%s:%d" % [ip, port]
	_set_status("Connecting to %s..." % _join_addr)
	return OK


func _on_connected() -> void:
	if mode != "joining":
		return
	_peer.get_peer(1).set_timeout(0, PEER_TIMEOUT_MS / 2, PEER_TIMEOUT_MS)
	_hello.rpc_id(1, {"protocol": PROTOCOL, "version": game_version(), "pid": Game.my_pid,
		"name": String(Game.settings.get("name", ""))})
	_set_status("Connected, saying hello...")


func _on_connection_failed() -> void:
	stop(false)
	_set_status("Couldn't reach %s. Is your friend's game open and hosting?" % _join_addr)


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
		if last_exit == "bye":
			_set_status("Your friend went home. The farm is yours now.")
		else:
			_set_status("Lost the connection to your friend. The farm is yours now.")
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
	stop(false)
	_set_status("Couldn't join: %s" % reason)


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
		var a: Variant = world.farmer if kind == "farmer" else (world.friend if kind == "friend" else by_uid.get(uid))
		var fresh := false
		if a == null and kind == "friend":
			world.friend = Farmer.new(world)
			world.friend.friend = true
			a = world.friend
			fresh = true
		elif a == null:
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
		elif world.friend and world.friend.uid == int(u):
			world.friend = null
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
	if _upnp:
		_unmap(_upnp)   # a quick request to the router
		_upnp = null
	upnp_state = ""
	external_ip = ""
	mode = "offline"
	guest_peer = 0
	guest_pid = ""
	_hello_wait = {}
	_sent = {}
	_fx = []
	_last_state_hash = 0
