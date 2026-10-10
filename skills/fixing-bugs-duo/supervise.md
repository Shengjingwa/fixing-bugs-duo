# A 的监督、终审与交付

第 5 步开 B、起监视脚本之后立刻读本文件。审查细节见 [review.md](review.md)，文件格式见 [files.md](files.md)。

## 7. 监督

监视脚本每行 `DUO_WAKE_<短名> <序号> <事件>`。一次醒来先处理完手上已有的全部 commit 和 R-n；之后到达的 `commit` 和 `request` 通知，如果没有比 `last_reviewed_sha` 更新的 commit，也没有新的 R-n，读一行 `review-state.md` 就结束本轮。其余来源都按下表处理。

每次被唤醒，读出上次处理过的序号之后的全部唤醒行，逐行按下表处理。同一次轮询可能出好几行，例如 `stall` 和 `slow`：

| 来源 | 做法 |
|---|---|
| `commit` | B 有带 `Flow: step`、`Flow: fix` 或没有 trailer 的新 commit。`wip` 和 `docs` 不唤醒 A，留到下次醒来一起处理。对 `review-state.md` 里 `last_reviewed_sha` 之后的每个 commit，按 review.md 的触发分级处理 |
| `request` | `progress.md` 出现新的 `### R-` 标题。读新增的 R-n，在 `rulings.md` 追加答复。B 结束本轮在等时，resume B；B 在跑时不打扰，B 会在下一个定点读到 |
| `stall` | B 本该在干活，但 10 分钟没有任何动静，也没有未超时的 `running` 标记。按下文「卡住」处理 |
| `slow <分钟>` | B 在干活，但离上一个唤醒 A 的 commit 或 B 这一轮开始，已过了 `handover.md` 的「步骤超时」，之后每过一个步骤超时再报一次；`running` 标记不影响它。按下文「步骤超时」处理 |
| `status`（只在退路里有） | `progress.md` 的 `STATUS:` 行变了，处理同下面「B 本轮结束」 |
| `DUO_ERROR_` 行，或宿主报告脚本退出 | 监视脚本停了。按错误原因修好，重启脚本，更新 `handover.md` 里的 pid。停掉期间 B 的 commit 和 R-n 没有唤醒 A，重启后先拍一次快照补审 |
| `heartbeat`（只在退路里有） | 拍快照：`git --no-optional-locks log` 和 `progress.md`。B 本该在干活，且连续两次心跳都没有新 commit、新 R-n 或 `STATUS:` 变化时，再按「卡住」第 2、3 条核对 duo 目录和 `running`，都成立就按「卡住」末尾的退路做法处理。再按「步骤超时」末段核对这一步做了多久 |
| B 本轮结束 | 读 B 的 `STATUS:` 行，按下表办。B 每结束一轮处理一次，`STATUS:` 和上一轮相同也照办，例如 DoD 撤销后再回的 `DOD`。回复里没有 `STATUS:` 行时，先读 `progress.md` 的 `STATUS:`；那里也是旧值，才 resume B 要它按现状补一行 |

`STATUS:` 的处理：

| 状态 | A 做什么 |
|---|---|
| `S0-DONE` | 核对复现输出确实像 `handover.md` 写的那样失败，复现不符预期就回第 3 步。基线失败写进 `test-plan.md`。用户已确认方案，就按 SKILL.md 第 6 步冻结并 resume B；还没确认就等 |
| `BLOCKED R-<n>` | 按 `request` 行处理，答复后 resume B |
| `PAUSED <原因>` | 按原因处理。缺提交身份时问用户，写进 `handover.md` 后 resume B。`步骤超时：…` 按下文「步骤超时」的「打断 B」处理 |
| `STOPPED` | 进入下面的换 B |
| `DOD` | 进入第 8 步 |
| `DELIVERED` / `DELIVER-BLOCKED` | 按第 8 步第 5 条处理 |

