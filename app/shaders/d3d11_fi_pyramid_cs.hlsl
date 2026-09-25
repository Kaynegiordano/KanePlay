// Frame interpolation: builds one level of the luma pyramid used for motion
// estimation. Each output texel is the average of a 2x2 block of the input,
// taken with a single bilinear sample. The first level is built from the
// RGB frame, the following ones from the previous luma level.

Texture2D<float4> inputTexture : register(t0);
RWTexture2D<float> outputLuma : register(u0);
SamplerState linearClamp : register(s0);

cbuffer PYRAMID_CONST_BUF : register(b0)
{
    float2 invInputSize;
    uint2 outputSize;
    uint fromRgb;
    uint3 padding;
};

[numthreads(8, 8, 1)]
void main(uint3 id : SV_DispatchThreadID)
{
    if (any(id.xy >= outputSize)) {
        return;
    }

    // The corner shared by the 2x2 input texels
    float2 uv = (float2(id.xy) * 2.0 + 1.0) * invInputSize;
    float4 value = inputTexture.SampleLevel(linearClamp, uv, 0);

    outputLuma[id.xy] = fromRgb ? dot(value.rgb, float3(0.299, 0.587, 0.114)) : value.r;
}
