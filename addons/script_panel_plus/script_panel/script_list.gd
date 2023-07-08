@tool
extends ItemList

signal item_dropped(data)


## DRAG & DROP

func _can_drop_data(at_position: Vector2, data) -> bool:
	return typeof(data) == TYPE_ARRAY\
	 and data[0] is int\
	 and data.size() == 2

func _get_drag_data(at_position: Vector2):
	if item_count < 1: return
	var index: int = get_item_at_position(at_position)
	var script = get_item_metadata(index)
	var mydata := [index, script]
	
	var label := Label.new()
	label.text = get_item_text(index)
	set_drag_preview(label)
	
	return mydata

func _drop_data(at_position: Vector2, data) -> void:
	item_dropped.emit(at_position, data as Array)
