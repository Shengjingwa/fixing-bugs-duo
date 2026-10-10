---
name: fixing-bugs-duo
description: 两会话修 bug：A 诊断、写方案并监督，B 子 agent 在同一个 worktree 里先红后绿；简单问题直接单会话修完。
disable-model-invocation: true
license: MIT
---

# 两会话修 bug

调用本 skill 的会话是 **A**：诊断、写交接材料、监督、裁决、验收，并且是唯一和用户对话的会话。**B** 是 A 开的后台子 agent，只读 [b.md](b.md)，在任务 worktree 里按冻结的方案先红后绿。

按需读：建 flow 文件时读 [files.md](files.md)；第 5 步开 B 之后立刻读 [supervise.md](supervise.md)，里面是监视脚本的事件、监督、终审和交付；审查时读 [review.md](review.md)。

调用本 skill，就是要求 A 在 Cursor 里用 Shell 的 `notify_on_output` 监视 B，并授权 A 在 P0 和判卡住时对 B 设 `interrupt`，也授权 A 在豁免档自己 commit、push、建 Draft MR/PR。

简单问题不开 B：快修档，以及第 4 步判为豁免的问题，A 单会话修完。

## 依赖

- `fixing-bugs`（<https://github.com/Shengjingwa/fixing-bugs>）：先找本 skill 目录的同级目录 `../fixing-bugs/`，找不到再按宿主的 skill 清单找。A 用它的「开头」「升档」「快修」「排查」「停下与交付」和 `full.md` 第 1–4 段，豁免且有风险信号时读到第 6 段；B 用 `full.md` 第 5–6 段，和 `b.md` 不一致的地方以 `b.md` 为准。豁免档要 commit、push、建 MR，和「停下与交付」里「改动默认留在工作区」相反，以本 skill 为准。读不到时按 `fixing-bugs` 的「依赖」一节处理：标 `blocked`，写明缺什么，继续不依赖它的部分。
- `diagnosing-bugs`、`tdd`：`fixing-bugs` 已声明，读取方式同上。

## 1. 开头

1. 做 `fixing-bugs` 的「开头」：记主仓库基线，写一句现象和修好标准，定起始档位。
2. 给这个 bug 起一个短名 `<短名>`（小写短横线，例如 `csv-missing-row`）。
3. 起始档位是快修：在主仓库按 `fixing-bugs` 的「快修」修完，本 skill 到此结束。快修中碰到升档信号时，先把本轮在主仓库里的增量撤回（基线不动），已有的事实和复现命令带到第 2 步。

**完成：** 对话里有基线摘要、一句话现象和修好标准、起始档位、`<短名>`；快修档已修完，或已转到第 2 步且主仓库除基线外无本轮增量。

## 现场

| 位置 | 路径 | 写者 |
|---|---|---|
| 主仓库 | `<父目录>/<repo>` | 全程不写，只用来记基线和建 worktree |
| 任务 worktree | `<父目录>/<repo>-wt-<短名>`，分支 `fix/<短名>`（项目有分支规范时按规范） | 分时独占，见下 |
| duo 目录 | worktree 私有 git 目录下的 `duo/`：`git -C <worktree> rev-parse --absolute-git-dir` 的输出加 `/duo`。放 `progress.md`、`logs/` 和 `running` 标记 | A 建目录，之后只有 B 写 |
| flow 仓库 | `<父目录>/<repo>-flow/`，自带 git；本任务子目录 `<短名>/`，根目录有 `registry.md` | 只有 A |

duo 目录不在工作区里，`git status` 看不到它，也不用改 `info/exclude`；`git worktree remove` 时它会一起删掉。

**运行生成物**：跑复现或测试时自动生成、项目又没有忽略的缓存和编译产物，例如 `__pycache__/`、`bin/`、`obj/`。worktree 从 HEAD 新建，所以里面的未跟踪文件只可能是 A 或 B 造出来的。运行生成物不算打点，不提交，也不让 worktree 变脏。下文说 `git status --short` 为空，都是指除了运行生成物以外为空。

