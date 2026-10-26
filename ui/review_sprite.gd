extends Control
## Integer display scale preserves the native pixel grid while fitting the card.
var texture: Texture2D

func show_image(image: Image) -> void:
	texture = ImageTexture.create_from_image(image) if image != null else null
	queue_redraw()

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("111923"))
	if texture == null: return
	var native := texture.get_size()
	var zoom := maxi(1, floori(minf((size.x - 24) / native.x, (size.y - 24) / native.y)))
	var extent := native * zoom
	var origin := ((size - extent) * 0.5).floor()
	draw_texture_rect(texture, Rect2(origin, extent), false)
