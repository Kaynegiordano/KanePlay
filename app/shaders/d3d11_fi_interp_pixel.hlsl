// Frame interpolation: draws the frame halfway between the previous and the
// current frame using the block motion field.
//
// Each pixel tries the smoothly interpolated vector, the vectors of the four
// surrounding blocks and zero, and keeps the one where both frames agree best
// around it. This keeps object edges and static overlays (game HUD) sharp.

Texture2D<float4> prevFrame : register(t0);
Texture2D<float4> currFrame : register(t1);
Texture2D<float2> motionField : register(t2);
Texture2D<float> prevLuma : register(t3);  // Half resolution
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

// A single pixel matches by chance too often in flat areas, so the
// neighbourhood is compared as well
#define NEIGHBOURHOOD_RADIUS 4.0

void tryVector(float2 pos, float2 d, float bias,
               inout float bestError, inout float4 bestColor)
{
    float2 uvA = (pos - d) * invVideoSize;
    float2 uvB = (pos + d) * invVideoSize;

    float4 a = prevFrame.SampleLevel(linearClamp, uvA, 0);
    float4 b = currFrame.SampleLevel(linearClamp, uvB, 0);
    float3 diff = abs(a.rgb - b.rgb);
    float error = diff.r + diff.g + diff.b + bias;

    float2 dx = float2(NEIGHBOURHOOD_RADIUS * invVideoSize.x, 0);
    float2 dy = float2(0, NEIGHBOURHOOD_RADIUS * invVideoSize.y);
    error += abs(prevLuma.SampleLevel(linearClamp, uvA - dx, 0) - currLuma.SampleLevel(linearClamp, uvB - dx, 0));
    error += abs(prevLuma.SampleLevel(linearClamp, uvA + dx, 0) - currLuma.SampleLevel(linearClamp, uvB + dx, 0));
    error += abs(prevLuma.SampleLevel(linearClamp, uvA - dy, 0) - currLuma.SampleLevel(linearClamp, uvB - dy, 0));
    error += abs(prevLuma.SampleLevel(linearClamp, uvA + dy, 0) - currLuma.SampleLevel(linearClamp, uvB + dy, 0));

    if (error < bestError) {
        bestError = error;
        bestColor = (a + b) * 0.5;
    }
}

float4 main(ShaderInput input) : SV_TARGET
{
    float2 pos = input.tex * videoSize;

    float2 grid = pos / blockSize - 0.5;
    int2 g0 = (int2)floor(grid);
    float2 f = grid - g0;
    int2 maxBlock = int2(gridSize) - 1;

    float2 v00 = motionField.Load(int3(clamp(g0, int2(0, 0), maxBlock), 0));
    float2 v10 = motionField.Load(int3(clamp(g0 + int2(1, 0), int2(0, 0), maxBlock), 0));
    float2 v01 = motionField.Load(int3(clamp(g0 + int2(0, 1), int2(0, 0), maxBlock), 0));
    float2 v11 = motionField.Load(int3(clamp(g0 + int2(1, 1), int2(0, 0), maxBlock), 0));
    float2 smooth = lerp(lerp(v00, v10, f.x), lerp(v01, v11, f.x), f.y);

    float bestError = 1e30;
    float4 bestColor = float4(0, 0, 0, 1);

    // Static content (game HUD) must never move, so zero wins whenever it
    // matches as well as anything else. Then the smooth vector wins unless
    // the vector of a single block is clearly better (object edges).
    tryVector(pos, float2(0, 0), 0.0, bestError, bestColor);
    tryVector(pos, smooth, 0.01, bestError, bestColor);
    tryVector(pos, v00, 0.04, bestError, bestColor);
    tryVector(pos, v10, 0.04, bestError, bestColor);
    tryVector(pos, v01, 0.04, bestError, bestColor);
    tryVector(pos, v11, 0.04, bestError, bestColor);

    return float4(bestColor.rgb, 1.0);
}
