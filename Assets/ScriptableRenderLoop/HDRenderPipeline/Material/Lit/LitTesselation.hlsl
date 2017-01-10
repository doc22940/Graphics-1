/*
float _Tess;
float _TessNear;
float _TessFar;
float _UseDisplacementfalloff;
float _DisplacementfalloffNear;
float _DisplacementfalloffFar;
*/

float4 TesselationEdge(Attributes input0, Attributes input1, Attributes input2)
{
 //   float minDist = 0; // _TessNear;
//    float maxDist = 15; // _TessFar;

 //   return UnityDistanceBasedTess(input0.positionOS, input1.positionOS, input2.positionOS, minDist, maxDist, 0.5 /* _Tess */, unity_ObjectToWorld, _WorldSpaceCameraPos);

    return float4(_TesselationFactor, _TesselationFactor, _TesselationFactor, _TesselationFactor);
}

void Displacement(inout Attributes v)
{
    /*
    float LengthLerp = length(ObjSpaceViewDir(v.vertex));
    LengthLerp -= _DisplacementfalloffNear;
    LengthLerp /= _DisplacementfalloffFar - _DisplacementfalloffNear;
    LengthLerp = 1 - (saturate(LengthLerp));

    float d = ((tex2Dlod(_DispTex, float4(v.texcoord.xy * _Tiling, 0, 0)).r) - _DisplacementCenter) * (_Displacement * LengthLerp);
    d /= max(0.0001, _Tiling);
    */

#if _HEIGHTMAP
    float height = SAMPLE_LAYER_TEXTURE2D(ADD_IDX(_HeightMap), ADD_ZERO_IDX(sampler_HeightMap), ADD_IDX(layerTexCoord.base)).r * ADD_IDX(_HeightScale) + ADD_IDX(_HeightBias);
#else
    float height = 0.0;
#endif

    v.positionOS.xyz += height * v.normalOS;
}
