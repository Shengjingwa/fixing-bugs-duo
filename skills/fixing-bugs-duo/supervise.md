# A 的监督、终审与交付

第 5 步开 B、起监视脚本之后立刻读本文件。审查细节见 [review.md](review.md)，文件格式见 [files.md](files.md)。

## 7. 监督

监视脚本每行 `DUO_WAKE_<短名> <序号> <事件>`。一次醒来先处理完手上已有的全部 commit 和 R-n；之后到达的 `commit` 和 `request` 通知，如果没有比 `last_reviewed_sha` 更新的 commit，也没有新的 R-n，读一行 `review-state.md` 就结束本轮。其余来源都按下表处理。

每次被唤醒，读出上次处理过的序号之后的全部唤醒行，逐行按下表处理。同一次轮询可能出好几行，例如 `stall` 和 `slow`。

在 Cursor 里，通知要等 A 这一轮结束才送到。A 在一轮里做别的长活时（例如同时管另一个 duo 任务、跑长评测），每做完一段、切换任务之前，读一次监视脚本的输出（Cursor：它的终端文件），按序号补处理新行；同时管几个任务时，每个任务的脚本各读一次，序号按任务分别记。B 在跑时，A 若同时等别的后台命令（例如跟进另一张 MR 的流水线），阻塞等待只等监视脚本那个 shell，或把别的单次等待压在 2 分钟以内，每次返回先读一次监视脚本输出。不然 B 的 BLOCKING 请求和步骤轻检都会积压。

| 来源 | 做法 |
|---|---|
| `commit` | B 有带 `Flow: step`、`Flow: fix` 或没有 trailer 的新 commit。`wip` 和 `docs` 不唤醒 A，留到下次醒来一起处理。唤醒行只带轮询时的最新 sha，同一次轮询里的几个 commit 只出一行，所以按 `git --no-optional-locks -C <worktree> log --reverse <last_reviewed_sha>..HEAD` 逐个看，每个按 review.md 的触发分级处理 |
| `request` | `progress.md` 出现新的 `### R-` 标题。读新增的 R-n，在 `rulings.md` 追加 `### R-<n> →` 答复（A 主动发起的裁决用 `### D-<n>`）。B 结束本轮在等时，resume B；B 在跑时不打扰，B 会在下一个定点读到。B 报改法上限的 R-n，说明根因或方案可能不对：A 读 B 存在 `logs/` 里的 diff 和失败输出，在临时 worktree 里重新核对根因；要改方案，按 files.md 的升版规程走 |
| `idle`（传了转录时有） | B 的转录末行变成 `"type":"turn_ended"`，B 这一轮已结束。处理同下面「B 本轮结束」 |
| `stall` | B 本该在干活，但 10 分钟没有任何动静，也没有未超时的 `running` 标记。按下文「卡住」处理 |
| `slow <分钟>` | B 在干活，但离上一个唤醒 A 的 commit 或 B 这一轮开始，已过了 `handover.md` 的「步骤超时」，之后每过一个步骤超时再报一次；`running` 标记不影响它。按下文「步骤超时」处理 |
| `status`（只在退路里有） | `progress.md` 的 `STATUS:` 行变了，处理同下面「B 本轮结束」 |
| `DUO_ERROR_` 行，或宿主报告脚本退出 | 监视脚本停了，或者宿主以为它停了。按错误原因修好，按 SKILL.md 第 5 步「停和重启脚本」重启 |
| `heartbeat`（只在不传转录时有） | 拍快照：`git --no-optional-locks log` 和 `progress.md`。B 本该在干活，且连续两次心跳都没有新 commit、新 R-n 或 `STATUS:` 变化时，再按「卡住」第 2、3 条核对 duo 目录和 `running`。都成立就算卡住：B 是 A 的子 agent 时，按「卡住」的「确认卡住后」处理；退路里按「卡住」末尾的退路做法处理。再按「步骤超时」末段核对这一步做了多久 |
| B 本轮结束 | 读 B 的 `STATUS:` 行，按下表办。B 每结束一轮处理一次，`STATUS:` 和上一轮相同也照办，例如 DoD 撤销后再回的 `DOD`。回复里没有 `STATUS:` 行时，先读 `progress.md` 的 `STATUS:`；那里也是旧值，才 resume B 要它按现状补一行。A 按转录末行判 B 结束本轮时，B 的回复从转录里读；之后宿主的通知送到，它带的回复 A 已经读过，或者转录末行已不是 `"type":"turn_ended"`（B 在跑下一轮），就不再处理 |

`STATUS:` 的处理：

