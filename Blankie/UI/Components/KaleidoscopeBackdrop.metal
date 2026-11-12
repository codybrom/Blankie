//
//  KaleidoscopeBackdrop.metal
//  Blankie
//
//  Created by Cody Bromley on 11/10/26.
//

#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

// A kaleidoscope's object chamber seen through two fixed mirrors. Loose
// glass tumbles in the chamber as it turns: tumbled chunks, cut gems and rods.
// Each has a thickness, so light bends at its edges, deepens its color where
// it is thick, glints off its surface and casts a shadow on what lies beneath.
//
// The glass is drawn once, as the single wedge the mirrors look into. A second pass
// then folds that wedge around the center, the way the mirrors would.

static float hash21(float2 p) {
  p = fract(p * float2(123.34, 456.21));
  p += dot(p, p + 45.32);
  return fract(p.x * p.y);
}

static float valueNoise(float2 p) {
  float2 i = floor(p);
  float2 f = fract(p);
  f = f * f * (3.0 - 2.0 * f);
  return mix(
    mix(hash21(i), hash21(i + float2(1.0, 0.0)), f.x),
    mix(hash21(i + float2(0.0, 1.0)), hash21(i + float2(1.0, 1.0)), f.x), f.y);
}

// The lamp behind the chamber: an uneven field of light with a few hot patches.
// Glass bends the view of it, which is what makes a piece read as glass.
static float lampLight(float2 x) {
  float broad = valueNoise(x * 5.0) * 0.6 + valueNoise(x * 11.0 + 3.7) * 0.4;
  float hot = pow(valueNoise(x * 23.0 + 9.1), 4.0);
  return 0.30 + 1.25 * smoothstep(0.32, 0.72, broad) + 0.9 * hot;
}

// The uneven surface of worked glass, as a height. Tumbled pieces are pitted and
// hammered, so their slopes scatter light broadly.
static float surfaceHeight(float2 v) {
  return valueNoise(v * 3.1) * 0.6 + valueNoise(v * 7.3 + 5.2) * 0.3 + valueNoise(v * 17.0 + 1.9) * 0.1;
}

struct GlassShape {
  // Signed distance to the outline in piece radii, negative inside.
  float distance;
  // Which way the nearest edge faces.
  float2 outward;
  // How far in from the edge the surface keeps sloping.
  float bevel;
  // Cut flat facets (1) or a tumbled rounded edge (0).
  float faceted;
};

static GlassShape glassShape(float2 v, float kind, float seed) {
  GlassShape shape;
  if (kind < 1.5) {
    // A tumbled chunk has uneven sides and soft corners. A gem is regular and crisp.
    bool gem = kind > 0.5;
    float count = gem ? 6.0 + 2.0 * floor(seed * 2.0) : 5.0 + floor(seed * 3.0);
    float sharp = gem ? 48.0 : 13.0;
    float sum = 0.0;
    float2 lean = float2(0.0);
    for (int k = 0; k < 8; k++) {
      if (float(k) >= count) { break; }
      float jitter = gem ? 0.0 : hash21(float2(float(k), seed * 91.7)) - 0.5;
      float theta = (float(k) + jitter * 0.6) * 2.0 * M_PI_F / count;
      float offset = gem ? 0.86 : 0.66 + 0.30 * hash21(float2(seed * 37.1, float(k)));
      float2 n = float2(cos(theta), sin(theta));
      float weight = exp((dot(v, n) - offset) * sharp);
      sum += weight;
      lean += weight * n;
    }
    shape.distance = log(sum) / sharp;
    shape.outward = normalize(lean);
    shape.bevel = gem ? 0.42 : 0.30;
    shape.faceted = gem ? 1.0 : 0.0;
  } else {
    // A rod of glass cane.
    float2 offset = v - float2(clamp(v.x, -0.80, 0.80), 0.0);
    float reach = length(offset);
    shape.distance = reach - 0.17;
    shape.outward = reach > 1e-4 ? offset / reach : float2(0.0, 1.0);
    shape.bevel = 0.17;
    shape.faceted = 0.0;
  }
  return shape;
}

