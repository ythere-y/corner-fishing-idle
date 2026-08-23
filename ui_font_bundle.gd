class_name UIFontBundle
extends RefCounted

## Web 不能读取系统字体：用随包中文字体为主，符号与 Emoji 依次回退。
const PRIMARY_PATH := "res://assets/fonts/NotoSerifSC-Bold.woff2"
const FALLBACK_PATHS := [
	"res://assets/fonts/NotoSerifCJKsc-Fish-Subset.otf",
	"res://assets/fonts/NotoSansSymbols2-Regular.ttf",
	"res://assets/fonts/NotoColorEmoji-UI-Subset.ttf",
]


static func load_font() -> Font:
	var primary: Font = load(PRIMARY_PATH)
	if primary == null:
		return ThemeDB.fallback_font
	var fallbacks: Array[Font] = []
	for path in FALLBACK_PATHS:
		var fallback: Font = load(path)
		if fallback != null:
			fallbacks.append(fallback)
	primary.fallbacks = fallbacks
	return primary
