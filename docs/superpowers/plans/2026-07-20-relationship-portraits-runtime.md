# Relationship Portraits Runtime Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the river-bend relationship UI's color-only placeholders with the five existing watercolor NPC images in the visit HUD, relationship book, and visit panel.

**Architecture:** Add portrait paths to NPC data and introduce a focused `RelationshipPortrait` helper that owns loading, sizing, circular masking, theme-color framing, and fallback behavior. `main.gd` and `ui_panels.gd` consume the helper without duplicating crop logic.

**Tech Stack:** Godot 4.6, GDScript, `TextureRect`, `ShaderMaterial`, the existing headless validator and screenshot harness.

## Global Constraints

- Use the five existing 1254×1254 RGBA files under `assets/art/character/npc/`; do not edit or regenerate them.
- HUD uses circular framed portraits, the relationship book uses 72 px card portraits, and visit headers use a 144 px transparent hero portrait.
- Missing or invalid resources fall back to the existing colored shape without returning an empty control.
- Do not change relationship progression, visit scheduling, rewards, save version, or gameplay values.
- Validation must report `0 失败`; visual changes require `tools/dev_screenshot.gd`.

---

## File Structure

- Create `relationship_portrait.gd`: portrait loading and presentation.
- Modify `relationship_data.gd`: explicit runtime portrait paths.
- Modify `main.gd`: circular portraits in right-side visit buttons.
- Modify `ui_panels.gd`: card and hero portraits.
- Modify `tools/validate_game.gd`: resource, mode, fallback, and UI structure assertions.
- Modify `tools/dev_screenshot.gd`: fixtures for all three portrait levels.
- Modify `README.md`, `ROADMAP.md`, `BACKLOG.md`, and `docs/three-spot-linkage-design-huchao.md`: runtime truth.
- Regenerate the four existing relationship screenshots.

### Task 1: Portrait data truth and safe helper

**Files:**
- Create: `relationship_portrait.gd`
- Modify: `relationship_data.gd:85-113`
- Modify: `tools/validate_game.gd:1215-1240`

**Interfaces:**
- Produces: `RelationshipPortrait.texture_for(npc: Dictionary) -> Texture2D`
- Produces: `RelationshipPortrait.make(npc: Dictionary, mode: String) -> Control`
- Supported modes: `circle`, `card`, `hero`

- [ ] **Step 1: Write failing resource and fallback assertions**

Preload the helper and add to `_check_relationship_foundation()`:

```gdscript
const RelationshipPortraitScript := preload("res://relationship_portrait.gd")

for npc_data in RelationshipDataScript.NPCS:
	var portrait_path := str(npc_data.get("portrait", ""))
	_assert(portrait_path.begins_with("res://assets/art/character/npc/") \
		and ResourceLoader.exists(portrait_path),
		"每位河湾 NPC 应配置可加载的运行时头像")
	_assert(RelationshipPortraitScript.texture_for(npc_data) != null,
		"每位河湾 NPC 的头像应加载为纹理")
var fallback := RelationshipPortraitScript.make({"color": Color("C98472")}, "circle")
_assert(fallback != null and fallback.custom_minimum_size == Vector2(40, 40),
	"头像缺失时应返回可见的主题色回退控件")
fallback.free()
```

- [ ] **Step 2: Run validation and confirm RED**

Run `/Applications/Godot.app/Contents/MacOS/Godot --headless -s tools/validate_game.gd`.

Expected: compile or assertion failure because the helper and `portrait` fields do not exist.

- [ ] **Step 3: Add explicit portrait paths**

Add each exact `res://assets/art/character/npc/<id>.png` path to its corresponding NPC. The Zhou entry uses `zhou_uncle.png`; the other filenames match their ids.

- [ ] **Step 4: Implement the focused helper**

Create `class_name RelationshipPortrait`. `texture_for()` checks `ResourceLoader.exists()`, loads the resource, and returns it only when it is a `Texture2D`. `make()` returns a fixed-size container for these exact sizes:

```gdscript
const MODE_SIZES := {
	"circle": Vector2(40, 40),
	"card": Vector2(72, 72),
	"hero": Vector2(144, 144),
}
```

It adds a theme-colored `StyleBoxFlat` background and a `TextureRect` when loading succeeds. Circle mode uses a cached canvas-item shader that masks pixels outside `distance(UV, vec2(0.5)) <= 0.5`; card and hero retain native transparency. Texture nodes use `EXPAND_IGNORE_SIZE` and aspect-preserving stretch modes. Missing textures leave the themed background visible.

- [ ] **Step 5: Run validation and confirm GREEN**

Expected: the new assertions pass and the complete suite reports `0 失败`.

- [ ] **Step 6: Commit**

```bash
git add relationship_data.gd relationship_portrait.gd tools/validate_game.gd
git commit -m "接入河湾人物头像资源真值" -m "Co-Authored-By: GPT-5 Codex <noreply@openai.com>"
```

