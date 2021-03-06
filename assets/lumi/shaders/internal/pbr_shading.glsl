/*******************************************************
 *  lumi:shaders/internal/pbr_shading.glsl             *
 *******************************************************
 *  Copyright (c) 2020 spiralhalo and Contributors.    *
 *  Released WITHOUT WARRANTY under the terms of the   *
 *  GNU Lesser General Public License version 3 as     *
 *  published by the Free Software Foundation, Inc.    *
 *******************************************************/
 
const float pbr_specularBloomStr = 0.01;
const float pbr_specularAlphaStr = 0.1;

vec3 pbr_specularBRDF(float roughness, vec3 radiance, vec3 halfway, vec3 lightDir, vec3 viewDir, vec3 normal, vec3 fresnel, float NdotL) {
	// cook-torrance brdf
	float distribution = pbr_distributionGGX(normal, halfway, roughness);
	float geometry     = pbr_geometrySmith(normal, viewDir, lightDir, roughness);

	vec3  num   = distribution * geometry * fresnel;
	float denom = 4.0 * pbr_dot(normal, viewDir) * NdotL;

	vec3  specular = num / max(denom, 0.001);
	return specular * radiance * NdotL;
}

vec3 pbr_lightCalc(vec3 albedo, vec3 radiance, vec3 lightDir, vec3 viewDir, vec3 normal, bool diffuseOn, bool isAmbiance, float haloBlur, inout vec3 specularAccu) {
	
	vec3 halfway = normalize(viewDir + lightDir);
	float roughness = pbr_roughness;

	// ambiance hack
	if (isAmbiance) {
		roughness = min(1.0, roughness + 0.5 * (1 - pbr_metallic));
	}
	
	// disableDiffuse hack
	if (!diffuseOn) {
		return albedo / PI * radiance * pbr_dot(lightDir, vec3(.0, 1.0, .0));
	}

	vec3 specularRadiance;
	vec3 fresnel = pbr_fresnelSchlick(pbr_dot(viewDir, halfway), pbr_f0);
	float NdotL = pbr_dot(normal, lightDir);

	if (haloBlur > roughness) {
		// sun halo hack
		specularRadiance = pbr_specularBRDF(roughness, radiance * 0.75, halfway, lightDir, viewDir, normal, fresnel, NdotL);
		specularRadiance += pbr_specularBRDF(haloBlur, radiance * 0.25, halfway, lightDir, viewDir, normal, fresnel, NdotL);
	} else {
		specularRadiance = pbr_specularBRDF(roughness, radiance, halfway, lightDir, viewDir, normal, fresnel, NdotL);
	}

	vec3 diffuse = (1.0 - fresnel) * (1.0 - pbr_metallic);
	vec3 diffuseRadiance = albedo * diffuse / PI * radiance * NdotL;
	specularAccu += specularRadiance;

	return specularRadiance + diffuseRadiance;
}

