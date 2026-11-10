shader_type canvas_item;

// =================================================
// OCCLUSION SILHOUETTE
// =================================================
// Desenhado numa CÓPIA da sprite da entidade, por cima de todo o mundo.
// Em cada pixel do corpo compara duas cores:
//   - a que o corpo DEVERIA ter ali (COLOR = pixel da sprite × modulate)
//   - a que REALMENTE está na tela naquele ponto
// Iguais → o corpo está visível → não desenha nada.
// Diferentes → algo está na frente (tile da frente, outra entidade)
// → desenha a silhueta: contorno interno de 1 px + miolo levemente
// preenchido.
//
// Não depende de camadas: qualquer coisa opaca desenhada por cima do corpo
// dispara a silhueta, em qualquer TileMapLayer.

uniform sampler2D screen_tex : hint_screen_texture, filter_nearest;

// Cor do contorno (e, com alpha reduzido, do miolo).
uniform vec4 outline_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);

// Opacidade do miolo, relativa à do contorno. 0 = só contorno.
uniform float fill_alpha : hint_range(0.0, 1.0) = 0.25;

// Diferença de cor (0 a ~1.7) abaixo da qual "é o próprio corpo".
uniform float tolerance : hint_range(0.0, 0.5) = 0.02;

// Alpha mínimo para um pixel contar como corpo (e para achar a borda do
// contorno). Pixels semitransparentes ficam de fora: na tela eles aparecem
// misturados com o fundo, então a comparação de cor sempre acusaria algo na
// frente e a silhueta acenderia sozinha.
uniform float alpha_cutoff : hint_range(0.0, 1.0) = 0.99;

// MAPA DE CÉLULAS DA FRENTE — preenchido em runtime por FrontTiles.bind_mask()
// (inimigos e itens). Com ele ligado, um pixel só vira silhueta se ALÉM de a
// cor diferir ele estiver numa célula com tile da frente: um inimigo passando
// pela parte APARENTE de um item meio coberto não acende essa parte. O
// jogador nunca liga isto (deve mostrar o contorno com inimigos na frente).
// Não calibrar no Inspector: é dado da cena, escrito por código.
uniform bool use_front_mask = false;
uniform sampler2D front_mask : filter_nearest;
uniform vec2 mask_origin = vec2(0.0);
uniform vec2 mask_cell_size = vec2(16.0);
uniform vec2 mask_size_cells = vec2(1.0);

varying vec2 world_pos;

void vertex() {
	// Posição de MUNDO do vértice (local → mundo), para o fragmento saber em
	// que célula do mapa está.
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

// Alpha da sprite numa UV; fora da imagem conta como vazio, para que a borda
// do quadro também gere contorno.
float alpha_at(sampler2D tex, vec2 uv) {
	if (uv.x < 0.0 || uv.y < 0.0 || uv.x > 1.0 || uv.y > 1.0) {
		return 0.0;
	}
	return texture(tex, uv).a;
}

void fragment() {
	// COLOR já chega como pixel da sprite × modulate — exatamente a cor que
	// a sprite original desenhou neste ponto.
	vec4 expected = COLOR;
	if (expected.a < alpha_cutoff) {
		discard;
	}

	vec4 screen = texture(screen_tex, SCREEN_UV);
	if (distance(screen.rgb, expected.rgb) <= tolerance) {
		discard; // o corpo está visível aqui
	}

	if (use_front_mask) {
		vec2 cell = floor((world_pos - mask_origin) / mask_cell_size);
		if (cell.x < 0.0 || cell.y < 0.0 || cell.x >= mask_size_cells.x || cell.y >= mask_size_cells.y) {
			discard; // fora do mapa: não há tile da frente
		}
		if (texture(front_mask, (cell + 0.5) / mask_size_cells).r < 0.5) {
			discard; // coberto, mas não por tile da frente (outra entidade)
		}
	}

	// Contorno INTERNO: pixel do corpo com algum vizinho vazio.
	vec2 px = TEXTURE_PIXEL_SIZE;
	bool edge = alpha_at(TEXTURE, UV + vec2(px.x, 0.0)) < alpha_cutoff
		|| alpha_at(TEXTURE, UV - vec2(px.x, 0.0)) < alpha_cutoff
		|| alpha_at(TEXTURE, UV + vec2(0.0, px.y)) < alpha_cutoff
		|| alpha_at(TEXTURE, UV - vec2(0.0, px.y)) < alpha_cutoff;

	if (edge) {
		COLOR = outline_color;
	} else {
		COLOR = vec4(outline_color.rgb, outline_color.a * fill_alpha);
	}
}
