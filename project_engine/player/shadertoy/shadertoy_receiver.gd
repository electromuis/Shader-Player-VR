@tool
class_name ShadertoyReceiver
extends Node

## Where the Chrome extension (tools/shadertoy_extension) sends shaders: a
## small HTTP server on 127.0.0.1, the first free port from DEFAULT_PORT
## (the extension tries them in order). What it receives goes into
## `library`. The authoring addon has a copy (addon_vj/shadertoy/, kept
## identical by tests/test_addon_shader_copies.gd).
##
##   GET  /vj/ping       → {"app", "version"}
##   POST /vj/shadertoy  ← {"shader": <the site's JSON>, "thumbnail": <base64 JPEG>}
##                       → {"ok", "id", "name", "errors", "edits", "warnings"}
##                         (ShadertoyShader.analyze), or {"ok": false, "error"}
##
## Only the extension may post: requests from web pages carry their origin
## and are refused, and so are other Host names (DNS rebinding).

signal received(shader: Dictionary)
signal pinged

const DEFAULT_PORT := 47811
const PORT_TRIES := 5
const VERSION := 1
const MAX_BODY := 16 * 1024 * 1024

var library: ShadertoyLibrary
## Shown by the extension ("Sent to <app>").
var app_name := "Godot"
var port: int = 0
var last_ping_msec: int = -1
var _server: TCPServer
var _clients: Array = []  # [{peer: StreamPeerTCP, buf: PackedByteArray, since: msec}]


func start(preferred_port: int = DEFAULT_PORT) -> bool:
	if _server != null:
		return true
	_server = TCPServer.new()
	for i in PORT_TRIES:
		if _server.listen(preferred_port + i, "127.0.0.1") == OK:
			port = preferred_port + i
			return true
	push_warning("Shadertoy receiver: no free port in %d-%d." % [preferred_port, preferred_port + PORT_TRIES - 1])
	_server = null
	return false


func stop() -> void:
	for c in _clients:
		c.peer.disconnect_from_host()
	_clients.clear()
	if _server != null:
		_server.stop()
		_server = null


func is_listening() -> bool:
	return _server != null


func _exit_tree() -> void:
	stop()


func _process(_delta: float) -> void:
	if _server == null:
		return
	while _server.is_connection_available():
		_clients.append({"peer": _server.take_connection(), "buf": PackedByteArray(), "since": Time.get_ticks_msec()})
	for c in _clients.duplicate():
		var peer: StreamPeerTCP = c.peer
		peer.poll()
		if peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
			_clients.erase(c)
			continue
		var n := peer.get_available_bytes()
		if n > 0:
			var got := peer.get_data(n)
			if got[0] == OK:
				c.buf.append_array(got[1])
		var req := parse_request(c.buf)
		if req.is_empty() and Time.get_ticks_msec() - c.since < 10000 and c.buf.size() <= MAX_BODY + 65536:
			continue  # not all here yet
		var res: Array = [400, {"ok": false, "error": "bad request"}] if req.is_empty() else handle(req)
		_respond(peer, res[0], res[1])
		_clients.erase(c)


## {method, path, headers (lower-case names), body} once `buf` holds a
## whole request, else {}.
static func parse_request(buf: PackedByteArray) -> Dictionary:
	var text := buf.get_string_from_ascii()
	var end := text.find("\r\n\r\n")
	if end < 0:
		return {}
	var lines := text.substr(0, end).split("\r\n")
	var first := lines[0].split(" ")
	if first.size() < 2:
		return {"method": "", "path": "", "headers": {}, "body": PackedByteArray()}
	var headers := {}
	for i in range(1, lines.size()):
		var colon := lines[i].find(":")
		if colon > 0:
			headers[lines[i].substr(0, colon).strip_edges().to_lower()] = lines[i].substr(colon + 1).strip_edges()
	var length := int(headers.get("content-length", "0"))
	if length > MAX_BODY:
		return {"method": first[0], "path": first[1], "headers": headers, "body": PackedByteArray(), "too_big": true}
	var body_start := end + 4
	if buf.size() < body_start + length:
		return {}
	return {"method": first[0], "path": first[1], "headers": headers, "body": buf.slice(body_start, body_start + length)}


## [status, reply] for a request (see the top of this file).
func handle(req: Dictionary) -> Array:
	var headers: Dictionary = req.headers
	var origin := String(headers.get("origin", ""))
	if origin != "" and not (origin.begins_with("chrome-extension://") or origin.begins_with("moz-extension://")):
		return [403, {"ok": false, "error": "only the extension may send shaders"}]
	var host := String(headers.get("host", ""))
	if not host in ["127.0.0.1:%d" % port, "localhost:%d" % port]:
		return [403, {"ok": false, "error": "wrong host"}]
	match [req.method, req.path]:
		["GET", "/vj/ping"]:
			last_ping_msec = Time.get_ticks_msec()
			pinged.emit()
			return [200, {"app": app_name, "version": VERSION}]
		["POST", "/vj/shadertoy"]:
			if req.get("too_big", false):
				return [413, {"ok": false, "error": "too big"}]
			if not String(headers.get("content-type", "")).begins_with("application/json"):
				return [415, {"ok": false, "error": "send JSON"}]
			var msg = JSON.parse_string(req.body.get_string_from_utf8())
			if not msg is Dictionary or not msg.has("shader"):
				return [400, {"ok": false, "error": "no shader"}]
			var thumb := PackedByteArray()
			if msg.get("thumbnail") is String and msg.thumbnail != "":
				thumb = Marshalls.base64_to_raw(msg.thumbnail)
			var st := library.add(msg.shader, thumb)
			if st.is_empty():
				return [400, {"ok": false, "error": "that isn't a Shadertoy shader"}]
			last_ping_msec = Time.get_ticks_msec()
			received.emit(st)
			var a := ShadertoyShader.analyze(st)
			return [200, {"ok": true, "id": st.id, "name": st.name, "app": app_name,
					"errors": a.errors, "edits": a.edits, "warnings": a.warnings}]
	return [404, {"ok": false, "error": "not found"}]


static func _respond(peer: StreamPeerTCP, status: int, reply: Dictionary) -> void:
	var body := JSON.stringify(reply).to_utf8_buffer()
	var reason := {200: "OK", 400: "Bad Request", 403: "Forbidden", 404: "Not Found", 413: "Payload Too Large", 415: "Unsupported Media Type"}
	var head := "HTTP/1.1 %d %s\r\nContent-Type: application/json\r\nContent-Length: %d\r\nConnection: close\r\n\r\n" % [
			status, reason.get(status, "Error"), body.size()]
	peer.put_data(head.to_ascii_buffer())
	peer.put_data(body)
	peer.disconnect_from_host()
