// Frame interpolation: draws the frame halfway between the previous and the
// current frame.
//
// Each pixel tries the smoothly interpolated motion, the motion of the four
// surrounding blocks and zero, and keeps the one where both frames agree best
// around it. The motion field was cleaned of isolated wrong vectors before.
// Frames are sampled with a Catmull-Rom filter so the interpolated frame is as
// sharp as the decoded ones, and pixels that didn't change between the two
// frames are copied as is, so static content (game HUD) never moves.

Texture2D<float4> prevFrame : register(t0);
Texture2D<float4> currFrame : register(t1);
Texture2D<float4> motionField : register(t2);   // xy: motion
Texture2D<float> prevLuma : register(t3);       // Half resolution
Texture2D<float> currLuma : register(t4);
SamplerState linearClamp : register(s0);

cbuffer INTERP_CONST_BUF : register(b1)
{
    float2 videoSize;
    float2 invVideoSize;
    float2 gridSize;
    float blockSize;
    float padding;
};

struct ShaderInput
{
    float4 pos : SV_POSITION;
    float2 tex : TEXCOORD0;
};

// Change below which a pixel counts as static
#define STATIC_START 0.015
#define STATIC_END 0.04

// Distance of the neighbourhood samples, in full resolution pixels
#define NEIGHBOURHOOD_RADIUS 3.0

// Catmull-Rom filter with 9 bilinear taps. pos is in pixels.
float4 sampleSharp(Texture2D<float4> tex, float2 pos)
{
    float2 samplePos = pos - 0.5;
    float2 texPos1 = floor(samplePos) + 0.5;
    float2 f = samplePos - floor(samplePos);

    float2 w0 = f * (-0.5 + f * (1.0 - 0.5 * f));
    float2 w1 = 1.0 + f * f * (-2.5 + 1.5 * f);
    float2 w2 = f * (0.5 + f * (2.0 - 1.5 * f));
    float2 w3 = f * f * (-0.5 + 0.5 * f);

    float2 w12 = w1 + w2;
    float2 texPos0 = (texPos1 - 1.0) * invVideoSize;
    float2 texPos3 = (texPos1 + 2.0) * invVideoSize;
    float2 texPos12 = (texPos1 + w2 / w12) * invVideoSize;

    float4 result = 0;
    result += tex.SampleLevel(linearClamp, float2(texPos0.x, texPos0.y), 0) * w0.x * w0.y;
    result += tex.SampleLevel(linearClamp, float2(texPos12.x, texPos0.y), 0) * w12.x * w0.y;
    result += tex.SampleLevel(linearClamp, float2(texPos3.x, texPos0.y), 0) * w3.x * w0.y;
    result += tex.SampleLevel(linearClamp, float2(texPos0.x, texPos12.y), 0) * w0.x * w12.y;
    result += tex.SampleLevel(linearClamp, float2(texPos12.x, texPos12.y), 0) * w12.x * w12.y;
    result += tex.SampleLevel(linearClamp, float2(texPos3.x, texPos12.y), 0) * w3.x * w12.y;
    result += tex.SampleLevel(linearClamp, float2(texPos0.x, texPos3.y), 0) * w0.x * w3.y;
    result += tex.SampleLevel(linearClamp, float2(texPos12.x, texPos3.y), 0) * w12.x * w3.y;
    result += tex.SampleLevel(linearClamp, float2(texPos3.x, texPos3.y), 0) * w3.x * w3.y;

    return saturate(result);
}

float luma(float3 rgb)
{
    return dot(rgb, float3(0.299, 0.587, 0.114));
}

// Mean luma difference around two positions (in pixels) of the previous and
// the current frame, on the half resolution luma
float neighbourhoodMismatch(float2 posA, float2 posB)
{
    float2 uvA = posA * invVideoSize;
    float2 uvB = posB * invVideoSize;
    float2 dx = float2(NEIGHBOURHOOD_RADIUS * invVideoSize.x, 0);
    float2 dy = float2(0, NEIGHBOURHOOD_RADIUS * invVideoSize.y);

    float mismatch = 0;
    mismatch += abs(prevLuma.SampleLevel(linearClamp, uvA - dx, 0) - currLuma.SampleLevel(linearClamp, uvB - dx, 0));
    mismatch += abs(prevLuma.SampleLevel(linearClamp, uvA + dx, 0) - currLuma.SampleLevel(linearClamp, uvB + dx, 0));
    mismatch += abs(prevLuma.SampleLevel(linearClamp, uvA - dy, 0) - currLuma.SampleLevel(linearClamp, uvB - dy, 0));
    mismatch += abs(prevLuma.SampleLevel(linearClamp, uvA + dy, 0) - currLuma.SampleLevel(linearClamp, uvB + dy, 0));
    return mismatch / 4;
}

float4 main(ShaderInput input) : SV_TARGET
{
    float2 pos = input.tex * videoSize;

    // Motion of the 4 surrounding blocks and their smooth interpolation
    float2 grid = pos / blockSize - 0.5;
    int2 g0 = (int2)floor(grid);
    float2 f = grid - g0;
    int2 maxBlock = int2(gridSize) - 1;

    float2 v00 = motionField.Load(int3(clamp(g0, int2(0, 0), maxBlock), 0)).xy;
    float2 v10 = motionField.Load(int3(clamp(g0 + int2(1, 0), int2(0, 0), maxBlock), 0)).xy;
    float2 v01 = motionField.Load(int3(clamp(g0 + int2(0, 1), int2(0, 0), maxBlock), 0)).xy;
    float2 v11 = motionField.Load(int3(clamp(g0 + int2(1, 1), int2(0, 0), maxBlock), 0)).xy;
    float2 smooth = lerp(lerp(v00, v10, f.x), lerp(v01, v11, f.x), f.y);

    float4 current = currFrame.SampleLevel(linearClamp, input.tex, 0);

    // Static pixels are copied, so static content never moves
    float4 previous = prevFrame.SampleLevel(linearClamp, input.tex, 0);
    float staticChange = max(abs(luma(previous.rgb) - luma(current.rgb)), neighbourhoodMismatch(pos, pos));
    float staticWeight = 1.0 - smoothstep(STATIC_START, STATIC_END, staticChange);

    // Moving pixels take the vector where both frames agree best around them.
    // The smooth vector is preferred unless a block vector is clearly better
    // (object edges).
    float2 candidates[6] = { smooth, v00, v10, v01, v11, float2(0, 0) };
    float biases[6] = { 0.0, 0.03, 0.03, 0.03, 0.03, 0.02 };
    float bestError = 1e30;
    float2 bestVector = smooth;

    [unroll]
    for (int i = 0; i < 6; i++) {
        float2 posA = pos - candidates[i];
        float2 posB = pos + candidates[i];
        float centerError = abs(luma(prevFrame.SampleLevel(linearClamp, posA * invVideoSize, 0).rgb) -
                                luma(currFrame.SampleLevel(linearClamp, posB * invVideoSize, 0).rgb));
        float error = centerError + neighbourhoodMismatch(posA, posB) * 4 + biases[i];
        if (error < bestError) {
            bestError = error;
            bestVector = candidates[i];
        }
    }

    // Meet halfway along the chosen motion
    float4 a = sampleSharp(prevFrame, pos - bestVector);
    float4 b = sampleSharp(currFrame, pos + bestVector);
    float4 result = lerp((a + b) * 0.5, current, staticWeight);

    return float4(result.rgb, 1.0);
}
