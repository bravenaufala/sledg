shader_type spatial;
render_mode specular_schlick_ggx;

uniform vec4 albedo_color : source_color = vec4(0.54, 0.84, 0.97, 1.0);
uniform vec4 shimmer_color : source_color = vec4(0.90, 0.99, 1.0, 1.0);
uniform float roughness_amount : hint_range(0.02, 0.5) = 0.10;
uniform float specular_amount : hint_range(0.0, 1.0) = 0.92;
uniform float fresnel_strength : hint_range(0.0, 2.0) = 0.55;
uniform float scroll_speed = 0.75;
uniform vec2 uv_scale = vec2(7.0, 36.0);

void fragment() {
	vec2 scaled_uv = UV * uv_scale;
	float t = TIME * scroll_speed;

	float wave_a = sin(scaled_uv.x * 3.1 + scaled_uv.y * 2.1 - t * 2.6);
	float wave_b = cos(scaled_uv.x * 5.4 - scaled_uv.y * 3.3 - t * 3.2);
	float wave_c = sin((scaled_uv.x + scaled_uv.y) * 4.2 + t * 1.4);
	float ripple = (wave_a * 0.45 + wave_b * 0.35 + wave_c * 0.20) * 0.5 + 0.5;

	float caustic_band = smoothstep(0.64, 0.94, ripple);
	float streak = smoothstep(0.72, 0.98, sin(scaled_uv.x * 8.0 + sin(scaled_uv.y * 1.5 - t * 2.0)) * 0.5 + 0.5);
	float ndotv = clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0);
	float fresnel = pow(1.0 - ndotv, 3.0);

	vec3 base_col = mix(albedo_color.rgb, shimmer_color.rgb, caustic_band * 0.28 + streak * 0.14);
	ALBEDO = base_col;
	ROUGHNESS = clamp(roughness_amount + (0.5 - ripple) * 0.03 - caustic_band * 0.03, 0.04, 0.18);
	SPECULAR = specular_amount;
	METALLIC = 0.08;
	EMISSION = shimmer_color.rgb * (fresnel * fresnel_strength * 0.42 + caustic_band * 0.07 + streak * 0.05);
}
