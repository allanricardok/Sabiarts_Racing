# token_reward_ui.gd
extends CanvasLayer
class_name TokenRewardUI

@onready var status_lbl = find_child("StatusLabel", true, false) as Label
@onready var tokens_ganhos_lbl = find_child("TokensGanhosLabel", true, false) as Label
@onready var saldo_total_lbl = find_child("SaldoTotalLabel", true, false) as Label
@onready var fechar_btn = %FecharBtn as Button

var _controller_callback: Node = null

func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS
	hide()
	# Só conecta por código se não estiver conectado pelo Editor
	if not fechar_btn.pressed.is_connected(_on_fechar_pressed):
		fechar_btn.pressed.connect(_on_fechar_pressed)

## Preenche os dados calculados e exibe a tela na tela do jogador
func exibir_extrato(mission_name: String, status_tipo: String, tokens_ganhos: int, controller_ref: Node):
	_controller_callback = controller_ref
	get_tree().paused = true
	show()
	
	# 1. Atualiza os textos dinamicamente
	if status_tipo == "FIRST_TIME":
		status_lbl.text = "Missão Inédita Concluída! (Bônus de 20%)"
		status_lbl.add_theme_color_override("font_color", Color.GOLD)
	elif status_tipo == "REPEATED":
		status_lbl.text = "Missão Concluída Novamente! (Taxa de 10%)"
		status_lbl.add_theme_color_override("font_color", Color.AQUAMARINE)
	else:
		# --- TEXTO CORRIGIDO AQUI ---
		status_lbl.text = "Limite de tokens desta partida alcançado"
		status_lbl.add_theme_color_override("font_color", Color.DARK_GRAY)
		
	tokens_ganhos_lbl.text = "+" + str(tokens_ganhos) + " TOKENS LOJA"
	if tokens_ganhos > 0:
		tokens_ganhos_lbl.add_theme_color_override("font_color", Color.YELLOW)
	else:
		tokens_ganhos_lbl.add_theme_color_override("font_color", Color.WHITE)
		
	if is_instance_valid(Global):
		saldo_total_lbl.text = "Saldo Atual da Carteira: " + str(Global.total_tokens) + " Tokens"
		
	fechar_btn.grab_focus()

func _on_fechar_pressed():
	hide()
	# Devolve o controle para o StoryModeController despausar ou carregar o menu
	if is_instance_valid(_controller_callback) and _controller_callback.has_method("resume_open_world"):
		_controller_callback.resume_open_world()