任务 worktree **分时独占**：
- A 诊断期间由 A 独占。A 的打点从不 commit，交给 B 前清理到 `git status --short` 为空。
- B 在跑时由 B 独占，A 只读。A 读 git 一律加 `--no-optional-locks`，审查钉在 commit sha 上，不读 B 的工作区。
- B 结束本轮、A 还没 resume 它时，A 可以在 worktree 里运行命令。A 不改跟踪文件，不 commit，不 checkout，跑完后 `git status --short` 和 B 交回时一致。A 的 shell 跑完就切回 flow 仓库：Windows 上，shell 的工作目录停在 worktree 里，第 9 步就删不掉它。
- B 在跑而 A 要亲手做实验时，A 用 `git worktree add --detach <临时路径> <sha>` 开临时 worktree，用完即删。

A 和 B 都不用 `git stash`：stash 栈由同一仓库的全部 worktree 共享。

flow 仓库里的每次写入，A 都立即 commit。**先落盘再回复**：裁决、审查结论和攒批意见，都要先写进文件、commit 之后，才算做完，才能通知 B 或回复用户。

**门槛硬条件**，碰到任一条就不能豁免：
- 需要外部裁决：改动会改变别的团队、协议或接口属主定下的约定。
- 碰到关键路径：按 `registry.md` 的关键路径清单判断。
- 属于历史翻车域：`registry.md` 里该模块出过 P0 或 P1，或者该模块的 git 历史里有回滚、热修提交。

A 先自己判断，拿不准才问用户：
- 关键路径清单为空时，A 按代码先拟一份，写进 `registry.md` 并标「A 推断」。参考范围：鉴权与权限、资金与计费、数据写入与迁移、对外接口与协议、密钥与安全、并发与调度核心。
- 历史翻车域：查 `registry.md`，再运行 `git -C <主仓库> log --oneline -i -E --grep "revert|hotfix|回滚|热修" -- <模块路径>`。两处都没有记录，就算未命中。
- 外部裁决和关键路径：从代码和方案能确认没碰到，就算未命中；碰到了，或者拿不准，问用户，时机见第 4 步。
- 用户答不上，按命中处理，在 `registry.md` 记「用户不确定」，下次同一模块直接按命中，不再问。用户的答复都写回 `registry.md`。

## 2. 建现场

1. 记下目标分支：`git -C <主仓库> branch --show-current`。输出为空（detached HEAD）时，目标分支记为「待用户」。
2. 建任务 worktree：`git -C <主仓库> worktree add -b fix/<短名> <父目录>/<repo>-wt-<短名> HEAD`。运行前先查短名用过没有：分支 `fix/<短名>`，以及 flow 仓库里的 `<短名>/`、`archive/<短名>/` 和 tag `<短名>-v1`。任一项已经存在，短名依次加后缀 `-2`、`-3`，直到四项都不存在。
3. 建 duo 目录和其中的 `logs/`。项目需要装依赖时，在后台装，输出写进 `logs/deps.txt`，命令结束时追加一行 `DEPS_DONE exit=<退出码>`，不等它结束，直接往下做。
4. 查提交身份：在 worktree 里运行 `git config user.name` 和 `git config user.email`，两个都有值就用它们。缺了，从 `git -C <主仓库> log -5 --format="%an <%ae>"` 里挑候选，留到确认提问时问用户。
5. flow 仓库不存在时：建目录，`git init`，按 [files.md](files.md) 建 `registry.md`。flow 仓库没有可用的提交身份时，给它配仓库级身份：`user.name` 为 `fixing-bugs-duo`，`user.email` 为 `fixing-bugs-duo@localhost`。flow 仓库只在本机用，这个身份不会进任务分支。建本任务子目录 `<短名>/`，commit。
6. 读 `registry.md`，按「门槛硬条件」逐条核对，记下已命中、未命中和要问用户的。先不问，到第 4 步按需要再问。

