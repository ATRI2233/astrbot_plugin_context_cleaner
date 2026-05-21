# AstrBot Context Cleaner

自动清理 AstrBot 对话上下文中旧轮次的思考块（think block）和工具调用（tool_calls），减少 token 消耗，降低 API 成本。

## 功能

- **清理思考块** — 移除旧轮次中 Assistant 的推理/思考内容
- **清理工具调用** — 移除旧轮次的工具调用请求（tool_calls）
- **清理工具结果** — 移除旧轮次中 Tool 角色的工具调用结果
- **可配置间隔** — 每 N 轮对话触发一次清理
- **保留最近轮次** — 保留最近若干轮的完整上下文，不影响对话连贯性
- **按会话独立计数** — 不同会话互不干扰
- **异步执行** — 清理不阻塞 LLM 回复
- **所有配置在 WebUI 可调** — 无需手动改文件

## 安装

### 方式一：命令行安装

```bash
git clone https://github.com/your-username/astrbot_plugin_context_cleaner.git
cd astrbot_plugin_context_cleaner
bash install.sh
# 重启 AstrBot
```

### 方式二：手动安装

将 `astrbot_plugin_context_cleaner/` 整个目录复制到 AstrBot 数据目录下的 `plugins/` 中，然后在 `cmd_config.json` 的 `plugin_set` 中添加 `"astrbot_plugin_context_cleaner"`，最后重启 AstrBot。

## 配置

| 配置项 | 类型 | 默认值 | 说明 |
|--------|------|--------|------|
| `clean_interval` | int | 5 | 每多少轮对话触发一次清理，设为 0 关闭自动清理 |
| `preserve_rounds` | int | 3 | 保留最近多少轮对话的完整内容 |
| `clean_think` | bool | true | 是否清理旧轮次的思考块 |
| `clean_tool_calls` | bool | true | 是否清理旧轮次的工具调用请求 |
| `clean_tool_results` | bool | true | 是否清理旧轮次的工具调用结果 |

所有配置项可在 AstrBot WebUI 插件设置页面中调整。

## 工作原理

1. 每次 LLM 回复完成后，插件会为该会话的轮次计数器 +1
2. 当计数器达到 `clean_interval` 时，触发清理
3. 清理时，将对话历史按 user 消息分组为"轮次"
4. 保留最近 `preserve_rounds` 轮完整内容
5. 对旧轮次的消息，根据配置移除思考块、tool_calls 和 tool 结果
6. 清理完成后将更新后的历史写回，并输出节省的字符数

## 效果日志示例

```
[ContextCleaner] [session_id] 清理完成: 2840 字符 (62%)，保留最近 3 轮，清理 7 轮
```

## License

MIT
