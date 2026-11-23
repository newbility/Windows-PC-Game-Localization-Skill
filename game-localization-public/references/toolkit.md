# 共享工具库与项目配置

公开技能与面向维护者的项目使用相同的工具库约定。Windows 项目可使用随技能提供的 [Toolkit.ps1](../scripts/Toolkit.ps1)，支持 Windows PowerShell 5.1 和 PowerShell 7。项目公开交接时，将验证过的入口随仓库分发并在开发说明中给出实际位置。其他平台可沿用三层配置和校验原则，使用项目验证过的入口。

| 范围 | 保存内容 |
|---|---|
| 本机共享配置 | 只记录工具库位置，默认保存为 `%LOCALAPPDATA%\game-localization\toolkit.json`。 |
| 项目本地配置 | 记录当前电脑的游戏安装目录等本地参数，通过项目自己的入口设置并由版本控制忽略。 |
| 项目公开锁文件 | 记录构建所需的依赖版本、来源、许可证、相对安装路径和文件 SHA-256。游戏原版版本和文件指纹可单独记录。 |

## 初始化与使用

首次使用时，让使用者选工具库位置，或采用默认位置 `%LOCALAPPDATA%\game-localization\toolkit`。已有工具库可直接选它的根目录。初始化脚本检查并按需建立 `tools/`、`profiles/`、`assets/` 和 `cache/`，保存路径。新电脑首次初始化后得到基础目录。项目锁确定后才准备项目实际需要的依赖。

下例从技能根目录运行，`$lock` 指向具体项目的锁文件。项目复制入口后，在其开发说明中使用实际路径。

```powershell
# 使用默认目录，或登记团队已有工具库
& ./scripts/Toolkit.ps1 init
# & ./scripts/Toolkit.ps1 init -ToolkitRoot 'D:\汉化工具库'

# 按项目锁复用或补齐依赖，然后校验
$lock = 'D:\汉化项目\toolchain.lock.json'
& ./scripts/Toolkit.ps1 prepare -LockFile $lock
& ./scripts/Toolkit.ps1 verify -LockFile $lock

# 已取得锁定的归档或单文件时，可从指定目录离线准备
& ./scripts/Toolkit.ps1 prepare -LockFile $lock -PackageDirectory ./downloads -Offline
```

`-ToolkitRoot` 可覆盖一次调用的工具根目录，只有 `init` 写入配置。`-ConfigPath` 可在测试时指定独立配置文件。三个操作返回工具库的实际位置，项目构建入口可读取结果的 `ToolkitRoot`。项目构建前使用 `verify`，将工具路径从已校验的库根目录和锁文件计算出来。

`prepare` 先校验已存在的依赖，优先从明确指定的文件目录导入缺项，其次在允许联网时从锁文件所列 HTTPS 地址取得。归档必须先通过 SHA-256 校验，脚本只安装锁文件列出的 ZIP 成员或指定单文件，核对安装后的文件再放到版本目录。已有目录若缺文件或哈希不符，报告冲突并保留原目录。换用经核对的版本目录或由维护者检查冲突来源。`verify` 只读取文件，两个操作都无需调整全局 PATH 或修改已有工具。

## 锁文件约定

JSON 根对象包含 `schema`，取数值 `1`，以及 `dependencies` 数组。每个依赖用下列字段描述。清单要覆盖实际构建用到的可执行文件、加载的库和必要数据。

| 字段 | 写法 |
|---|---|
| `id`、`version` | 工具标识与已验证的版本字符串。 |
| `directory` | 工具库相对目录，使用正斜杠，位于 `tools/`、`profiles/` 或 `assets/` 下。不同版本使用独立目录。目录内结构匹配已有库时可直接复用。 |
| `license` | 项目核对过的许可证名称或说明。 |
| `files` | 至少一个 `path`、`sha256` 对象。路径相对于该依赖的 `directory`。SHA-256 为 64 位十六进制字符串。 |
| `source` | 可选对象，包含 `format`（`zip` 或 `file`）、`filename`、原始包 `sha256` 和可选的 HTTPS `url`。ZIP 中的成员名与 `files[].path` 对应，单文件只列一条。省略下载来源时，在项目说明给出可取得相同依赖的方式。已有目录仍按文件哈希校验。 |

运行时组合、宿主编译器或只能通过厂商安装器取得的依赖，可以保留项目的安装说明和验证逻辑。按项目记录依赖准备方式和适用环境。迁移已有项目时另建并验证公开锁，先核对旧目录里的版本和字节，避免替换其他项目正在用的档案。
