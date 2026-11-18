shader_type spatial;
render_mode specular_schlick_ggx;

void fragment() {
	vec2 p = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xz;
	float t = TIME;
	float w1 = sin(p.x * 0.35 + t * 1.3) * cos(p.y * 0.28 + t * 0.9);
	float w2 = sin(p.x * 1.3 - p.y * 1.1 + t * 2.1) * 0.5;
	float w3 = sin(p.x * 3.1 + p.y * 2.7 - t * 3.0) * 0.25;
	vec3 n = normalize(vec3((w1 + w2 + w3) * 0.12, 1.0, (w1 - w2 + w3) * 0.12));
	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 4.0);
	ALBEDO = mix(vec3(0.02, 0.09, 0.12), vec3(0.08, 0.22, 0.28), fres);
	ROUGHNESS = 0.06;
	METALLIC = 0.2;
	SPECULAR = 0.7;
}
