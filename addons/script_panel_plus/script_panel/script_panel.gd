@tool
extends HBoxContainer

signal current_script_changed

## Engine's Internal Nodes
var plugin_reference:          EditorPlugin
var engine_editor_interface:   EditorInterface
var engine_script_editor:      ScriptEditor
var engine_script_list:        ItemList

## new Nodes
var script_list:     ItemList
var error_label:     Label
var line_label:      Label
var script_label:    Label
var menu_button:     MenuButton
var search_line:     LineEdit
var tab_bar:         TabBar
var popup:           PopupMenu
var rename_bar:      BoxContainer
var rename_bar_line: LineEdit
var hide_button: BaseButton
var show_button: BaseButton

var save_data := {}
var load_data := {}
const save_path := "res://addons/script_panel_plus/saves/save.dat"

## Script Arrays
var all:     Array[ScriptItem] = []
var scripts: Array[ScriptItem] = []
var docs:    Array[ScriptItem] = []
var files:   Array[ScriptItem] = []
var favs:    Array[ScriptItem] = []

## Custom Data
var errors: = []
var script_editors: Array[ScriptEditorBase] = []
var not_saved: Array[ScriptEditorBase] = []
var locked_scripts := {}
var settings := {}

var current_script: ScriptItem
var renamed_script: ScriptItem
var tab_was_changed_manually := true

## Font Size
const min_font_size := 5
const max_font_size := 99

var list_font_size_scripts  := 16 
var list_font_size_docs     := 16 
var list_font_size_files    := 16 
var list_font_size_favs     := 16 
var list_font_size_all      := 16 

## Sorting
enum {
	NAME,
	NAME_BACKWARDS,
	DATE,
	DATE_BACKWARDS,
	MANUAL,
	}

var group_types := {
	"all": true,
	"★": true,
}

var current_sorting = {
	"all": DATE,
	"scripts": DATE,
	"docs": DATE,
	"files": DATE,
	"★": DATE,
	}

## Script Class in ItemList
class ScriptItem:
	var original_text: String
	var text: String
	var path: String
	var type: String
	
	var last_time_edited: String
	var is_saved := true
	
	func _init(_text: String, _path: String, _type: String) -> void:
		text = _text
		path = _path
		type = _type
		original_text = _text
	
	func _to_string() -> String:
		return path



## MAIN

func _ready() -> void:
	## NODES
	script_list = $VBoxContainer/ScriptList
	popup = $VBoxContainer/ScriptList/PopupMenu
	tab_bar = $VBoxContainer/TabBar
	menu_button = $VBoxContainer/SearchBar/MenuButton
	error_label = $VBoxContainer/ErrorLabel
	line_label = $VBoxContainer/InfoPanel/LineNum
	script_label = $VBoxContainer/InfoPanel/ScriptName
	search_line = $VBoxContainer/SearchBar/SearchLine
	rename_bar = $VBoxContainer/RenameBar
	rename_bar_line = $VBoxContainer/RenameBar/LineEdit
	hide_button = $VBoxContainer/InfoPanel/HideButton
	show_button = $ShowButton
	
	## SIGNALS
	menu_button.get_popup().id_pressed.connect(_on_menu_button_pressed)
	popup.id_pressed.connect(_on_popup_action)
	tab_bar.tab_changed.connect(on_tab_changed)
	script_list.gui_input.connect(_on_list_input)
	error_label.gui_input.connect(_on_error_input)
	search_line.text_changed.connect(_on_search_input)
	script_list.item_selected.connect(_on_item_selected)
	script_list.item_clicked.connect(_on_item_click)
	script_list.item_dropped.connect(_on_list_item_dropped)
	show_button.pressed.connect(show_panel)
	hide_button.pressed.connect(hide_panel)
	rename_bar.get_node("./Buttons/ButtonCancel").pressed.connect(_on_custom_name_cancel)
	rename_bar.get_node("./Buttons/ButtonRestore").pressed.connect(_on_custom_name_restore)
	rename_bar.get_node("./Buttons/ButtonSubmit").pressed.connect(_on_custom_name_submit)
	rename_bar_line.text_submitted.connect(_on_custom_name_submit.unbind(1))
	rename_bar_line.text_changed.connect(_on_custom_name_change.unbind(1))
	rename_bar_line.gui_input.connect(_on_rename_bar_line_input)

func _process(delta: float) -> void:
	if not is_instance_valid(plugin_reference): return
	if not engine_script_list.is_anything_selected(): return
	if settings.is_empty(): return
	check_for_script_change()
	check_current_line_label()
	check_current_error_label()
	check_for_missing_scripts()
	check_current_save_state()
	check_not_saved()
	list_update()


## CHECKS

func check_not_saved()           -> void:
	if not_saved.is_empty(): return
	for i in not_saved: check_save_state(i)

func check_for_script_change()   -> void:
	if not script_list.is_anything_selected(): reselect_current_script()
	
	var selected_item := engine_script_list.get_selected_items()[0]
	var tooltip := engine_script_list.get_item_tooltip(selected_item)
	
	if current_script and current_script.get("path") == tooltip: return
	
	var prev_script:ScriptItem = current_script
	var selected_script := get_script_from_engine_list_index(selected_item)
	
	if selected_script: # already exists
		current_script = selected_script
		reselect_current_script()
	else: # nothing is selected = new script
		add_script_item_by_engine_index(selected_item, true)
		current_script = get_script_from_engine_list_index(selected_item)
		sort_all_tab()
		update_locked_scripts_position()
	
	_on_script_editor_changed(current_script)
	check_current_tab()
	check_current_script_label()
	check_rename_status(current_script)
	
	if prev_script:
		_on_script_change(prev_script)
		current_script_changed.emit()