**完成：** worktree、duo 目录和 flow 子目录都在，flow 仓库已 commit；对话里有目标分支、提交身份，以及三条硬条件的现状。

## 3. 诊断

在任务 worktree 里做 `fixing-bugs` 的 `full.md` 第 1–2 段。

- 原始复现命令和一次性 harness 放进 flow 的 `<短名>/repro/`，不放进 worktree。这样清理打点后它们还在，B 也能直接运行。
- A 自己搭复现、打点。同时派只读子 agent 并行侦察：代码路径、git 历史（`log -S`、`blame`、bisect 候选）、日志。用前台 Task，几个侦察 agent 和 A 自己的打点命令放在同一条消息里发出，一起返回，不用等通知。每个子 agent 只拿一句现象和它负责的那个问题，交回带证据（路径加行号，或 commit sha）的结论；不让它们运行复现命令，免得和 A 的打点抢 worktree。
- 干净的 worktree 复现不出、而主仓库能复现时，说明 bug 依赖基线里的未提交改动。停下问用户：先把这些改动提交到一个分支、再从那个分支重建 worktree，还是只带哪几个文件。A 不擅自搬运改动。

**完成：** `full.md` 第 2 段的完成条件全部满足；复现命令和 harness 在 flow 的 `repro/` 里，并已 commit。

## 4. 分流

按根因估算执行顺序，不含 S0 准备步骤。再按诊断时实际跑过的耗时，估一轮「原始复现加相关测试」要多久，下表简称「一轮耗时」：

| 情况 | 做法 |
|---|---|
| 没命中硬条件，并且满足其一：≤2 步；≤4 步且一轮耗时不超过 5 分钟 | **豁免**：A 不开 B，自己在任务 worktree 里按 `fixing-bugs` 修完。没有风险信号时接排查档第 3 步；有风险信号时接 `full.md` 第 3 段，文档放 flow 的 `<短名>/`。按「停下与交付」收尾后，A 按路径 `git add` 本轮改动和新文件，用记下的提交身份 commit。3–4 步的豁免，接着按 [review.md](review.md) 的轻量版派 1 个审查 agent 看维度 1、2，审这个 commit（`<sha>~1..<sha>`）；没有 flow 文档时，给它的文档片段换成根因、修好标准和回归测试的期望。审出的问题修好后，重跑原始复现和相关测试，再另 commit。然后 push，向目标分支建 Draft MR/PR，按下文「交付报告」报告，写明为什么没开 B，再做第 9 步。 |
| 其余没命中硬条件、≤8 步的 | **轻量版**：只在最后一步标 `[M]`，只在最后一步的完成 commit 上做一次全量审查 |
| >8 步，或命中硬条件 | **全流程**：`[M]` 按 [files.md](files.md) 的规则标，每个 `[M]` 做一次全量审查；历史翻车型判据各写一条锚定断言 |

开 B 有固定开销：写 7 个以上 flow 文件、起监视脚本、每步审查。步数少、测试又快时，A 自己修更快。B 划算的是测试慢、步骤多，或有活能并行的 bug。

轻量版和全流程都锚定第一条正式回归测试（锚定断言 A-1）。

有事要问用户时（硬条件拿不准、目标分支待用户、缺提交身份），按分流结果定时机：
- 豁免：现在一次问齐，等回答再分流或交付。
- 轻量版：先按轻量版往下做，问题并进第 6 步的确认提问；答案命中硬条件就改成全流程。
- >8 步：直接走全流程，问题并进第 6 步的确认提问。

**完成：** 对话里有估算步数、一轮耗时、硬条件结论、分流结果和理由；豁免时已转去单会话修复。

## 5. 先开 B 做准备

1. 按 `fixing-bugs`「停下与交付」第 1 步，清掉 worktree 里的打点，直到 `git status --short` 为空。
2. 按 [files.md](files.md) 写 `handover.md` 和只有 S0 的 `steps.md`，再把 `rulings.md`、`batch.md`、`review-state.md` 建成只有标题的骨架（`last_reviewed_sha` 填 worktree 当前 HEAD），commit。B 启动时就要读这些文件。
3. 用后台子 agent 开 B（Cursor：`Task`，`run_in_background: true`，之后每次 resume B 也带上它，否则 A 会一直等到 B 这一轮结束；用户给 B 或审查 agent 指定了模型时，带上 `model`，并记进 `handover.md` 的「模型」），提示词：