- **P0**：先落盘，再 resume B 并设 `interrupt: true`，消息写发现编号和证据。P1、P2 不发消息，写进 `batch.md`，靠 B 的定点读送达；B 已过最后一次定点读时，按第 8 步撤销 DoD 送达。A 只在这几种情况下 resume B：P0、流程指令（开始 S1、DoD 撤销、交付、用户确认的升版、转达 MR/PR 评审意见）、BLOCKING 答复通知、判卡住时重发的最后一条指令、步骤超时时用户要打断它（以及打断后让它继续）、要它补 `STATUS:` 行、要它停手。
- **要用户拍板的事**：推翻勿翻案项、改变方案行为、P1 遗留放行、同一问题 3 轮修不好、同一步第二次步骤超时、B 对裁决有异议且 A 复核后仍分歧。A 去问用户，B 先做不受影响的步骤。用户拍板改方案时，按 files.md 的升版规程走。用户没回应时，在 `handover.md` 标「待用户」；全部步骤被阻塞时暂停任务，A 和 B 都不得自行裁决。
- **换 B**：`progress.md` 的压缩日志显示连续 3 个压缩间隔都短于 30 分钟，且剩余步骤 ≥ 3 时，A 建议用户换 B。用户同意后，宿主若仍显示旧 B 在跑，A 先 interrupt 旧 B，要它停手并回复 `STATUS: STOPPED`；收不到这条回复，就报给用户，不开新 B，免得两个 B 同时写 worktree。旧 B 停下后，A 用 SKILL.md 第 5 步的提示词和 `handover.md` 里记的模型新开一个 B（「本轮」写成「接着 progress.md 的当前步骤继续」），把新 ID 和转录写进 `handover.md`，再用新转录重启监视脚本。B 出错退出时，同样新开一个 B 接上。退路里，请用户先停掉旧 B 的聊天；A 把 `b-prompt.md` 的「本轮」改成同样的话，commit，再请用户新开一个聊天粘贴它，监视脚本不用重启。
- **A 自己压缩或恢复后**：读 `handover.md`、`review-state.md`、`progress.md`，以及 `git log <last_reviewed_sha>..HEAD`。按 `handover.md` 里的 pid 确认监视脚本还在跑，不在就重启，并更新 pid。

### 卡住

下面三条同时成立，才算 B 卡住。监视脚本按这三条发 `stall`，A 收到后再亲自核对一遍：
1. B 本该在干活：A 给 B 发了指令，还没收到 B 本轮结束的通知。在 Cursor 里，B 的转录最后一行不是 `"type":"turn_ended"`。
2. 10 分钟没有动静：duo 目录里的文件、worktree 私有 git 目录里的 `index`、`HEAD` 和 `logs/HEAD`、工作区里改动中的文件，都没有更新。
3. 没有在跑的长命令：duo 目录里没有 `running` 标记，或者标记写下的时间已经超过它的预计时长再加 10 分钟。

B 的转录不能当作动静：Cursor 只在 B 一轮结束时才写子 agent 的转录，B 正常干活时它可以很久不变。转录只用来判断第 1 条。

确认卡住后：
1. A 用最后一条指令 interrupt B 一次，并汇报，不用再问用户。消息里加一句：「你要是在等后台长命令，补写 `running` 标记，接着等。」interrupt 会取消 B 的前台命令，b.md 因此要求长命令放后台跑。
2. interrupt 之后又收到一次 `stall`，也就是又过了 10 分钟仍没有动静，就报给用户。用户同意后按上文「换 B」新开一个 B。

退路里 B 是用户开的聊天，A 收不到 `stall`，也不能 interrupt B。heartbeat 判卡住后：
1. A 汇报，请用户在 B 的聊天里先停掉当前这一轮，再发：「继续。你要是在等后台长命令，补写 `running` 标记，接着等。」
2. 之后又连续两次心跳仍没有变化，报给用户，用户同意后按上文「换 B」换。

### 步骤超时

