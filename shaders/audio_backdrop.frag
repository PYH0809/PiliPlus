#version 460 core

#include <flutter/runtime_effect.glsl>

precision highp float;

// The last pass of 听视频's background (lib/pages/audio/backdrop/), with
// Apple Music's numbers (BackdropMaths.finish): saturation 2 capped below
// white, a quarter of the way to black less 0.02, then held within 0.07 and
// 0.97. The noise, half a level of 8 bits either way, keeps the gradients
// from banding on an 8 bit surface.

// The size drawn, in its own coordinates, and the device pixels to each.
uniform vec2 uSize;
uniform float uPixelRatio;
// The warped, blurred cover, a fraction of the size, read bilinearly.
uniform sampler2D uImage;

out vec4 fragColor;

void main() {
  vec2 position = FlutterFragCoord().xy;
  vec3 color = texture(uImage, position / uSize).rgb;
  float luma = dot(color, vec3(0.30, 0.59, 0.11));
  color = min(vec3(0.9951171875), vec3(luma) + 2.0 * (color - vec3(luma)));
  color = color * 0.75 - 0.02;
  vec2 pixel = floor(position * uPixelRatio);
  float noise = fract(sin(dot(pixel, vec2(12.9898, 78.233))) * 43758.5453);
  color = clamp(color + (noise - 0.5) / 255.0, 0.07, 0.97);
  fragColor = vec4(color, 1.0);
}
