extends Node
## Renders the wall-map texture (TubeMapTexture) to build/map_texture.png so it can be inspected.
func run():
	var t := TubeMapTexture.texture()
	for i in 12: await get_tree().process_frame
	var img := t.get_image()
	print("map texture ", img.get_size())
	img.save_png("res://build/map_texture.png")
	print("OK")
