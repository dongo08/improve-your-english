# improve your English

背单词小游戏（Godot 4.7）。三种玩法、pp 实力值、联机对战、在线账号。

## 玩法与 pp

| 玩法 | 规则 | 单场 pp |
| --- | --- | --- |
| 英汉配对 | 30 对，60 秒内点英文 + 对应中文 | 初级 50 / 中级 100 / 高级 300，按 `(有效/30)²` |
| 快问快答 | 60 秒，一直出题 | 60 题 = 200pp，按 `(有效/60)²`，超过 60 题继续涨 |
| 快速拼写 | 60 秒，看中文拼英文 | 拼对 20 个拿满 150，按 `(有效/20)²` |

- **有效 = 做对 − 做错**，不低于 0（配错/答错一个等于少一个词）。
- **总 pp** 取历史最高的 100 场，按 `0.95^i` 递减加权求和（osu 的算法）。
- 英汉配对的难度配比：
  - 初级：100% 初级词
  - 中级：50% 中级 + 50% 初级
  - 高级：50% 高级 + 25% 初级 + 25% 中级

## 词库

词库来自根目录的 3000 词 xlsx 与原 `assets/gaozhong.tres` 合并，生成 `assets/wordbook.tres`：

当前 **4129 词 / 24936 条词义**，其中初级 1537、中级 478、高级 2114。

等级映射：

| xlsx「类型」 | 等级 |
| --- | --- |
| 初中 | 初级 |
| `*` | 中级 |
| `**` | 高级 |
| 原词库里表格没有的词 | 高级 |

重新生成词库（xlsx 更新后跑这两步）：

```bash
# 1. 解析 xlsx（需要 openpyxl）
python tools/import_words.py
# 2. 合并进词库（Godot 4.7 的 headless 模式）
godot --headless --path . res://tools/build_wordbook.tscn
# 可选：检查结果
godot --headless --path . res://tools/verify_wordbook.tscn
```

- 解析脚本会处理脏数据：Excel 自动转成布尔值的 `false`、括号里的另一种拼写（`criticise(criticize)`）、`a.&ad.` 这类合并词性、全角标点、多余空格。
- 合并时同一个词（不分大小写，含括号别名）只保留一条，重复的只补新词义，并顺手去掉完全相同的词义。

## 存档

存档在 `user://players.json`（Windows 下是 `%APPDATA%\Godot\app_userdata\improve your English\players.json`），schema 版本 2。
首次启动会自动把旧的 `user://data.tres` 迁移过来，旧文件保留不动。

```json
{
  "schema": 2,
  "saved_unix": 1792765203.5,
  "accounts": [
    {
      "id": "小明",
      "is_formal": false,
      "score": 142,
      "total_score": 980,
      "total_pp": 156.53,
      "stamina": 240.0,
      "max_stamina": 240,
      "last_stamina_recovery_unix": 1792321350.5,
      "bag": [{ "path": "res://assets/items/name_change_card.tres", "count": 1 }],
      "plays": [
        {
          "game": 0,
          "level": 2,
          "mode": "local",
          "unix": 1792765915.1,
          "duration": 60.3,
          "score": 142,
          "pp": 192.0,
          "correct": 27,
          "wrong": 3,
          "total": 30,
          "effective": 24,
          "words": [{ "en": "abandon", "zh": "vt.舍弃…", "result": "correct" }]
        }
      ]
    }
  ]
}
```

- `plays` 保存每一次游玩：模式、难度、时间、时长、得分、pp、对错数、逐词结果。
- `total_pp` 不直接信任存档里的值，读档时用 `plays` 重算。
- 相关代码：`script/data/play_record.gd`、`script/pp/pp_system.gd`、`script/account.gd`、`script/global/account_manager.gd`。

## 在线模式

账号、积分、pp、游玩记录都存在服务端，换台电脑登录同一个账号就能接着玩。

### 启动服务端

Windows 下直接双击项目根目录的 **`start_server.bat`**：自动找 Godot、检查端口、打印局域网地址、启动服务端并打开面板。配置在 `server/server.cfg`。

手动启动：

```bash
godot --headless --path . res://server/server_main.tscn -- --port=9000 --data=user://server/accounts.json
```

- `--port` 监听端口，默认 9000；`--data` 账号数据文件。
- 服务端用 TCP + 一行一个 JSON 通信，协议见 `server/account_server.gd` 顶部注释。
- 密码用随机盐 + SHA-256 存哈希；上传存档时服务端会用 `plays` 重算积分和总 pp，客户端改数没用。
- 自带只读网页面板：`http://127.0.0.1:8080/`，看账号、pp 排行、最近战绩；加 `--admin-password=xxx` 可对外访问并要求密码。见 [server/README.md](server/README.md)。
- 更详细的部署说明见 [server/README.md](server/README.md)。

### 客户端

主界面「在线模式」→ 填服务器地址、端口、用户名、密码 → 注册或登录。
登录后主界面右上角会显示「（在线）」，之后每次保存都会自动上传。

## 目录

```
scenes/
  games/            三种玩法与结算场景
  multiplayer/      联机大厅与实时排名
  online/           在线模式登录
  menu/             设置弹窗、背包等
script/
  word/             词条、词义、词库资源
  data/             游玩记录
  pp/               pp 计算
  online/           在线服务端客户端
  global/           Global / AccountManager / NetworkManager / DateHelper
server/             独立账号服务端（server.cfg 配置、web 面板）
start_server.bat    Windows 一键启动服务端
tools/              词库导入与合并、自检
tests/              自动化测试与截图工具
assets/             wordbook.tres（合并后的词库）等
```

## 开发与测试

```bash
# 单元测试：词库等级、pp 公式、JSON 往返
godot --headless --path . res://tests/systems_test.tscn

# 玩法统计：配对、快问快答、拼写
godot --headless --path . res://tests/game_test.tscn

# 结算链路：真实加载 answer_area，检查 pp / 逐词记录 / 存档
godot --headless --path . res://tests/session_test.tscn

# 联机对战（两个进程，先房主后客户端）
godot --headless --path . res://tests/mp_test.tscn -- --host
godot --headless --path . res://tests/mp_test.tscn -- --join

# 联机完整流程（大厅 → 开局 → 结算 → 重开）
godot --headless --path . res://tests/flow_test.tscn -- --host
godot --headless --path . res://tests/flow_test.tscn -- --join

# 在线模式（先起服务端再跑客户端测试）
godot --headless --path . res://server/server_main.tscn -- --port=47653 --data=user://server/test_accounts.json
godot --headless --path . res://tests/online_test.tscn -- --port=47653

# 截图（需要图形界面）
godot --path . res://tests/shot.tscn -- --settings
```

> 选端口时注意：如果某端口已被别的程序绑定在 `127.0.0.1`，Windows 下它会优先于 `0.0.0.0`，客户端会连到别的程序上。测试脚本用独立端口就是为了避开这种情况。
