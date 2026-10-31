shader_type canvas_item;

// =================================================
// OCCLUSION SILHOUETTE
// =================================================
// Desenhado numa CÓPIA da sprite da entidade, por cima de todo o mundo.
// Em cada pixel do corpo compara duas cores:
//   - a que o corpo DEVERIA ter ali (COLOR = pixel da sprite × modulate)
//   - a que REALMENTE está na tela naquele ponto
// Iguais → o corpo está visível → não desenha nada.
// Diferentes → algo está na frente (tile da frente, outra entidade, efeito)
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
	if (expected.a < 0.5) {
		discard;
	}

	vec4 screen = texture(screen_tex, SCREEN_UV);
	if (distance(screen.rgb, expected.rgb) <= tolerance) {
		discard; // o corpo está visível aqui
	}

	// Contorno INTERNO: pixel do corpo com algum vizinho vazio.
	vec2 px = TEXTURE_PIXEL_SIZE;
	bool edge = alpha_at(TEXTURE, UV + vec2(px.x, 0.0)) < 0.5
		|| alpha_at(TEXTURE, UV - vec2(px.x, 0.0)) < 0.5
		|| alpha_at(TEXTURE, UV + vec2(0.0, px.y)) < 0.5
		|| alpha_at(TEXTURE, UV - vec2(0.0, px.y)) < 0.5;

	if (edge) {
		COLOR = outline_color;
	} else {
		COLOR = vec4(outline_color.rgb, outline_color.a * fill_alpha);
	}
}
