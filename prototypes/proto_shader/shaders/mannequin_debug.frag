// GENERATED from mannequin.frag by tool/make_debug_shader.py - do not edit
#version 460 core
// SDF raymarched artist's mannequin ("Gliederpuppe").
// All per-frame skeleton data comes from Dart as individual vec4 uniforms
// (see MannequinScene.writeUniforms in lib/mannequin/mannequin_scene.dart -- ORDER MATTERS).
#include <flutter/runtime_effect.glsl>
precision highp float;

uniform vec2 uSize;     // target size (local units)
uniform vec4 uCamPos;   // xyz camera position, w focal length (1/tan(fov/2))
uniform vec4 uCamR;     // xyz right, w pixel size (NDC units / focal) for AA
uniform vec4 uCamU;     // xyz up, w background luminance (0 dark .. 1 light)
uniform vec4 uCamF;     // xyz forward
uniform vec4 uBg;       // rgb background (sRGB)
uniform vec4 uKey;      // xyz dir to key light, w intensity
uniform vec4 uFill;     // xyz dir to fill light, w intensity
uniform vec4 uRim;      // xyz dir to rim light, w intensity
uniform vec4 uBMin;     // figure AABB min
uniform vec4 uBMax;     // figure AABB max
uniform vec4 uHip;
uniform vec4 uT;        // torso up
uniform vec4 uF;        // torso forward (chest)
uniform vec4 uL;        // torso lateral (side 1)
uniform vec4 uNeck;
uniform vec4 uHead;
uniform vec4 uHU;
uniform vec4 uHF;
uniform vec4 uHL;
uniform vec4 uSh1;
uniform vec4 uEl1;
uniform vec4 uWr1;
uniform vec4 uSh2;
uniform vec4 uEl2;
uniform vec4 uWr2;
uniform vec4 uHp1;
uniform vec4 uKn1;
uniform vec4 uAn1;
uniform vec4 uHp2;
uniform vec4 uKn2;
uniform vec4 uAn2;
uniform vec4 uHa1C;     // hand 1 centre
uniform vec4 uHa1X;     // axis + half extent in w
uniform vec4 uHa1Y;
uniform vec4 uHa1Z;
uniform vec4 uHa2C;
uniform vec4 uHa2X;
uniform vec4 uHa2Y;
uniform vec4 uHa2Z;
uniform vec4 uFt1C;
uniform vec4 uFt1X;
uniform vec4 uFt1Y;
uniform vec4 uFt1Z;
uniform vec4 uFt2C;
uniform vec4 uFt2X;
uniform vec4 uFt2Y;
uniform vec4 uFt2Z;
uniform vec4 uBTorso;   // bounding spheres (xyz, r)
uniform vec4 uBHead;
uniform vec4 uBArm1;
uniform vec4 uBArm2;
uniform vec4 uBLeg1;
uniform vec4 uBLeg2;
uniform vec4 uFloor;    // y, enabled, stage centre x, stage centre z
uniform vec4 uBar;      // x, y, half length, enabled
uniform vec4 uPbar;     // y, x1, x2, enabled
uniform vec4 uPbar2;    // z offset, floor y, -, -
uniform vec4 uPole;     // x, z, floor y, enabled
uniform vec4 uWall;     // x, floor y, side (normal.x), enabled
uniform vec4 uBox0;     // min xyz, enabled
uniform vec4 uBox1;     // max xyz
uniform vec4 uQual;     // max march steps, AO taps, interior edge AA (0/1), floor stage radius

out vec4 fragColor;

// ------------------------------------------------------------------ SDF utils
float smin(float a, float b, float k) {
  float h = max(k - abs(a - b), 0.0) / k;
  return min(a, b) - h * h * k * 0.25;
}

float smax(float a, float b, float k) {
  return -smin(-a, -b, k);
}

float sdEll(vec3 p, vec3 r) {
  float k0 = length(p / r);
  float k1 = length(p / (r * r));
  return k0 * (k0 - 1.0) / k1;
}

float sdCap(vec3 p, vec3 a, vec3 b, float r) {
  vec3 pa = p - a;
  vec3 ba = b - a;
  float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
  return length(pa - ba * h) - r;
}

// Tapered capsule with a muscle bulge (skew 0: peak mid, 1: peak at 1/3).
float sdLimb(vec3 p, vec3 a, vec3 b, float ra, float rb, float bulge, float skew) {
  vec3 pa = p - a;
  vec3 ba = b - a;
  float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
  float g = 1.0 - h;
  float prof = mix(4.0 * h * g, 6.75 * h * g * g, skew);
  return length(pa - ba * h) - (mix(ra, rb, h) + bulge * prof);
}

float sdRBox(vec3 q, vec3 b, float r) {
  vec3 d = abs(q) - b + r;
  return length(max(d, 0.0)) + min(max(d.x, max(d.y, d.z)), 0.0) - r;
}

