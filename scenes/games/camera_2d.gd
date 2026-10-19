extends Camera2D

var short_shake_tween:Tween
# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass
func camera_shake_short(strength:float=10):
	if short_shake_tween and short_shake_tween.is_running():
		short_shake_tween.kill()
	short_shake_tween=create_tween()
	offset=Vector2.ONE.rotated(randf_range(-PI,PI))*int(strength*3)
	short_shake_tween.tween_property(self,"offset",Vector2.ZERO,0.8).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
