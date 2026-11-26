# 场景与建筑物美术

美术分两套，**互不影响**，可以单独换：

1. **3D 模型**（塔 / 地面 / 基地水晶）→ 放在 `res://models/kenney/`，见本文「模型槽位」
2. **贴图**（敌人 / 子弹 / 天空盒）→ 放在 `res://textures/`，见本文「贴图槽位」

---

## 模型槽位（`res://models/kenney/`）

塔、地面、基地现在是 **Kenney Tower Defense Kit 的 GLB 模型**（CC0 免署名），
模型来自 `Models/GLB format/`，全部共享一张调色板贴图 `Textures/colormap.png`。

| 文件 | 用在哪 | 缺了会怎样 |
| --- | --- | --- |
| `tower-round-base.glb` | 所有塔的底座 | 塔直接从地面堆起 |
| `tower-round-bottom-a/b/c.glb` | 塔底层（随等级换造型） | |
| `tower-round-middle-a/b/c.glb` | 塔中层 | |
| `tower-round-top-a/b/c.glb` | 塔上层 | |
| `tower-round-roof-a/b/c.glb` | 塔屋顶（Lv4+ 才装） | |
| `tower-round-crystals.glb` | 塔顶水晶（Lv5 装饰） | |
| `weapon-ballista.glb` | 箭塔顶武器 | |
| `weapon-cannon.glb` | 炮塔顶武器 | |
| `weapon-turret.glb` | 冰塔顶武器 | |
| `tile.glb` | 可建造区的草地瓦片 | |
| `tile-rock.glb` | 外圈刷怪环的岩石瓦片 | |
| `tile-tree.glb` | 棋盘四角的树 | |
| `detail-crystal-large.glb` | 左侧基地的水晶 | |

**规则**：

- 三种塔靠「顶部武器 + 整体色调」区分：箭塔原色、炮塔偏橙、冰塔偏蓝（`Tower.KIND_TINT`）。
- 5 个等级靠「部件造型 a→b→c + 是否装屋顶/水晶」区分（`Tower.LVL_PARTS`）。
- 部件的堆叠高度是**运行时用 AABB 算出来的**，所以替换成任意 GLB 都能自动对齐，不用改代码。
- 加模型后**要让 Godot 导入一次**（打开编辑器，或命令行 `--import`）。
- 想换成别的模型：只要保持文件名不变（或改 `ModelLib.DIR` 与对应引用），任何 GLB 都能用。

### 敌人模型（可选，`res://models/enemies/`）

新建这个目录，把 GLB 按下面的名字丢进去，敌人就会用模型替换掉程序化几何：

| 文件 | 用在哪 |
| --- | --- |
| `enemy_grunt.glb` | 小兵 |
| `enemy_runner.glb` | 疾行者 |
| `enemy_tank.glb` | 重甲 |
| `enemy_boss.glb` | 首领 |
| `enemy_flyer.glb` | 飞行怪 |
| `enemy_shield.glb` | 护盾怪 |

- 尺寸随便：`Enemy._build_custom_body()` 会按**目标身高自动缩放**、底部贴地、水平居中。
- 模型朝向：默认朝 **+Z**（Godot 前向是 -Z，这里按「模型正面朝 +Z」对齐，和程序化敌人一致）。
- 隐身怪（`cloak`）仍用程序化外观，因为它要靠材质透明度做隐身效果。

> 想要更多部件（UFO 敌人、雪地变体、木结构等）：去 `kenney.nl` 下载完整包，
> 把 GLB 直接丢进 `res://models/kenney/` 即可，导入方式相同。

---

## 贴图槽位（`res://textures/`）

敌人、子弹仍是程序化几何体，靠贴图换皮；文件名对上槽位就自动生效，
**没放图的槽位自动回退到纯色外观**。支持 `png / jpg / webp / svg / bmp / tga`。
槽位清单以 `TextureLib.SLOTS` 为准，游戏启动时控制台会打印一次「还缺哪些槽位」。

| 文件名 | 用在哪 | 建议尺寸 | 备注 |
| --- | --- | --- | --- |
| `sky.png` | 天空盒 | 2048×1024 | 等距柱状（Equirectangular）全景图 |
| `path.png` | 敌人土路路面 | 256×256 | **必须无缝平铺**，俯视看是棕色泥土/碎石 |
| `spawn_pad.png` | 出生踏板 | 128×128 | 转盘/箭头类图案，中心对称 |
| `bullet.png` | 子弹 | 64×64 | 亮色，最好有发光核心 |
| `bullet_stone.png` | 炮塔的石弹 | 32×32 ~ 64×64 | **要带透明通道**，billboard 方片贴到路上；斜俯视看着像一块石头 |
| `fx_explosion.png` | 炮塔命中的爆炸 | 128×64 | **要带透明通道**，烟 + 火花；放大淡出用，四周留点空隙别切边 |
| `fx_explosion_l2.png` | 二级及以上炮塔命中的爆炸 | 128×96 | **要带透明通道**，碎石 + 浓烟 + 火花；没有这张图时自动回退到 `fx_explosion.png` |
| `fx_siege_0.png` … `fx_siege_8.png` | 变异「攻城巨炮」命中的爆炸（序列帧） | 128×112（9 张同尺寸） | **要带透明通道**，按 0→8 顺序播放：落石 → 聚拢 → 爆燃；缺帧会自动跳过，整组缺失则回退到 `fx_explosion_l2.png` |
| `fx_mud_0.png` … `fx_mud_6.png` | 变异「震地雷」的泥潭（序列帧） | 128×96（7 张同尺寸） | **要带透明通道**，俯视看是一滩冒泡的泥浆，平铺在地面上，1.5 秒内正好播完一遍再淡出；整组缺失时回退成半透明泥色圆盘 |
| `fx_ice_0.png` / `fx_ice_1.png` | 冰塔冰冻射线命中时的碎冰（序列帧） | 64×48（2 张同尺寸） | **要带透明通道**，冰晶 + 冰渣炸开的一小团，0.3 秒内按 0→1 播完；整组缺失时回退成冰蓝闪光 + 冲击环 |
| `fx_frost_fog.png` | 变异「霜环」铺满射程的冰雾 | 256×256（正方形） | **要带透明通道**，雾团居中、四周透明：这张图会被贴在一个圆盘上（UV 缩放后铺满整圈），形状由网格顶点 alpha 决定，所以贴图本身只要「中间亮、边缘软」即可；缺失时退化成半透明淡蓝雾圈 |
| `enemy_grunt.png` | 小兵 | 128×128 | |
| `enemy_runner.png` | 疾行者 | 128×128 | |
| `enemy_tank.png` | 重甲 | 128×128 | |
| `enemy_boss.png` | 首领 | 256×256 | |
| `enemy_flyer.png` | 飞行怪 | 128×128 | |
| `enemy_shield.png` | 护盾怪 | 128×128 | |
| `enemy_frostling.png` | 霜崽（冰原小怪） | 128×128 | **已停用**：霜崽改成程序化 3D 造型（`scripts/FrostlingModel.gd`），这张 png 只作设计参考 |