// Hand in its box frame. c.w = side (+-1): open mitten, x = fingers (wrist
// end -x.w .. tip +x.w), y = width, z = back of the hand.
// c.w = side * 2: fist closed around a grip cylinder whose axis is the frame
// y axis through c; x.w = wrist -> axis distance, y.w = half hand width along
// the axis, z.w = cylinder radius. The fingers form a cuff around the
// cylinder, the back of the hand bridges to the wrist, knuckles on the far side.
float handD(vec3 p, vec4 c, vec4 x, vec4 y, vec4 z) {
  vec3 w = p - c.xyz;
  vec3 q = vec3(dot(w, x.xyz), dot(w, y.xyz), dot(w, z.xyz));
  float ex = x.w;
  float ey = y.w;
  float ez = z.w;
  if (abs(c.w) > 1.5) {
    float rc = ez;
    float rho = length(q.xz);
    // finger cuff: rounded annulus rc-0.1 .. rc+0.95, |y| < ey
    vec2 rw = vec2(abs(rho - rc - 0.42) - 0.12, abs(q.y) - ey + 0.4);
    float cuff = min(max(rw.x, rw.y), 0.0) + length(max(rw, 0.0)) - 0.4;
    // finger grooves (4 fingers) on the outside of the cuff
    cuff += 0.07 * (1.0 - abs(sin(q.y * 3.1416 / (ey * 0.5)))) * smoothstep(rc + 0.2, rc + 0.9, rho);
    // back of the hand: from the wrist to the cuff
    float back = sdRBox(q - vec3(-rc - 0.45, 0.0, 0.0), vec3(1.05, ey * 0.86, rc * 0.62 + 0.4), 0.62);
    float d = smin(cuff, back, 0.8);
    // knuckle ridge where the fingers turn over the top of the grip
    float kn = sdCap(q, vec3(-0.25, -0.72 * ey, rc + 0.55), vec3(-0.25, 0.72 * ey, rc + 0.55), 0.62);
    d = smin(d, kn, 0.6);
    // thumb along the palm side
    float side = sign(c.w);
    float th = sdCap(q, vec3(-rc - 0.9, side * 0.85 * ey, -rc * 0.35), vec3(-0.2, side * 1.0 * ey, -rc - 0.55), 0.5);
    return smin(d, th, 0.5);
  }
  float side = sign(c.w);
  // palm: rounded slab at the wrist end (a little wider than the wrist)
  float palm = sdEll(q - vec3(-0.32 * ex, 0.0, 0.0), vec3(0.64 * ex, 0.97 * ey, ez));
  // finger block, tapering in width and thickness toward the tip
  float u = clamp(q.x / ex, 0.0, 1.0);
  vec3 fb = vec3(0.5 * ex, 0.86 * ey * (1.0 - 0.14 * u), 0.72 * ez * (1.0 - 0.25 * u));
  float fing = sdRBox(q - vec3(0.46 * ex, 0.0, -0.08 * ez), fb, min(fb.y, fb.z) * 0.92);
  float d = smin(palm, fing, 0.9);
  // thumb along the index side, toward the palm, lying close to the hand
  vec3 ta = vec3(-0.5 * ex, side * 0.6 * ey, -0.25 * ez);
  vec3 tb = vec3(0.04 * ex, side * 0.98 * ey, -0.5 * ez);
  return smin(d, sdCap(q, ta, tb, 0.32 * ey), 0.7);
}

// Foot in its box frame: x = heel .. toes, y = width, z = sole (-z.w) .. up.
float footD(vec3 p, vec4 c, vec4 x, vec4 y, vec4 z) {
  vec3 w = p - c.xyz;
  vec3 q = vec3(dot(w, x.xyz), dot(w, y.xyz), dot(w, z.xyz));
  float ex = x.w;
  float ey = y.w;
  float ez = z.w;
  float heel = sdEll(q - vec3(-0.64 * ex, 0.0, -0.2 * ez), vec3(0.34 * ex, 0.7 * ey, 0.8 * ez));
  float mid = sdEll(q - vec3(-0.12 * ex, 0.0, -0.12 * ez), vec3(0.6 * ex, 0.84 * ey, 0.86 * ez));
  float toes = sdEll(q - vec3(0.5 * ex, 0.0, -0.46 * ez), vec3(0.5 * ex, ey, 0.54 * ez));
  float d = smin(heel, mid, 1.0);
  d = smin(d, toes, 1.1);
  return smax(d, -(q.z + ez), 0.35);  // flattened, rounded sole
}

// ------------------------------------------------------------- body groups
// Hip ball: inside the pelvis socket (slightly inward, forward and down).
vec3 hipBall(vec3 hp, float side) {
  return hp - uL.xyz * (side * 0.3) + uF.xyz * 0.35 - uT.xyz * 0.35;
}

// Torso group in its own frame (x = lateral, y = up the spine: hip joint
// centre 0 .. neck 24, z = chest forward) plus the neck and BOTH whole
// thighs: the thighs blend into the pelvis with a blend radius that tapers
// to zero along the thigh, so the pelvis flows into the legs without a
// shelf. Returns (distance, group): 0 torso / neck, 6 / 7 thigh 1 / 2.
vec2 torsoD(vec3 p, float thr) {
  vec3 w = p - uHip.xyz;
  // core (pelvis .. neck) only when near its own bounding sphere. Parts are
  // culled only beyond thr + the largest thigh blend radius (1.52): a bound
  // inside the blend range would change the smin result, so march and
  // normal taps (different thr) would see different surfaces.
  float d = length(w - uT.xyz * 13.0) - 19.5;
  if (d <= thr + 1.6) {
    vec3 q = vec3(dot(w, uL.xyz), dot(w, uT.xyz), dot(w, uF.xyz));
    vec3 qs = vec3(abs(q.x), q.y, q.z);
    // ribcage: broad on top, flatter chest plate, narrowing to the waist
    float rib = sdEll(q - vec3(0.0, 16.6, -0.1), vec3(6.5, 7.2, 3.85));
    float pec = sdEll(qs - vec3(2.9, 18.6, 1.2), vec3(3.5, 2.7, 2.65));
    float lat = sdCap(qs, vec3(6.2, 19.4, -0.9), vec3(4.2, 11.5, -0.7), 2.1);
    float yoke = sdCap(qs, vec3(0.0, 22.6, -0.7), vec3(6.6, 23.4, -0.45), 2.55);
    float trap = sdCap(qs, vec3(1.7, 25.0, -1.0), vec3(5.4, 24.2, -0.7), 1.55);
    float scap = sdEll(qs - vec3(3.2, 19.3, -2.75), vec3(2.3, 2.9, 0.8));
    float abd = sdEll(q - vec3(0.0, 8.8, 0.05), vec3(5.6, 5.6, 3.45));
    float obl = sdEll(qs - vec3(3.7, 7.6, 0.4), vec3(2.0, 3.9, 2.3));
    float pel = sdEll(q - vec3(0.0, 1.8, -0.25), vec3(5.8, 4.4, 3.75));
    float glu = sdEll(qs - vec3(2.7, 0.2, -1.5), vec3(2.9, 3.4, 2.8));
    d = smin(rib, yoke, 3.0);
    d = smin(d, trap, 1.6);
    d = smin(d, pec, 1.6);
    d = smin(d, lat, 2.4);
    d = smin(d, scap, 1.2);
    d = smin(d, abd, 2.2);
    d = smin(d, obl, 1.8);
    d = smin(d, pel, 2.0);
    d = smin(d, glu, 1.5);
    // spine groove (smooth subtraction)
    float sp = min(sdCap(q, vec3(0.0, 6.0, -3.55), vec3(0.0, 15.5, -4.25), 0.6),
                   sdCap(q, vec3(0.0, 15.5, -4.25), vec3(0.0, 21.5, -3.85), 0.6));
    d = smax(d, -sp, 0.8);
    // neck, blended into the trapezius / chest (no crease at the collar)
    vec3 n0 = uNeck.xyz - uT.xyz * 2.2;
    vec3 n1 = uHead.xyz - uHU.xyz * 1.5;
    d = smin(d, sdLimb(p, n0, n1, 2.6, 2.2, 0.0, 0.0), 1.2);
  }
  vec2 r = vec2(d, 0.0);
  float best = d;
  for (int i = 0; i < 2; i++) {
    bool s1 = i == 0;
    float side = s1 ? 1.0 : -1.0;
    vec3 hp = s1 ? uHp1.xyz : uHp2.xyz;
    vec3 kn = s1 ? uKn1.xyz : uKn2.xyz;
    // thigh root slightly inward (femur angles toward the knee)
    vec3 hr = hp - uL.xyz * (side * 0.45);
    vec3 ba = kn - hr;
    float h = clamp(dot(p - hr, ba) / dot(ba, ba), 0.0, 1.0);
    float t = length(p - hr - ba * h) - 3.4;
    if (t <= thr + 1.6) {
      t = sdLimb(p, hr, mix(hr, kn, 0.93), 2.55, 1.7, 0.55, 0.45);
      t = smin(t, length(p - hipBall(hp, side)) - 2.35, 0.5);
    }
    float k = 1.5 * (1.0 - smoothstep(0.1, 0.38, h)) + 0.02;
    float m = smin(r.x, t, k);
    if (t < best) { best = t; r.y = 6.0 + float(i); }
    r.x = m;
  }
  return r;
}

