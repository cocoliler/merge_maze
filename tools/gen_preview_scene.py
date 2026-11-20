#!/usr/bin/env python3
"""生成只用于「看模型」的预览场景。

相机角度故意和游戏里一致（Main.gd: CAM_BACK_RATIO = 18/21 → 俯角约 49.4°），
这样截图看到的就是玩家实际会看到的样子。

    python tools/gen_preview_scene.py            # 敌人 → scenes/_ModelPreview.tscn
    python tools/gen_preview_scene.py --set towers   # 塔 → scenes/_TowerPreview.tscn

塔的排布：每排一个等级（近→远 = L1→L3），相邻排横向错开半格，避免前排挡住后排。
"""

from __future__ import annotations

import argparse
import math
import os

SETS = {
    "enemies": {
        "out": "scenes/_ModelPreview.tscn",
        "dir": "res://models/enemies",
        "models": ["enemy_grunt", "enemy_runner", "enemy_tank", "enemy_shield",
                   "enemy_healer", "enemy_splitter", "enemy_miniboss", "enemy_boss"],
        "cols": 4,
        "spacing": 1.75,
        "row_gap": 2.30,
        "stagger": 0.0,
        "dist": 7.0,
        "fov": 42.0,
        "target": (0.0, 0.55, 0.9),
        "ground": "Color(0.20, 0.28, 0.19, 1)",
    },
    "towers": {
        "out": "scenes/_TowerPreview.tscn",
        "dir": "res://models/towers",
        "models": [
            "tower_arrow_l1", "tower_cannon_l1", "tower_frost_l1", "tower_sniper_l1",
            "tower_tesla_l1", "tower_flame_l1", "tower_bounce_l1",
            "tower_arrow_l2", "tower_cannon_l2", "tower_frost_l2", "tower_sniper_l2",
            "tower_tesla_l2", "tower_flame_l2", "tower_bounce_l2",
            "tower_arrow_l3", "tower_cannon_l3", "tower_frost_l3", "tower_sniper_l3",
            "tower_tesla_l3", "tower_flame_l3", "tower_bounce_l3",
            # 变异专属外观：满级炮塔的「双管齐射」
            "tower_cannon_l3_twin",
        ],
        "cols": 7,
        "spacing": 3.20,
        "row_gap": 5.20,
        "stagger": 1.60,
        "dist": 20.0,
        "fov": 40.0,
        "target": (0.0, 2.30, 0.0),
        "ground": "Color(0.22, 0.26, 0.20, 1)",
    },
}

PITCH_DEG = 49.4


def _cross(a, b):
    return [a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]]


def _norm(v):
    ln = math.sqrt(sum(c * c for c in v)) or 1.0
    return [c / ln for c in v]


def _transform3d(col_x, col_y, col_z, origin) -> str:
    """Godot 的 .tscn 把 Transform3D 按 basis 的**行**写：rows[i] = (x[i], y[i], z[i])。"""
    vals = [col_x[0], col_y[0], col_z[0],
            col_x[1], col_y[1], col_z[1],
            col_x[2], col_y[2], col_z[2]] + list(origin)
    return "Transform3D(%s)" % ", ".join("%.4f" % v for v in vals)


def cam_transform(cfg) -> str:
    tx, ty, tz = cfg["target"]
    p = math.radians(PITCH_DEG)
    pos = (tx, ty + math.sin(p) * cfg["dist"], tz + math.cos(p) * cfg["dist"])
    z = _norm([pos[i] - (tx, ty, tz)[i] for i in range(3)])   # 相机看向 -Z
    x = _norm(_cross((0.0, 1.0, 0.0), z))
    y = _cross(z, x)
    return _transform3d(x, y, z, pos)


def sun_transform() -> str:
    """等价于 Main.gd 里 rotation_degrees = (-58, 32, 0) 的主光。"""
    d = _norm([-0.55, -0.72, -0.42])          # 光的传播方向
    z = [-c for c in d]                        # 光沿自身 -Z 照射
    x = _norm(_cross((0.0, 1.0, 0.0), z))
    y = _cross(z, x)
    return _transform3d(x, y, z, (0.0, 12.0, 0.0))


def build(cfg) -> str:
    models = cfg["models"]
    cols = cfg["cols"]
    rows = (len(models) + cols - 1) // cols
    lines = []
    lines.append("[gd_scene load_steps=%d format=3]\n" % (len(models) + 4))
    for i, res in enumerate(models):
        lines.append('[ext_resource type="PackedScene" path="%s/%s.glb" id="%d"]'
                     % (cfg["dir"], res, i + 1))
    lines.append("")
    lines.append('[sub_resource type="PlaneMesh" id="Plane_1"]')
    lines.append("size = Vector2(120, 120)")
    lines.append("")
    lines.append('[sub_resource type="StandardMaterial3D" id="Mat_ground"]')
    lines.append("albedo_color = %s" % cfg["ground"])
    lines.append("roughness = 0.95")
    lines.append("")
    lines.append('[sub_resource type="Environment" id="Env_1"]')
    lines.append("background_mode = 1")
    lines.append("background_color = Color(0.09, 0.11, 0.16, 1)")
    lines.append("ambient_light_source = 2")
    lines.append("ambient_light_color = Color(0.55, 0.60, 0.75, 1)")
    lines.append("ambient_light_energy = 0.12")
    lines.append("")
    lines.append('[node name="ModelPreview" type="Node3D"]')
    lines.append("")
    lines.append('[node name="WorldEnvironment" type="WorldEnvironment" parent="."]')
    lines.append('environment = SubResource("Env_1")')
    lines.append("")
    lines.append('[node name="Sun" type="DirectionalLight3D" parent="."]')
    lines.append("transform = %s" % sun_transform())
    lines.append("light_energy = 0.80")
    lines.append("shadow_enabled = true")
    lines.append("")
    lines.append('[node name="Ground" type="MeshInstance3D" parent="."]')
    lines.append('mesh = SubResource("Plane_1")')
    lines.append('material_override = SubResource("Mat_ground")')
    lines.append("")
    lines.append('[node name="Camera3D" type="Camera3D" parent="."]')
    lines.append("transform = %s" % cam_transform(cfg))
    lines.append("current = true")
    lines.append("fov = %.1f" % cfg["fov"])
    lines.append("")

    for i, res in enumerate(models):
        col = i % cols
        row = i // cols
        x = -cfg["spacing"] * (cols - 1) * 0.5 + col * cfg["spacing"]
        if row % 2 == 1:
            x += cfg["stagger"]
        # 第一排（等级最低）放在离相机最近的一侧，读图时"越往上等级越高"
        z = -((row) - (rows - 1) * 0.5) * cfg["row_gap"]
        lines.append('[node name="%s" parent="." instance=ExtResource("%d")]' % (res, i + 1))
        lines.append("transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, %.3f, 0, %.3f)" % (x, z))
        lines.append("")
    return "\n".join(lines)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--set", default="enemies", choices=sorted(SETS))
    args = ap.parse_args()
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    cfg = SETS[args.set]
    out = os.path.join(root, cfg["out"])
    with open(out, "w", encoding="utf-8", newline="\n") as fh:
        fh.write(build(cfg))
    print("wrote", out)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