func check_for_missing_scripts()                       -> void:
	var __count := -1
	if __count != engine_script_list.item_count:
		for i in all:
			if i.type == "docs": continue
			
			if not ResourceLoader.exists(i.path): 
				remove_script_lock(i)
				all.erase(i)
				get_script_array(i.type).erase(i)
				if favs.has(i): favs.erase(i)
			
		__count = engine_script_list.item_count

func check_errors(script_editor: ScriptEditorBase)     -> void:
	var label: Label = get_error_label(script_editor)
	var text:String = label.text
	
	if text:
		for i in errors: if i[1] == text: return
		add_error(script_editor.get("metadata/_edit_res_path"), text)
	
	elif errors.size() > 0: for error in errors:
		if error[0] == script_editor.get("metadata/_edit_res_path"):
			errors.erase(error)

func check_save_state(script_editor: ScriptEditorBase) -> void:
	if not ProjectSettings.get_setting(plugin_reference.\
	project_settings_category + "show_script_save_indicator", true):
		return
	
	if not script_editor: return
	
	var _code_edit := get_code_edit(script_editor)
	var _script := get_script_from_script_editor(script_editor)
	
	if not _script: return
	
	if _code_edit.get_saved_version() == _code_edit.get_version():
		_script.is_saved = true
		if not_saved.has(script_editor): not_saved.erase(script_editor)
	else:
		_script.is_saved = false
		if not not_saved.has(script_editor): not_saved.append(script_editor)
	
	check_current_script_label()

func check_rename_status(script: ScriptItem) -> void:
	if renamed_script:
		if script != renamed_script: _on_custom_name_cancel()
		else: rename_bar_show(renamed_script)
	else:
		_on_custom_name_cancel()


## CHECK CURRENT

func check_current_tab()          -> void:
	if not current_script: return
	
	if tab_was_changed_manually: 
		tab_was_changed_manually = false
		return
	if get_current_tab() == "all": return
	if get_current_tab() == "★": return
	
	if current_script.type != get_current_tab():
		change_current_tab(current_script.type)

func check_current_error_label()  -> void:
	if not ProjectSettings.get_setting\
	(plugin_reference.project_settings_category + "show_errors", true):
		error_label.visible = false
		return
	
	if not current_script: 
		error_label.visible = false
		return
	
	if not current_script.type == "scripts":
		error_label.visible = false
		return
	
	if not get_current_script_editor(): 
		error_label.visible = false
		return
	
	var current_editor := get_current_script_editor()
	var engine_error_label = get_error_label(current_editor)
	
	var engine_error_text:String = engine_error_label.text
	
	error_label.text = engine_error_text
	
	error_label.visible = (error_label.text != "")

func check_current_line_label()   -> void:
	if not ProjectSettings.get_setting\
	(plugin_reference.project_settings_category + "show_line_num", true):
		line_label.visible = false
		return
	
	if not current_script: return
	
	
	var is_script:bool = current_script.get("type") == "scripts"
	
	line_label.visible = is_script
	
	if not is_script: return
	
	var current_editor := get_current_script_editor()
	
	var engine_lines_label = get_line_label(current_editor)
	
	var text:String = engine_lines_label.text
	
	line_label.text = "[%s :  %s]" % \
	[text.get_slice(":", 0).to_int(), text.get_slice(":", 1).to_int()]

func check_current_script_label() -> void:
	if not plugin_reference: 
		return
	
	if not ProjectSettings.get_setting\
	(plugin_reference.project_settings_category + "show_script_title", true):
		script_label.visible = false
		return
	
	if not current_script: return
	
	var current_editor := get_current_script_editor()
	
	script_label.visible = true
	script_label.text = current_script.text
	script_label.text = script_label.text.strip_edges()
	
	if not current_script.is_saved: script_label.text += "~"

func check_current_save_state()   -> void:
	check_save_state(get_script_editor(current_script))


## INPUT

func _on_list_input(event: InputEvent) -> void:
	# ZOOMING
	if not event is InputEventMouseButton: return
	if not event.ctrl_pressed: return
	if not script_list.item_count > 0: return
	
	var zoom_amount: int
	
	if event.button_index == MOUSE_BUTTON_WHEEL_UP: 
		zoom_amount = 1
	elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN: 
		zoom_amount = -1
	else:  return
	
	match get_current_tab():
		"scripts":
			list_font_size_scripts = clampi(\
			list_font_size_scripts + zoom_amount, min_font_size, max_font_size)
		"docs":
			list_font_size_docs = clampi(\
			list_font_size_docs + zoom_amount, min_font_size, max_font_size)
		"files":
			list_font_size_files = clampi(\
			list_font_size_files + zoom_amount, min_font_size, max_font_size)
		"all":
			list_font_size_all = clampi(\
			list_font_size_all + zoom_amount, min_font_size, max_font_size)
		"★":
			list_font_size_favs = clampi(\
			list_font_size_favs + zoom_amount, min_font_size, max_font_size)
	
	tab_was_changed_manually = true
	update_font_size()

