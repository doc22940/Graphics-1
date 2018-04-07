#include "Decal.hlsl"

DECLARE_DBUFFER_TEXTURE(_DBufferTexture);

DecalData FetchDecal(uint start, uint i)
{
#ifdef LIGHTLOOP_TILE_PASS
    int j = FetchIndex(start, i);
#else
    int j = start + i;
#endif
    return _DecalDatas[j];
}

// Caution: We can't compute LOD inside a dynamic loop. The gradient are not accessible.
// we need to find a way to calculate mips. For now just fetch first mip of the decals
void ApplyBlendNormal(inout float4 dst, inout int matMask, float2 texCoords, int mapMask, float3x3 decalToWorld, float blend, float lod)
{
	float4 src;
	src.xyz = mul(decalToWorld, UnpackNormalmapRGorAG(SAMPLE_TEXTURE2D_LOD(_DecalAtlas2D, _trilinear_clamp_sampler_DecalAtlas2D, texCoords, lod))) * 0.5f + 0.5f;
	src.w = blend;
	dst.xyz = src.xyz * src.w + dst.xyz * (1.0f - src.w);
	dst.w = dst.w * (1.0f - src.w);
	matMask |= mapMask;
}

void ApplyBlendDiffuse(inout float4 dst, inout int matMask, float2 texCoords, int mapMask, inout float blend, float lod)
{
	float4 src = SAMPLE_TEXTURE2D_LOD(_DecalAtlas2D, _trilinear_clamp_sampler_DecalAtlas2D, texCoords, lod);
	src.w *= blend;
	blend = src.w;	// diffuse texture alpha affects all other channels
	dst.xyz = src.xyz * src.w + dst.xyz * (1.0f - src.w);
	dst.w = dst.w * (1.0f - src.w);
	matMask |= mapMask;
}

void ApplyBlendMask(inout float4 dst, inout int matMask, float2 texCoords, int mapMask, float blend, float lod)
{
	float4 src = SAMPLE_TEXTURE2D_LOD(_DecalAtlas2D, _trilinear_clamp_sampler_DecalAtlas2D, texCoords, lod);
	src.z = src.w;
	src.w = blend;
	dst.xyz = src.xyz * src.w + dst.xyz * (1.0f - src.w);
	dst.w = dst.w * (1.0f - src.w);
	matMask |= mapMask;
}

float ComputeTextureLOD(float2 uv, float2 uvdx, float2 uvdy, float2 scale)
{
	float2 ddx_ = scale * (uvdx - uv);
	float2 ddy_ = scale * (uvdy - uv);
	float d = max(dot(ddx_, ddx_), dot(ddy_, ddy_));

	return max(0.5 * log2(d), 0.0);
}

