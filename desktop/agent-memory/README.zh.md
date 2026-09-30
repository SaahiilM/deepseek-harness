# Agent Memory

[English](README.md) | 中文

由 agent 为 agent 撰写的、持久化的按会话笔记，服务于在 `desktop-app` 分支上工作的场景。项目级决策记录在 [`../PROJECT_MEMORY.md`](../PROJECT_MEMORY.md)；本目录记录*每个会话实际做了什么、观察到什么、学到了什么*，使后续会话（或一个没有对话上下文的新 agent）能够重建这项工作。

## 协议

1. **开始工作前**：先读 `../PROJECT_MEMORY.md`，再读本目录中最新的条目。
2. **工作过程中**：每完成一个有意义的单元，优先运行 `desktop/scripts/log-session.sh "<summary>"`——它会为今天追加一条带时间戳的条目。
3. **条目格式**（每天一个文件，`sessions/YYYY-MM-DD.md`）：

   ```markdown
   ## HH:MM — <short title>
   - Did: …
   - Learned: …            (non-obvious facts: commands that failed, timings, quirks)
   - Decided: …            (only if it changes PROJECT_MEMORY.md too)
   - Next: …               (concrete hand-off to the next session)
   ```

4. **绝不删除或改写既有条目**；更正以新条目的形式追加。
5. 条目应保持简短且以事实为主。推演过程不属于这里。

## 索引

- `sessions/2026-08-23.md` — 分支初始化、记忆脚手架、shell v1。