float headD(vec3 p) {
  vec3 w = p - uHead.xyz;
  vec3 q = vec3(dot(w, uHL.xyz), dot(w, uHU.xyz), dot(w, uHF.xyz));
  vec3 qs = vec3(abs(q.x), q.y, q.z);
  float cran = sdEll(q - vec3(0.0, 0.6, -0.35), vec3(3.4, 3.9, 3.75));
  float jaw = sdEll(q - vec3(0.0, -1.75, 0.7), vec3(2.4, 2.6, 2.75));
  float d = smin(cran, jaw, 2.2);
  // brow ridge, eye sockets, nose and chin so the facing direction reads
  d = smin(d, sdEll(q - vec3(0.0, 0.95, 2.85), vec3(2.55, 0.72, 0.75)), 0.8);
  d = smax(d, -sdEll(qs - vec3(1.15, 0.2, 3.62), vec3(0.85, 0.5, 0.5)), 0.6);
  d = smin(d, sdEll(q - vec3(0.0, -0.55, 3.3), vec3(0.6, 1.2, 0.9)), 0.55);
  d = smin(d, sdEll(q - vec3(0.0, -3.55, 2.2), vec3(1.35, 0.95, 0.95)), 0.9);
  return d;
}

// Joint balls are 15-25 % wider than the limb ends next to them and the limb
// shafts stop short of the joint centres, so every joint reads as a sphere.
float armD(vec3 p, vec3 sh, vec3 el, vec3 wr, vec4 hc, vec4 hx, vec4 hy, vec4 hz) {
  float d = length(p - sh) - 2.6;
  d = min(d, sdLimb(p, mix(sh, el, 0.1), mix(sh, el, 0.93), 2.15, 1.22, 0.42, 0.25));
  d = min(d, length(p - el) - 1.55);
  d = min(d, sdLimb(p, mix(el, wr, 0.09), mix(el, wr, 0.93), 1.3, 1.05, 0.42, 1.0));
  d = min(d, length(p - wr) - 1.2);
  return smin(d, handD(p, hc, hx, hy, hz), 0.35);
}

// Leg group below the thigh (the thigh lives in the torso group).
float legD(vec3 p, vec3 kn, vec3 an, vec4 fc, vec4 fx, vec4 fy, vec4 fz) {
  float d = length(p - kn) - 2.1;
  d = min(d, sdLimb(p, mix(kn, an, 0.08), mix(kn, an, 0.93), 1.75, 1.08, 0.55, 1.0));
  d = min(d, length(p - an) - 1.35);
  return smin(d, footD(p, fc, fx, fy, fz), 0.45);
}

// Figure SDF -> (distance, group). Groups: 0 torso, 1 head, 2/3 arms,
// 4/5 knee .. foot, 6/7 thighs.
// A group whose bounding sphere is farther than [thr] contributes only its
// (conservative) bound distance, so far-away parts cost one length().
// Arms/legs are evaluated in 2-iteration loops so the GPU code stays small.
vec2 map(vec3 p, float thr) {
  float b = length(p - uBTorso.xyz) - uBTorso.w;
  vec2 r = vec2(b, 0.0);
  if (b <= thr) { r = torsoD(p, thr); }
  b = length(p - uBHead.xyz) - uBHead.w;
  float d = b;
  if (b <= thr) { d = headD(p); }
  if (d < r.x) { r = vec2(d, 1.0); }
  for (int i = 0; i < 2; i++) {
    bool s1 = i == 0;
    vec4 bs = s1 ? uBArm1 : uBArm2;
    b = length(p - bs.xyz) - bs.w;
    d = b;
    if (b <= thr) {
      d = armD(p, s1 ? uSh1.xyz : uSh2.xyz, s1 ? uEl1.xyz : uEl2.xyz, s1 ? uWr1.xyz : uWr2.xyz,
               s1 ? uHa1C : uHa2C, s1 ? uHa1X : uHa2X, s1 ? uHa1Y : uHa2Y, s1 ? uHa1Z : uHa2Z);
    }
    if (d < r.x) { r = vec2(d, 2.0 + float(i)); }
  }
  for (int i = 0; i < 2; i++) {
    bool s1 = i == 0;
    vec4 bs = s1 ? uBLeg1 : uBLeg2;
    b = length(p - bs.xyz) - bs.w;
    d = b;
    if (b <= thr) {
      d = legD(p, s1 ? uKn1.xyz : uKn2.xyz, s1 ? uAn1.xyz : uAn2.xyz,
               s1 ? uFt1C : uFt2C, s1 ? uFt1X : uFt2X, s1 ? uFt1Y : uFt2Y, s1 ? uFt1Z : uFt2Z);
    }
    if (d < r.x) { r = vec2(d, 4.0 + float(i)); }
  }
  return r;
}