// One piece of glass at a point, as light and coverage ready to lay over what is
// beneath it. `center` and `radius` are in points, and `span` is how many points
// make one unit of the chamber.
static float4 glassPieceColor(
  float2 position, float2 center, float radius, float rotation, float3 tint, float glow,
  float kind, float seed, float depth, float span
) {
  float2 local = position - center;
  float2 keyLight = normalize(float2(-0.5, -0.62));
  float cf = cos(rotation);
  float sf = sin(rotation);
  float2 v = float2(cf * local.x + sf * local.y, -sf * local.x + cf * local.y) / radius;
  float2 light = float2(cf * keyLight.x + sf * keyLight.y, -sf * keyLight.x + cf * keyLight.y);

  GlassShape shape = glassShape(v, kind, seed);
  float soft = (1.0 + 2.0 * depth * depth) / radius;
  float cover = 1.0 - smoothstep(-soft, soft, shape.distance);
  if (cover <= 0.0) { return float4(0.0); }

  // Thickness rises from the edge to a flat top.
  float t = saturate(-shape.distance / shape.bevel);
  float height;
  float slope;
  if (shape.faceted > 0.5) {
    height = t;
    slope = t < 1.0 ? 0.9 : 0.0;
  } else {
    float u = 1.0 - t;
    height = sqrt(max(1.0 - u * u, 0.0));
    slope = min(u / max(height, 0.08), 6.0) * 0.75;
  }
  // Tumbled chunks are frosted and hammered. Gems and rods are polished.
  float frost = kind < 0.5 ? 1.0 : (kind < 1.5 ? 0.12 : 0.3);
  float2 at = v + seed * 13.0;
  float here = surfaceHeight(at);
  float2 worked = float2(
    surfaceHeight(at + float2(0.03, 0.0)) - here, surfaceHeight(at + float2(0.0, 0.03)) - here)
    / 0.03;
  float2 tilt = shape.outward * slope - worked * (0.04 + 0.08 * frost);
  float3 normal = normalize(float3(tilt, 1.0));

  float3 key = normalize(float3(light * 0.8, 0.62));
  float2 fillLight = float2(-light.x * 0.8 + light.y * 0.4, -light.y * 0.8 - light.x * 0.4);
  float3 fill = normalize(float3(fillLight, 0.7));
  float3 keyHalf = normalize(key + float3(0.0, 0.0, 1.0));
  float3 fillHalf = normalize(fill + float3(0.0, 0.0, 1.0));
  float keyFacing = max(dot(normal, keyHalf), 0.0);
  // Polished glass gives a tight glint. Frosted glass spreads it into a sheen.
  float tight = mix(260.0, 26.0, frost);
  float glint =
    pow(keyFacing, tight) * mix(1.5, 0.30, frost)
    + pow(max(dot(normal, fillHalf), 0.0), tight * 0.5) * mix(0.35, 0.12, frost);
  if (kind > 1.5) { glint *= 0.6; }
  // A fainter glint comes back off the far face, through the glass.
  float3 farNormal = normalize(float3(-tilt, 1.0));
  float farGlint = pow(max(dot(farNormal, keyHalf), 0.0), 50.0) * 0.30 * (1.0 - frost);
  float fresnel = 0.04 + 0.96 * pow(1.0 - normal.z, 5.0);
  // The surface itself scatters lamp light, which gives each piece its volume.
  float diffuse = saturate(dot(normal, key)) * 0.8 + saturate(dot(normal, fill)) * 0.25 + 0.12;

  // Light entering a sloped edge gathers on the side away from the lamp.
  float steep = saturate(length(tilt) * 0.8);
  float caustic =
    steep * smoothstep(0.0, 0.22, t) * (0.35 + 0.65 * saturate(dot(normalize(tilt + 1e-5), -light)));
  // Right at its edge, glass turns light away and reads as a dark line.
  float contour = 1.0 - (1.0 - smoothstep(0.0, 0.16, t)) * 0.6;
  // Glass deepens in color where it is thick.
  float3 through = pow(tint, float3(0.35 + 1.5 * height));
  float mottle = 0.80 + 0.40 * valueNoise(v * 5.0 + seed * 7.0);
  float pitting = 1.0 - frost * 0.09 * valueNoise(v * 46.0 + seed * 3.0);
  float energy = 0.5 + 0.8 * glow;
  // Lamp light comes through the glass, bent by the slope of its surface, and each
  // color bends a little differently, which fringes the edges.
  float2 bend = float2(cf * tilt.x - sf * tilt.y, sf * tilt.x + cf * tilt.y);
  float2 behind = position / span + seed * 3.0;
  float2 shift = bend * radius / span * 1.1;
  float3 lamp = float3(
    lampLight(behind - shift), lampLight(behind - shift * 1.14), lampLight(behind - shift * 1.28));
  // Frost blurs the view of the lamp into an even glow.
  lamp = mix(lamp, float3(0.95), frost * 0.45);
  float3 lit = through * (0.46 * lamp * mottle + 0.40 * caustic) * energy * contour * pitting;
  float3 pale = mix(through, float3(1.0), 0.45);
  lit += pale * diffuse * (0.06 + 0.30 * frost) * energy * pitting;
  lit += farGlint * pale;
  lit += glint * (0.6 + 0.5 * glow) + fresnel * 0.16 * mix(tint, float3(1.0), 0.5);
  lit *= 1.0 - 0.25 * depth;
  // Bright spots roll off softly, the way a lens and film would take them.
  lit = 1.0 - exp(-lit * 1.7);
  lit = mix(float3(dot(lit, float3(0.2125, 0.7154, 0.0721))), lit, 1.12);

  // Glass lets some of what is beneath it show through, darkened.
  float3 pass = through * 0.7 + 0.05;
  float alpha = cover * (1.0 - dot(pass, float3(1.0 / 3.0)) * 0.85);
  return float4(saturate(lit) * cover, alpha);
}

