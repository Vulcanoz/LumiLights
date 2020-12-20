/*******************************************************
 *  lumi:shaders/internal/lightsource.glsl             *
 *******************************************************
 *  Copyright (c) 2020 spiralhalo and Contributors.    *
 *  Released WITHOUT WARRANTY under the terms of the   *
 *  GNU Lesser General Public License version 3 as     *
 *  published by the Free Software Foundation, Inc.    *
 *******************************************************/

const float hdr_sunStr = 5;
const float hdr_moonStr = 0.4;
const float hdr_minBlockStr = 2;
const float hdr_maxBlockStr = 3;
const float hdr_handHeldStr = 1.5;
const float hdr_skylessStr = 0.2;
const float hdr_baseMinStr = 0.01;
const float hdr_baseMaxStr = 0.8;
const float hdr_emissiveStr = 1;
const float hdr_relAmbient = 0.2;
const float hdr_zWobbleDefault = 0.1;
const vec3 blockColor = vec3(1.0, 0.875, 0.75);

/*  BASE AMBIENT LIGHT
 *******************************************************/

vec3 l2_baseAmbient(float userBrightness){
	if(frx_worldHasSkylight()){
		return vec3(0.1) * mix(hdr_baseMinStr, hdr_baseMaxStr, userBrightness);
	} else {
		return l2_dimensionColor() * mix(hdr_baseMinStr, hdr_baseMaxStr, userBrightness);
	}
}

/*  BLOCK LIGHT
 *******************************************************/

vec3 l2_blockRadiance(float blockLight, float userBrightness) {
	float bl = l2_clampScale(0.03125, 1.0, blockLight);
	bl *= bl * mix(hdr_minBlockStr, hdr_maxBlockStr, userBrightness);
	return hdr_gammaAdjust(bl * blockColor);
}

/*  HELD LIGHT
 *******************************************************/

#if HANDHELD_LIGHT_RADIUS != 0
vec3 l2_handHeldRadiance() {
	vec4 held = frx_heldLight();
	float hl = l2_clampScale(held.w * HANDHELD_LIGHT_RADIUS, 0.0, gl_FogFragCoord);
	hl *= hl * hdr_handHeldStr;
	return hdr_gammaAdjust(held.rgb * hl);
}
#endif

/*  EMISSIVE LIGHT
 *******************************************************/

vec3 l2_emissiveRadiance(float emissivity) {
	return vec3(hdr_gammaAdjust(emissivity) * hdr_emissiveStr);
}

/*  SKY AMBIENT LIGHT
 *******************************************************/

float l2_skyLight(float skyLight, float intensity) {
	float sl = l2_clampScale(0.03125, 1.0, skyLight);
	return hdr_gammaAdjust(sl) * intensity;
}

vec3 l2_ambientColor(float time) {
	vec3 ambientColor = hdr_gammaAdjust(vec3(0.6, 0.9, 1.0)) * hdr_sunStr * hdr_relAmbient;
	vec3 sunriseAmbient = hdr_gammaAdjust(vec3(1.0, 0.8, 0.4)) * hdr_sunStr * hdr_relAmbient;
	vec3 sunsetAmbient = hdr_gammaAdjust(vec3(1.0, 0.6, 0.2)) * hdr_sunStr * hdr_relAmbient;
	vec3 nightAmbient = hdr_gammaAdjust(vec3(1.0, 1.0, 2.0)) * hdr_moonStr * hdr_relAmbient;
	if(time > 0.94){
		ambientColor = mix(nightAmbient, sunriseAmbient, l2_clampScale(0.94, 0.98, time));
	} else if(time > 0.52){
		ambientColor = mix(sunsetAmbient, nightAmbient, l2_clampScale(0.52, 0.56, time));
	} else if(time > 0.48){
		ambientColor = mix(ambientColor, sunsetAmbient, l2_clampScale(0.48, 0.5, time));
	} else if(time < 0.02){
		ambientColor = mix(ambientColor, sunriseAmbient, l2_clampScale(0.02, 0, time));
	}
	return ambientColor;
}

vec3 l2_skyAmbient(float skyLight, float time, float intensity) {
	float sa = l2_skyLight(skyLight, intensity) * 2.5;
	return sa * l2_ambientColor(time);
}

/*  SKYLESS LIGHT
 *******************************************************/

vec3 l2_skylessLightColor() {
	return hdr_gammaAdjust(vec3(1.0));
}