// 0 = body material, 1 = joint ball material (soft transition). The hip
// sockets only get a faint tint where the ball meets the surface.
float jointness(vec3 p, float surf) {
  float j = length(p - uSh1.xyz) - 2.6;
  j = min(j, length(p - uSh2.xyz) - 2.6);
  j = min(j, length(p - uEl1.xyz) - 1.55);
  j = min(j, length(p - uEl2.xyz) - 1.55);
  j = min(j, length(p - uWr1.xyz) - 1.2);
  j = min(j, length(p - uWr2.xyz) - 1.2);
  j = min(j, length(p - uKn1.xyz) - 2.1);
  j = min(j, length(p - uKn2.xyz) - 2.1);
  j = min(j, length(p - uAn1.xyz) - 1.35);
  j = min(j, length(p - uAn2.xyz) - 1.35);
  float jh = min(length(p - hipBall(uHp1.xyz, 1.0)), length(p - hipBall(uHp2.xyz, -1.0))) - 2.35;
  return max(1.0 - smoothstep(0.02, 0.12, j - surf), 0.45 * (1.0 - smoothstep(-0.1, 0.55, jh - surf)));
}

// Surface normal (tetrahedron taps, when computeN) and SDF ambient occlusion
// (uQual.y taps along the normal, when doAO; [sc] scales the probe distances,
// the floor uses wider probes) in ONE loop, so the figure SDF is inlined only
// twice in the whole shader: here and in the march.
vec4 surfNA(vec3 p, vec3 n0, bool computeN, bool doAO, float sc) {
  vec3 n = n0;
  vec3 acc = vec3(0.0);
  float occ = 0.0;
  float sca = 1.0;
  float wsum = 0.0;
  for (int i = 0; i < 8; i++) {
    bool nTap = i < 4;
    if (nTap && !computeN) { continue; }
    if (i == 4 && computeN) { n = normalize(acc); }
    if (!nTap && (!doAO || float(i - 4) >= uQual.y)) { break; }
    vec3 e = vec3((i == 0 || i == 3) ? 1.0 : -1.0, (i >= 2) ? 1.0 : -1.0, (i == 1 || i == 3) ? 1.0 : -1.0);
    float h = (0.35 + 1.25 * float(i - 4)) * sc;
    float d = map(nTap ? p + e * 0.015 : p + n * h, nTap ? 0.5 : 6.0 * sc).x;
    if (nTap) {
      acc += e * d;
    } else {
      occ += (h - d) * sca;
      wsum += sca;
      sca *= 0.72;
    }
  }
  if (computeN && !doAO) { n = normalize(acc); }
  return vec4(n, clamp(1.0 - occ * (2.61 / max(wsum, 0.5)) * 0.16 / sc, 0.0, 1.0));
}

// --------------------------------------------------- analytic soft shadows
// World-fixed high sun used only for the shadow the figure casts on the
// floor, so the floor shadow does not swing around while the view rotates.
const vec3 kSun = vec3(-0.0697, 0.9968, 0.0399);

// [fd] > 0: the shadow weakens with the occluder's distance from the
// receiver (floor: high body parts cast fainter shadows, contacts stay dark).
float capShadow(vec3 ro, vec3 rd, vec3 a, vec3 b, float r, float k, float fd) {
  vec3 ba = b - a;
  vec3 oa = ro - a;
  float oad = dot(oa, rd);
  float dba = dot(rd, ba);
  float baba = dot(ba, ba);
  float oaba = dot(oa, ba);
  vec2 th = vec2(-oad * baba + dba * oaba, oaba - oad * dba) / max(baba - dba * dba, 1e-4);
  if (th.x <= 0.0) return 1.0;  // closest approach behind the origin
  th.y = clamp(th.y, 0.0, 1.0);
  vec3 p = a + ba * th.y;
  vec3 q = ro + rd * th.x;
  float d = length(p - q) - r;
  float s = clamp(k * d / max(th.x, 0.8) + 0.5, 0.0, 1.0);
  s = s * s * (3.0 - 2.0 * s);
  return fd > 0.0 ? 1.0 - (1.0 - s) * clamp(1.35 - th.x / fd, 0.25, 1.0) : s;
}

// Shadow of the figure (capsule proxies). The receiver's own group [skip]
// is excluded; torso and thighs are blended into one surface, so they never
// shadow each other (no discontinuity where the group id changes).
float bodyShadow(vec3 ro, vec3 rd, float skip, float k, float fd) {
  float s = 1.0;
  bool trunk = skip == 0.0 || skip >= 6.0;
  if (!trunk) {
    s *= capShadow(ro, rd, uHip.xyz + uT.xyz * 1.5, uNeck.xyz - uT.xyz * 4.0, 5.3, k, fd);
  }
  if (skip != 1.0) {
    s *= capShadow(ro, rd, uHead.xyz - uHU.xyz * 1.2, uHead.xyz + uHU.xyz * 0.8, 3.7, k, fd);
  }
  for (int i = 0; i < 2; i++) {
    bool s1 = i == 0;
    if (skip != 2.0 + float(i)) {
      vec3 sh = s1 ? uSh1.xyz : uSh2.xyz;
      vec3 el = s1 ? uEl1.xyz : uEl2.xyz;
      s *= capShadow(ro, rd, sh, el, 1.8, k, fd);
      s *= capShadow(ro, rd, el, s1 ? uHa1C.xyz : uHa2C.xyz, 1.25, k, fd);
    }
    bool ownLeg = skip == 4.0 + float(i) || skip == 6.0 + float(i);
    vec3 kn = s1 ? uKn1.xyz : uKn2.xyz;
    if (!trunk && !ownLeg) {
      s *= capShadow(ro, rd, s1 ? uHp1.xyz : uHp2.xyz, kn, 2.6, k, fd);
    }
    if (!ownLeg) {
      vec4 fc = s1 ? uFt1C : uFt2C;
      vec4 fx = s1 ? uFt1X : uFt2X;
      s *= capShadow(ro, rd, kn, s1 ? uAn1.xyz : uAn2.xyz, 1.6, k, fd);
      s *= capShadow(ro, rd, fc.xyz - fx.xyz * 3.0, fc.xyz + fx.xyz * 3.0, 1.2, k, fd);
    }
  }
  return s;
}