func _on_item_click(index: int, \
at_position: Vector2, button_index: int) -> void:
	if button_index == MOUSE_BUTTON_RIGHT:
		_call_popup(index)
	elif button_index == MOUSE_BUTTON_MIDDLE:
		script_list.select(index)
		script_list.item_selected.emit(index)
		delete_script_item(index)

func _on_item_selected(index: int)       -> void:
	var _script := script_list.get_item_metadata(index)
	list_select_script(_script, index)

func _on_error_input(event: InputEvent)  -> void:
	if not event is InputEventMouseButton: return
	var line := 0
	if event.button_index == MOUSE_BUTTON_LEFT:
		if engine_script_editor.get_current_editor().get_base_editor():
			engine_script_editor.goto_line( error_label.text.get_slice(",", 0).to_int() -1 )

func _on_search_input(new_text: String)  -> void:
	pass

func _on_rename_bar_line_input(event: InputEvent) -> void:
	# Cancel Renaming
	if event is InputEventKey and event.is_pressed():
		if event.keycode == KEY_ESCAPE:
			renamed_script = null
			check_rename_status(current_script)

func _on_list_item_dropped(pos: Vector2, data: Array) -> void:
	if data.is_empty(): return
	
	var current_tab := get_current_tab()
	var script_array := get_current_script_array()
	var script := data[1] as ScriptItem
	var index_at_position := script_list.get_item_at_position(pos)
	var script_at_position := get_script_from_list_by_index(index_at_position)
	
	if not script: return
	if not script_at_position: return
	if index_at_position == -1: return
	
	if is_script_locked(script): return
	
	if is_script_locked(script_at_position): return
	
	current_sorting[current_tab] = MANUAL
	script_array.erase(script)
	script_array.insert(index_at_position, script)
	menu_button_update()
	update_locked_scripts_position()


## ENGINE INTERNAL NODES

func update_script_editor_list() -> void:
	script_editors.assign(engine_script_editor.get_open_script_editors())

func get_current_script_editor() -> ScriptEditorBase:
	return get_script_editor(current_script)

func get_script_editor(script: ScriptItem) -> ScriptEditorBase:
	if script:
		update_script_editor_list()
		for i in script_editors:
			if script.path == i.get("metadata/_edit_res_path"): 
				return i
	return null

func get_code_edit(script_editor: ScriptEditorBase)   -> CodeEdit:
	var result: CodeEdit = script_editor.find_children("*", "CodeEdit", true, false)[0]
	return result

func get_error_label(script_editor: ScriptEditorBase) -> Label:
	var result: Label = script_editor.get_child(0).get_child(0).get_child(1).get_child(1).get_child(0) as Label
	return result

func get_line_label(script_editor: ScriptEditorBase)  -> Label:
	var result: Label = script_editor.get_child(0).get_child(0).get_child(1).get_child(4) as Label
	return result


## SCRIPT EDITOR

func _on_script_editor_caret_moved(script_editor: ScriptEditorBase) -> void:
	var timer := Timer.new()
	timer.wait_time = 3
	timer.autostart = true
	script_editor.add_child(timer)
	await timer.timeout
	timer.queue_free()
	
	if plugin_reference and is_instance_valid(script_editor):
		check_errors(script_editor)
		check_current_script_label()

func _on_script_editor_text_changed(script_editor: ScriptEditorBase) -> void:
	var curr_script := get_current_script()
	script_update_time(curr_script)
	check_current_save_state()

func _on_script_editor_changed(script_item: ScriptItem)  -> void:
	if not script_item: return
	
	var script_editor := get_script_editor(script_item)
	
	if not script_editor: return
	
	if script_editor.get_class() != "ScriptTextEditor": return
	
	var code_edit := get_code_edit(script_editor)
	var _callable: Callable
	
	## TEXT CHANGED
	_callable = _on_script_editor_text_changed
	_callable = _callable.bind(script_editor)
	
	if not code_edit.text_changed.is_connected(_callable):
		code_edit.text_changed.connect(_callable)
	
	## CARET
	_callable = _on_script_editor_caret_moved
	_callable = _callable.bind(script_editor)
	
	if not code_edit.caret_changed.is_connected(_callable):
		code_edit.caret_changed.connect(_callable)


## TABS

func change_current_tab(type: String) -> void:
	var index := find_tab_by_title(type)
	
	if index == -1: return
	
	tab_bar.current_tab = index
	sort_current_tab()

func get_current_tab() -> String:
	return tab_bar.get_tab_title(tab_bar.current_tab).to_lower()

func on_tab_changed(_id: int) -> void:
	tab_was_changed_manually = true
	renamed_script = null
	update_font_size()
	menu_button_update()
	update_locked_scripts_position()

func find_tab_by_title(title: String) -> int:
	for i in range(0, tab_bar.tab_count):
		if title in tab_bar.get_tab_title(i).to_lower():
			return i
	return -1

func update_tabs() -> void:
	if settings["show_tab_bar"]: 
		tab_bar.visible = true
	else: 
		tab_bar.visible = false
		change_current_tab("all")
	
	if settings["clip_tabs"]:
		tab_bar.clip_tabs = true
	else:
		tab_bar.clip_tabs = false
	
	toggle_tab_visibility("scripts", settings["show_scripts_tab"])
	toggle_tab_visibility("docs", settings["show_docs_tab"])
	toggle_tab_visibility("files", settings["show_files_tab"])
	toggle_tab_visibility("★", settings["show_favourites_tab"])
	
	if settings["show_tab_bar"] == false: return
	if not settings["show_scripts_tab"] and not settings["show_docs_tab"]\
	and not settings["show_files_tab"] and not settings["show_favourites_tab"]:
		tab_bar.visible = false
	else:
		tab_bar.visible = true