```text
你是 fixing-bugs-duo 的执行会话 B。先读 <本 skill 目录>/b.md，按它执行。
- 任务 worktree：<路径>（分支 fix/<短名>）
- duo 目录（progress.md 和日志放这里）：<路径>
- flow 目录（只读）：<父目录>/<repo>-flow/<短名>/
- fixing-bugs 目录：<路径>
- 本轮：只做 S0，方案还没冻结
```

4. 把 B 的 agent ID 写进 `handover.md`，并在对话里告诉用户（带链接）。
5. 在后台起监视脚本，工作目录设为 flow 仓库，用宿主的输出通知唤醒 A。Cursor 用 Shell 的 `notify_on_output`，匹配 `^DUO_(WAKE|ERROR)_<短名>`。B 的转录路径在开 B 时由宿主返回，一并传进去。步骤超时 `<N>` 用 `handover.md` 里的值。
   - Windows：`powershell -NoProfile -ExecutionPolicy Bypass -File <本 skill 目录>/scripts/watch.ps1 -Worktree <路径> -Tag <短名> -Transcript <B 的转录> -StepMinutes <N>`
   - 其他：`DUO_STEP_MINUTES=<N> bash <本 skill 目录>/scripts/watch.sh <路径> <短名> <B 的转录>`

   脚本先打一行 `DUO_READY_<短名> pid=<pid> …`，之后每行是 `DUO_WAKE_<短名> <序号> <事件>`。事件的含义和处理见 supervise.md。

   起脚本后，先等到 `DUO_READY` 行再往下做（Cursor：AwaitShell 匹配 `^DUO_(READY|ERROR)_<短名>`）。等到的是 `DUO_ERROR_` 行时，按它写的原因修好再起。传了转录、READY 行却是 `transcript=False`，说明路径错了，同样修好再起。把 `DUO_READY` 行里的 pid 写进 `handover.md`，停脚本时用它：`Stop-Process -Id <pid>` 或 `kill <pid>`。宿主报的 PID 可能是外层 shell，停掉它，脚本还会在。

   脚本中途出错，会打一行 `DUO_ERROR_<短名> <原因>` 后退出，A 会被唤醒。宿主报告脚本的 shell 退出、又不是 A 停的时，A 重启脚本并更新 pid。worktree 删掉后，脚本打一行 `DUO_EXIT_<短名>` 自己退出，这一行不唤醒 A。换 B 时，用新的转录路径重启脚本。

**退路：两个独立聊天。** 宿主没有后台子 agent，或不能给运行中的子 agent 发消息时：
1. A 把上面的提示词写进 flow 的 `<短名>/b-prompt.md`，请用户新开一个聊天粘贴。
2. 监视脚本打开 `status` 事件，不传转录：Windows 在上面第 5 条的命令里去掉 `-Transcript`，加 `-WatchStatus`；其他平台去掉 `<B 的转录>`，在命令前加 `DUO_WATCH_STATUS=1`。B 每次停下都写 `progress.md` 的 `STATUS:` 行，A 靠 `status` 事件知道。
3. A 给 B 的指令（开始 S1、BLOCKING 答复、P0、交付）追加进 `handover.md` 的「给 B 的指令」，编号 `I-<n>`。commit 后，请用户在 B 的聊天里发「继续」。B 在跑时不用转达，B 会在定点读时读到。
4. B 的 BLOCKING 请求等 30 分钟没有答复时，B 直接问用户。

**完成：** worktree 干净，B 在跑 S0，用户已拿到 B 的 ID，监视脚本在跑，`handover.md` 已 commit。

## 6. 写交接材料并冻结

