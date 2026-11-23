# Windows PC 游戏简体中文汉化技能

`game-localization-public` 为 Windows PC 游戏的简体中文汉化提供项目工作流，涵盖开工检索、内容盘点、排版预检、分批初译校对、隔离实机测试和安装包构建。

- **简化版发布**交付玩家安装包、SHA-256、使用说明和实机截图。仅要求上传到 GitHub 时，默认使用此模式。
- **开发版发布**同时提供可接手的译文、源码、依赖锁和开发说明。上传前验证维护者能在干净环境中修改译文、构建、安装和恢复。验收成功后清理本次创建的临时验收目录。

## 安装和使用

下载或克隆本仓库，把整个 [`game-localization-public` 目录](game-localization-public/) 放进客户端的技能目录。保留其中的 `SKILL.md`、`references/` 和 `scripts/`。
**或者最简单的，直接告诉你的AI，请帮我安装这个仓库里的skill。**

| 客户端 | 项目内位置 | 调用方式 |
| --- | --- | --- |
| Codex CLI | `.agents/skills/game-localization-public/` | 在提示词中使用 `$game-localization-public`。 |
| Claude Code | `.claude/skills/game-localization-public/` | 在聊天中输入 `/game-localization-public`。 |
| Gemini CLI | `.agents/skills/game-localization-public/` | 用 `/skills list` 确认已发现技能，然后在任务中点名。 |

其他兼容 Agent Skills 的宿主使用各自的发现目录。宿主只支持读取文件时，可在任务里指定 `game-localization-public/SKILL.md`，让它按需读取随附资料。工作流从同一套 [Agent Skills](https://agentskills.io/specification) 文件加载。客户端的目录和调用方式见 [Codex](https://learn.chatgpt.com/docs/build-skills)、[Claude Code](https://code.claude.com/docs/en/skills) 和 [Gemini CLI](https://geminicli.com/docs/cli/skills/) 的官方说明。

例如，在游戏的项目目录启动客户端后，可以说：

> 使用 game-localization-public 开始这个游戏的简体中文汉化。先核对游戏版本、现有汉化和开工参数。

## 在其他宿主运行时

- 技能正文和相对路径引用可以随目录移植。`agents/openai.yaml` 提供 OpenAI 客户端的可选界面元数据。
- 初译和校对使用用户指定的模型、推理强度和子代理。开始这些步骤前，先确认当前宿主具备对应能力。指定设置不可用时，说明缺项，由用户决定可用设置，再继续受影响的步骤。
- 工具准备和验收清理脚本面向 Windows PowerShell 5.1 或 PowerShell 7。宿主需要有权访问游戏和项目文件、运行脚本，并在适合的 Windows 环境执行实机检查。发布到 GitHub 需要目标仓库的写权限。客户端能够加载技能文件时，仍要分别核对这些运行能力。

更多细节见 [技能入口](game-localization-public/SKILL.md)、[工具库配置](game-localization-public/references/toolkit.md)和 [开发工程交接](game-localization-public/references/developer-handoff.md)。