func toggle_tab_visibility(title: String, toggle: bool) -> void:
	var _tab := find_tab_by_title(title)
	
	if toggle == false and tab_bar.current_tab == _tab:
		change_current_tab("all")
	
	tab_bar.set_tab_hidden(_tab, not toggle)

func sort_current_tab() -> void:
	sort_tab(get_current_tab())
	menu_button_update()
	on_tab_changed(-1)

func sort_tab(tab_name: String) -> void:
	var _array := get_script_array(tab_name)
	
	var sort_name := sort_alphabetical
	var sort_date := sort_by_date
	
	var sort_name_rev := sort_alphabetical_reversed
	var sort_date_rev := sort_by_date_reversed
	
	if group_types.has(tab_name) and group_types[tab_name]:
		sort_name = sort_type_alphabetical
		sort_date = sort_type_by_date
		
		sort_name_rev = sort_type_alphabetical_reversed
		sort_date_rev = sort_type_by_date_reversed
	
	match current_sorting[tab_name]:
		NAME:
			_array.sort_custom(sort_name)
		NAME_BACKWARDS:
			_array.sort_custom(sort_name_rev)
		DATE:
			_array.sort_custom(sort_date)
		DATE_BACKWARDS:
			_array.sort_custom(sort_date_rev)
	

func sort_all_tab() -> void:
	sort_tab("all")
	sort_tab("scripts")
	sort_tab("docs")
	sort_tab("files")
	sort_tab("★")


## SORTING ALGORITHMS

func sort_type_alphabetical(a: ScriptItem, b: ScriptItem) -> bool:
	var a_type := a.type
	var b_type := b.type
	
	if a_type == b_type: return sort_alphabetical(a, b)
	
	if a_type == "scripts": return true
	
	if a_type == "files":
		if b_type == "scripts": return false
		else: return true
	
	return false

func sort_type_alphabetical_reversed(a: ScriptItem, b: ScriptItem) -> bool:
	var a_type := a.type
	var b_type := b.type
	
	if a_type == b_type: return sort_alphabetical_reversed(a, b)
	
	if a_type == "scripts": return true
	
	if a_type == "files":
		if b_type == "scripts": return false
		else: return true
	
	return false

func sort_type_by_date(a: ScriptItem, b: ScriptItem) -> bool:
	var a_type := a.type
	var b_type := b.type
	
	if a_type == b_type: return sort_by_date(a, b)
	
	if a_type == "scripts": return true
	
	if a_type == "files":
		if b_type == "scripts": return false
		else: return true
	
	return false

func sort_type_by_date_reversed(a: ScriptItem, b: ScriptItem) -> bool:
	var a_type := a.type
	var b_type := b.type
	
	if a_type == b_type: return sort_by_date_reversed(a, b)
	
	if a_type == "scripts": return true
	
	if a_type == "files":
		if b_type == "scripts": return false
		else: return true
	
	return false

func sort_by_date(a: ScriptItem, b: ScriptItem)  -> bool:
	var a_date := a.last_time_edited
	var b_date := b.last_time_edited
	
	if a_date == b_date: return sort_alphabetical(a, b)
	
	if a_date < b_date: return true
	
	return false

func sort_by_date_reversed(a: ScriptItem, b: ScriptItem)  -> bool:
	var a_date := a.last_time_edited
	var b_date := b.last_time_edited
	
	if a_date == b_date: return sort_alphabetical(a, b)
	
	if a_date > b_date: return true
	
	return false

func sort_alphabetical(a: ScriptItem, b: ScriptItem) -> bool:
	var a_char := a.text.left(1)
	var b_char := b.text.left(1)
	
	if settings["sorting_ignore_case"]:
		a_char = a_char.to_lower()
		b_char = b_char.to_lower()
	
	if a_char < b_char: return true
	
	return false

func sort_alphabetical_reversed(a: ScriptItem, b: ScriptItem) -> bool:
	var a_char := a.text.left(1)
	var b_char := b.text.left(1)
	
	if settings["sorting_ignore_case"]:
		a_char = a_char.to_lower()
		b_char = b_char.to_lower()
	
	if a_char > b_char: return true
	
	return false


## LOCKED SCRIPTS

func is_script_locked(script_item: ScriptItem) -> bool:
	if locked_scripts.is_empty(): return false
	
	var current_tab := get_current_tab()
	
	if locked_scripts.has(current_tab):
		var _array := locked_scripts[current_tab] as Array
		for i in _array:
			if i[0] == script_item:
				return true
	return false

func toggle_script_lock(script_item: ScriptItem, tab: String) -> void:
	## REMOVED
	if locked_scripts.has(tab):
		var _array := locked_scripts[tab] as Array
		for i in _array: if i[0] == script_item:
			locked_scripts[tab].erase(i)
			return
	
	## ADD
	var _index := get_script_array(tab).find(script_item)
	if _index == -1: return
	
	if locked_scripts.has(tab):
		locked_scripts[tab].append([script_item, _index])
	else:
		locked_scripts[tab] = [[script_item, _index]]

func remove_script_lock(script_item: ScriptItem) -> void:
	for tab in locked_scripts.keys():
		var _array := locked_scripts[tab] as Array
		for i in _array: if i[0] == script_item:
			locked_scripts[tab].erase(i)
			return