| 状态 | A 做什么 |
|---|---|
| `S0-DONE` | 核对复现输出确实像 `handover.md` 写的那样失败，复现不符预期就回第 3 步。基线失败写进 `test-plan.md`。用户已确认方案，就按 SKILL.md 第 6 步冻结并 resume B；还没确认就等 |
| `BLOCKED R-<n>` | 按 `request` 行处理，答复后 resume B |
| `PAUSED <原因>` | 按原因处理。缺提交身份时问用户，写进 `handover.md` 后 resume B。缺不入仓的文件时，A 照 SKILL.md 第 2 步第 4 条补齐，写进 `handover.md` 的「依赖」，再 resume B。`步骤超时：…` 按下文「步骤超时」的「打断 B」处理。原因写的是还在做（例如「S2 进行中」）时，是 B 干活中途改了状态行：退路里的 `status` 事件读到它、行末又没有 `@<时:分:秒>`，B 并没有停，不处理；B 确实结束了本轮的，resume B，要它按现状接着做 |
| `STOPPED` | 进入下面的换 B |
| `DOD` | 进入第 8 步。MR/PR 已经建好时（转达评审意见那一轮），按第 8 步「MR/PR 评审意见」收尾，不再走第 8 步第 1–4 条 |

- **P0**：先落盘，再 resume B 并设 `interrupt: true`，消息写发现编号和证据。P1、P2 不发消息，写进 `batch.md`，靠 B 的定点读送达；B 已过最后一次定点读时，按第 8 步撤销 DoD 送达。最后一步已经 commit、`progress.md` 的已读游标又没读到这一条，就是已过。
- **resume B**：ID 从 `handover.md` 读，不凭记忆：A 压缩后，摘要里常常只剩 ID 前缀。A 只在这几种情况下 resume B：P0、流程指令（开始 S1、DoD 撤销、用户确认的升版；转达 MR/PR 评审意见也走 DoD 撤销）、BLOCKING 答复通知、处理完 `PAUSED` 的原因后让它继续（例如补好提交身份）、判卡住时重发的最后一条指令、步骤超时时用户要打断它（以及打断后让它继续）、要它补 `STATUS:` 行、要它停手。这是完整清单，b.md「A 的消息」只展开 B 那边有特定做法的几种。
- **要用户拍板的事**：推翻勿翻案项、改变方案行为、P1 遗留放行、同一问题 3 轮修不好、同一步第二次步骤超时、B 对裁决有异议且 A 复核后仍分歧。用户已事先书面授权 A 在范围内自定时，不超出用户给的范围、不放宽验收门槛、不需要外部团队裁决的「改变方案行为」可由 A 按 files.md「方案升版」代定，在交付报告里单列。其余情况 A 去问用户，B 先做不受影响的步骤。用户拍板改方案时，按 files.md 的升版规程走。用户没回应时，在 `handover.md` 标「待用户」；全部步骤被阻塞时暂停任务，A 和 B 都不得自行裁决。
- **换 B**：`progress.md` 的压缩日志显示连续 3 个压缩间隔都短于 30 分钟，且剩余步骤 ≥ 3 时，A 建议用户换 B。用户同意后，宿主若仍显示旧 B 在跑，A 先 interrupt 旧 B，要它停手并回复 `STATUS: STOPPED`；收不到这条回复，就报给用户，不开新 B，免得两个 B 同时写 worktree。旧 B 停下后，A 用 SKILL.md 第 5 步的提示词和 `handover.md` 里记的模型新开一个 B（「本轮」写成「接着 progress.md 的当前步骤继续」），把新 ID 和转录写进 `handover.md`，再按 SKILL.md 第 5 步「停和重启脚本」用新转录重启。B 出错退出时，同样新开一个 B 接上。退路里，请用户先停掉旧 B 的聊天；A 把 `b-prompt.md` 的「本轮」改成同样的话，commit，再请用户新开一个聊天粘贴它，监视脚本不用重启。
- **A 自己压缩或恢复后**：读 `handover.md`、`review-state.md`、`progress.md`，以及 `git log <last_reviewed_sha>..HEAD`。按 `handover.md` 里的 pid 确认监视脚本还在跑。不在、且 `handover.md` 没写「已停」时，按 SKILL.md 第 5 步「停和重启脚本」重启。同时管几个任务时，从分拣表的去向（没有分拣表时看压缩摘要）找出自己的短名：开了 B 的逐个做一遍；排队的看「待收尾」那一行的备注和 `<短名>/` 里记的根因。在第 8 步中途恢复时，已做完的不重做：fetch 后 `git -C <worktree> merge-base --is-ancestor <远端>/<目标分支> HEAD` 退出码为 0，就不再变基，只核对 `handover.md` 的起点等于 `<远端>/<目标分支>`，不等就按 SKILL.md「交付前同步」第 4 条末项补记；`test-plan.md` 里已有最终 sha 上的读数，就不重跑验收；push 重做无妨；建 MR/PR 前，先在平台上查这个工作分支到目标分支有没有开着的 MR/PR，有就不再建，接着读回和报告。

