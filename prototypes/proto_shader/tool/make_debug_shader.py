"""Generate shaders/mannequin_debug.frag (outputs march step counts) from mannequin.frag."""
import os
P = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
s = open(os.path.join(P, 'shaders', 'mannequin.frag')).read()
s = s.replace("  float tHit = -1.0;\n", "  float tHit = -1.0;\n  float dbgSteps = 0.0;\n", 1)
s = s.replace("      t += d * 0.92;\n", "      dbgSteps += 1.0;\n      t += d * 0.92;\n", 1)
s = s.replace("  fragColor = vec4(col, 1.0);",
              "  // DEBUG: r = march steps / 80, g = 1 if body hit, b = 1 if any marching\n"
              "  fragColor = vec4(dbgSteps / 80.0, tHit > 0.0 ? 1.0 : 0.0, dbgSteps > 0.0 ? 1.0 : 0.0, 1.0);", 1)
assert 'dbgSteps / 80.0' in s
open(os.path.join(P, 'shaders', 'mannequin_debug.frag'), 'w').write(
    "// GENERATED from mannequin.frag by tool/make_debug_shader.py - do not edit\n" + s)
print('ok')