func update_locked_scripts_position() -> void:
	if locked_scripts.is_empty(): return
	
	var tab_name := get_current_tab()
	var _array := get_script_array(tab_name)
	
	if not locked_scripts.has(tab_name): return
	var _locked_scripts: Array = locked_scripts[tab_name]
	
	for i in _locked_scripts:
		var _script:ScriptItem = i[0]
		var _index:int = i[1]
		
		if not _script: continue
		if not _array.has(_script): continue
		
		move_script_item(_script, _array, _index)


## FONT SIZE

func update_font_size() -> void:
	match get_current_tab():
		"scripts":
			script_list.add_theme_font_size_override("font_size", list_font_size_scripts)
		"docs":
			script_list.add_theme_font_size_override("font_size", list_font_size_docs)
		"files":
			script_list.add_theme_font_size_override("font_size", list_font_size_files)
		"★":
			script_list.add_theme_font_size_override("font_size", list_font_size_favs)
		"all":
			script_list.add_theme_font_size_override("font_size", list_font_size_all)
	
	# ItemList needs to clear() for adjusting items text-width
	script_list.clear()
	current_script = null

func get_current_font_size() -> int:
	match get_current_tab():
		"all": return list_font_size_all
		"scripts": return list_font_size_scripts
		"docs": return list_font_size_docs
		"files": return list_font_size_files
		"★": return list_font_size_favs
	return -1


## SCRIPTS

func _on_script_change(prev_script: ScriptItem) -> void:
	if prev_script:
		if prev_script.type == "docs":
			script_update_time(prev_script)
		if prev_script.type == "scripts":
			var _editor := get_script_editor(prev_script)
			if is_instance_valid(_editor): check_errors(_editor)
	
	if current_script:
		if current_script.type == "scripts":
			var _editor := get_script_editor(current_script)
			if is_instance_valid(_editor): check_errors(_editor)

func add_script_item_by_engine_index(index: int, push_front := false) -> void:
	## SCRIPT
	if engine_script_list.get_item_tooltip(index).find(".gd") != -1 or\
	engine_script_list.get_item_tooltip(index).find(".cs") != -1:
		var text := engine_script_list.get_item_text(index)
		var path := engine_script_list.get_item_tooltip(index)
		var type := "scripts"
		add_script_item(text, path, type, push_front)
	
	## DOCUMENT
	elif engine_script_list.get_item_tooltip(index).find\
	("Class Reference") != -1:
		var text := engine_script_list.get_item_tooltip(index).get_slice(" Class Reference", 0)
		var path := engine_script_list.get_item_tooltip(index)
		var type := "docs"
		add_script_item(text, path, type, push_front)
	
	## FILE
	else:
		var text :=  engine_script_list.get_item_text(index)
		var path := engine_script_list.get_item_tooltip(index)
		var type := "files"
		add_script_item(text, path, type, push_front)

func add_script_item(text: String, path: String, type: String, \
push_front := false, add_to_favourite := false) -> ScriptItem:
	var script_array := get_script_array(type)
	var item := ScriptItem.new(text.replace("(*)", ""), path, type)
	script_update_time(item)
	
	if push_front:
		script_array.push_front(item)
		all.push_front(item)
		if add_to_favourite: favs.push_front(item)
	else:
		script_array.push_back(item)
		all.push_back(item)
		if add_to_favourite: favs.push_back(item)
	return item

func delete_script_item(index: int) -> void:
	## ID:  10 Current | 11 Docs | 12 All | 13 Others
	
	var script_item := get_script_from_list_by_index(index)
	
	match script_item.type:
		"scripts":
			scripts.erase(script_item)
		"docs":
			docs.erase(script_item)
		"files":
			files.erase(script_item)
	
	if favs.has(script_item):
			favs.erase(script_item)
	
	remove_script_lock(script_item)
	
	var _top_bar:Control = plugin_reference.top_bar
	if _top_bar:_top_bar.get_child(0).get_popup().emit_signal("id_pressed", 10)
	
	all.erase(script_item)

func move_script_item(script_item: ScriptItem, script_array: Array[ScriptItem],\
index: int) -> void:
	if script_array[index] != script_item:
		script_array.erase(script_item)
		script_array.insert(index, script_item)

func update_all_scripts() -> void:
	var script_count:int = engine_script_list.item_count
	for i in range(0, script_count): add_script_item_by_engine_index(i)

func script_update_time(script: ScriptItem) -> void:
	script.last_time_edited = Time.get_datetime_string_from_system(false, true)

func reselect_current_script() -> void:
	if not current_script: return
	if script_list.is_anything_selected(): return
	
	script_list.add_theme_color_override("font_selected_color", list_get_current_script_color())
	script_list.deselect_all()
	
	
	var index := list_get_scripts_index(current_script)
	if index == -1: return
	script_list.select( index )

func get_script_from_engine_list_index(index: int) -> ScriptItem:
	var tooltip := engine_script_list.get_item_tooltip(index)
	var result: ScriptItem
	
	for i in all: if i.path == tooltip:
		result = i
		return result
	
	return result

func get_script_from_list_by_index(index: int) -> ScriptItem:
	return script_list.get_item_metadata(index)

func get_script_by_path(path: String) -> ScriptItem:
	for i in all: if path in i.path:return i
	return null

func get_current_script() -> ScriptItem:
	return current_script

func get_current_script_as_resource() -> Script:
	return engine_script_editor.get_current_script()

