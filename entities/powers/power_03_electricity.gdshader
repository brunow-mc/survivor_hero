shader_type canvas_item;

uniform float pulse_speed = 6.0;

/* brilho */
uniform float brightness_min = 0.8;
uniform float brightness_max = 1.6;

/* transparência */
uniform float alpha_min = 0.25;
uniform float alpha_max = 0.45;

void fragment() {
    vec4 tex = texture(TEXTURE, UV);

    // Pulso base (0 → 1)
    float pulse = 0.5 + 0.5 * sin(TIME * pulse_speed);

    // Brilho alternando entre mínimo e máximo
    float brightness = mix(brightness_min, brightness_max, pulse);
    vec3 final_color = tex.rgb * brightness;

    // Alpha sempre transparente
    float alpha = mix(alpha_min, alpha_max, pulse);

    COLOR = vec4(final_color, tex.a * alpha);
}
