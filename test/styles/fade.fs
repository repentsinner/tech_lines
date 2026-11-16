// Test style: fades a line from full at fadeCenter to nothing at
// fadeRadius, measured in the xy plane, and fades its pulse glow with it.
// The world position carries the depth bias, which moves it along z, so a
// fade over a plane measures within the plane.
void styleLine(inout ScreenLineStyle style, ScreenLineFragment fragment) {
    float reach = distance(fragment.worldPosition.xy,
        materialParams.fadeCenter.xy) / max(materialParams.fadeRadius, 1e-6);
    float fade = 1.0 - smoothstep(0.0, 1.0, reach);
    style.alpha *= fade;
    style.glowScale *= fade;
}
