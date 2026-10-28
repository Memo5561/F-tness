#version 460 core
#include <flutter/runtime_effect.glsl>
precision highp float;
uniform vec2 uSize;
uniform vec4 uColor;
uniform float uArr[4];
out vec4 fragColor;
void main() {
  vec2 p = FlutterFragCoord().xy / uSize;
  fragColor = vec4(p.x, p.y, uColor.b + uArr[2], 1.0);
}
