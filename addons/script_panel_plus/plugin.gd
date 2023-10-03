@tool
extends EditorPlugin

const project_settings_category := "script_panel_plus/panel_settings/"
const scene := preload("res://addons/script_panel_plus/script_panel/script_panel.tscn")

const default_config_path := "res://addons/script_panel_plus/configs"
var config_path := "res://addons/script_panel_plus/configs"
var config_name := "config.cfg"

var defaults_path := "res://addons/script_panel_plus/configs/defaults.cfg"

var config: ConfigFile
var defaults: ConfigFile

var engine_editor_interface:     EditorInterface
var engine_script_editor:        ScriptEditor
var engine_script_vbox:          VSplitContainer
var engine_script_list:          ItemList
var engine_method_list:          ItemList
var engine_method_searchline:    LineEdit
var engine_docs_headers_list:     ItemList
var engine_screen_select_button: Control

var script_panel:                Control
var top_bar:                     Control
var top_bar_parent:              Control

var settings := {}


## PLUGIN

func _enter_tree() -> void:
	while _scripts_are_loading(): 
		await get_tree().process_frame
	
	load_config()
	load_engine_nodes()
	create_script_panel()
	update()
	project_settings_changed.connect(update)
	script_panel.current_script_changed.connect(check_current_bottom_bar_visibility)
	script_panel.load_last_session()
	script_panel.update_tabs()
	script_panel.set_process(true)

func _exit_tree() -> void:
	hide_screen_select_button()
	script_panel.save_last_session()
	close_config()
	unload_config_path_settings()
	script_panel.show_panel()
	script_panel.queue_free()
	show_engine_script_vbox()
	show_top_bar()
	show_all_bottom_bars()


## SETTINGS

func update() -> void:
	load_settings()
	hide_engine_script_vbox()
	script_panel.toggle_hide_button()
	script_panel.update_tabs()
	script_panel.methods_list_update()
	
	check_top_bar_visibility()
	check_current_bottom_bar_visibility()
	check_current_screen_button_visibility()
	check_search_bar_visibility()
	
	script_panel.update()


## CONFIG

func load_config() -> void:
	if not config: config = ConfigFile.new()
	if not defaults: defaults = ConfigFile.new()
	
	var err := config.load(config_path.path_join(config_name))
	var err2 := defaults.load(defaults_path)
	
	if err: 
		return
	if err2: 
		return
	
	load_project_settings()
	set_defaults()

func close_config() -> void:
	save_project_settings()
	unload_project_settings()
	config = null
	defaults = null

func load_settings():
	settings.clear()
	for section in config.get_sections():
		for key in config.get_section_keys(section):
			var path := project_settings_category + key
			var default_value = defaults.get_value(section, key)
			var value = ProjectSettings.get_setting(path, default_value)
			settings[key] = value
	script_panel.settings = settings

func load_project_settings() -> void:
	update_config_file()
	
	for section in config.get_sections():
		for key in config.get_section_keys(section):
			var value = config.get_value(section, key)
			var path := project_settings_category + key
			ProjectSettings.set_setting(path, value)
			ProjectSettings.set_as_basic(path, true)
	
	add_save_path_property_info()
	ProjectSettings.save()

func save_project_settings() -> void:
	update_config_file()
	
	for section in config.get_sections():
		for key in config.get_section_keys(section):
			var path := project_settings_category + key
			config.set_value(section, key, ProjectSettings.get_setting(path))
	
	config.save(config_path.path_join(config_name))

func unload_project_settings() -> void:
	for section in config.get_sections():
		for key in config.get_section_keys(section):
			var path := project_settings_category + key
			ProjectSettings.clear(path)
	ProjectSettings.save()

func set_defaults() -> void:
	for section in defaults.get_sections():
		for key in defaults.get_section_keys(section):
			var value = defaults.get_value(section, key)
			var path := project_settings_category + key
			ProjectSettings.set_initial_value(path, value)
	ProjectSettings.save()

