shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, fog_disabled;

uniform sampler2D noise : repeat_enable, filter_linear_mipmap;
uniform float coverage = 0.45;
uniform vec4 tint : source_color = vec4(1.0);

void fragment() {
	vec2 p = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xz;
	vec2 uv = p * 0.00045 + vec2(TIME * 0.004, TIME * 0.0015);
	float n = texture(noise, uv).r * 0.65 + texture(noise, uv * 2.7 + 0.3).r * 0.35;
	float c = smoothstep(1.0 - coverage, 1.0 - coverage + 0.25, n);
	// fade toward the horizon so the plane edge is never visible
	float d = length(p - (INV_VIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xz);
	float fade = 1.0 - smoothstep(600.0, 1400.0, d);
	ALBEDO = tint.rgb * mix(0.82, 1.0, n);
	ALPHA = c * fade * 0.9;
}
