"""
Muscle Burger - low-poly stylized (v2)

Run from Blender's Scripting tab, Python console (paste once, then Up + Enter to rebuild):
    exec(open(r"C:\\Users\\Grorian\\Documents\\GitHub\\Hold-or-Drop\\blender\\muscle_burger.py", encoding="utf-8").read())

Z up. Front of the burger faces +Y. Built around the world origin.
Arms are a single metaball object (smooth fused muscle). Everything lives in the
"MuscleBurger" collection and is wiped + rebuilt on each run.
"""
import bpy
import bmesh
import math

COLL = "MuscleBurger"

# ----------------------------- reset ------------------------------------
if COLL in bpy.data.collections:
    old = bpy.data.collections[COLL]
    for o in list(old.objects):
        bpy.data.objects.remove(o, do_unlink=True)
    bpy.data.collections.remove(old)
coll = bpy.data.collections.new(COLL)
bpy.context.scene.collection.children.link(coll)
for junk in ("Cube",):
    obj = bpy.data.objects.get(junk)
    if obj and obj.type == "MESH":
        bpy.data.objects.remove(obj, do_unlink=True)


def to_coll(o):
    for c in list(o.users_collection):
        c.objects.unlink(o)
    coll.objects.link(o)


def mat(name, rgb, rough=0.55):
    m = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    nt = m.node_tree
    if nt is None:
        m.use_nodes = True
        nt = m.node_tree
    b = nt.nodes.get("Principled BSDF")
    if b:
        b.inputs["Base Color"].default_value = (rgb[0], rgb[1], rgb[2], 1.0)
        b.inputs["Roughness"].default_value = rough
    m.diffuse_color = (rgb[0], rgb[1], rgb[2], 1.0)
    return m


def set_smooth(o, s=True):
    for p in o.data.polygons:
        p.use_smooth = s


def subsurf(o, levels=1):
    md = o.modifiers.new("Subsurf", "SUBSURF")
    md.levels = levels
    md.render_levels = levels
    return md


# ----------------------------- materials --------------------------------
M_BUN = mat("MB_Bun", (0.93, 0.55, 0.16), 0.50)
M_LETTUCE = mat("MB_Lettuce", (0.40, 0.68, 0.15), 0.65)
M_RED = mat("MB_Red", (0.85, 0.13, 0.11), 0.45)
M_PATTY = mat("MB_Patty", (0.30, 0.16, 0.10), 0.70)
M_CHEESE = mat("MB_Cheese", (0.97, 0.80, 0.28), 0.40)
M_SKIN = mat("MB_Skin", (0.95, 0.78, 0.62), 0.60)
M_SESAME = mat("MB_Sesame", (0.96, 0.89, 0.72), 0.50)

# ----------------------------- bottom bun -------------------------------
bpy.ops.mesh.primitive_cylinder_add(radius=1.02, depth=0.40, vertices=32, location=(0, 0, 0.22))
bb = bpy.context.active_object
bb.name = "BunBottom"
bev = bb.modifiers.new("Bevel", "BEVEL")
bev.width = 0.14
bev.segments = 3
bev.limit_method = "ANGLE"
bb.data.materials.append(M_BUN)
set_smooth(bb)
subsurf(bb, 1)
to_coll(bb)

# ------------------------------ top bun (dome) --------------------------
bpy.ops.mesh.primitive_uv_sphere_add(segments=28, ring_count=16, location=(0, 0, 1.12))
bt = bpy.context.active_object
bt.name = "BunTop"
bt.scale = (1.06, 1.06, 0.74)
bt.data.materials.append(M_BUN)
set_smooth(bt)
subsurf(bt, 1)
to_coll(bt)

# ------------------------- red sauce (drippy band) ----------------------
bpy.ops.mesh.primitive_cylinder_add(radius=1.05, depth=0.20, vertices=44, location=(0, 0, 1.00))
red = bpy.context.active_object
red.name = "RedSauce"
for v in red.data.vertices:
    if v.co.z < -0.05:  # bottom rim -> drips
        ang = math.atan2(v.co.y, v.co.x)
        v.co.z -= 0.05 + 0.05 * (0.5 + 0.5 * math.sin(8 * ang))
red.data.materials.append(M_RED)
set_smooth(red)
subsurf(red, 1)
to_coll(red)

# --------------------------- patty core (fills middle) ------------------
bpy.ops.mesh.primitive_cylinder_add(radius=0.95, depth=0.52, vertices=28, location=(0, 0, 0.74))
pc = bpy.context.active_object
pc.name = "PattyCore"
pc.data.materials.append(M_PATTY)
set_smooth(pc)
to_coll(pc)