func add_save_path_property_info() -> void:
	var save_folder_property_info = {
	"name": project_settings_category + "save_path",
	"type": TYPE_STRING,
	"hint": PROPERTY_HINT_GLOBAL_DIR,
	"hint_string": "Session save folder"
	}
	
	ProjectSettings.add_property_info(save_folder_property_info)

func add_config_path_property_info() -> void:
	var save_folder_property_info = {
	"name": project_settings_category + "config_path",
	"type": TYPE_STRING,
	"hint": PROPERTY_HINT_GLOBAL_DIR,
	"hint_string": "Config Filepath"
	}
	
	ProjectSettings.add_property_info(save_folder_property_info)


## CONFIG PATH SETTING (EXPERIMENTAL)
const _config_path_holder := "res://addons/script_panel_plus/configs/config_path.txt"

func unload_config_path_settings() -> void:
	var new_file := FileAccess.open(_config_path_holder, FileAccess.WRITE)
	
	var config_folder := ProjectSettings.get_setting(project_settings_category + "config_path", default_config_path) as String
	
	if new_file: new_file.store_string(config_folder)
	
	ProjectSettings.set_setting(project_settings_category + "config_path", null)

func update_config_file() -> void:
	var file := FileAccess.open(_config_path_holder, FileAccess.READ)
	if file:
		var text := file.get_as_text().strip_edges()
		
		if DirAccess.dir_exists_absolute(text):
			config_path = text
			ProjectSettings.set_setting(project_settings_category + "config_path", config_path)
			ProjectSettings.set_as_basic(project_settings_category + "config_path", false)
			ProjectSettings.set_initial_value(project_settings_category + "config_path", default_config_path)
			add_config_path_property_info()


## SHOW / HIDE

func check_top_bar_visibility() -> void:
	if not top_bar: return
	
	if settings["show_top_bar"]:
		show_top_bar()
	else:
		hide_top_bar()

func check_current_screen_button_visibility() -> void:
	var editor_settings := engine_editor_interface.get_editor_settings()
	var multi_window := editor_settings.get_setting("interface/multi_window/enable")
	
	if settings["show_screen_select_button"] and multi_window and not settings["show_top_bar"]:
		show_screen_select_button()
	else:
		hide_screen_select_button()

func check_current_bottom_bar_visibility() -> void:
	if settings["show_bottom_bar"]: 
		show_current_bottom_bar()
	else: 
		hide_current_bottom_bar()

func check_search_bar_visibility() -> void:
	var search_bar := script_panel.search_line.get_parent() as Control
	search_bar.visible = settings["show_script_search_bar"]

func hide_top_bar() -> void:
	if not top_bar: return
	
	top_bar.visibility_layer = 0
	
	var new_parent = engine_script_editor
	if new_parent: top_bar.reparent(new_parent, false)
	new_parent.move_child(top_bar, 0)

func show_top_bar() -> void:
	if not top_bar: return
	
	top_bar.reparent(top_bar_parent, false)
	top_bar_parent.move_child(top_bar, 0)
	top_bar.visibility_layer = 1

func hide_engine_script_vbox() -> void:
	engine_script_vbox.set("visible", false)

func show_engine_script_vbox() -> void:
	engine_script_vbox.set("visible", true)

func show_all_bottom_bars() -> void:
	for i in get_all_bottom_bars():
		i.visible = true

func hide_all_bottom_bars() -> void:
	for i in get_all_bottom_bars():
		i.visible = false

func hide_current_bottom_bar() -> void:
	var cur_bottom_bar := get_current_bottom_bar()
	if cur_bottom_bar: cur_bottom_bar.visible = false
	else: hide_all_bottom_bars()

func show_current_bottom_bar() -> void:
	var cur_bottom_bar := get_current_bottom_bar()
	if cur_bottom_bar: cur_bottom_bar.visible = true