void pbr_shading(in frx_FragmentData fragData, inout vec4 a, inout float bloom, in float userBrightness, in bool translucent) {

	vec3 albedo = hdr_gammaAdjust(a.rgb);
	vec3 dielectricF0 = vec3(0.1) * frx_luminance(albedo);
	pbr_roughness = clamp(pbr_roughness, 0.0, 1.0);
	pbr_metallic = clamp(pbr_metallic, 0.0, 1.0);
	pbr_f0 = pbr_f0.r < 0 ? mix(dielectricF0, albedo, pbr_metallic) : clamp(pbr_f0, 0.0, 1.0);

    a.rgb = albedo;

    float ao = l2_ao(fragData);
    vec3 emissive = l2_emissiveRadiance(fragData.emissivity);
    a.rgb *= emissive;
    
    vec3 viewDir = normalize(-l2_viewPos) * frx_normalModelMatrix() * gl_NormalMatrix;

    vec3 normal = fragData.vertexNormal * frx_normalModelMatrix();

    vec3 specularAccu = vec3(0.0);
#if LUMI_LightingMode == LUMI_LightingMode_Dramatic
    float dramaticBloom = 0;
#endif

#if HANDHELD_LIGHT_RADIUS != 0
    if (frx_heldLight().w > 0) {
        vec3 handHeldDir = viewDir;
        vec3 handHeldRadiance = l2_handHeldRadiance();
        if (handHeldRadiance.x + handHeldRadiance.y + handHeldRadiance.z > 0) {
            vec3 adjustedNormal = fragData.diffuse ? normal : viewDir;
            a.rgb += pbr_lightCalc(albedo, handHeldRadiance, handHeldDir, viewDir, adjustedNormal, true, false, 0.0, specularAccu);
        }
    }
#endif

    float perceivedBl = fragData.light.x;
#if LUMI_LightingMode == LUMI_LightingMode_Dramatic
	if (frx_modelOriginType() != MODEL_ORIGIN_REGION) {
		perceivedBl = max(0, perceivedBl - fragData.light.y * 0.1);
	}
#endif
    vec3 blockRadiance = l2_blockRadiance(perceivedBl, userBrightness);
    vec3 baseAmbientRadiance = l2_baseAmbient(userBrightness);
    vec3 ambientDir = normalize(vec3(0.1, 0.9, 0.1) + normal);

#if LUMI_LightingMode == LUMI_LightingMode_Dramatic
    a.rgb += pbr_lightCalc(albedo, blockRadiance * mix(ao, 1.0, 0.5), ambientDir, viewDir, normal, fragData.diffuse, true, 0.0, specularAccu);
#else
    a.rgb += pbr_lightCalc(albedo, blockRadiance * ao, ambientDir, viewDir, normal, fragData.diffuse, true, 0.0, specularAccu);
#endif
    a.rgb += pbr_lightCalc(albedo, baseAmbientRadiance * ao, ambientDir, viewDir, normal, fragData.diffuse, true, 0.0, specularAccu);

    if (frx_worldHasSkylight()) {
        if (fragData.light.y > 0.03125) {
            vec3 sunRadiance = l2_sunRadiance(fragData.light.y, frx_worldTime(), frx_ambientIntensity(), frx_rainGradient());
            vec3 sunDir = l2_vanillaSunDir(frx_worldTime(), 0.0);
            vec3 skyRadiance = l2_skyAmbient(fragData.light.y, frx_worldTime(), frx_ambientIntensity());

            vec3 sunIrradiance = pbr_lightCalc(albedo, sunRadiance * ao, sunDir, viewDir, normal, fragData.diffuse, false, 0.15, specularAccu);
            #if LUMI_LightingMode == LUMI_LightingMode_Dramatic
            dramaticBloom = frx_luminance(sunIrradiance);
            #endif

            a.rgb += sunIrradiance;
            a.rgb += pbr_lightCalc(albedo, skyRadiance * ao, ambientDir, viewDir, normal, fragData.diffuse, true, 0.0, specularAccu);

            #ifndef LUMI_TrueDarkness_DisableMoonlight
            vec3 moonRadiance = l2_moonRadiance(fragData.light.y, frx_worldTime(), frx_ambientIntensity());
            vec3 moonDir = l2_moonDir(frx_worldTime());
            a.rgb += pbr_lightCalc(albedo, moonRadiance * ao, moonDir, viewDir, normal, fragData.diffuse, false, 0.15, specularAccu);
            #endif
        }
    } else {
        vec3 skylessRadiance = l2_skylessRadiance(userBrightness);
        vec3 skylessDir = l2_skylessDir();

        if (skylessRadiance.r + skylessRadiance.g + skylessRadiance.b > 0) {
            a.rgb += pbr_lightCalc(albedo, skylessRadiance * ao, skylessDir, viewDir, normal, fragData.diffuse, false, 0.0, specularAccu);
            if (frx_isSkyDarkened()) {
                vec3 skylessDarkenedDir = l2_skylessDarkenedDir();
                a.rgb += pbr_lightCalc(albedo, skylessRadiance * ao, skylessDarkenedDir, viewDir, normal, fragData.diffuse, false, 0.0, specularAccu);
            }
        }
    }

    // float skyAccess = smoothstep(0.89, 1.0, fragData.light.y);

    float specularLuminance = frx_luminance(specularAccu);
    float smoothness = (1-pbr_roughness);
    bloom += specularLuminance * pbr_specularBloomStr * smoothness * smoothness;
#if LUMI_LightingMode == LUMI_LightingMode_Dramatic
    bloom += dramaticBloom * l2_sunHorizonScale(frx_worldTime()) * hdr_dramaticStr * clamp(LUMI_DramaticLighting_DramaticBloomIntensity * 0.1, 0.0, 1.0);
#endif
    if (translucent) {
        a.a += specularLuminance * pbr_specularBloomStr;
    }
}
