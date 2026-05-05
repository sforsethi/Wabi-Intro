#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>

using namespace metal;

[[ stitchable ]] half4 ryceRefractiveGlass(
    float2 position,
    SwiftUI::Layer layer,
    float2 size,
    float2 glassCenter,
    float glassRadius,
    float refraction,
    float shadowBlur,
    float time
) {
    float2 safePosition = clamp(position, float2(1.0), size - float2(1.0));
    half4 originalColor = layer.sample(safePosition);

    float2 toCenter = position - glassCenter;
    float dist = length(toCenter);
    float normalizedDist = dist / max(glassRadius, 1.0);
    float2 direction = toCenter / max(dist, 1.0);

    float shadowOffset = shadowBlur * 0.36;
    float2 shadowCenter = glassCenter + float2(shadowOffset, shadowOffset);
    float shadowDist = length(position - shadowCenter);
    float shadowRadius = glassRadius + shadowBlur;

    half4 result = originalColor;

    if (normalizedDist > 1.0) {
        if (shadowDist < shadowRadius) {
            float shadowFalloff = (shadowDist - glassRadius) / max(shadowBlur, 1.0);
            float shadowStrength = smoothstep(1.0, 0.0, shadowFalloff);
            result.rgb = mix(result.rgb, half3(0.0), half(shadowStrength * 0.055));
        }

        return result;
    }

    float falloff = 1.0 - normalizedDist * normalizedDist;
    float edgeFalloff = smoothstep(0.42, 1.0, normalizedDist);
    float2 refractedOffset = toCenter * falloff * refraction;

    float edgeDistanceToScreen = min(min(position.x, size.x - position.x), min(position.y, size.y - position.y));
    float screenEdgeFade = smoothstep(0.0, 36.0, edgeDistanceToScreen);
    float chromaticStrength = edgeFalloff * screenEdgeFade * 0.18;

    float2 refractedPosition = clamp(position - refractedOffset, float2(1.0), size - float2(1.0));
    float2 redPosition = clamp(position - refractedOffset * (1.0 + chromaticStrength), float2(1.0), size - float2(1.0));
    float2 bluePosition = clamp(position - refractedOffset * (1.0 - chromaticStrength), float2(1.0), size - float2(1.0));

    half4 refractedColor = layer.sample(refractedPosition);
    half4 redSample = layer.sample(redPosition);
    half4 blueSample = layer.sample(bluePosition);
    refractedColor.r = redSample.r;
    refractedColor.b = blueSample.b;

    result = refractedColor;
    float darkAmount = 1.0 - clamp(float(dot(result.rgb, half3(0.299, 0.587, 0.114))), 0.0, 1.0);

    float horizontalSide = dot(direction, normalize(float2(1.0, 0.0)));
    half3 manualChroma = mix(
        half3(0.05, 0.22, 1.0),
        half3(1.0, 0.08, 0.03),
        half(horizontalSide * 0.5 + 0.5)
    );

    float manualChromaMask = edgeFalloff * screenEdgeFade * darkAmount;
    result.rgb += manualChroma * half(manualChromaMask * 0.18);

    float edgeThickness = 0.045 * min(size.x, size.y);
    float edgeDistance = abs(dist - glassRadius);
    float edgeFade = smoothstep(edgeThickness, 0.0, edgeDistance);

    float2 lightDir = normalize(float2(-0.5, -0.8));
    float rimBias = clamp(dot(direction, lightDir), 0.0, 1.0);
    half3 highlightColor = half3(1.06, 1.08, 1.14);
    result.rgb += half(edgeFade * rimBias * 0.28) * highlightColor;

    float lowerOcclusion = smoothstep(0.10, 0.92, normalizedDist) * smoothstep(-0.25, 0.92, direction.y);
    result.rgb = mix(result.rgb, half3(0.0), half(lowerOcclusion * 0.035));

    float innerSheen = (1.0 - smoothstep(0.0, 0.64, normalizedDist)) * 0.12;
    float caustic = (sin(position.x * 0.028 + position.y * 0.018 + time * 1.6) * 0.5 + 0.5) * edgeFade;
    result.rgb = mix(result.rgb, half3(1.0), half(innerSheen + caustic * 0.035));

    float darkAmount2 = 1.0 - clamp(float(dot(result.rgb, half3(0.299, 0.587, 0.114))), 0.0, 1.0);

    float leftFringe = smoothstep(-0.85, -0.15, direction.x);
    float rightFringe = smoothstep(0.15, 0.85, direction.x);

    half3 blueFringe = half3(0.0, 0.35, 1.0) * half(leftFringe);
    half3 redFringe  = half3(1.0, 0.12, 0.0) * half(rightFringe);

    float fringeMask = edgeFade * darkAmount2;

    result.rgb += (blueFringe + redFringe) * half(fringeMask * 4.0);
    return result;
}