### 卡住

下面三条同时成立，才算 B 卡住。监视脚本按这三条发 `stall`，A 收到后再亲自核对一遍：
1. B 本该在干活：A 给 B 发了指令，还没收到 B 本轮结束的通知。在 Cursor 里，B 的转录最后一行不是 `"type":"turn_ended"`。
2. 10 分钟没有动静：duo 目录里的文件、worktree 私有 git 目录里的 `index`、`HEAD` 和 `logs/HEAD`、工作区里改动中的文件，都没有更新。
3. 没有在跑的长命令：duo 目录里没有 `running` 标记，或者标记写下的时间已经超过它的预计时长再加 10 分钟。

B 的转录不能当作动静：Cursor 只在 B 一轮结束时才写子 agent 的转录，B 正常干活时它可以很久不变。转录只用来判断第 1 条。

确认卡住后：
1. A 用最后一条指令 interrupt B 一次，并汇报，不用再问用户。消息里加一句：「你要是在等后台长命令，补写 `running` 标记，接着等。」interrupt 会取消 B 的前台命令，b.md 因此要求长命令放后台跑。
2. interrupt 之后仍没有动静，就报给用户：传了转录时是又收到一次 `stall`（约 10 分钟后），不传转录时是下一次 `heartbeat`（约 20 分钟后）仍没有变化。用户同意后按上文「换 B」新开一个 B。

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

不传转录时脚本不发 `slow`。A 每次收到 heartbeat，从上一个 `Flow: step`、`Flow: fix` 或没有 trailer 的 commit 和 A 的上一条指令中较晚的那个算起，看 B 这一步做了多久。B 本该在干活，且这段时间每多满一个步骤超时，就当作收到一次 `slow`，按上面两条处理。退路里，「打断 B」改为请用户在 B 的聊天里停掉当前这一轮，再发「步骤超时」。

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
2. **独立验收**：开始前先查 `batch.md`，还有 `open` 的 P1 就按第 3 条下的做法撤销 DoD，不做验收。没有，就先按 SKILL.md「交付前同步」处理目标分支的新 commit。B 停着时，A 在任务 worktree 的最终 sha 上亲手重跑两类命令：未缩小的原始复现命令，以及 `test-plan.md` 里全部本轮必做用例，包括标「执行者：A 验收」的（标了上线后才量的门槛，其中能离线预测的部分也在此时先量一次）。几条耗时长的验收按「不过会不会改代码」排先后：新加的、没过要改代码的门槛先跑，过了再开耗时长、只判不改的扩展或全量回归；并行跑时，中途改了某段代码，受那段代码影响的在途读数全部作废重跑。评测或重放设过环境变量时，跑相关测试前先清掉变量（或单开干净子进程跑）；相关测试出现新增失败时，先用同一环境在起点 sha 上单跑这几条，排除环境残留。不通过的用例按 review.md 定级，写进 `batch.md`。输出写回 `test-plan.md`，同时把 `progress.md`「用例记录」一次转抄进 `test-plan.md`：取这一节里所有以 `|` 开头的行，直到下一个行首的 `## `，核对每行只有一条记录（B 漏换行导致行内出现 `|| ` 粘连时拆成两行）。转抄后核对：不标「执行者：A 验收」的每条本轮必做用例，在转抄过来的行里都有 green 记录；缺的先按用例编号在 `progress.md` 全文里找，B 写错了位置的一并转抄。B 的回报不能代替这一步。B 交回 `STATUS: DOD` 时终审 agent 还在跑、目标分支又没动过，也不用等，直接开始验收；要变基的，等终审交回再变基。慢命令放后台跑，同时核对 DoD 的其他条目。
3. 逐条核对 `steps.md` 末尾的 DoD，那是 DoD 的唯一定义。

   终审或验收发现 P0，或 `batch.md` 里还有 `open` 的 P1 时，DoD 撤销：先落盘 commit flow 仓库，再 resume B「DoD 撤销」，消息列出这些发现编号，回到第 7 步。会进 MR/PR diff、多半会引来评审意见的 P2（例如重复的段落、同一处措辞只改了一半），可以一起列进去；没有 P0、P1 时，也可以只为这类 P2 撤销 DoD：交付后的评审意见往往要多一轮评审，有的项目还要重新变基、重审，比现在让 B 修贵。只影响描述的 P2 照旧写进 MR/PR 描述。