# ------------------------- lettuce (wavy ruffled rings) -----------------
def wavy_ring(name, R, r, z, lobes, amp, zsquash, m):
    bpy.ops.mesh.primitive_torus_add(major_radius=R, minor_radius=r,
                                     major_segments=44, minor_segments=10,
                                     location=(0, 0, 0))
    o = bpy.context.active_object
    o.name = name
    for v in o.data.vertices:
        x, y, zz = v.co
        rad = math.hypot(x, y)
        if rad > 1e-6:
            f = (rad + amp * math.sin(lobes * math.atan2(y, x))) / rad
            v.co.x = x * f
            v.co.y = y * f
        v.co.z = zz * zsquash
    o.location = (0, 0, z)
    o.data.materials.append(m)
    set_smooth(o)
    to_coll(o)
    return o

wavy_ring("LettuceLow", 1.16, 0.15, 0.52, 11, 0.08, 0.8, M_LETTUCE)
wavy_ring("LettuceHigh", 1.16, 0.15, 0.92, 12, 0.08, 0.8, M_LETTUCE)

# ----------------- cheese triangle (front +Y, apex down) ----------------
me = bpy.data.meshes.new("CheeseMesh")
cheese = bpy.data.objects.new("Cheese", me)
to_coll(cheese)
bm = bmesh.new()
w, h, th = 0.52, 0.58, 0.10
tri = [(-w, 0.02), (w, 0.02), (0.0, -h)]
front = [bm.verts.new((x, th / 2, z)) for (x, z) in tri]
back = [bm.verts.new((x, -th / 2, z)) for (x, z) in tri]
bm.faces.new(front)
bm.faces.new(list(reversed(back)))
for i in range(3):
    a, b2 = front[i], front[(i + 1) % 3]
    c, d = back[i], back[(i + 1) % 3]
    bm.faces.new((a, b2, d, c))
bm.normal_update()
bm.to_mesh(me)
bm.free()
cheese.location = (0.0, 1.06, 0.74)
cheese.data.materials.append(M_CHEESE)
set_smooth(cheese, False)
bc = cheese.modifiers.new("Bevel", "BEVEL")
bc.width = 0.03
bc.segments = 2

# ----------------------- arms (one metaball, both sides) ----------------
mball = bpy.data.metaballs.new("ArmsMeta")
arms = bpy.data.objects.new("Arms", mball)
to_coll(arms)
mball.resolution = 0.17
mball.render_resolution = 0.12
mball.threshold = 0.6
mball.materials.append(M_SKIN)

def meta(co, radius, stiff=2.0):
    el = mball.elements.new()
    el.co = co
    el.radius = radius
    el.stiffness = stiff

for s in (1, -1):
    meta((s * 0.92, 0.00, 0.62), 0.46)   # deltoid / shoulder
    meta((s * 1.20, 0.06, 0.60), 0.40)   # upper arm
    meta((s * 1.42, 0.10, 0.74), 0.42)   # bicep bulge
    meta((s * 1.62, 0.00, 0.60), 0.34)   # elbow
    meta((s * 1.64, 0.00, 0.86), 0.33)   # forearm low
    meta((s * 1.60, 0.02, 1.12), 0.30)   # forearm high
    meta((s * 1.58, 0.06, 1.40), 0.36)   # fist
    meta((s * 1.58, 0.30, 1.44), 0.13)   # knuckles
    meta((s * 1.66, 0.20, 1.40), 0.12)

# ------------------------------ sesame seeds ----------------------------
seeds = [(18, 34), (-22, 30), (2, 17), (44, 44), (-48, 42), (14, 56), (-16, 60)]
cz = 1.12
Rx, Ry, Rz = 1.06, 1.06, 0.74
for i, (az, pol) in enumerate(seeds):
    a = math.radians(az)
    p = math.radians(pol)
    px = Rx * math.sin(p) * math.sin(a)
    py = Ry * math.sin(p) * math.cos(a)
    pz = cz + Rz * math.cos(p)
    bpy.ops.mesh.primitive_uv_sphere_add(segments=10, ring_count=6, location=(px, py, pz))
    sd = bpy.context.active_object
    sd.name = f"Sesame_{i}"
    sd.scale = (0.075, 0.05, 0.03)
    sd.data.materials.append(M_SESAME)
    set_smooth(sd)
    to_coll(sd)

print("Muscle Burger v2:", len(coll.objects), "objects")
