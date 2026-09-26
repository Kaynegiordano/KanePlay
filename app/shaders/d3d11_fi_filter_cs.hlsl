// Frame interpolation: cleans up the final motion field.
//
// A block whose vector agrees with none of its 8 neighbours is almost always a
// wrong match (noise, repeated textures). It gets the vector median of its
// neighbourhood instead. Blocks that agree with at least one neighbour are
// kept, so the edges of moving objects are preserved.

Texture2D<float4> inputField : register(t0);
RWTexture2D<float4> outputField : register(u0);

cbuffer FILTER_CONST_BUF : register(b0)
{
    uint2 gridSize;
    float agreement;    // Full resolution pixels
    float padding;
};

[numthreads(8, 8, 1)]
void main(uint3 id : SV_DispatchThreadID)
{
    if (any(id.xy >= gridSize)) {
        return;
    }

    int2 maxBlock = int2(gridSize) - 1;
    float4 samples[9];
    int n = 0;

    [unroll]
    for (int y = -1; y <= 1; y++) {
        [unroll]
        for (int x = -1; x <= 1; x++) {
            samples[n++] = inputField[clamp(int2(id.xy) + int2(x, y), int2(0, 0), maxBlock)];
        }
    }

    float4 center = samples[4];

    bool isolated = true;
    [unroll]
    for (int i = 0; i < 9; i++) {
        float2 d = abs(samples[i].xy - center.xy);
        if (i != 4 && d.x + d.y <= agreement) {
            isolated = false;
        }
    }

    if (!isolated) {
        outputField[id.xy] = center;
        return;
    }

    // The vector closest to all the others
    int best = 4;
    float bestDistance = 1e30;
    float averageCost = 0;

    [unroll]
    for (int j = 0; j < 9; j++) {
        float distance = 0;
        [unroll]
        for (int k = 0; k < 9; k++) {
            float2 d = abs(samples[j].xy - samples[k].xy);
            distance += d.x + d.y;
        }
        if (distance < bestDistance) {
            bestDistance = distance;
            best = j;
        }
        averageCost += samples[j].z;
    }

    // The matching cost of the replacement vector is unknown here, so take the
    // neighbourhood's, and never less than the cost of the rejected match
    outputField[id.xy] = float4(samples[best].xy, max(averageCost / 9, center.z), 0);
}
