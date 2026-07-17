# 河湾人情 NPC 头像生成规范

> 用途：五位固定 NPC 的运行时头像候选。透明成品位于
> `assets/art/character/npc/`，色键源稿位于其 `source/` 子目录。

## 统一媒介

- 低饱和中国编辑插画式水彩，保留纸张颗粒、颜料晕染与少量淡墨线。
- 漫画动作和轮廓优先于写实肖像；在 30-64px 下先认出姿态和形状，再看道具。
- 只统一媒介与质量，不统一机位、头肩比例、脸型、重心或姿势。
- 单人、方形画布、主体完整、有安全边距；不生成文字、边框、徽章、场景或投影。
- 色键背景必须完全纯色。绿色角色改用洋红色键，其余默认 `#00ff00`。

## 角色形状语言

| NPC | 形状与重心 | 动作 | 个人色 |
|---|---|---|---|
| 林阿姨 | 圆形、低重心、云朵卷发 | 双手把巨大热茶杯递向镜头，蒸汽环绕 | `#C98472` |
| 周叔 | 针形、三角、极细长 | 身体后仰控制画外大鱼，手臂与鱼竿形成强对角 | `#6F8EA3` |
| 阿棠 | 楔形、钩形、宽三角 | 俯身拍案，算盘和空白票据形成爆发线 | `#C49A50` |
| 小满 | 叶片、雨滴、侧向 C 形 | 深蹲观察水面线索，一边放大观察一边速记 | `#76A68A` |
| 马会长 | 新月、螺旋、横向 S 形 | 背身大步离场并回头招手，围巾与旅行签飞扬 | `#9075A6` |

## 通用 Prompt 骨架

```text
Draw <NPC> in an exaggerated ACTION POSE for a 30-64px game avatar.
Use bold Chinese editorial watercolor cartoon, expressive ink accents,
visible pigment blooms and low-saturation personal colors.

The character must be driven by <shape language>, <center of gravity>,
<camera angle> and <action>. Props only support the action.
Avoid upright headshots, neutral poses, generic oval faces, realistic studio
portraits, anime, glossy mobile-game rendering and fantasy costumes.

Use a perfectly flat solid chroma-key background with no scenery, shadow,
gradient, halo, text, border or watermark.
```

## 当前候选

- `lin_aunt.png`：递出热茶的圆形近景。
- `zhou_uncle.png`：后仰控竿的细长对角构图。
- `tang.png`：拍案结算的宽三角构图。
- `xiaoman.png`：蹲姿观察的叶片构图。
- `ma.png`：回头招手离场的横向运动构图。

当前文件是美术候选，尚未替换人情簿中的纯色占位头像。
