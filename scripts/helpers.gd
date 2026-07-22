extends Node


const INFO_FILENAME := "catapult_install_info.json"


func create_info_file(location: String, install_name: String) -> void:
	
	var info = {"name": install_name}
	var path = location + "/" + INFO_FILENAME
	var info_file := FileAccess.open(path, FileAccess.WRITE)
	if info_file:
		info_file.store_string(JSON.stringify(info, "    "))
		info_file.close()
	else:
		Status.post(tr("msg_cannot_create_install_info") % path, Enums.MSG_ERROR)


func get_all_nodes_within(n: Node) -> Array:
	
	var result = []
	for node in n.get_children():
		result.append(node)
		if node.get_child_count() > 0:
			result.append_array(get_all_nodes_within(node))
	return result


func load_json_file(file: String) -> Variant:
	
	var f := FileAccess.open(file, FileAccess.READ)
	
	if f == null:
		Status.post(tr("msg_file_read_fail") % [file.get_file(), FileAccess.get_open_error()], Enums.MSG_ERROR)
		Status.post(tr("msg_debug_file_path") % file, Enums.MSG_DEBUG)
		return null
	
	var json := JSON.new()
	var err := json.parse(f.get_as_text())
	var data = json.get_data()
	f.close()
	
	if err:
		Status.post(tr("msg_json_parse_fail") % file.get_file(), Enums.MSG_ERROR)
		Status.post(tr("msg_debug_json_result") % [err, json.get_error_message(), json.get_error_line()], Enums.MSG_DEBUG)
		return null
	
	# Reject non-object/array payloads: a scalar or error-shaped response (e.g.
	# GitHub returning HTML on outage, or a MITM/HTML body) would otherwise be
	# indexed later as a Dictionary and crash with "Invalid get index".
	if not (data is Dictionary or data is Array):
		Status.post(tr("msg_json_unexpected_shape") % file.get_file(), Enums.MSG_ERROR)
		return null
	
	return data


# Returns true if `name` is safe to use as a single path component (a file/zip
# name). Rejects anything that could escape the intended directory: path
# separators, parent-dir references (".."), and any character outside a strict
# allow-list. Used to confine remote-controlled filenames (GitHub asset names,
# mod/soundpack names) so they cannot be used for path traversal / arbitrary
# file write.
func is_safe_filename(name: String) -> bool:
	
	if name == "":
		return false
	# is_valid_filename() already rejects slashes, backslashes, "..", and
	# device/UNC patterns; the allow-list below tightens it further.
	if not name.is_valid_filename():
		return false
	if ".." in name:
		return false
	return true


# Safely joins a base directory with a single (sanitized) file name. Returns ""
# if the name is unsafe, so callers MUST check for "" and bail. Prefer this over
# raw `base + "/" + name` (which does not normalize and enables traversal).
func safe_join(base_dir: String, name: String) -> String:
	
	if not is_safe_filename(name):
		return ""
	return base_dir.path_join(name)


# Returns a sanitized copy of `world` safe to interpolate inside a cmd /C
# command. The game engine must be launched from its own directory (Godot 4
# has no CWD setter, so we use `cd /d`), and the original code interpolated an
# unsanitized world name into that command -- a crafted save/world name could
# break the quoting and inject commands (RCE on Resume). Only the strict
# allow-list below is permitted; anything else returns "" so the caller drops
# --world instead of risking injection.
func sanitize_world_name(world: String) -> String:
	
	var allowed := RegEx.create_from_string("^[A-Za-z0-9 _\\-]+$")
	if allowed.search(world) != null:
		return world
	return ""


# Opens `meta` via OS.shell_open ONLY for http(s) web links. The value can come
# from remote data (GitHub release/changelog URLs), so a crafted value
# (file://..., a dangerous protocol handler, an UNC path) must never reach the
# OS shell. Returns true if it was opened.
func safe_shell_open(meta: String) -> bool:
	
	if meta.begins_with("http://") or meta.begins_with("https://"):
		OS.shell_open(meta)
		return true
	Status.post(tr("msg_shell_open_rejected") % meta, Enums.MSG_ERROR)
	return false


func save_to_json_file(data, file: String) -> bool:
	
	var f := FileAccess.open(file, FileAccess.WRITE)
	
	if f == null:
		Status.post(tr("msg_file_write_fail") % [file.get_file(), FileAccess.get_open_error()], Enums.MSG_ERROR)
		Status.post(tr("msg_debug_file_path") % file, Enums.MSG_DEBUG)
		return false
	
	var text := JSON.stringify(data, "    ")
	f.store_string(text)
	f.close()
	
	return true