### Task 2: Replace all three runtime placeholder levels

**Files:**
- Modify: `main.gd:1313-1356`
- Modify: `ui_panels.gd:503-650`
- Modify: `tools/validate_game.gd:1215-1300`

**Interfaces:**
- Consumes: `RelationshipPortrait.make(npc, mode)`.
- Produces named controls: `RelationshipPortraitCircle`, `RelationshipPortraitCard`, `RelationshipPortraitHero`.

- [ ] **Step 1: Add failing UI structure assertions**

After generating visits, rebuild the visit bar, open the relationship tab and open Lin Aunt's visit panel. Assert each named control can be found recursively:

```gdscript
g._update_relationship_visit_bar()
_assert(g._relationship_visit_bar.find_child("RelationshipPortraitCircle", true, false) != null,
	"右侧到访入口应使用圆形人物头像")
g._catch_tab = 9
g._open_panel("catch")
await process_frame
_assert(g._panel.find_child("RelationshipPortraitCard", true, false) != null,
	"人情簿应使用人物卡片头像")
g.selected_relationship_visit_id = "lin_aunt"
g._open_panel("relationship_visit")
await process_frame
_assert(g._panel.find_child("RelationshipPortraitHero", true, false) != null,
	"到访面板应使用透明人物立绘")
```

- [ ] **Step 2: Run validation and confirm RED**

Expected: all three named controls are absent because the UI still creates `ColorRect` placeholders.

- [ ] **Step 3: Replace the right-side placeholder**

Preload the helper in `main.gd`. Keep the existing button, tooltip, click behavior, and hover/pressed styles. Increase the button to 42×42, center `make(npc, "circle")` as its child, disable the child's mouse filtering, and name it `RelationshipPortraitCircle`.

- [ ] **Step 4: Replace book and visit placeholders**

Preload the helper in `ui_panels.gd`. Replace the book's `ColorRect` with `make(npc, "card")`, named `RelationshipPortraitCard`. Replace the visit header's `ColorRect` with `make(npc, "hero")`, named `RelationshipPortraitHero`. Preserve the right-side text containers and all lower interaction content.

- [ ] **Step 5: Run validation and confirm GREEN**

Expected: all structure assertions pass and the suite reports `0 失败`.

- [ ] **Step 6: Commit**

```bash
git add main.gd ui_panels.gd tools/validate_game.gd
git commit -m "在河湾人情界面展示人物头像" -m "Co-Authored-By: GPT-5 Codex <noreply@openai.com>"
```

### Task 3: Visual QA and project truth synchronization

**Files:**
- Modify: `tools/dev_screenshot.gd:80-125`
- Modify: `README.md`
- Modify: `ROADMAP.md`
- Modify: `BACKLOG.md`
- Modify: `docs/three-spot-linkage-design-huchao.md`
- Update: `docs/img/panel_relations.png`
- Update: `docs/img/panel_relationship_visit.png`
- Update: `docs/img/panel_relationship_buff.png`
- Update: `docs/img/panel_relationship_finale.png`

**Interfaces:**
- Consumes the completed three-level portrait UI.
- Produces reviewable screenshots and documentation that no longer describes pure-color runtime placeholders.

- [ ] **Step 1: Confirm screenshot fixtures exercise every level**

Keep at least three simultaneous visits for the HUD, all five book cards, a Lin Aunt story, a Tang buff, and a Ma finale. Add no gameplay-only test hooks.

- [ ] **Step 2: Generate screenshots**

Run `/Applications/Godot.app/Contents/MacOS/Godot --path . -s tools/dev_screenshot.gd`.

Expected: relationship screenshots regenerate without script errors.

- [ ] **Step 3: Inspect all four screenshots**

Check recognizable portraits, intact aspect ratios, visible theme frames, unobscured text, and an unobstructed delivery grid. If the hero makes text too narrow, reduce compact hero mode to 128×128 rather than changing the panel or gameplay layout.

- [ ] **Step 4: Synchronize project truth**

Update all four truth documents to say the five portraits are used in the HUD, book, and visit panel with a theme-color fallback. Remove pure-color runtime wording. Add a dated BACKLOG decision explaining the layered B presentation.

- [ ] **Step 5: Run final verification**

```bash
/Applications/Godot.app/Contents/MacOS/Godot --headless -s tools/validate_game.gd
git diff --check
git status --short
```

Expected: `0 失败`, no whitespace errors, and only explicit portrait implementation, screenshots, and documentation changes.

- [ ] **Step 6: Commit**

```bash
git add tools/dev_screenshot.gd README.md ROADMAP.md BACKLOG.md docs/three-spot-linkage-design-huchao.md docs/img/panel_relations.png docs/img/panel_relationship_visit.png docs/img/panel_relationship_buff.png docs/img/panel_relationship_finale.png
git commit -m "同步河湾人物头像视觉与文档" -m "Co-Authored-By: GPT-5 Codex <noreply@openai.com>"
```

