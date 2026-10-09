# A 的监督、终审与交付

第 6 步冻结方案、resume B 之后读本文件。审查细节见 [review.md](review.md)，文件格式见 [files.md](files.md)。

## 7. 监督

每次被唤醒，先看唤醒来源，再按下表处理：

| 来源 | 做法 |
|---|---|
| `commit` | 对 `review-state.md` 里 `last_reviewed_sha` 之后的每个 commit，按 review.md 的触发分级处理 |
| `request` | 读 `progress.md` 新增的 R-n，在 `rulings.md` 追加答复。B 结束本轮在等时，resume B；B 在跑时不打扰，B 会在下一个定点读到 |
| `stall` | 按下文「卡住」处理 |
| `DUO_ERROR_` 行，或宿主报告脚本退出 | 监视脚本停了。按错误原因修好，重启脚本，更新 `handover.md` 里的 pid。停掉期间 B 的 commit 和 R-n 没有唤醒 A，重启后先拍一次快照补审 |
| `heartbeat` | 拍快照：`git --no-optional-locks log`、`progress.md`、B 的转录（可得时）。没有转录、B 本该在干活，且连续两次心跳都没有新 commit、新 R-n 或 `STATUS:` 变化时，按卡住处理 |
| B 本轮结束，或 `status` | 读 B 的 `STATUS:` 行，按 [b.md](b.md) 的约定处理。宿主的结束通知和 `status` 事件可能都会到，同一行 `STATUS:` 只处理一次。B 的回复里没有 `STATUS:` 行时，先拍一次快照，再 resume B，要它按现状补一行 |

- **P0**：先落盘，再 resume B 并设 `interrupt: true`，消息写发现编号和证据。A→B 的消息只有四种：P0、流程指令（开始 S1、交付、用户确认的升版）、BLOCKING 答复通知、判卡住时重发的最后一条指令。其余一律写进 `batch.md`，靠 B 的定点读送达。
- **要用户拍板的事**：推翻勿翻案项、改变方案行为、P1 遗留放行、同一问题 3 轮修不好、B 对裁决有异议且 A 复核后仍分歧。A 去问用户，B 先做不受影响的步骤。用户拍板改方案时，按 files.md 的升版规程走。用户没回应时，在 `handover.md` 标「待用户」；全部步骤被阻塞时暂停任务，A 和 B 都不得自行裁决。
- **换 B**：`progress.md` 的压缩日志显示连续 3 个压缩间隔都短于 30 分钟，且剩余步骤 ≥ 3 时，A 建议用户换 B。用户同意后，A 用 SKILL.md 第 5 步的提示词新开一个 B（「本轮」写成「接着 progress.md 的当前步骤继续」），再把新 ID 写进 `handover.md`。B 出错退出时，同样新开一个 B 接上。
- **A 自己压缩或恢复后**：读 `handover.md`、`review-state.md`、`progress.md`，以及 `git log <last_reviewed_sha>..HEAD`。按 `handover.md` 里的 pid 确认监视脚本还在跑，不在就重启，并更新 pid。

### 卡住

下面三条同时成立，才算 B 卡住。监视脚本按这三条发 `stall`，A 收到后再亲自核对一遍：
1. B 本该在干活：A 给 B 发了指令，还没收到 B 本轮结束的通知。在 Cursor 里，B 的转录最后一行不是 `"type":"turn_ended"`。
2. 10 分钟没有动静：duo 目录里的文件、worktree 私有 git 目录里的 `index`、`HEAD` 和 `logs/HEAD`、工作区里改动中的文件，都没有更新。
3. 没有在跑的长命令：duo 目录里没有 `running` 标记，或者标记写下的时间已经超过它的预计时长再加 10 分钟。

B 的转录不能当作动静：Cursor 只在 B 一轮结束时才写子 agent 的转录，B 正常干活时它可以很久不变。转录只用来判断第 1 条。

确认卡住后：
1. A 用最后一条指令 interrupt B 一次，并汇报。调用本 skill 即授权 A 这样做，不用再问用户。消息里加一句：「你要是在等后台长命令，补写 `running` 标记，接着等。」interrupt 会取消 B 的前台命令，b.md 因此要求长命令放后台跑。
2. interrupt 之后又收到一次 `stall`，也就是又过了 10 分钟仍没有动静，就报给用户。用户同意后新开一个 B。新开之前，宿主若仍显示旧 B 在跑，先 interrupt 旧 B，要它停手并回复 `STATUS: STOPPED`；收不到这条回复，就报给用户，不开新 B，免得两个 B 同时写 worktree。

### 汇报

A 在自己的对话里汇报，每次一行，格式固定：

```text
[duo <短名>] <进度，如 S2/3 完成> · <sha> · <审查或验收结论> · 待你拍板：<无 | 事项>
```

下面的事件各汇报一次：
1. B 已开，附 B 的 ID 链接。
2. 步骤完成（`Flow: step`），附轻检或全量审查的结论。
3. 发现 P0，以及 P0 修好。
4. 需要用户拍板。这一行放在消息最前面，同时用问答工具发问。
5. B 卡住、被 interrupt、换 B，或出错。
6. 最终交付，即 SKILL.md 的「交付报告」。

没有变化的心跳不汇报，`wip` 和 `docs` commit 也不汇报。进度不另记一份：步骤看 `git log`，审查看 `review-state.md`。用户随时问进度时，A 先拍一次快照再回答。

**完成：** B 交回 `STATUS: DOD`；`last_reviewed_sha` 等于 B 的最终 sha；`test-plan.md` 已转抄到最终 sha；没有在途审查项，也没有未答复的 R-n。

## 8. 终审、验收与交付

1. 按 review.md 终审：最后一个 `[M]` 的全量审查要审整个任务区间，它兼作终审，不再另做一轮。终审时还要复读 `batch.md` 里的全部驳回项。
2. **独立验收**：B 停着时，A 在任务 worktree 的最终 sha 上亲手重跑两类命令：未缩小的原始复现命令，以及 `test-plan.md` 里全部本轮必做用例。输出写回 `test-plan.md`，commit。B 的回报不能代替这一步。
3. 核对 DoD：
   - 规格表全部通过
   - 全部步骤完成
   - 没有 P0
   - P1 遗留都经用户批准
   - 生产路径上没有诊断前缀

   终审或验收发现 P0 时，DoD 撤销，回到第 7 步。
4. 通过后 resume B：「交付」，附终审意见和 `batch.md` 路径。B push 分支，向 `handover.md` 里的目标分支建 Draft MR/PR。
5. B 回 `STATUS: DELIVERED` 或 `STATUS: DELIVER-BLOCKED` 后，停掉监视脚本，按 SKILL.md「交付报告」报告。

MR/PR 评审意见由 A 转给 B：重启监视脚本并更新 `handover.md` 里的 pid，B 按 `Flow: fix` 修，A 亲验，B 推完后再停脚本。意见触及方案行为时，问用户。用户确认合入或宣布放弃后，做 SKILL.md 第 9 步。

**完成：** 终审和独立验收的证据都在 flow 仓库里；Draft MR/PR 已建，或已写明缺什么；监视脚本已停；用户已收到报告。
