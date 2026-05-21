"""
自动清理对话上下文中旧轮次的思考块和工具调用，减少 token 消耗。
每 N 轮对话触发一次，仅清理当前对话上下文，异步执行不阻塞回复。
所有配置项可在 AstrBot WebUI 插件设置中调整。
"""

import asyncio
import json

from astrbot.api import logger
from astrbot.api.event import AstrMessageEvent, filter
from astrbot.api.provider import LLMResponse
from astrbot.api.star import Context, Star, register


@register(
    "context_cleaner",
    "astrbot",
    "自动清理旧轮次的思考块/工具调用，减少 token 消耗。",
    "1.0.0",
)
class ContextCleanerPlugin(Star):
    def __init__(self, context: Context, config: dict):
        super().__init__(context)
        self.config = config
        self.clean_interval = int(config.get("clean_interval", 5))
        self.preserve_rounds = int(config.get("preserve_rounds", 3))
        self.clean_think = bool(config.get("clean_think", True))
        self.clean_tool_calls = bool(config.get("clean_tool_calls", True))
        self.clean_tool_results = bool(config.get("clean_tool_results", True))

        # 按会话统计已完成的对话轮数
        self._round_counters: dict[str, int] = {}

    @filter.on_llm_response()
    async def on_llm_response(
        self, event: AstrMessageEvent, resp: LLMResponse
    ) -> None:
        """每次 LLM 响应完成后计数，达到间隔触发清理。"""
        if self.clean_interval <= 0:
            return
        if resp.role != "assistant":
            return

        session = event.unified_msg_origin
        if not session:
            return

        count = self._round_counters.get(session, 0) + 1
        self._round_counters[session] = count

        if count >= self.clean_interval:
            self._round_counters[session] = 0
            asyncio.create_task(self._cleanup(session))

    async def _cleanup(self, session: str) -> None:
        """清理指定会话中旧轮次的思考块和工具调用。"""
        conv_mgr = self.context.conversation_manager
        try:
            cid = await conv_mgr.get_curr_conversation_id(session)
            if not cid:
                return

            conv = await conv_mgr.get_conversation(session, cid)
            if not conv or not conv.history:
                return

            msgs = json.loads(conv.history)
            if not isinstance(msgs, list) or len(msgs) <= 3:
                return

            # 按轮次分组：每条 user 消息开始新的一轮
            rounds = []
            cur = []
            for m in msgs:
                if m.get("role") == "user" and cur:
                    rounds.append(cur)
                    cur = []
                cur.append(m)
            if cur:
                rounds.append(cur)

            preserve = min(self.preserve_rounds, len(rounds))
            old_rounds = rounds[:-preserve]
            preserved_rounds = rounds[-preserve:]

            cleaned = []
            for rnd in old_rounds:
                for m in rnd:
                    role = m.get("role")
                    if role == "assistant":
                        content = m.get("content")
                        # 清理思考块: {"type": "think", "think": "...", "encrypted": null}
                        if self.clean_think and isinstance(content, list):
                            m["content"] = [
                                p
                                for p in content
                                if not (
                                    isinstance(p, dict) and p.get("type") == "think"
                                )
                            ]
                            if not m["content"] and not m.get("tool_calls"):
                                continue
                        # 清理工具调用: tool_calls 列表
                        if self.clean_tool_calls and m.get("tool_calls"):
                            m["tool_calls"] = None
                            if not m.get("content"):
                                continue
                    elif role == "tool":
                        # 清理工具结果: role 为 tool 的消息
                        if self.clean_tool_results:
                            continue
                    cleaned.append(m)

            for rnd in preserved_rounds:
                cleaned.extend(rnd)

            await conv_mgr.update_conversation(session, cid, history=cleaned)

            before = len(json.dumps(msgs, ensure_ascii=False))
            after = len(json.dumps(cleaned, ensure_ascii=False))
            saved = before - after
            pct = saved / before * 100 if before else 0
            logger.info(
                f"[ContextCleaner] [{session}] 清理完成: "
                f"{saved} 字符 ({pct:.0f}%)，"
                f"保留最近 {preserve} 轮，"
                f"清理 {len(old_rounds)} 轮"
            )

        except Exception as e:
            logger.error(f"[ContextCleaner] [{session}] 清理失败: {e}")
