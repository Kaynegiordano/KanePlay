// Frame interpolation: symmetric block motion estimation for one pyramid level.
//
// Each block of the frame to be interpolated (halfway between the previous and
// the current frame) looks for the displacement d that best matches
// prev(p - d) with curr(p + d). The motion between the two frames is 2d.
//
// The coarsest level runs an exhaustive search. The finer levels only test a
// few predictors (the coarser result for this block and its neighbours, the
// result of the previous frame and zero) and refine the best one.
//
// Vectors are stored in full resolution pixels, one per block, on a grid that
// is identical for all levels. The third channel holds the matching cost (mean
// luma difference per sample) that tells how much the vector can be trusted.

Texture2D<float> prevLuma : register(t0);
Texture2D<float> currLuma : register(t1);
Texture2D<float4> coarseField : register(t2);
Texture2D<float4> temporalField : register(t3);
RWTexture2D<float4> outputField : register(u0);
SamplerState linearClamp : register(s0);

cbuffer MOTION_CONST_BUF : register(b0)
{
    float2 invLevelSize;
    float levelScale;       // Level pixels per full resolution pixel
    float blockSize;        // Block size in level pixels

    float sampleSpacing;    // Distance between matching samples in level pixels
    int searchRadius;       // > 0 for the exhaustive search of the coarsest level
    int refineHalf;         // Also refine by half a level pixel
    int hasTemporal;        // temporalField holds the previous frame's motion

    uint2 gridSize;
    float lambda;           // Penalty per level pixel away from the prediction
    float padding;
};

#define THREADS 64

groupshared float gsCost[THREADS];
groupshared float2 gsVector[THREADS];

// Where the image doesn't tell (flat areas), keep the motion of the coarser
// level, or no motion at all on the coarsest one. This keeps the motion field
// coherent instead of letting it pick random vectors.
static float2 g_Prediction;

float blockCost(float2 center, float2 d)
{
    float sad = 0;

    [loop]
    for (int y = 0; y < 8; y++) {
        [unroll]
        for (int x = 0; x < 8; x++) {
            float2 offset = (float2(x, y) - 3.5) * sampleSpacing;
            float a = prevLuma.SampleLevel(linearClamp, (center - d + offset) * invLevelSize, 0);
            float b = currLuma.SampleLevel(linearClamp, (center + d + offset) * invLevelSize, 0);
            sad += abs(a - b);
        }
    }

    float2 deviation = abs(d - g_Prediction);
    return sad + lambda * (deviation.x + deviation.y);
}

void consider(float2 center, float2 d, inout float bestCost, inout float2 bestVector)
{
    float cost = blockCost(center, d);
    if (cost < bestCost) {
        bestCost = cost;
        bestVector = d;
    }
}

// Must be reached by all threads of the group
void reduceBest(uint tid, inout float bestCost, inout float2 bestVector)
{
    gsCost[tid] = bestCost;
    gsVector[tid] = bestVector;
    GroupMemoryBarrierWithGroupSync();

    [unroll]
    for (uint stride = THREADS / 2; stride > 0; stride /= 2) {
        if (tid < stride && gsCost[tid + stride] < gsCost[tid]) {
            gsCost[tid] = gsCost[tid + stride];
            gsVector[tid] = gsVector[tid + stride];
        }
        GroupMemoryBarrierWithGroupSync();
    }

    bestCost = gsCost[0];
    bestVector = gsVector[0];
    GroupMemoryBarrierWithGroupSync();
}

void refine(uint tid, float2 center, float step, inout float bestCost, inout float2 bestVector)
{
    float cost = 1e30;
    float2 d = bestVector;

    if (tid < 9) {
        if (tid == 4) {
            // The center of the pattern is the current best
            cost = bestCost;
        }
        else {
            d = bestVector + (float2(tid % 3, tid / 3) - 1.0) * step;
            cost = blockCost(center, d);
        }
    }

    reduceBest(tid, cost, d);
    bestCost = cost;
    bestVector = d;
}

[numthreads(THREADS, 1, 1)]
void main(uint3 groupId : SV_GroupID, uint tid : SV_GroupIndex)
{
    uint2 block = groupId.xy;
    float2 center = (float2(block) + 0.5) * blockSize;

    float bestCost = 1e30;
    float2 bestVector = float2(0, 0);

    g_Prediction = searchRadius > 0 ? float2(0, 0) : coarseField[block].xy * levelScale;

    if (searchRadius > 0) {
        uint side = (uint)searchRadius * 2 + 1;
        uint count = side * side;

        for (uint i = tid; i < count; i += THREADS) {
            consider(center, float2(i % side, i / side) - searchRadius, bestCost, bestVector);
        }

        // Fast pans can go beyond the search window, the previous frame knows about them
        if (hasTemporal && tid == THREADS - 1) {
            consider(center, temporalField[block].xy * levelScale, bestCost, bestVector);
        }
    }
    else {
        int2 maxBlock = int2(gridSize) - 1;

        if (tid == 0) {
            consider(center, float2(0, 0), bestCost, bestVector);
        }
        else if (tid <= 5) {
            static const int2 neighbours[5] = { int2(0, 0), int2(-1, 0), int2(1, 0), int2(0, -1), int2(0, 1) };
            int2 source = clamp(int2(block) + neighbours[tid - 1], int2(0, 0), maxBlock);
            consider(center, coarseField[source].xy * levelScale, bestCost, bestVector);
        }
        else if (tid == 6 && hasTemporal) {
            consider(center, temporalField[block].xy * levelScale, bestCost, bestVector);
        }
    }

    reduceBest(tid, bestCost, bestVector);

    if (searchRadius <= 0) {
        refine(tid, center, 1.0, bestCost, bestVector);
        if (refineHalf) {
            refine(tid, center, 0.5, bestCost, bestVector);
        }
    }

    if (tid == 0) {
        outputField[block] = float4(bestVector / levelScale, bestCost / 64.0, 0);
    }
}