[[ stitchable ]] float2 rycePortalCompressionWarp(
    float2 position,
    float diameter,
    float intensity,
    float time
) {
    float radius = max(diameter * 0.5, 1.0);
    float2 center = float2(radius, radius);
    float2 delta = position - center;
    float distanceFromCenter = length(delta);
    float normalizedRadius = clamp(distanceFromCenter / radius, 0.0, 1.0);
    float edgeMask = smoothstep(0.32, 0.96, normalizedRadius);
    float coreMask = 1.0 - smoothstep(0.0, 0.58, normalizedRadius);

    float wave = sin(delta.y * 0.095 + time * 18.0) + cos(delta.x * 0.075 - time * 14.0);
    float edgeFlutter = wave * 2.4 * intensity * edgeMask;
    float pinchX = 1.0 - intensity * 0.28 * coreMask;
    float stretchY = 1.0 + intensity * 0.18 * coreMask;

    float angle = intensity * 0.10 * sin(time * 8.0 + normalizedRadius * 8.0);
    float s = sin(angle);
    float c = cos(angle);

    float2 warped = float2(
        delta.x * pinchX + edgeFlutter,
        delta.y * stretchY - edgeFlutter * 0.42
    );

    return center + float2(
        warped.x * c - warped.y * s,
        warped.x * s + warped.y * c
    );
}

[[ stitchable ]] half4 rycePortalRedBlueGlow(
    float2 position,
    half4 currentColor,
    float diameter,
    float intensity,
    float time
) {
    float radius = max(diameter * 0.5, 1.0);
    float2 center = float2(radius, radius);
    float2 delta = position - center;
    float normalizedRadius = clamp(length(delta) / radius, 0.0, 1.0);
    float angle = atan2(delta.y, delta.x);

    float whiteCore = 1.0 - smoothstep(0.0, 0.48 - intensity * 0.10, normalizedRadius);
    float edgeBand = smoothstep(0.82, 0.91, normalizedRadius) * (1.0 - smoothstep(0.96, 1.0, normalizedRadius));
    float rimBand = smoothstep(0.90, 0.97, normalizedRadius) * (1.0 - smoothstep(0.985, 1.0, normalizedRadius));

    float edgeWave = sin(angle * 2.0 + time * 2.4 + normalizedRadius * 3.0);
    float3 redBlue = mix(
        float3(1.0, 0.04, 0.025),
        float3(0.04, 0.22, 1.0),
        smoothstep(-0.9, 0.9, edgeWave)
    );

    float3 base = float3(currentColor.rgb);
    base = mix(base, float3(1.0), whiteCore * (0.58 + intensity * 0.20));
    base = mix(base, redBlue, edgeBand * (0.07 + intensity * 0.16));
    base = mix(base, redBlue, rimBand * intensity * 0.24);

    float glow = (whiteCore * 0.24 + edgeBand * 0.05) * intensity;
    base = min(base + glow, float3(1.0));

    return half4(half3(base), currentColor.a);
}
