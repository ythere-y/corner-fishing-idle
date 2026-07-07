# 十站海港主视觉概念图（废弃海港方向）

> 用途：为「背包钓鱼手记」十个钓点提供统一的主视觉概念图，作为场景绘制（`scene_painter.gd`）与美术接入的视觉锚点。
> 风格方向：**废弃海港（Abandoned Harbor）**——静谧、微忧郁的旅途叙事，画意像素（painterly pixel）。
> 图片位置：`docs/img/harbor_concepts/`
> 状态：概念稿（concept），非最终游戏内资产。程序车道接入时以 `bg_key` 对齐。

---

## 风格锚点

- **色板**：低饱和青绿（muted teal）+ 琥珀暖光（amber）为主，冷底暖点，营造黄昏／清晨的孤旅感。
- **笔触**：画意像素——保留像素颗粒，但用柔和的笔刷式过渡处理天光与水面反射。
- **氛围**：每一站都是旅人途经的一处“废弃／半废弃”的水边站点，安静、有故事感，避免喧闹与饱和的卡通感。
- **叙事**：十站串成一条由家门口河湾 → 出海 → 深海 → 极地 → 溶洞的旅程线，视觉上从温暖熟悉逐步走向陌生、清冷、幽深。

---

## 十站对照表

| # | 概念图 | `bg_key` | 站点（spot_data.gd） | 视觉基调 |
|---|--------|----------|----------------------|----------|
| 01 | `harbor_concepts/01_river_bend_河湾港.jpg` | `river_bend` | 第1站 · 中国 · 家门口河湾 | 温暖黄昏、熟悉、旅程起点 |
| 02 | `harbor_concepts/02_still_lake_冬泊港.jpg` | `still_lake` | 冬泊 · 静湖 | 清冷、静水如镜 |
| 03 | `harbor_concepts/03_mountain_stream_雪溪港.jpg` | `mountain_stream` | 第3站 · 中国 · 雪线溪谷 | 高原冷冽、透亮溪流 |
| 04 | `harbor_concepts/04_urban_pond_进城港.jpg` | `urban_pond` | 进城 · 都市水塘 | 都市边缘、人工与自然交界 |
| 05 | `harbor_concepts/05_coast_pier_出海港.jpg` | `coast_pier` | 第5站 · 菲律宾 · 出海码头 | 咸腥海风、栈桥灯火 |
| 06 | `harbor_concepts/06_estuary_红树港.jpg` | `estuary` | 河口 · 红树林 | 半咸水、湿热、根系交错 |
| 07 | `harbor_concepts/07_deep_sea_深海港.jpg` | `deep_sea` | 第7站 · 新西兰 · 租船出深海 | 深蓝、开阔、未知 |
| 08 | `harbor_concepts/08_coral_reef_珊瑚港.jpg` | `coral_reef` | 珊瑚礁 | 斑斓但克制、水下光斑 |
| 09 | `harbor_concepts/09_polar_lake_极地港.jpg` | `polar_lake` | 极地湖 | 极寒、冰蓝、极简 |
| 10 | `harbor_concepts/10_cavern_pool_溶洞港.jpg` | `cavern_pool` | 溶洞潭 | 幽深、微光、终点的静谧 |

---

## 接入说明（给程序车道）

- 这些图为**概念稿**，用于统一场景绘制的色调与构图意图，不直接作为运行时背景导入（运行时背景仍由 `scene_painter.gd` 程序化绘制，缺图自动回退河湾主图）。
- 若后续决定改为图片背景，游戏内背景应放 `assets/art/bg/<bg_key>.png`，由程序按 `spot_data.gd` 的 `bg_key` 加载。
- 拉到新美术资源后先 `godot --headless --import` 再运行，否则看不到新图。

---

_概念图由视觉总监整理，风格方向见根目录 `docs/art_direction.md`。_
