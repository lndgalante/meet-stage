#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>

using namespace metal;

constant float chromeEdgeSoftness = 2.104;

constant float chromeReferenceHalfWidth = 160.0;
constant float chromeReferenceHalfHeight = 210.0;

constant float2 chromeHaloExtent = float2(230.4, 130.2);
constant float2 chromeHaloCenter = float2(0.0, -205.8);
constant float chromeHaloStop1 = 0.44;
constant float chromeHaloStop2 = 0.76;
constant float chromeHaloAlpha1 = 0.60;
constant float chromeHaloSlope0 = -(1.0 - chromeHaloAlpha1) / chromeHaloStop1;
constant float chromeHaloSlope1 = -chromeHaloAlpha1 / (chromeHaloStop2 - chromeHaloStop1);
constant float chromeHaloNear = 1.45;
constant float chromeHaloFar = 0.85;
constant float chromeHaloBlend = 2.0;

constant float chromeWashStop1 = 0.22;
constant float chromeWashStop2 = 0.48;
constant float chromeWashAlpha0 = 0.30;
constant float chromeWashAlpha1 = 0.12;

constant float chromeFootMidpoint = 0.62;

constant float chromeNoiseFrequency = 0.75;
constant float chromeNoiseGain = 0.26;
constant float chromeNoiseSeed = 17.0;

static inline float chromeRoundedBoxDistance(float2 point, float2 extent, float radius) {
    float2 distance = abs(point) - extent + radius;
    return length(max(distance, 0.0))
        + min(max(distance.x, distance.y), 0.0)
        - radius;
}

static inline float chromeSoftRamp(float value, float antialiasing) {
    float width = max(antialiasing, 1e-6);
    float progress = clamp((value + width) / (2.0 * width), 0.0, 1.0);
    return 2.0 * width
        * (progress * progress * progress - 0.5 * progress * progress * progress * progress)
        + max(value - width, 0.0);
}

static inline float4 chromeCSSMix(
    float3 firstColor,
    float firstAlpha,
    float3 secondColor,
    float secondAlpha,
    float fraction
) {
    float4 first = float4(firstColor * firstAlpha, firstAlpha);
    float4 second = float4(secondColor * secondAlpha, secondAlpha);
    float4 mixed = mix(first, second, clamp(fraction, 0.0, 1.0));
    float3 color = mixed.a > 1e-6 ? mixed.rgb / mixed.a : secondColor;
    return float4(color, mixed.a);
}

static inline float2 chromeHaloOffset(float2 lightDirection, float2 halfExtent) {
    return (lightDirection - float2(0.0, -1.0)) * halfExtent;
}

static inline float chromeHash(float2 lattice, float channel) {
    float3 value = float3(lattice, channel + chromeNoiseSeed);
    return fract(sin(dot(value, float3(127.1, 311.7, 74.7))) * 43758.5453123);
}

static inline float chromeValueNoise(float2 point, float channel) {
    float2 cell = floor(point);
    float2 offset = fract(point);
    float2 weight = offset * offset * (3.0 - 2.0 * offset);
    float topLeft = chromeHash(cell, channel);
    float topRight = chromeHash(cell + float2(1.0, 0.0), channel);
    float bottomLeft = chromeHash(cell + float2(0.0, 1.0), channel);
    float bottomRight = chromeHash(cell + float2(1.0, 1.0), channel);
    return mix(
        mix(topLeft, topRight, weight.x),
        mix(bottomLeft, bottomRight, weight.x),
        weight.y
    ) * 2.0 - 1.0;
}

static inline float chromeFractalNoise(float2 point, float channel) {
    float sum = 0.0;
    float amplitude = 1.0;
    float frequency = 1.0;

    for (int octave = 0; octave < 4; ++octave) {
        sum += chromeValueNoise(
            point * frequency,
            channel + float(octave) * 37.0
        ) * amplitude;
        frequency *= 2.0;
        amplitude *= 0.5;
    }

    return clamp(0.5 + chromeNoiseGain * sum, 0.0, 1.0);
}

static inline float chromeLinearToSRGB(float component) {
    return component <= 0.0031308
        ? component * 12.92
        : 1.055 * pow(component, 1.0 / 2.4) - 0.055;
}

static inline float chromeOverlay(float base, float blend) {
    return base < 0.5
        ? 2.0 * base * blend
        : 1.0 - 2.0 * (1.0 - base) * (1.0 - blend);
}

static inline float3 chromeComposite(float3 destination, float3 source, float alpha) {
    return mix(destination, source, clamp(alpha, 0.0, 1.0));
}