`slow` 说明 B 一直有动静，但这一步做得太久，可能在原地打转。A 取 `progress.md`「当前步骤」所在的 `S<n>`，和 `handover.md` 的「已报 slow」比：
1. 「已报 slow」不是这个 `S<n>`（包括「无」）：这一步第一次超时。A 看 `git --no-optional-locks log` 和 `progress.md`，把「已报 slow」改成 `S<n>`，commit，再汇报一行，不打扰 B。
2. 「已报 slow」就是这个 `S<n>`：用问答工具请用户三选一，附上 B 这一步的 commit 和 `progress.md` 摘要。等用户回答期间再来的 `slow` 不再问。
   - 打断 B：resume B 并设 `interrupt: true`，消息写「步骤超时」。B 交回 `STATUS: PAUSED 步骤超时：…` 后，A 照下一项复查计划，在 `rulings.md` 写下怎么继续，commit，再 resume B。
   - 复查计划：A 核对这一步在 `steps.md` 里的拆法和完成判据。要改方案，按 files.md 的升版规程问用户。
   - 继续等。

   用户选完，A 把「已报 slow」改回「无」，commit。下一次 `slow` 又按第 1 条处理。

退路里脚本不发 `slow`。A 每次收到 heartbeat，从上一个 `Flow: step`、`Flow: fix` 或没有 trailer 的 commit 和 A 的上一条指令中较晚的那个算起，看 B 这一步做了多久。B 本该在干活，且这段时间每多满一个步骤超时，就当作收到一次 `slow`，按上面两条处理。「打断 B」改为请用户在 B 的聊天里停掉当前这一轮，再发「步骤超时」。

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
5. B 卡住、步骤超时、被 interrupt、换 B，或出错。
6. 最终交付，即 SKILL.md 的「交付报告」。

没有变化的心跳不汇报，`wip` 和 `docs` commit 也不汇报。进度不另记一份：步骤看 `git log`，审查看 `review-state.md`。用户随时问进度时，A 先拍一次快照再回答。

**完成：** B 交回 `STATUS: DOD`；`last_reviewed_sha` 等于 B 的最终 sha；没有在途审查项，也没有未答复的 R-n。

## 8. 终审、验收与交付

1. 按 review.md 终审：最后一个 `[M]` 的全量审查要审整个任务区间，它兼作终审，不再另做一轮。终审时还要复读 `batch.md` 里的全部驳回项。
2. **独立验收**：开始前先查 `batch.md`，还有 `open` 的 P1 就按第 3 条下的做法撤销 DoD，不做验收。B 停着时，A 在任务 worktree 的最终 sha 上亲手重跑两类命令：未缩小的原始复现命令，以及 `test-plan.md` 里全部本轮必做用例。输出写回 `test-plan.md`，同时把 `progress.md`「用例记录」整表一次转抄进 `test-plan.md`，commit。B 的回报不能代替这一步。B 交回 `STATUS: DOD` 时终审 agent 还在跑，也不用等，直接开始验收；慢命令放后台跑，同时核对 DoD 的其他条目。
3. 逐条核对 `steps.md` 末尾的 DoD，那是 DoD 的唯一定义。

   终审或验收发现 P0，或 `batch.md` 里还有 `open` 的 P1 时，DoD 撤销：先落盘，再 resume B「DoD 撤销」，消息列出这些发现编号，回到第 7 步。
4. 通过后 resume B：「交付」，附终审意见和 `batch.md` 路径。B push 分支，向 `handover.md` 里的目标分支建 Draft MR/PR。
5. B 回 `STATUS: DELIVERED` 或 `STATUS: DELIVER-BLOCKED` 后，停掉监视脚本，按 SKILL.md「交付报告」报告。转达 MR/PR 评审意见那一轮，先按下段亲验再停。

MR/PR 评审意见由 A 转给 B：重启监视脚本并更新 `handover.md` 里的 pid，B 按 `Flow: fix` 修完并 push，回 `DELIVERED`。A 亲验 `last_reviewed_sha` 之后的 fix commit，通过后再停脚本、报告；不通过就再转给 B。意见触及方案行为时，问用户。用户确认合入或宣布放弃后，做 SKILL.md 第 9 步。

**完成：** 终审和独立验收的证据都在 flow 仓库里，`test-plan.md` 已转抄到最终 sha；Draft MR/PR 已建，或已写明缺什么；监视脚本已停；用户已收到报告。