func get_current_script_array() -> Array[ScriptItem]:
	return get_script_array(get_current_tab())

func get_script_array(tab_name: String) -> Array[ScriptItem]:
	var array_ref: Array[ScriptItem]
	
	match tab_name:
		"all": array_ref = all
		"scripts": array_ref = scripts
		"docs": array_ref = docs
		"files": array_ref = files
		"★":   array_ref = favs
		"favs": array_ref = favs
	
	return array_ref

func get_script_from_script_editor(\
script_editor: ScriptEditorBase) -> ScriptItem:
	var result: ScriptItem
	
	for i in all:
		if i.path == script_editor.get("metadata/_edit_res_path"):
			result = i
	
	return result


## LIST

func list_update() -> void:
	script_list.clear()
	const newline := "\n"
	
	for object in get_current_script_array():
		if search_line.text.is_empty() or \
		search_line.text.is_subsequence_ofn(object.text):
			list_add_item(object)
			script_list.set_item_tooltip(list_get_scripts_index(object), \
			object.path + newline + "---" + newline + object.last_time_edited)
	
	if plugin_reference: list_check_settings()
	
	reselect_current_script()

func list_get_current_script_color() -> Color:
	var script_item := current_script
	var color := Color.WHITE
	
	if script_item.type == "scripts":
		color = settings["scripts_color"]
	
	if script_item.type == "docs":
		color = settings["docs_color"]
	
	if script_item.type == "files":
		color = settings["files_color"]
	
	return color

func list_set_items_color(id: int, script_item: ScriptItem) -> void:
	if script_item.type == "scripts":
		var color:Color = settings["scripts_color"]
		script_list.set_item_custom_fg_color(id, color)
		script_list.add_theme_color_override("font_hovered_color", color)
	
	if script_item.type == "docs":
		var color:Color = settings["docs_color"]
		script_list.set_item_custom_fg_color(id, color)
	
	if script_item.type == "files":
		var color:Color = settings["files_color"]
		script_list.set_item_custom_fg_color(id, color)

func list_check_settings() -> void:
	## V SEPARATION
	script_list.add_theme_constant_override("v_separation", \
	settings["list_vertical_spacing"])
	
	## H SEPARATION
	script_list.add_theme_constant_override("h_separation", \
	settings["list_horizontal_spacing"])
	
	## SAME COLUMN WIDTH
	script_list.same_column_width = \
	settings["list_same_column_width"]

func list_add_item(script_item: ScriptItem) -> void:
	var text := script_item.text
	var current_tab := get_current_tab()
	
	match script_item.type:
		"scripts":
			if not settings["show_file_formats"]: 
				text = text.get_slice(".", 0)
			if settings["convert_scripts_to_pascal_case"]: 
				text = text.to_pascal_case()
			if settings["script_icons"]: 
				text = "📝 " + text
			elif settings["script_decorators"]: 
				text = "▪ " + text
		"docs":
			if settings["convert_docs_to_snake_case"]: 
				text = text.to_snake_case()
			if settings["script_icons"]: 
				text = "🔍 " + text
			elif settings["script_decorators"]: 
				text = "▪ " + text
		"files":
			if not settings["show_file_formats"]: 
				text = text.get_slice(".", 0)
			if settings["convert_files_to_pascal_case"]: 
				text = text.to_pascal_case()
			if settings["script_icons"]: 
				text = "️📦 " +  text
			elif settings["script_decorators"]: 
				text = "▪ " + text
	
	if settings["show_script_save_indicator"]:
		if not script_item.is_saved:
			if settings["indicator_icons"]: text += " 💬"
			else: text += settings["save_indicator"]
	
	if settings["show_script_error_indicator"]:
		if errors.size() > 0: for i in errors:
			if script_item.path in i[0]:
				if settings["indicator_icons"]: text += " ❌"
				else: text += settings["error_indicator"]
				break
	
	if settings["show_script_lock_indicator"]:
		if locked_scripts.has(current_tab):
			for i in locked_scripts[current_tab]:
				if i[0] == script_item:
					if settings["indicator_icons"]: text += " 🔒"
					else: text += settings["lock_indicator"]
					break
	
	if settings["show_script_favourite_indicator"]:
		if favs.has(script_item):
			if settings["indicator_icons"]:
				text += " ★"
			else:
				text += settings["favourite_indicator"]
	
	var id := script_list.add_item(text)
	script_list.set_item_metadata(id, script_item)
	
	list_set_items_color(id, script_item)

func list_select_script(_script: ScriptItem, index := -1) -> void:
	var res_path := _script.path
	
	if index == -1: index = list_get_scripts_index(_script)
	
	if ResourceLoader.exists(res_path):
		## For Scripts and files
		var file: Resource = load(res_path)
		engine_editor_interface.edit_resource(file)
	elif res_path.contains("Class Reference"):
		## For Documentation
		var _editor := engine_script_editor.get_open_script_editors()[0]
		if _editor:
			_editor.go_to_help.emit(res_path.get_slice(" Class Reference", 0))
		else: ## Alternative Search
			var editor_help = engine_script_editor.find_children\
			("*", "EditorHelp", true, false)[0]
			if editor_help:
				editor_help.go_to_help.emit(res_path.get_slice(" Class Reference", 0))
	else:
		## Deleted
		if index != -1: delete_script_item(index)
	
	if index != -1: script_list.select(index)

