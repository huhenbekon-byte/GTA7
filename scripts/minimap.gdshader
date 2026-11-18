shader_type canvas_item;
uniform vec2 center_uv = vec2(0.5);
uniform float angle = 0.0;
uniform float zoom = 0.08;

void fragment() {
	vec2 d = UV - vec2(0.5);
	float r = length(d);
	if (r > 0.5) discard;
	float c = cos(angle), s = sin(angle);
	vec2 md = vec2(d.x * c + d.y * s, -d.x * s + d.y * c);
	vec2 uv = center_uv + md * zoom * 2.0;
	vec4 col = vec4(0.12, 0.2, 0.3, 1.0);
	if (uv.x >= 0.0 && uv.x <= 1.0 && uv.y >= 0.0 && uv.y <= 1.0) {
		vec4 t = texture(TEXTURE, uv);
		col = mix(col, t, t.a);
	}
	col.rgb *= 1.0 - smoothstep(0.42, 0.5, r) * 0.35;
	COLOR = vec4(col.rgb, 0.92);
}