void AddDecalContribution(PositionInputs posInput, inout SurfaceData surfaceData, inout float alpha)
{
	if(_EnableDBuffer)
	{
		DecalSurfaceData decalSurfaceData;
		int mask = 0;
		// the code in the macros, gets moved inside the conditionals by the compiler
		FETCH_DBUFFER(DBuffer, _DBufferTexture, posInput.positionSS);

#ifdef _SURFACE_TYPE_TRANSPARENT	// forward transparent using clustered decals
        uint decalCount, decalStart;
		DBuffer0 = float4(0.0f, 0.0f, 0.0f, 1.0f);
		DBuffer1 = float4(0.5f, 0.5f, 0.5f, 1.0f);
		DBuffer2 = float4(0.0f, 0.0f, 0.0f, 1.0f);

    #ifdef LIGHTLOOP_TILE_PASS
        GetCountAndStart(posInput, LIGHTCATEGORY_DECAL, decalStart, decalCount);
    #else
        decalCount = _DecalCount;
        decalStart = 0;
    #endif

		float3 positionWS = GetAbsolutePositionWS(posInput.positionWS);

		// get world space position for adjacent pixels to be used later in mipmap lod calculation
		float3 positionWSDX = positionWS + ddx(positionWS);
		float3 positionWSDY = positionWS + ddy(positionWS);

        for (uint i = 0; i < decalCount; i++)
        {
            DecalData decalData = FetchDecal(decalStart, i);

			// need to compute the mipmap LOD manually because we are sampling inside a loop
			float3 positionDS = mul(decalData.worldToDecal, float4(positionWS, 1.0)).xyz;
			float3 positionDSDX = mul(decalData.worldToDecal, float4(positionWSDX, 1.0)).xyz;
			float3 positionDSDY = mul(decalData.worldToDecal, float4(positionWSDY, 1.0)).xyz;

			positionDS = positionDS * float3(1.0, -1.0, 1.0) + float3(0.5, 0.0f, 0.5);
			positionDSDX = positionDSDX * float3(1.0, -1.0, 1.0) + float3(0.5, 0.0f, 0.5);
			positionDSDY = positionDSDY * float3(1.0, -1.0, 1.0) + float3(0.5, 0.0f, 0.5);
			
			float2 sampleDiffuse = positionDS.xz * decalData.diffuseScaleBias.xy + decalData.diffuseScaleBias.zw;
			float2 sampleDiffuseDX = positionDSDX.xz * decalData.diffuseScaleBias.xy + decalData.diffuseScaleBias.zw;
			float2 sampleDiffuseDY = positionDSDY.xz * decalData.diffuseScaleBias.xy + decalData.diffuseScaleBias.zw;

			float2 sampleNormal = positionDS.xz * decalData.normalScaleBias.xy + decalData.normalScaleBias.zw;
			float2 sampleNormalDX = positionDSDX.xz * decalData.normalScaleBias.xy + decalData.normalScaleBias.zw;
			float2 sampleNormalDY = positionDSDY.xz * decalData.normalScaleBias.xy + decalData.normalScaleBias.zw;

			float2 sampleMask = positionDS.xz * decalData.maskScaleBias.xy + decalData.maskScaleBias.zw;
			float2 sampleMaskDX = positionDSDX.xz * decalData.maskScaleBias.xy + decalData.maskScaleBias.zw;
			float2 sampleMaskDY = positionDSDY.xz * decalData.maskScaleBias.xy + decalData.maskScaleBias.zw;

			float lodDiffuse = ComputeTextureLOD(sampleDiffuse, sampleDiffuseDX, sampleDiffuseDY, _DecalAtlasResolution);
			float lodNormal = ComputeTextureLOD(sampleNormal, sampleNormalDX, sampleNormalDY, _DecalAtlasResolution);
			float lodMask = ComputeTextureLOD(sampleMask, sampleMaskDX, sampleMaskDY, _DecalAtlasResolution);

			float decalBlend = decalData.normalToWorld[0][3];

			if ((all(positionDS.xyz > 0.0f) && all(1.0f - positionDS.xyz > 0.0f))) 
			{ 
				if((decalData.diffuseScaleBias.x > 0) && (decalData.diffuseScaleBias.y > 0))
				{
					ApplyBlendDiffuse(DBuffer0, mask, sampleDiffuse, DBUFFERHTILEBIT_DIFFUSE, decalBlend, lodDiffuse);
					alpha = alpha < decalBlend ? decalBlend : alpha;	// use decal alpha if it is higher than transparent alpha
				}

				if ((decalData.normalScaleBias.x > 0) && (decalData.normalScaleBias.y > 0))
				{
					ApplyBlendNormal(DBuffer1, mask, sampleNormal, DBUFFERHTILEBIT_NORMAL, (float3x3)decalData.normalToWorld, decalBlend, lodNormal);
				}

				if ((decalData.maskScaleBias.x > 0) && (decalData.maskScaleBias.y > 0))
				{
					ApplyBlendMask(DBuffer2, mask, sampleMask, DBUFFERHTILEBIT_MASK, decalBlend, lodMask);
				}
			}
		}
#else
		mask = UnpackByte(LOAD_TEXTURE2D(_DecalHTileTexture, posInput.positionSS / 8).r);
#endif
		DECODE_FROM_DBUFFER(DBuffer, decalSurfaceData);
		// using alpha compositing https://developer.nvidia.com/gpugems/GPUGems3/gpugems3_ch23.html
		if(mask & DBUFFERHTILEBIT_DIFFUSE)
		{
			surfaceData.baseColor.xyz = surfaceData.baseColor.xyz * decalSurfaceData.baseColor.w + decalSurfaceData.baseColor.xyz;
		}

		if(mask & DBUFFERHTILEBIT_NORMAL)
		{
			surfaceData.normalWS.xyz = normalize(surfaceData.normalWS.xyz * decalSurfaceData.normalWS.w + decalSurfaceData.normalWS.xyz);
		}
		if(mask & DBUFFERHTILEBIT_MASK)
		{
			surfaceData.metallic = surfaceData.metallic * decalSurfaceData.mask.w + decalSurfaceData.mask.x;
			surfaceData.ambientOcclusion = surfaceData.ambientOcclusion * decalSurfaceData.mask.w + decalSurfaceData.mask.y;
			surfaceData.perceptualSmoothness = surfaceData.perceptualSmoothness * decalSurfaceData.mask.w + decalSurfaceData.mask.z;
		}
	}
}


