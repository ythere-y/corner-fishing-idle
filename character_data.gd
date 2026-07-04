class_name CharacterData
## 【新增文件】背包客角色数据（纯数据，模式对齐 SpotData/EventData/AchievementData）。
## 玩家首次进入游戏、看完开场故事后，从这里选一个"这次出发在外面的人"。
## 只是人设文案，不影响任何数值/玩法——main.gd 只存一个 character 字段（见 save_system.gd）。

const CHARACTERS := {
	"jim": {
		"name": "Jim",
		"tag": "路痴，但运气好得不科学",
		"blurb": "背包比人还高，地图基本看不明白，可每次迷路都能蹭到一顿当地人请的饭。",
	},
	"ganie": {
		"name": "Ganie",
		"tag": "认路，但从不认输",
		"blurb": "相机挂脖子，小本子写满路线备注，计划永远比实际多绕三个弯，但从不喊累。",
	},
}

## 默认角色（旧档 / 异常兜底用；不代表强制指定，仅防止空字典取值报错）。
const DEFAULT_CHARACTER := "jim"


static func has(id: String) -> bool:
	return CHARACTERS.has(id)


static func get_character(id: String) -> Dictionary:
	return CHARACTERS.get(id, CHARACTERS[DEFAULT_CHARACTER])


static func display_name(id: String) -> String:
	return str(get_character(id).get("name", "TA"))