float propShadow(vec3 ro, vec3 rd, float k) {
  float s = 1.0;
  if (uBar.w > 0.5) {
    s *= capShadow(ro, rd, vec3(uBar.x, uBar.y, -uBar.z), vec3(uBar.x, uBar.y, uBar.z), 1.2, k, 0.0);
  }
  if (uPole.w > 0.5) {
    s *= capShadow(ro, rd, vec3(uPole.x, uPole.z, uPole.y), vec3(uPole.x, 400.0, uPole.y), 1.4, k, 0.0);
  }
  if (uPbar.w > 0.5) {
    s *= capShadow(ro, rd, vec3(uPbar.y, uPbar.x, uPbar2.x), vec3(uPbar.z, uPbar.x, uPbar2.x), 1.1, k, 0.0);
    s *= capShadow(ro, rd, vec3(uPbar.y, uPbar.x, -uPbar2.x), vec3(uPbar.z, uPbar.x, -uPbar2.x), 1.1, k, 0.0);
  }
  return s;
}

// ---------------------------------------------------- analytic prop tracing
float capIntersect(vec3 ro, vec3 rd, vec3 pa, vec3 pb, float ra) {
  vec3 ba = pb - pa;
  vec3 oa = ro - pa;
  float baba = dot(ba, ba);
  float bard = dot(ba, rd);
  float baoa = dot(ba, oa);
  float rdoa = dot(rd, oa);
  float oaoa = dot(oa, oa);
  float a = baba - bard * bard;
  float b = baba * rdoa - baoa * bard;
  float c = baba * oaoa - baoa * baoa - ra * ra * baba;
  float h = b * b - a * c;
  if (h >= 0.0) {
    float t = (-b - sqrt(h)) / a;
    float y = baoa + t * bard;
    if (y > 0.0 && y < baba) return t;
    vec3 oc = (y <= 0.0) ? oa : ro - pb;
    b = dot(rd, oc);
    c = dot(oc, oc) - ra * ra;
    h = b * b - c;
    if (h > 0.0) return -b - sqrt(h);
  }
  return -1.0;
}

vec3 capNormal(vec3 pos, vec3 a, vec3 b) {
  vec3 ba = b - a;
  vec3 pa = pos - a;
  float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
  return normalize(pa - h * ba);
}

// One capsule prop with analytic anti-aliasing: pixels whose ray passes the
// capsule within half a pixel of its silhouette become a coverage layer
// (eg = alpha, t; eN = normal) instead of a binary hit.
void propCap(vec3 ro, vec3 rd, vec3 a, vec3 b, float r, float pix,
             inout float tP, inout vec3 nP, inout float mP, inout vec2 eg, inout vec3 eN) {
  vec3 ba = b - a;
  vec3 oa = ro - a;
  float baba = dot(ba, ba);
  float bard = dot(ba, rd);
  float rdoa = dot(rd, oa);
  float den = max(baba - bard * bard, 1e-5);
  float sg = clamp((dot(ba, oa) - bard * rdoa) / den, 0.0, 1.0);
  float t = bard * sg - rdoa;
  if (t <= 0.0 || t >= tP) return;
  float d = length(oa + rd * t - ba * sg);
  float cov = clamp(0.5 - (d - r) / (pix * t), 0.0, 1.0);
  if (cov >= 1.0) {
    float th = capIntersect(ro, rd, a, b, r);
    if (th > 0.0 && th < tP) {
      tP = th;
      mP = 2.0;
      nP = capNormal(ro + rd * th, a, b);
    }
  } else if (cov > eg.x || (cov > 0.0 && t < eg.y)) {
    eg = vec2(cov, t);
    eN = normalize(oa + rd * t - ba * sg);
  }
}

// Bar uprights: tracked separately (nearest one, with coverage) so they can
// be drawn semi-transparent where they pass in front of the figure.
void ghostCap(vec3 ro, vec3 rd, vec3 a, vec3 b, float r, float pix,
              inout float tU, inout vec3 nU, inout float cU) {
  vec3 ba = b - a;
  vec3 oa = ro - a;
  float baba = dot(ba, ba);
  float bard = dot(ba, rd);
  float rdoa = dot(rd, oa);
  float den = max(baba - bard * bard, 1e-5);
  float sg = clamp((dot(ba, oa) - bard * rdoa) / den, 0.0, 1.0);
  float t = bard * sg - rdoa;
  if (t <= 0.0 || t >= tU) return;
  vec3 off = oa + rd * t - ba * sg;
  float cov = clamp(0.5 - (length(off) - r) / (pix * t), 0.0, 1.0);
  if (cov <= 0.0) return;
  float th = cov >= 1.0 ? capIntersect(ro, rd, a, b, r) : -1.0;
  tU = th > 0.0 ? th : t;
  nU = th > 0.0 ? capNormal(ro + rd * th, a, b) : normalize(off);
  cU = cov;
}

vec2 boxHit(vec3 ro, vec3 rd, vec3 bmin, vec3 bmax) {
  vec3 ird = 1.0 / rd;
  vec3 t0 = (bmin - ro) * ird;
  vec3 t1 = (bmax - ro) * ird;
  vec3 tmin = min(t0, t1);
  vec3 tmax = max(t0, t1);
  return vec2(max(max(tmin.x, tmin.y), tmin.z), min(min(tmax.x, tmax.y), tmax.z));
}

// --------------------------------------------------------------- shading
vec3 toneMap(vec3 x) {
  // luminance-based soft shoulder (keeps the material's hue/saturation)
  float l = dot(x, vec3(0.2126, 0.7152, 0.0722));
  float m = l > 0.6 ? 0.6 + (l - 0.6) / (1.0 + (l - 0.6) * 1.6) : l;
  x *= m / max(l, 1e-4);
  return pow(clamp(x, 0.0, 1.0), vec3(1.0 / 2.2));
}

