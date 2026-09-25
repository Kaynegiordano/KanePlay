// Frame interpolation: draws a decoded frame that was converted to RGB

Texture2D<float4> frameTexture : register(t0);
SamplerState linearClamp : register(s0);

struct ShaderInput
{
    float4 pos : SV_POSITION;
    float2 tex : TEXCOORD0;
};

float4 main(ShaderInput input) : SV_TARGET
{
    return float4(frameTexture.Sample(linearClamp, input.tex).rgb, 1.0);
}