func list_get_scripts_index(script: ScriptItem) -> int:
	for i in range(0, script_list.item_count):
		if script_list.get_item_metadata(i) == script:
			return i
	return -1

func is_list_showing_script(script: ScriptItem) -> bool:
	if list_get_scripts_index(script) != -1: return true
	else: return false


## SAVE

func save_last_session() -> void:
	if not settings["save_session"]: return
	
	var file = FileAccess.open(save_path, FileAccess.WRITE)
	
	_save_sorting()
	_save_font_size()
	_save_current_script()
	_save_script_arrays()
	_save_locked_scripts()
	_save_tabs()
	
	file.store_var(save_data, true)

func _save_font_size() -> void:
	save_data["list_font_size_scripts"] = list_font_size_scripts
	save_data["list_font_size_docs"] = list_font_size_docs
	save_data["list_font_size_files"] = list_font_size_files
	save_data["list_font_size_favs"] = list_font_size_favs
	save_data["list_font_size_all"] = list_font_size_all

func _save_sorting() -> void:
	save_data["current_sorting"] = current_sorting
	save_data["group_types"] = group_types

func _save_script_arrays() -> void:
	save_data["all"] = []
	save_data["scripts"] = []
	save_data["docs"] = []
	save_data["files"] = []
	save_data["favs"] = []
	
	for i in all:
		save_data["all"].append(_script_item_to_array(i))
	for i in scripts:
		save_data["scripts"].append(_script_item_to_array(i))
	for i in docs:
		save_data["docs"].append(_script_item_to_array(i))
	for i in files:
		save_data["files"].append(_script_item_to_array(i))
	for i in favs:
		save_data["favs"].append(_script_item_to_array(i))

func _save_locked_scripts() -> void:
	save_data["locked_scripts"] = []
	for _tab in locked_scripts.keys():
		for x in locked_scripts[_tab]:
			var _script: ScriptItem = x[0]
			var index: int = x[1]
			save_data["locked_scripts"].append([_script_item_to_array(_script), _tab, index])

func _script_item_to_array(script_item: ScriptItem) -> Array:
	return [script_item.original_text, script_item.text,\
		 script_item.path, script_item.type, script_item.last_time_edited]

func _save_current_script() -> void:
	save_data["current_script"] = get_current_script().path

func _save_tabs() -> void:
	save_data["tabs"] = []
	save_data["current_tab"] = get_current_tab()
	
	for i in tab_bar.tab_count:
		save_data["tabs"].append( tab_bar.get_tab_title(i) )


## LOAD

func load_last_session() -> void:
	if not settings["save_session"]: return
	
	var file = FileAccess.open(save_path, FileAccess.READ)
	if file: 
		load_data = file.get_var()
	else:
		return
	
	if load_data.is_empty(): return
	
	_load_tabs()
	_load_script_arrays()
	_load_sorting()
	_load_font_size()
	_load_locked_scripts()
	_load_current_script()
	update_font_size()
	sort_current_tab()

func _load_font_size() -> void:
	if not load_data.has("list_font_size_scripts"): return
	if not load_data.has("list_font_size_docs"): return
	if not load_data.has("list_font_size_files"): return
	if not load_data.has("list_font_size_favs"): return
	if not load_data.has("list_font_size_all"): return
	
	list_font_size_scripts = load_data["list_font_size_scripts"]
	list_font_size_docs = load_data["list_font_size_docs"]
	list_font_size_files = load_data["list_font_size_files"]
	list_font_size_favs = load_data["list_font_size_favs"]
	list_font_size_all = load_data["list_font_size_all"]

func _load_sorting() -> void:
	if not load_data.has("group_types"): return
	if not load_data.has("current_sorting"): return
	
	group_types = load_data["group_types"]
	current_sorting = load_data["current_sorting"]

func _load_script_arrays() -> void:
	if not load_data.has("all"): return
	if not load_data.has("scripts"): return
	if not load_data.has("docs"): return
	if not load_data.has("files"): return
	if not load_data.has("favs"): return
	
	_load_custom_array(load_data["all"], "all")
	_load_custom_array(load_data["scripts"], "scripts")
	_load_custom_array(load_data["docs"], "docs")
	_load_custom_array(load_data["files"], "files")
	_load_custom_array(load_data["favs"], "favs")

func _load_locked_scripts() -> void:
	var _array := load_data["locked_scripts"] as Array
	for i in _array:
		var new_script := _load_script_item(i[0], i[1])
		toggle_script_lock(new_script, i[1])

func _load_custom_array(saved_array: Array, array_name: String) -> void:
	for i in range(0, saved_array.size() ):
		_load_script_item(saved_array[i], array_name)
	for x in range(0, saved_array.size()):
		var _array := get_script_array(array_name)
		move_script_item(get_script_by_path(saved_array[x][2]), _array, x)

func _load_script_item(saved_script: Array, script_array_name: String) -> ScriptItem:
	var _orig_text: String = saved_script[0]
	var _text:String = saved_script[1]
	var _path:String = saved_script[2]
	var _type:String = saved_script[3]
	var _time:String = saved_script[4]
	
	var script := get_script_by_path(_path)
	var script_array := get_script_array(script_array_name)
	var is_favs := script_array_name == "favs"
	
	
	if script:
		script.text = _text
		script.original_text = _orig_text
		script.path = _path
		script.type = _type
		script.last_time_edited = _time
		
		if is_favs and not favs.has(script): favs.append(script)
		
		return script
	else:
		var _script := add_script_item(_text, _path, _type, false, is_favs)
		_script.original_text = _orig_text
		_script.last_time_edited = _time
		
		return _script