vec3 l2_dimensionColor() {
	if (frx_isWorldTheNether()) {
		float min_col = min(min(gl_Fog.color.rgb.x, gl_Fog.color.rgb.y), gl_Fog.color.rgb.z);
		float max_col = max(max(gl_Fog.color.rgb.x, gl_Fog.color.rgb.y), gl_Fog.color.rgb.z);
		float sat = 0.0;
		if (max_col != 0.0) {
			sat = (max_col-min_col)/max_col;
		}
	
		return hdr_gammaAdjust(clamp((gl_Fog.color.rgb*(1/max_col))+pow(sat,2)/2, 0.0, 1.0));
	}
	else {
		return hdr_gammaAdjust(vec3(0.8, 0.7, 1.0));
	}
}

vec3 l2_skylessDarkenedDir() {
	return vec3(0, -0.977358, 0.211593);
}

vec3 l2_skylessDir() {
	return vec3(0, 0.977358, 0.211593);
}

vec3 l2_skylessRadiance(float userBrightness) {
	if (frx_worldHasSkylight()) {
		return vec3(0);
	} else {
		return ( frx_isSkyDarkened() ? 0.5 : 1.0 )
			* hdr_skylessStr
			* l2_skylessLightColor()
			* userBrightness;
	}
}

/*  SUN LIGHT
 *******************************************************/

vec3 l2_sunColor(float time){
	vec3 sunColor = hdr_gammaAdjust(vec3(1.0, 1.0, 0.8)) * hdr_sunStr;
	vec3 sunriseColor = hdr_gammaAdjust(vec3(1.0, 0.8, 0.4)) * hdr_sunStr;
	vec3 sunsetColor = hdr_gammaAdjust(vec3(1.0, 0.6, 0.4)) * hdr_sunStr;
	if(time > 0.94){
		sunColor = sunriseColor;
	} else if(time > 0.56){
		sunColor = vec3(0); // pitch black at night
	} else if(time > 0.54){
		sunColor = mix(sunsetColor, vec3(0), l2_clampScale(0.54, 0.56, time));
	} else if(time > 0.5){
		sunColor = sunsetColor;
	} else if(time > 0.48){
		sunColor = mix(sunColor, sunsetColor, l2_clampScale(0.48, 0.5, time));
	} else if(time < 0.02){
		sunColor = mix(sunColor, sunriseColor, l2_clampScale(0.02, 0, time));
	}
	return sunColor;
}

vec3 l2_vanillaSunDir(in float time, float zWobble){

	// wrap time to account for sunrise
	time -= (time >= 0.75) ? 1.0 : 0.0;

	// supposed offset of sunset/sunrise from 0/12000 daytime. might get better result with datamining?
	float sunHorizonDur = 0.04;

	// angle of sun in radians
	float angleRad = l2_clampScale(-sunHorizonDur, 0.5+sunHorizonDur, time) * PI;

	return normalize(vec3(cos(angleRad), sin(angleRad), zWobble));
}

vec3 l2_sunRadiance(float skyLight, in float time, float intensity, float rainGradient){

	// wrap time to account for sunrise
	float customTime = (time >= 0.75) ? (time - 1.0) : time;

    float customIntensity = l2_clampScale(-0.08, 0.00, customTime);

    if(customTime >= 0.25){
		customIntensity = l2_clampScale(0.58, 0.5, customTime);
    }

	customIntensity *= mix(1.0, 0.0, rainGradient);

	float sl = l2_skyLight(skyLight, max(customIntensity, intensity));

	// direct sun light doesn't reach into dark spot as much as sky ambient
	sl = frx_smootherstep(0.5,1.0,sl);

	return sl * l2_sunColor(time);
}

/*  MOON LIGHT
 *******************************************************/

vec3 l2_moonDir(float time){
    float aRad = l2_clampScale(0.56, 0.94, time) * PI;
	return normalize(vec3(cos(aRad), sin(aRad), 0));
}

vec3 l2_moonRadiance(float skyLight, float time, float intensity){
	float ml = l2_skyLight(skyLight, intensity) * frx_moonSize() * hdr_moonStr;
	if(time < 0.58){
		ml *= l2_clampScale(0.54, 0.58, time);
	} else if(time > 0.92){
		ml *= l2_clampScale(0.96, 0.92, time);
	}
	return vec3(ml);
}