[[ stitchable ]] half4 idleStageChrome(
    float2 position,
    half4 sourceColor,
    float4 boundingRect,
    float radius,
    float haloBlur,
    float haloSize,
    float washAmount,
    float footHeight,
    float grainAmount,
    float intensity,
    float2 light,
    half4 backgroundColor,
    half4 haloColor,
    half4 haloMidColor,
    half4 washTopColor,
    half4 washMidColor,
    half4 footColor
) {
    float2 resolution = max(boundingRect.zw, float2(1.0));
    float2 halfExtent = resolution * 0.5;
    float2 point = position - halfExtent;
    float2 uv = clamp(position / resolution, 0.0, 1.0);
    float scale = max(
        min(
            halfExtent.x / chromeReferenceHalfWidth,
            halfExtent.y / chromeReferenceHalfHeight
        ),
        0.0001
    );
    float cornerRadius = clamp(radius, 0.0, min(halfExtent.x, halfExtent.y));
    float2 lightDirection = (light - 0.5) * 2.0;
    float safeIntensity = max(intensity, 0.0);

    float3 cardColor = float3(backgroundColor.rgb);

    float2 haloExtent = chromeHaloExtent * scale * max(haloSize, 0.0001);
    float2 haloPoint = point - (
        chromeHaloCenter * scale + chromeHaloOffset(lightDirection, halfExtent)
    );
    float2 normalizedHaloPoint = haloPoint / max(haloExtent, float2(0.0001));
    float squaredDistance = dot(normalizedHaloPoint, normalizedHaloPoint);

    float2 blurKernel = (haloBlur * scale) / max(haloExtent, float2(0.0001));
    float2 squaredKernel = blurKernel * blurKernel;
    float averageKernel = 0.5 * (squaredKernel.x + squaredKernel.y);
    float haloEdge = chromeHaloBlend * averageKernel;
    float inverseDistance = 1.0 / max(squaredDistance + haloEdge, 1e-8);
    float haloMix = haloEdge * inverseDistance;

    float radialSigma = (
        squaredKernel.x * normalizedHaloPoint.x * normalizedHaloPoint.x
        + squaredKernel.y * normalizedHaloPoint.y * normalizedHaloPoint.y
        + averageKernel * haloEdge
    ) * inverseDistance;
    float tangentialSigma = 2.0 * averageKernel - radialSigma;

    float haloProgress = sqrt(
        squaredDistance
        + mix(chromeHaloFar, chromeHaloNear, haloMix) * tangentialSigma
    );
    float haloWidth = chromeEdgeSoftness * sqrt(radialSigma);
    float haloAlpha = 1.0
        + chromeHaloSlope0 * haloProgress
        + (chromeHaloSlope1 - chromeHaloSlope0)
            * chromeSoftRamp(haloProgress - chromeHaloStop1, haloWidth)
        - chromeHaloSlope1
            * chromeSoftRamp(haloProgress - chromeHaloStop2, haloWidth);
    haloAlpha = max(haloAlpha, 0.0);

    float excessWhite = chromeSoftRamp(
        chromeHaloStop1 - haloProgress,
        haloWidth
    ) / chromeHaloStop1;
    float3 haloMid = float3(haloMidColor.rgb);
    float3 haloPremultiplied = haloMid * haloAlpha
        + (float3(haloColor.rgb) - haloMid) * excessWhite;
    float3 haloRGB = haloAlpha > 1e-6
        ? haloPremultiplied / haloAlpha
        : haloMid;
    cardColor = chromeComposite(cardColor, haloRGB, haloAlpha * safeIntensity);

    float4 wash;
    if (uv.y < chromeWashStop1) {
        wash = chromeCSSMix(
            float3(washTopColor.rgb), chromeWashAlpha0,
            float3(washMidColor.rgb), chromeWashAlpha1,
            uv.y / chromeWashStop1
        );
    } else {
        wash = chromeCSSMix(
            float3(washMidColor.rgb), chromeWashAlpha1,
            float3(washMidColor.rgb), 0.0,
            (uv.y - chromeWashStop1) / (chromeWashStop2 - chromeWashStop1)
        );
    }
    cardColor = chromeComposite(
        cardColor,
        wash.rgb,
        wash.a * washAmount * safeIntensity
    );

    float footProgress = clamp(
        (uv.y - (1.0 - footHeight)) / max(footHeight, 0.0001),
        0.0,
        1.0
    );
    cardColor = chromeComposite(
        cardColor,
        float3(footColor.rgb),
        min(footProgress / chromeFootMidpoint, 1.0)
    );

    if (grainAmount > 0.0) {
        float2 noisePoint = point / scale * chromeNoiseFrequency;
        float red = chromeLinearToSRGB(chromeFractalNoise(noisePoint, 0.0));
        float green = chromeLinearToSRGB(chromeFractalNoise(noisePoint, 101.0));
        float blue = chromeLinearToSRGB(chromeFractalNoise(noisePoint, 211.0));
        float alpha = chromeFractalNoise(noisePoint, 307.0);
        float3 mixed = float3(
            chromeOverlay(cardColor.r, red),
            chromeOverlay(cardColor.g, green),
            chromeOverlay(cardColor.b, blue)
        );
        cardColor = mix(
            cardColor,
            mixed,
            clamp(grainAmount * alpha, 0.0, 1.0)
        );
    }

    float cardDistance = chromeRoundedBoxDistance(point, halfExtent, cornerRadius);
    float coverage = 1.0 - smoothstep(-1.0, 1.0, cardDistance);
    float3 color = chromeComposite(float3(sourceColor.rgb), cardColor, coverage);

    float dither = (
        fract(sin(dot(position, float2(12.9898, 78.233))) * 43758.5453) - 0.5
    ) / 255.0;
    return half4(half3(clamp(color + dither, 0.0, 1.0)), sourceColor.a);
}