func show_screen_select_button() -> void:
	var _children: Array[Node] = engine_script_editor.get_child(0).find_children("*", "ScreenSelect", false, false)
	var new_parent :Control = script_panel.line_label.get_parent()
	
	if _children.size() < 1: return
	if not new_parent: return
	
	engine_screen_select_button = _children[0]
	
	if not engine_screen_select_button: return
	
	engine_screen_select_button.reparent(new_parent)
	new_parent.move_child(engine_screen_select_button, -1)

func hide_screen_select_button() -> void:
	if not top_bar: return
	if not engine_screen_select_button: return
	
	engine_screen_select_button.reparent(top_bar)
	top_bar.move_child(engine_screen_select_button, -1)


## GET NODES

func get_current_bottom_bar() -> Control:
	var result: Control
	
	# Script
	if engine_script_editor.get_current_editor():
		var i = engine_script_editor.get_current_editor().\
		find_children("*", "CodeTextEditor", true, false)[0]
		result = i.get_child(1)
	# Docs
	else:
		if not engine_script_list.is_anything_selected(): return result
		
		var array := engine_script_editor.\
		find_children("*", "EditorHelp", true, false)
		var needed := engine_script_list.\
		get_item_text( engine_script_list.get_selected_items()[0] )
		
		for i in array:
			if i.name == needed: 
				return i.get_child(2)
	
	return result

func get_all_bottom_bars() -> Array[Control]:
	var result: Array[Control]
	# Bottom Bars in Scripts
	for i in get_editor_interface().get_script_editor().\
	find_children("*", "CodeTextEditor", true, false):
		result.append( i.get_child(1) )
	
	# Bottom Bars in Help Docs
	for i in get_editor_interface().get_script_editor().\
	find_children("*", "EditorHelp", true, false):
		result.append( i.get_child(2) )
	
	return result

func load_engine_nodes() -> void:
	engine_editor_interface = get_editor_interface()
	engine_script_editor = engine_editor_interface.get_script_editor()
	
	engine_script_vbox = engine_script_editor.\
	get_child(0).get_child(1).get_child(0)
	
	engine_script_list = engine_script_editor.get_child(0).get_child(1)\
	.get_child(0).get_child(0).get_child(1)
	
	engine_method_searchline = engine_script_vbox.get_child(1).find_children("*", "LineEdit", true, false)[0] as LineEdit
	engine_method_searchline.clear()
	
	engine_method_list = engine_script_vbox.get_child(1).get_child(-2)
	engine_docs_headers_list = engine_script_vbox.get_child(1).get_child(-1)
	
	top_bar = engine_script_editor.get_child(0).get_child(0)
	top_bar_parent = top_bar.get_parent()


## SCRIPT PANEL

func create_script_panel() -> void:
	script_panel = scene.instantiate()
	script_panel.plugin_reference = self
	script_panel.set_process(false)
	upload_engine_nodes_to_script_panel()
	
	engine_script_editor.get_child(0).get_child(1).add_child(script_panel)
	engine_script_editor.get_child(0).get_child(1).move_child(script_panel, 0)
	
	script_panel.update_script_editor_list()
	script_panel.update_all_scripts()

func upload_engine_nodes_to_script_panel() -> void:
	script_panel.engine_editor_interface = engine_editor_interface
	script_panel.engine_script_editor = engine_script_editor
	script_panel.engine_script_list = engine_script_list


## PRINT

func print_message(text: String) -> void:
	print_rich("[color=cadetblue][b]Script Panel Plus: [/b][/color]", text)

func print_error(text: String) -> void:
	print_rich("[color=cadetblue][b]Script Panel Plus: [/b][/color][color=lightcoral]", text, "[/color]")


## MISC

func _scripts_are_loading() -> bool:
	return get_editor_interface().get_script_editor().\
	get_child(0).get_child(0).get_children().size() < 15