// The soft shadow a piece casts on what lies beneath it, away from the light.
static float glassShadowAlpha(
  float2 position, float2 center, float radius, float rotation, float kind, float seed
) {
  float2 local = position - center;
  float2 keyLight = normalize(float2(-0.5, -0.62));
  float cf = cos(rotation);
  float sf = sin(rotation);
  float2 v = float2(cf * local.x + sf * local.y, -sf * local.x + cf * local.y) / radius;
  float2 light = float2(cf * keyLight.x + sf * keyLight.y, -sf * keyLight.x + cf * keyLight.y);
  float distance = glassShape(v + light * 0.15, kind, seed).distance;
  return (1.0 - smoothstep(-0.06, 0.24, distance)) * 0.36;
}

struct MirrorFold {
  // Where to look in the drawn wedge.
  float2 source;
  // What the mirrors and the tube do to the light on its way out.
  float dim;
};

// Folds a point on screen into the one wedge the mirrors look into. `apex` is where
// that wedge's point sits in the drawing and `axis` is the way it runs.
static MirrorFold mirrorFold(
  float2 position, float2 center, float folds, float2 apex, float2 axis, float span, float wall
) {
  float2 p = position - center;
  float r = length(p);
  // The view straight into the chamber is the wedge pointing down, and each wedge
  // further around has bounced off the mirrors one more time.
  float wedge = M_PI_F / max(folds, 1.0);
  float around = atan2(p.x, p.y) + wedge * 0.5;
  around -= 2.0 * M_PI_F * floor(around / (2.0 * M_PI_F));
  float sector = min(floor(around / wedge), 2.0 * folds - 1.0);
  float bounces = min(sector, 2.0 * folds - 1.0 - sector);
  float a = around - sector * wedge;
  if (fmod(sector, 2.0) > 0.5) { a = wedge - a; }
  float along = r * cos(a - wedge * 0.5);
  float across = r * sin(a - wedge * 0.5);

  MirrorFold fold;
  fold.source = apex + axis * along + float2(-axis.y, axis.x) * across;
  // Each bounce loses a little light, and the mirror joins show as faint lines.
  fold.dim = pow(0.97, bounces);
  fold.dim *= 1.0 - (1.0 - smoothstep(0.0, 1.5, min(a, wedge - a) * r)) * 0.10;
  // Past the chamber's wall there is only the dark of the tube.
  float fromMiddle = length(float2(across, along));
  fold.dim *= 1.0 - smoothstep(wall * span - 8.0, wall * span + 14.0, fromMiddle) * 0.9;
  return fold;
}

// The faint glow of the lamp where no glass covers it.
static float3 chamberGlow(float2 position, float2 center, float span, float3 wash) {
  return wash * (0.035 + 0.11 * (1.0 - smoothstep(0.0, 1.0, length(position - center) / span)));
}

// MARK: SwiftUI entry

// `presence` fades a piece toward clear glass that barely shows.
[[ stitchable ]] half4 glassPiece(
  float2 position, float2 center, float radius, float rotation, float3 tint, float glow,
  float kind, float seed, float depth, float span, float presence
) {
  return half4(
    glassPieceColor(position, center, radius, rotation, tint, glow, kind, seed, depth, span)
    * presence);
}

[[ stitchable ]] half4 glassShadow(
  float2 position, float2 center, float radius, float rotation, float kind, float seed,
  float presence
) {
  return half4(
    0.0, 0.0, 0.0, glassShadowAlpha(position, center, radius, rotation, kind, seed) * presence);
}

[[ stitchable ]] half4 kaleidoscopeFold(
  float2 position, SwiftUI::Layer layer, float2 center, float folds, float2 apex, float2 axis,
  float span, float wall, float3 wash
) {
  MirrorFold fold = mirrorFold(position, center, folds, apex, axis, span, wall);
  half4 glass = layer.sample(fold.source);
  float3 color = float3(glass.rgb) + chamberGlow(position, center, span, wash) * (1.0 - glass.a);
  color *= fold.dim;
  color += (hash21(position) - 0.5) * 0.012;
  return half4(half3(saturate(color)), 1.0);
}