> 敌人贴图是直接包在球体/立方体上的，**没有 UV 展开**：图案会被拉伸。
> 所以适合「对称、无方向性」的图案（图腾、脸、条纹、能量纹），不适合写实照片。

---

## 什么样的素材适合这个工程

**模型（GLB）**

- 格式：`.glb`（Godot 4 原生导入）；`.fbx / .obj` 需要先转成 GLB。
- 尺寸：按 **1×1 单位足迹、原点在模型底部中心、Y 轴向上** 建模最省事；
  本工程用 `ModelLib.SCALE = 2.0` 把 1 单位放大到 2 米的格子。
- 材质：**单个材质 / 一张调色板贴图**最好——`MultiMesh` 批处理与 `ModelLib.tint()` 都依赖它。
- 面数：塔 500~2000 tris、敌人 < 1000、地面瓦片 < 200，低多边形风格与现有 Kenney 资源一致。
- 高度不用管：塔身部件堆叠是运行时按 AABB 算的，换成任意 GLB 都会自动对齐。

**贴图（PNG / JPG）**

- 尺寸取 2 的幂（64 / 128 / 256 / 512 / 1024），文件尽量 < 512 KB。
- 颜色别太白：工程开了 Glow + 自发光，纯白容易糊成一片。
- 地面 / 路面类必须**无缝平铺**（tileable）。

---

## 去哪里找（免费可商用）

| 站点 | 内容 | 许可证 | 备注 |
| --- | --- | --- | --- |
| [kenney.nl](https://kenney.nl/assets) | 3D 模型 / UI / 音效 | **CC0** | 本工程现用的 Tower Defense Kit 就来自这里，风格最统一 |
| [quaternius.com](https://quaternius.com) | 低多边形角色 / 怪物 / 建筑 | **CC0** | 和 Kenney 混用几乎无违和 |
| [poly.pizza](https://poly.pizza) | 模型搜索聚合 | CC0 / CC-BY | 搜索时按许可证筛选，直接下 GLB |
| [opengameart.org](https://opengameart.org) | 2D / 3D / 音效 | 混合，可筛 CC0 | 老资源多，风格要挑 |
| [sketchfab.com](https://sketchfab.com) | 高质量模型 | 勾 Downloadable + CC0/CC-BY | 面数常偏高，需减面 |
| [ambientcg.com](https://ambientcg.com) | PBR 贴图 | **CC0** | 找泥土 / 草地 / 岩石，导出 1K PNG |
| [polyhaven.com](https://polyhaven.com/textures) | HDRI + PBR 贴图 | **CC0** | 天空盒可下 2K 全景图 |
| [game-icons.net](https://game-icons.net) | 图标 | **CC-BY 3.0** | 做 UI 图标用，需署名 |

> 许可证纪律：**CC0** 随便用；**CC-BY** 必须在 README / 报告里署名作者与出处；
> 标 «Non-Commercial / Editorial» 的资源不要用。

---

## 替换流程（3 步）

1. 放文件到位：GLB → `res://models/kenney/`（文件名与上表一致），贴图 → `res://textures/`。
2. 切回 Godot 编辑器一次让它生成 `.import`（或命令行 `godot --headless --import`）。
3. F5 运行，看输出面板：
   - `[TextureLib] 还缺 N 个槽位: ...` → 还能补哪些图
   - `[ModelLib] 找不到模型 xxx` → 文件名 / 路径不对
   - 模型比例不对：先调 `ModelLib.SCALE`，或给实例套一层 `Node3D` 做缩放 / 位移

---

## 注意事项

1. **丢完素材要切回 Godot 编辑器**让它导入一次（或命令行 `--import`）。
   否则运行时 `load()` 拿不到资源——这是 Godot 的机制，不是 bug。
2. 贴图会被当作**反照率（Albedo）**使用，放了贴图的部件会自动把自发光调弱。
3. 想换回程序化外观：把文件删掉或改名即可。
4. 交作业前在报告里写清素材来源与许可证：Kenney 是 **CC0**，无需署名。