func _load_current_script() -> void:
	if not load_data.has("current_script"): return
	
	var _script: ScriptItem = get_script_by_path(load_data["current_script"])
	
	for i in engine_script_list.item_count:
		if engine_script_list.get_item_tooltip(i) == _script.path:
			engine_script_list.select(i)
			engine_script_list.item_selected.emit(i)

func _load_tabs() -> void:
	if not load_data.has("tabs"): return
	if not load_data.has("current_tab"): return
	
	for i in range(0, load_data["tabs"].size()):
		for x in tab_bar.tab_count:
			if tab_bar.get_tab_title(x) == load_data["tabs"][i]:
				tab_bar.move_tab(x, i)
				if tab_bar.get_tab_title(i).to_lower() == load_data["current_tab"]:
					tab_bar.current_tab = i


## ERRORS

func add_error(script_path: String, error_text: String) -> void:
	var new_error := [script_path, error_text]
	errors.append(new_error)


## MENU BUTTON

func _on_menu_button_pressed(id: int) -> void:
	var tab := get_current_tab() # current_tab because we need a String
	var index := menu_button.get_popup().get_item_index(id)
	
	match id:
		0:
			current_sorting[tab] = MANUAL
		1:
			if current_sorting[tab] == NAME:
				current_sorting[tab] = NAME_BACKWARDS
			else:
				current_sorting[tab] = NAME
		2:
			if current_sorting[tab] == DATE:
				current_sorting[tab] = DATE_BACKWARDS
			else:
				current_sorting[tab] = DATE
		4:
			menu_button.get_popup().toggle_item_checked(index)
			if group_types.has(tab):
				group_types[tab] = menu_button.get_popup().is_item_checked(4)
	
	sort_current_tab()

func menu_button_update() -> void:
	for i in range(0, 3):
		menu_button.get_popup().set_item_checked(i, false)
	
	var index := 0
	var tab := get_current_tab()
	match current_sorting[tab]:
		MANUAL:
			index = 0
		NAME:
			index = 1
		NAME_BACKWARDS:
			index = 1
		DATE:
			index = 2
		DATE_BACKWARDS:
			index = 2
	
	menu_button.get_popup().set_item_checked(index, true)
	
	menu_button.get_popup().set_item_disabled(4, false)
	
	if group_types.has(tab):
		menu_button.get_popup().set_item_checked(4, group_types[tab])
	else:
		menu_button.get_popup().set_item_disabled(4, true)
		menu_button.get_popup().set_item_checked(4, false)


## POPUP

func _call_popup(item_index: int) -> void:
		popup.popup(Rect2i(get_global_mouse_position(), Vector2i(173, 62)))
		popup.set_item_metadata(popup.get_item_index(0), item_index) # CLOSE
		popup.set_item_metadata(popup.get_item_index(1), item_index) # FAVOURITE
		popup.set_item_metadata(popup.get_item_index(2), item_index) # LOCK
		popup.set_item_metadata(popup.get_item_index(3), item_index) # NAME

func _on_popup_action(id: int) -> void:
	var script_index: int = popup.get_item_metadata(popup.get_item_index(id))
	var script_item: ScriptItem = get_script_from_list_by_index(script_index)
	if id == 0: # Close
		script_list.item_selected.emit(script_index)
		delete_script_item(script_index)
	if id == 1: # Favourite
		if favs.has(script_item):
			favs.erase(script_item)
		else:
			favs.append(script_item)
			sort_tab("★")
	if id == 2: # Lock
		toggle_script_lock(script_item, get_current_tab())
	if id == 3: # Custom Name
		if renamed_script:
			if renamed_script == script_item:
				renamed_script = null
			else:
				renamed_script = script_item
				script_list.item_selected.emit(script_index)
		else:
			renamed_script = script_item
			script_list.item_selected.emit(script_index)
		check_rename_status(script_item)


## CUSTOM NAME

func rename_bar_show(script_item: ScriptItem) -> void:
		rename_bar.visible = true
		rename_bar_line.text = script_item.text
		rename_bar_line.grab_focus()
		rename_bar_line.select_all()

func _on_custom_name_change() -> void:
	if not rename_bar.visible: return
	
	current_script.text = rename_bar_line.text

func _on_custom_name_submit() -> void:
	_on_custom_name_change()
	renamed_script = null
	check_rename_status(current_script)

func _on_custom_name_restore() -> void:
	current_script.text = current_script.original_text
	_on_custom_name_cancel()

func _on_custom_name_cancel() -> void:
	renamed_script = null
	rename_bar.visible = false
	rename_bar_line.text = ""


## SHOW-HIDE SCRIPT PANEL

func toggle_hide_button() -> void:
	if settings["show_hide_panel_button"]:
		hide_button.visible = true
	else:
		hide_button.visible = false

func hide_panel() -> void:
	var split: HSplitContainer = get_parent() as HSplitContainer
	split.collapsed = true
	split.dragger_visibility = SplitContainer.DRAGGER_HIDDEN_COLLAPSED
	
	show_button.visible = true
	$VBoxContainer.visible = false

func show_panel() -> void:
	var split: HSplitContainer = get_parent() as HSplitContainer
	split.collapsed = false
	split.dragger_visibility = SplitContainer.DRAGGER_VISIBLE
	
	$VBoxContainer.visible = true
	show_button.visible = false