// brushed metal (bars, poles)
vec3 metalCol(vec3 n, vec3 rd) {
  vec3 r = reflect(rd, n);
  vec3 env = mix(vec3(0.08, 0.08, 0.09), vec3(0.75, 0.78, 0.82), smoothstep(-0.3, 0.6, r.y));
  float spe = pow(clamp(dot(r, uKey.xyz), 0.0, 1.0), 40.0);
  return toneMap(vec3(0.16, 0.17, 0.19) * (0.25 + clamp(dot(n, uKey.xyz), 0.0, 1.0) * 0.9) + env * 0.35 + vec3(spe * 1.2));
}

// fade distant props into the background
vec3 distFade(vec3 col, float t) {
  float fd = clamp((t - length(uCamPos.xyz - (uBMin.xyz + uBMax.xyz) * 0.5)) / 120.0, 0.0, 1.0);
  return mix(col, uBg.rgb, fd * fd);
}

// Analytic contact darkening on the ground: under hands / feet resting on
// it and around the bases of the pole and the parallel-bar posts.
float contactAO(vec3 p) {
  float c = 0.0;
  for (int i = 0; i < 4; i++) {
    vec4 bc = i == 0 ? uHa1C : (i == 1 ? uHa2C : (i == 2 ? uFt1C : uFt2C));
    vec4 bx = i == 0 ? uHa1X : (i == 1 ? uHa2X : (i == 2 ? uFt1X : uFt2X));
    float w = 1.0 - smoothstep(1.4, 3.2, bc.y - uFloor.x);
    if (w > 0.0) {
      vec2 a = bc.xz - bx.xz * (bx.w * 0.7);
      vec2 ba = bx.xz * (bx.w * 1.4);
      vec2 pa = p.xz - a;
      float h = clamp(dot(pa, ba) / max(dot(ba, ba), 1e-4), 0.0, 1.0);
      vec2 dv = pa - ba * h;
      c = max(c, w * exp(-dot(dv, dv) / 4.5));
    }
  }
  if (uPole.w > 0.5 && abs(uPole.z - uFloor.x) < 0.5) {
    float d = max(length(p.xz - vec2(uPole.x, uPole.y)) - 1.4, 0.0);
    c = max(c, exp(-d * d / 3.0));
  }
  if (uPbar.w > 0.5 && abs(uPbar2.y - uFloor.x) < 0.5) {
    vec2 q = vec2(min(abs(p.x - uPbar.y - 2.5), abs(p.x - uPbar.z + 2.5)), abs(abs(p.z) - uPbar2.x));
    float d = max(length(q) - 0.9, 0.0);
    c = max(c, exp(-d * d / 3.0));
  }
  return c;
}

// One shading routine for every visible surface (keeps the compiled shader
// small: the SDF is inlined only in march / normal / AO).
// mat: 0 body, 1 floor, 2 metal, 3 box, 4 wall. vig: screen-space vignette
// (x: stage + grid, y: floor shadows) so the floor fades to bg at the frame
// border. edge = 1 for the anti-aliasing layer (softer rim). ao from surfNA.
vec3 shade(vec3 p, vec3 n, vec3 rd, float t, float mat, vec2 g, vec2 vig, float edge, float ao) {
  vec3 bg = uBg.rgb;
  float lum = uCamU.w;
  vec3 v = -rd;
  float ndv = clamp(dot(n, v), 0.0, 1.0);
  bool body = mat < 0.5;
  bool floorM = mat > 0.5 && mat < 1.5;

  // distance from the figure (floor effects fade out)
  vec3 qb = clamp(p, uBMin.xyz, uBMax.xyz);
  float near = length(p - qb);
  bool fx = body || (floorM && near < 34.0 && vig.y > 0.0);

  float ndl = dot(n, uKey.xyz);
  float sh = 1.0;
  if (fx) {
    if (body) {
      if (ndl > -0.2) {
        vec3 ro = p + n * 0.45;
        sh = bodyShadow(ro, uKey.xyz, g.y, 3.0, 0.0) * propShadow(ro, uKey.xyz, 3.0);
      }
    } else {
      sh = bodyShadow(p + n * 0.05, kSun, -1.0, 3.5, 26.0);
    }
  }

  if (body) {
    float jm = jointness(p, g.x);
    vec3 base = mix(vec3(0.53, 0.46, 0.39), vec3(0.235, 0.165, 0.115), jm);
    if (g.y == 1.0) {
      // face plane slightly darker so the facing direction reads at 100 px
      vec3 hq = p - uHead.xyz;
      float face = smoothstep(0.3, 0.75, dot(n, uHF.xyz)) * smoothstep(1.8, 0.8, dot(hq, uHU.xyz));
      base *= 1.0 - 0.09 * face;
    }
    float dif = clamp((ndl + 0.2) / 1.2, 0.0, 1.0);
    vec3 h = normalize(uKey.xyz + v);
    float spe = pow(clamp(dot(n, h), 0.0, 1.0), 22.0) * (0.04 + 0.25 * pow(1.0 - ndv, 5.0));
    vec3 col = base * vec3(1.0, 0.95, 0.88) * (uKey.w * dif * sh);
    col += base * vec3(0.55, 0.6, 0.7) * (0.30 * (0.55 + 0.45 * n.y) * ao);
    col += base * vec3(0.55, 0.62, 0.75) * (uFill.w * clamp(dot(n, uFill.xyz) * 0.6 + 0.4, 0.0, 1.0) * ao);
    col += base * vec3(0.45, 0.36, 0.28) * (0.18 * clamp(-n.y * 0.5 + 0.5, 0.0, 1.0) * ao);
    col += vec3(1.0, 0.97, 0.92) * (spe * uKey.w * sh * (1.0 - 0.5 * jm));
    // rim: only where the surface actually faces the rim light; weak in the
    // AA layer (its normal is taken just off the surface)
    float fres = pow(1.0 - ndv, 3.0) * (1.0 - 0.7 * edge);
    float rimL = clamp(dot(n, uRim.xyz), 0.0, 1.0);
    col += vec3(0.75, 0.85, 1.0) * (fres * rimL * uRim.w * mix(1.0, 0.25, lum) * (0.4 + 0.6 * ao));
    vec3 o = toneMap(col);
    return o * (1.0 - lum * 0.28 * pow(1.0 - ndv, 4.0));  // soft contour on light bg
  }
  vec3 col;
  if (floorM) {
    vec2 rel = p.xz - uFloor.zw;
    float stage = exp(-dot(rel, rel) / (uQual.w * uQual.w));
    float st = stage * vig.x;
    col = bg + mix(vec3(0.045, 0.045, 0.05), vec3(-0.012, -0.012, -0.011), lum) * st;
    // subtle grid
    vec2 gg = abs(fract(p.xz / 10.0 + 0.5) - 0.5) * 10.0;
    float px = uCamR.w * t * 1.2 / max(abs(rd.y), 0.08);
    float line = 1.0 - smoothstep(0.0, px + 0.06, min(gg.x, gg.y));
    line *= clamp(1.0 - px * 1.5, 0.0, 1.0);
    col += mix(vec3(0.06), vec3(-0.05), lum) * line * st * 0.8;
    float shade = (1.0 - sh) * mix(0.55, 0.3, lum) * smoothstep(34.0, 20.0, near) + (1.0 - ao) * mix(0.85, 0.5, lum);
    shade += contactAO(p) * mix(0.5, 0.35, lum);
    col *= 1.0 - clamp(shade, 0.0, 0.9) * vig.y;
  } else if (mat < 2.5) {
    col = metalCol(n, rd);
    // props leaving the frame below the figure (pole, posts) fade out
    if (p.y < uBMin.y) { col = mix(col, bg, 1.0 - vig.y); }
  } else if (mat < 3.5) {
    col = toneMap(vec3(0.20, 0.22, 0.26) * (clamp(ndl, 0.0, 1.0) * 1.6 + (0.6 + 0.4 * n.y) * 0.5));
  } else {
    float fade = exp(-pow(length(p.yz - vec2((uBMin.y + uBMax.y) * 0.5, 0.0)) / 60.0, 2.0));
    col = bg + mix(vec3(0.045), vec3(-0.05), lum) * fade * vig.x;
  }
  return distFade(col, t);
}