B 跑 S0 期间，A 在 flow 的 `<短名>/` 里写交接材料：
1. `problem-and-solutions.md` 和 `test-plan.md`：按 `full.md` 第 3–4 段写，路径换成 flow 子目录。
2. `steps.md`：执行顺序，每步附完成判据和对应的用例编号，标 `[M]`，末尾写 DoD。
3. `rulings.md`：预埋区（勿翻案项，以及预见到的歧义和预设答案），锚定登记。
4. `anchored/A-1.*`：第一条正式回归测试的断言文本。

格式见 [files.md](files.md)。

然后用一次提问请用户确认：推荐方案、测试 seam、分流结果（轻量版或全流程），以及第 4 步并进来的问题。用户已授权 A 在范围内自选时，记下授权来源，不再问。等待期间可以继续完善文档。

确认后，答复写进对应文件，commit flow 仓库。冻结要等两件事都到位：用户确认，以及 B 回了 `S0-DONE`、按 supervise.md 的 `S0-DONE` 行核对通过。后到的那件一到就冻结：打 tag `<短名>-v1`，在 `handover.md` 写方案版本，commit，再 resume B：「方案 v1 已冻结，读 steps.md，从 S1 开始」。B 还在 S0 里时，不 resume，也不 interrupt；用户在步骤超时时选了「打断 B」除外。

**完成：** 文件齐全；用户确认或授权有记录；tag 已打；B 已收到开始指令。

## 7–8. 监督、终审与交付

见 [supervise.md](supervise.md)。

## 9. 收尾

用户确认合入或放弃之后（豁免任务同样做）：
1. 在 `registry.md` 回写：
   - 本任务发现的 P0/P1 和所在模块
   - 新的历史翻车域
   - 跨任务有效的勿翻案项
   - 硬条件里用户的答复，以及「用户不确定」的模块
   - 门槛判例：估算步数、实际步数、档位
2. 在 flow 仓库建 `archive/` 目录（已有就跳过），执行 `git mv <短名> archive/<短名>`，然后 commit。`archive/` 不存在时 `git mv` 会失败。
3. 监视脚本还在跑，就按 `handover.md` 里的 pid 停掉。
4. 清理现场。删 worktree 前：
   - 运行 `git -C <worktree> status --short`。只剩运行生成物时，下面的 `worktree remove` 加 `--force`，否则 git 会因为未跟踪文件拒绝删除。还有别的改动或未跟踪文件时，先弄清是谁写的、要不要留，不加 `--force`。
   - A 的 shell 先切出 worktree，从那里启动的后台进程也要停掉。Windows 上，只要还有进程的工作目录在 worktree 里，删除就会失败。这时 git 已注销这个 worktree，只剩目录，切出、停掉这些进程后再删目录。
   - 已合入：`git -C <主仓库> worktree remove <worktree>`，duo 目录随之删掉；再 `git -C <主仓库> branch -d fix/<短名>`。它报 `not fully merged` 时（推送时没带 `-u`，或 squash 合入，都可能这样），确认 `git -C <主仓库> rev-parse fix/<短名>` 等于 MR/PR 的最后一个 commit，再改用 `branch -D`；不相等就停下问用户。远端分支按平台设置处理，多数平台合入时会自动删除。
   - 放弃：同样删掉 worktree，本地分支用 `branch -D` 删。远端分支删不删、Draft MR/PR 关不关，在同一条消息里问用户，默认保留。
   - 用户要求保留现场时，在 `handover.md` 写明原因。

**完成：** `registry.md` 和归档已 commit；监视脚本已停；worktree 和本地分支已删，或写明保留原因。

## 交付报告

Draft MR/PR 建好或确认建不了之后，A 向用户报告：
- 最终档位，以及是否豁免、豁免理由
- 根因
- 改动
- 验证证据
- MR/PR 链接和目标分支
- 两份文档的路径
- 待用户拍板的事项

合入必须由人确认。A 和 B 都不合入，也不做等同于批准合入的动作，例如标记 ready、指派会自动合入的审查者。