4. 通过后由 A 交付，B 停着不动：
   1. 停掉监视脚本，把 `handover.md` 的「监视脚本 PID」改成「已停」。
   2. 目标仓库禁止 `Co-authored-by` 等宿主自动追加的 trailer 时，先运行 `git -C <worktree> log <起点 sha>..HEAD --format='%h %(trailers:key=Co-authored-by)'` 检查；有命中时，用 Python `subprocess` 调 `git commit-tree` 链或 `git filter-branch` 重写 `<起点 sha>..HEAD` 去掉该行（保留 `Flow:` trailer，提交身份照 SKILL.md 第 2 步第 5 条设环境变量；不要在宿主 shell 里直接写 `git commit-tree` 字面量，免得再次触发宿主注入），再把 `review-state.md` 的 `last_reviewed_sha` 更新为重写后的 HEAD。然后 push 工作分支：`git -C <worktree> push -u <远端> <工作分支>`，`<远端>` 见 SKILL.md 第 2 步。
   3. 向 `handover.md` 里的目标分支建 Draft MR/PR，按项目规范写。描述里写根因、改法、验证、`batch.md` 里的 P1/P2、待拍板项、方案版本。分支上保留 `Flow:` trailer。
   4. 按 SKILL.md「交付报告」更新 `registry.md`，连同本节的 `test-plan.md`、`handover.md`、`review-state.md` 一次 commit flow 仓库，再向用户报告。push 或建 MR/PR 做不了时，把描述草稿写进 flow 的 `<短名>/`，commit 后在报告里写明缺什么。

**MR/PR 评审意见**：A 先按 review.md 的严重度定级。
- 要改代码的：写进 `batch.md`。远端分支有本地没有的 commit 时（评审人在网页上应用了建议，或平台变基过），A 先按 SKILL.md「快修和豁免的 MR/PR 评审意见」第 2 条把 worktree 跟上去。再按 SKILL.md 第 5 步「停和重启脚本」起脚本，用「DoD 撤销」resume B，跟过远端的在消息里写明分支已到哪个 sha。B 修完回 `DOD` 后，A 亲验 `last_reviewed_sha` 之后的 fix commit，把受影响用例的新结果补进 `test-plan.md`，commit flow 仓库。通过后停脚本（`handover.md` 再写「已停」），运行 `git -C <worktree> push`（MR/PR 已在，不再建），按 SKILL.md「交付报告」报告；不通过就再交给 B。
- 不改代码就能回应的（解释、配置、上线后核对）：A 直接回复评审人。
- P2 可以留给后续 MR/PR：写进 `batch.md`，并告诉评审人。
- 意见触及方案行为时，问用户。

**跟到合入**：只在用户授权合入时做，见 SKILL.md「交付报告」。A 按项目的合入流程走。改 MR/PR 的状态或审查者前，先确认 push 的退出码是 0、MR/PR 的 head 等于 worktree 的 HEAD，再单独执行，不和 push 串在一条命令里。平台合入前变基了分支时，先 fetch，再对变基前后的 head 各跑一次 `git diff --numstat <远端>/<目标分支>...<head>`，逐文件改动有出入就看清再放行；`.gitattributes` 里按 `merge=union` 合并的文件（例如 CHANGELOG）行数一致也可能放错了位置，逐个看 diff。开了 B 的任务，放行后把 `review-state.md` 的 `last_reviewed_sha` 改成变基后的 head，注明「平台变基自 <旧 sha>」，commit flow 仓库，免得下一轮评审意见把上游的 commit 也当成要亲验的。

变基（平台做的，或 A 按项目合入流程做的）弄坏了合并类文件时，例如 union 合并的 CHANGELOG 多出别的 MR/PR 的小节、生成文档出现重复段，A 自己在 worktree 里修，不交 B：
1. B 停着。本地还没跟上远端时，按 SKILL.md「快修和豁免的 MR/PR 评审意见」第 2 条跟到 MR/PR 现在的 head。
2. 修完另 commit，说明里写原因。开了 B 的任务带 `Flow: docs`，提交身份用 `handover.md` 的「提交身份」，和 `git var` 打出的不同时按 b.md「边界」的写法；快修和豁免的身份照 SKILL.md 那一节第 3 条。
3. push 前，`git -C <worktree> diff --numstat <远端>/<目标分支>...HEAD` 要和 `git -C <worktree> diff --numstat <远端>/<目标分支>...<变基前的 head>` 逐文件一致。开了 B 的任务，push 后同样把 `last_reviewed_sha` 改成新 HEAD；之后再 resume B 时，消息里写明分支已到哪个 sha。

只限这类文件，别的改动照「MR/PR 评审意见」交 B。

MR/PR 合入或用户宣布放弃后，做 SKILL.md 第 9 步。

**完成：** 终审和独立验收的证据都在 flow 仓库里，`test-plan.md` 已转抄到最终 sha；Draft MR/PR 已建，或已写明缺什么；监视脚本已停；用户已收到报告。