void main() {
  vec2 fc = FlutterFragCoord().xy;
  vec2 uv = (2.0 * fc - uSize) / uSize.y;
  uv.y = -uv.y;
  vec3 ro = uCamPos.xyz;
  vec3 rd = normalize(uCamF.xyz * uCamPos.w + uv.x * uCamR.xyz + uv.y * uCamU.xyz);
  float pix = uCamR.w;
  float vm = max(abs(uv.x) * uSize.y / uSize.x, abs(uv.y));
  vec2 vig = vec2(smoothstep(1.0, 0.62, vm), smoothstep(1.0, 0.9, vm));

  // ---- props (analytic ray intersections, capsules anti-aliased)
  float tP = 1e9;
  vec3 nP = vec3(0.0, 1.0, 0.0);
  float mP = 0.0;  // 0 none, 1 floor, 2 metal, 3 box, 4 wall
  vec2 eg = vec2(0.0, 1e9);  // prop edge layer: coverage, t
  vec3 eN = vec3(0.0, 1.0, 0.0);
  if (uFloor.y > 0.5 && rd.y < 0.0) {
    float t = (uFloor.x - ro.y) / rd.y;
    if (t > 0.0) { tP = t; mP = 1.0; }
  }
  if (uBox0.w > 0.5) {
    vec2 tb = boxHit(ro, rd, uBox0.xyz, uBox1.xyz);
    if (tb.x < tb.y && tb.x > 0.0 && tb.x < tP) {
      tP = tb.x;
      mP = 3.0;
      vec3 dd = (ro + rd * tb.x - (uBox0.xyz + uBox1.xyz) * 0.5) / ((uBox1.xyz - uBox0.xyz) * 0.5);
      vec3 ad = abs(dd);
      if (ad.x > ad.y && ad.x > ad.z) { nP = vec3(sign(dd.x), 0.0, 0.0); }
      else if (ad.y > ad.z) { nP = vec3(0.0, sign(dd.y), 0.0); }
      else { nP = vec3(0.0, 0.0, sign(dd.z)); }
    }
  }
  if (uWall.w > 0.5 && (ro.x - uWall.x) * uWall.z > 0.0 && abs(rd.x) > 1e-4) {
    float t = (uWall.x - ro.x) / rd.x;
    vec3 ph = ro + rd * t;
    if (t > 0.0 && t < tP && ph.y > uWall.y && abs(ph.z) < 45.0) {
      tP = t; mP = 4.0; nP = vec3(uWall.z, 0.0, 0.0);
    }
  }
  float tU = 1e9;  // bar upright layer: t, normal, coverage
  vec3 nU = vec3(1.0, 0.0, 0.0);
  float cU = 0.0;
  if (uBar.w > 0.5) {
    for (int i = 0; i < 5; i++) {
      // bar along z, a sleeve at each end and two uprights going up out of frame
      float z = (i == 2 || i == 4) ? uBar.z : -uBar.z;
      vec3 a = vec3(uBar.x, uBar.y, -uBar.z);
      vec3 b = vec3(uBar.x, uBar.y, uBar.z);
      float r = 1.2;
      if (i == 1 || i == 2) {
        a = vec3(uBar.x, uBar.y, z - sign(z) * 1.2);
        b = vec3(uBar.x, uBar.y, z + sign(z) * 0.4);
        r = 1.75;
      } else if (i > 2) {
        a = vec3(uBar.x, uBar.y, z + sign(z) * 0.4);
        b = vec3(uBar.x, uBar.y + 400.0, z + sign(z) * 0.4);
        ghostCap(ro, rd, a, b, 1.05, pix, tU, nU, cU);
        continue;
      }
      propCap(ro, rd, a, b, r, pix, tP, nP, mP, eg, eN);
    }
  }
  if (uPbar.w > 0.5) {
    for (int i = 0; i < 6; i++) {
      // two rails along x at z = +-zoff, each with two posts down to the floor
      float z = (i < 3) ? uPbar2.x : -uPbar2.x;
      int k = (i < 3) ? i : i - 3;
      vec3 a = vec3(uPbar.y, uPbar.x, z);
      vec3 b = vec3(uPbar.z, uPbar.x, z);
      float r = 1.1;
      if (k > 0) {
        float x = (k == 1) ? uPbar.y + 2.5 : uPbar.z - 2.5;
        a = vec3(x, uPbar.x, z);
        b = vec3(x, uPbar2.y, z);
        r = 0.9;
      }
      propCap(ro, rd, a, b, r, pix, tP, nP, mP, eg, eN);
    }
  }
  if (uPole.w > 0.5) {
    propCap(ro, rd, vec3(uPole.x, uPole.z, uPole.y), vec3(uPole.x, 400.0, uPole.y), 1.4, pix, tP, nP, mP, eg, eN);
  }

  // ---- figure: sphere-traced inside its AABB, in front of the nearest prop.
  // Silhouette AA: the closest approach of a ray that passes a surface (a
  // local minimum of distance/pixel-footprint) becomes a coverage layer --
  // for rays that miss (outer silhouette) and, with uQual.z, for rays that
  // graze a limb and then hit something behind it (interior edges).
  float tHit = -1.0;
  float dbgSteps = 0.0;
  float minR = 1e9;
  float tMinR = 0.0;
  vec2 gMinR = vec2(0.0, -1.0);
  vec2 gHit = vec2(0.0, -1.0);  // (distance, group) at the hit
  vec2 tb = boxHit(ro, rd, uBMin.xyz, uBMax.xyz);
  if (tb.x < tb.y && tb.y > 0.0 && tb.x < tP) {
    float t = max(tb.x, 0.0);
    float tEnd = min(tb.y, tP);
    bool left = false;
    float d = 1e5;
    float prevD = 1e5;
    float cR = 1e9;
    float cT = 0.0;
    vec2 cG = vec2(0.0, -1.0);
    float rise = 0.0;  // how far the distance grew again after the pass-by
    for (int i = 0; i < 80; i++) {
      if (float(i) >= uQual.x) { break; }
      vec2 r = map(ro + rd * t, max(0.8, 2.0 * pix * t));
      d = r.x;
      float ratio = d / (pix * t);
      if (d > prevD) {
        // moving away again: the last local minimum was a pass-by
        if (cR < minR) { minR = cR; tMinR = cT; gMinR = cG; rise = 0.0; }
        cR = 1e9;
        rise = max(rise, d - gMinR.x);
      }
      if (ratio < cR) { cR = ratio; cT = t; cG = r; }
      if (minR < 1e8) { rise = max(rise, d - gMinR.x); }
      prevD = d;
      if (d < 0.25 * pix * t) { tHit = t; gHit = r; break; }
      dbgSteps += 1.0;
      t += d * 0.92;
      if (t > tEnd) { left = true; break; }
    }
    // out of steps while grazing a surface: accept as a hit
    if (tHit < 0.0 && !left && d < 4.0 * pix * t) { tHit = t; gHit = vec2(d, cG.y); }
    if (tHit < 0.0 && cR < minR) { minR = cR; tMinR = cT; gMinR = cG; }
    // interior edges only where a different body part passes in front of
    // the hit surface with a clear gap (limb over torso etc.)
    // (limb over torso etc.); concave blends (crotch, armpit) never open up
    // a real gap after the near pass, so they are excluded via [rise]
    if (tHit > 0.0 && (uQual.z < 0.5 || tHit - tMinR < 0.7 || gMinR.y == gHit.y || rise < 0.5)) { minR = 1e9; }
  }

  // ---- shade: layer 0 = opaque surface, layer 1 = anti-aliased silhouette
  bool bodyHit = tHit > 0.0;
  float edgeA = 0.0;
  if (minR < 1.0) {
    float a = clamp(1.0 - minR, 0.0, 1.0);
    edgeA = a * a * (3.0 - 2.0 * a);
  }
  vec3 col = uBg.rgb;
  for (int layer = 0; layer < 2; layer++) {
    bool isBody = bodyHit || layer == 1;
    if (layer == 1 && edgeA <= 0.0) break;
    if (!isBody && mP < 0.5) continue;
    float t = (layer == 1) ? tMinR : (bodyHit ? tHit : tP);
    vec3 p = ro + rd * t;
    float mat = isBody ? 0.0 : mP;
    // floor AO only near the figure (contact shadow); no AO in the AA layer
    vec3 qb = clamp(p, uBMin.xyz, uBMax.xyz);
    bool doAO = (isBody && layer == 0) || (mat == 1.0 && length(p - qb) < 9.0 && vig.y > 0.0);
    vec4 na = vec4(nP, 1.0);
    if (isBody || doAO) { na = surfNA(isBody ? p : p + nP * 0.05, nP, isBody, doAO, isBody ? 1.0 : 1.7); }
    float ao = (isBody && layer == 1) ? 0.9 : na.w;
    vec3 c = shade(p, na.xyz, rd, t, mat, (layer == 1) ? gMinR : gHit, vig, float(layer), ao);
    col = (layer == 0) ? c : mix(col, c, edgeA);
  }
  // prop silhouette layer (in front of whatever was shaded)
  float tFront = bodyHit ? tHit : tP;
  if (edgeA > 0.0) { tFront = min(tFront, tMinR); }
  if (eg.x > 0.0 && eg.y < tFront) {
    vec3 mc = metalCol(eN, rd);
    if (ro.y + rd.y * eg.y < uBMin.y) { mc = mix(mc, uBg.rgb, 1.0 - vig.y); }
    col = mix(col, distFade(mc, eg.y), eg.x);
  }
  // bar uprights: opaque over props / background, ghosted (38 %) where they
  // pass in front of the figure so they never cut through head or chest
  if (cU > 0.0 && tU < (bodyHit ? tHit : tP)) {
    float a = cU;
    if (bodyHit) {
      a *= 0.38;
    } else if (edgeA > 0.0) {
      a *= (tU < tMinR) ? mix(1.0, 0.38, edgeA) : 1.0 - edgeA;
    }
    col = mix(col, distFade(metalCol(nU, rd), tU), a);
  }
  // DEBUG: r = march steps / 80, g = 1 if body hit, b = 1 if any marching
  fragColor = vec4(dbgSteps / 80.0, tHit > 0.0 ? 1.0 : 0.0, dbgSteps > 0.0 ? 1.0 : 0.0, 1.0);
}
