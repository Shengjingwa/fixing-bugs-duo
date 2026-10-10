# real-problems 运行笔记：fixing-bugs-duo

2026-10-10 运行。本轮找出 15 条真问题，另有 7 条候选标准待用户决定是否采纳。用户批准了清单和最终方案，改动已落地并验收，见第 10 节。

## 1. 基准信息

- 修改对象（项目根目录 `C:\Users\Administrator\Projects\fixing-bugs-duo`，基线 commit `5c4fc1f`）：
  - `skills/fixing-bugs-duo/SKILL.md`、`b.md`、`supervise.md`、`review.md`、`files.md`
  - `skills/fixing-bugs-duo/scripts/watch.ps1`、`scripts/watch.sh`
- 文类：Agent Skill。前置阅读：`~/.cursor/skills/writing-for-agents/SKILL.md` 和 `SKILL-MECHANICS.md`，主 agent 和 3 名陪审员都已读。
- 核对材料：
  - `C:\Users\Administrator\.cursor\skills\fixing-bugs\SKILL.md` 和 `full.md`：用来核对修改对象引用的章节。
  - `C:\Users\Administrator\AppData\Local\Temp\rp-duo\host-facts.md`：三次试跑实测的宿主行为，共 12 条。
- 其它指针：`README.md` 只当背景，不审；最终方案改变了它描述的行为时，才同步改它。
- 用户指定改动：无具体改动。用户要求修复阶段「用 /fixing-bugs 优化」，记为方法要求：每处修改先做出能看见的失败，再改，再验证。
- 用户声明不动的部分：无。门槛硬条件的宽窄是待用户拍板的产品决定，不当问题报。

## 2. 完成条件（本轮工作假设）

原文没有整体判据，下面 4 条从 skill 的自述和用户的「高效干净、鲁棒没有问题」提炼而来。它们不改变评审范围和修改权限，所以记为工作假设，没有单独提问：

- C1 可执行、不卡死：A 和 B 照文件做，每个分支都有出口；没有等不到的信号、互相矛盾的指令，也没有达不到的「完成」条件。
- C2 与实际一致：命令、脚本参数和输出、路径、git、Cursor 宿主、Windows 的行为和文中写的一致；两个监视脚本语义一致。
- C3 引用闭合：跨文件引用的章节、字段、事件、状态都存在，同一件事各处说法一致。
- C4 按需加载：B 只读 b.md 和它点名的文件，A 在声明的时机读各文件，子 agent 只拿声明的片段；做某一步必需的信息都在声明范围内。

## 3. 调研、模式与模型

- 调研范围：调研项目代码与实际环境（推荐项）。3 名陪审员各自在沙箱 `%TEMP%\rp-duo\j1`–`j3` 里实测脚本和 git 命令。
- 评审模式：独立陪审团，3 人，任务书 `%TEMP%\rp-duo\juror-brief.md`，三人输入完全相同。
- 模型：三人都继承父会话模型。系统约定子 agent 默认继承，用户没点名模型。因此下文的「指出人数」只是独立上下文的重合信号，不同模型数都是 1。
- 陪审员：陪审员 1（agent `bd3dd8a6`）、陪审员 2（agent `4bb53e4b`）、陪审员 3（agent `beb432e0`）。三人都报告沙箱里没有残留进程，项目仓库未改动。

## 4. 真问题

按指出人数从多到少排列。

| 编号 | 位置 | 不改时的失败 | 条件 | 指出人数 |
|---|---|---|---|---|
| T1 | SKILL.md 第 5 步退路第 2 条「监视脚本加 `-WatchStatus`」 | `watch.sh` 只认环境变量 `DUO_WATCH_STATUS`，把 `-WatchStatus` 当成转录路径。非 Windows 的退路里，B 写的 `STATUS:` 不会唤醒 A，只能等 20 分钟一次的心跳。三人都实测复现 | C2 | 3 |
| T2 | SKILL.md 第 4 步豁免行「交付前…派 1 个审查 agent…收尾后…commit」 | 审查 agent 派出时改动还没 commit，而固定前缀只许按 sha 读、不读工作区。新测试是未跟踪文件，`git diff` 也看不到。结果是空审查 | C1 | 3 |
| T3 | SKILL.md 第 9 步「已合入：…`branch -d fix/<短名>`」 | squash 合入，或推送时没带 `-u`，`branch -d` 都报 `not fully merged`。文中只在「放弃」时给了 `-D`，第 9 步的完成条件达不到。三人都实测复现 | C2 | 3 |
| T4 | watch.sh:56 `transcript_len` 判断的是上一轮的 `$t` | 转录某一轮读不到，之后 watch.sh 永远按「没有转录」处理：不再报 `stall`，改报心跳。watch.ps1 在同样场景下照常报 `stall`。两人实测复现 | C2 | 3 |
| T5 | supervise.md 第 7 步「完成：…`test-plan.md` 已转抄到最终 sha」；b.md:19「A 审查时会转抄过去」 | 转抄按 review.md 和第 8 步第 2 条，要到验收时才做。B 交回 DOD 时，第 7 步的完成条件按定义达不到。b.md 的说法和 review.md 相反 | C1、C3 | 2 |
| T6 | supervise.md heartbeat 行「按卡住处理」；「卡住」小节第 1、2 条 | 退路里 B 是用户开的聊天，A 不能 interrupt 它；退路也不传转录，脚本从不发 `stall`，第 2 条等不到。这个分支没有出口，换 B 也做不到 | C1 | 2 |
| T7 | SKILL.md 第 2 步第 2 条「分支已经存在时，短名加后缀 `-2`」 | 旧任务收尾后分支已删，但 flow 里留着 tag `<短名>-v1` 和 `archive/<短名>/`。重用同一短名时，冻结报 `tag already exists`，归档变成 `archive/<短名>/<短名>`。两人实测复现 | C1、C2 | 2 |
| T8 | supervise.md 第 7 步首段「之后到达的通知…就结束本轮」；「B 本轮结束」行「同一行只处理一次」 | 照字面读，`stall`、只跑测试没有新 commit 的 DOD、P0 修完后的第二次 `STATUS: DOD` 都会被跳过，A 和 B 一起停住 | C1 | 2 |
| T9 | b.md「读什么」「只读下面这些，其余不读」 | 清单里没有 `batch.md`，第 3 条定点读和交付却要读它。收尾要重跑全部本轮必做用例，而 B 只许读步骤引用的用例行；没被引用的必做用例会漏跑，`n/n green` 不准 | C1、C4 | 2 |
| T10 | review.md P1 行「最后一个 `[M]` 发现的，在 DoD 前修好」；supervise.md 第 7 步 P0 条的 resume 清单；第 8 步第 3 条「发现 P0 时，DoD 撤销」；b.md「A 的消息」 | 最后一个 `[M]` 审出 P1 时，B 已经过了最后一次定点读。P1 不在 A 可以 resume B 的清单里，DoD 撤销也只针对 P0。DoD 的「P1 全部 fixed」达不到。轻量版的 P1 全在这个时点出现 | C1 | 1 |
| T11 | supervise.md「换 B」条 | 压缩过频触发换 B 时，旧 B 多半正在一轮中间。文中没要求先停旧 B，新旧两个 B 会同时改同一个 worktree、在同一分支上交替 commit | C1 | 1 |
| T12 | b.md S0 第 4 条「确认它像 `handover.md` 写的那样失败」、第 7 条「直接做 S1」；SKILL.md 第 6 步「B 结束 S0 前会读 `handover.md`…直接开始 S1」 | 复现不符时 B 没有出口，记一笔就往下做，最后「原始复现：通过」是空证据。冻结发生在 S0 期间时，A 收不到 S0-DONE，supervise.md 里 S0-DONE 那一行的核对不会做 | C1 | 1 |
| T13 | SKILL.md 第 6 步和 supervise.md S0-DONE 行的开始指令「读 steps.md，从 S1 开始」；b.md 已读游标「rulings.md 到 <最后读到的标题>」；files.md 里 `## 裁决` 排在 `## 方案版本` 之前 | B 在 S0 读的是只有标题的 `rulings.md`。冻结前写进预埋区的勿翻案项，B 只在碰到歧义时才查。新的 R-n 追加在 `## 方案版本` 之前，按标题位置记的游标会漏掉它们 | C1、C4 | 1 |
| T14 | SKILL.md 第 6 步、supervise.md 各处「resume B」 | 开 B 时写了 `run_in_background: true`，resume 时没写。前台 resume 会让 A 一直等到 B 这一轮结束：期间不能逐个 commit 审查，也不能因 P0 interrupt；B 挂住时 A 也跟着挂住。试跑里前台 resume 交付时，A 确实被挡住直到 B 返回 | C1、C2 | 1 |
| T15 | b.md 交付段末「MR/PR 的评审意见由 A 转给你，按 `Flow: fix` 处理」 | b.md 没要求修完 push，也没有对应的 `STATUS:`。supervise.md 第 8 步在等「B 推完」，MR 上却看不到修复 | C1、C3 | 1 |

## 5. 淘汰

- D1 冻结时按 `progress.md` 的 S0-DONE 去 resume，可能撞上 B 还在跑（陪审员 1 K-9、陪审员 2 K-4）。淘汰理由：resume 失败后流程能自己往前走。B 还在收尾时，它结束本轮会发通知，A 按 S0-DONE 行 resume；B 已进 S1 时，正是要的状态。没有卡死，也没做错事。
- D2 `watch.ps1:88` 的 `Get-Item` 在 `running` 被删的瞬间可能抛错（陪审员 1 S-1）。淘汰理由：抛错后脚本打 `DUO_ERROR_` 退出，文中有重启出口，不卡死。改记为候选标准 S3。

## 6. 候选标准（未启用，待用户决定）

- S1 删掉 supervise.md 第 8 步第 2 条「B 交回 `STATUS: DOD` 时终审 agent 还在跑，也不用等」。终审用前台 Task，A 等它返回期间收不到 DOD 通知，这个分支走不到。来源：陪审员 2 S-1、陪审员 3 S-1、陪审员 1 K-2 第 5 点。
- S2 「A 在哪几种情况下 resume B」只在 supervise.md 留一份清单，b.md 同步。现在 b.md 写 4 种，supervise.md 写 6 种。来源：陪审员 2 S-2、陪审员 3 S-3。
- S3 监视脚本容忍 `running` 标记在检查中途被删。来源：陪审员 1 S-1、E-9。
- S4 监视脚本解析 `git status --porcelain` 时不受非 ASCII 路径转义影响（加 `-z` 或 `-c core.quotepath=false`）。没有实测。来源：陪审员 2 S-3。
- S5 b.md 提交身份一条写出完整写法 `git -c user.name=… -c user.email=… commit …`。`-c` 放到 `commit` 后面会报错，但报错可见，B 能自行改正。来源：陪审员 1 S-3。
- S6 现场表「主仓库全程不写」「duo 目录之后只有 B 写」注明例外（快修档在主仓库修；A 后台装依赖写 `logs/deps.txt`）。具体步骤已写明，不造成失败。来源：陪审员 2 S-4。
- S7 SKILL.md「依赖」的后备查找写明已知安装位置。`fixing-bugs` 是 user-invoked，不在宿主的 skill 清单里，后备查找起不了作用；但主路径（同级目录）可用，读不到时有 `blocked` 出口。来源：陪审员 3 S-4、E-9。

## 7. 去向表

候选：

| 来源 | 去向 |
|---|---|
| 陪审员 1：K-1 / K-2 / K-3 / K-4 / K-5 / K-6 / K-7 / K-8 / K-9 | T10 / T5 / T1 / T6 / T11 / T2 / T3 / T9 / D1 |
| 陪审员 1：S-1 / S-2 / S-3 | S3（经 D2）/ T4 / S5 |
| 陪审员 2：K-1 / K-2 / K-3 / K-4 / K-5 / K-6 / K-7 / K-8 / K-9 | T1 / T3 / T7 / D1 / T12 / T8 / T2 / T4 / T15 |
| 陪审员 2：S-1 / S-2 / S-3 / S-4 | S1 / S2 / S4 / S6 |
| 陪审员 3：K-1 / K-2 / K-3 / K-4 / K-5 / K-6 / K-7 / K-8 / K-9 / K-10 | T1 / T2 / T5 / T3 / T7 / T6 / T13（末句的 batch.md 部分已在 T9 里）/ T4 / T14 / T8 |
| 陪审员 3：S-1 / S-2 / S-3 / S-4 | S1 / T9 的备选改法 / S2 / S7 |

调研事实：

| 来源 | 去向 |
|---|---|
| 陪审员 1：E-6 / E-8 / E-9 / E-2 | T1 / T3 / S3 / S1 |
| 陪审员 1：E-1、E-3、E-4、E-5、E-7、E-10 | 调研：与文档一致（转录末行格式、回滚检索命令、duo 目录随 worktree 删除、watch.ps1 唤醒与 stall 计时、`archive/` 需先建、沙箱无残留） |
| 陪审员 2：E-6 / E-7 / E-9、E-10 / E-12 / E-13 | T1 / T4 / T7 / T3 / D1 |
| 陪审员 2：E-1–E-5、E-8、E-11、E-14、E-15 | 调研：与文档一致（环境版本、duo 目录、唤醒规则、`running` 延长 stall、`DUO_EXIT_`/`DUO_ERROR_`、worktree 删除、检索命令、MSYS pid 与 watch.sh:4 的提示一致、沙箱无残留） |
| 陪审员 3：E-2 / E-3 / E-5 / E-6 / E-8 / E-9 / E-11 | T1 / T4 / T3 / T7 / T14 / S7 / T6 |
| 陪审员 3：E-1、E-4、E-7、E-10 | 调研：与文档一致（watch.ps1 行为、worktree 删除、检索命令、引用的章节都存在） |

## 8. 改法与异议裁决

用户在清单闸门选了「按这份清单继续」，候选标准 S1–S7 都不采纳。改法作者（agent `922ee306`） 写了 15 条改法，其中 T1、T2、T3、T4、T6、T7、T13 在沙箱实测了修前和修后。挑刺者（agent `e47d63b7`） 在独立上下文里审，只拿改法稿、修改对象和清单，提了 12 条异议。两人都继承父会话模型。

| 异议 | 针对 | 裁决 |
|---|---|---|
| O-1 审查后的修复没重跑验证 | T2 | 采纳：修好后重跑原始复现和相关测试，再另 commit |
| O-2 转抄从完成条件里消失 | T5 | 采纳：把「`test-plan.md` 已转抄到最终 sha」挪进第 8 步的完成条件 |
| O-3 退路判卡住不看 `running` | T6 | 采纳：heartbeat 行先按「卡住」第 2、3 条核对，再走退路做法 |
| O-4 前台挂住时发「继续」只会排队 | T6 | 采纳：请用户先停掉 B 当前这一轮，再发「继续」并附补写 `running` 的提示 |
| O-5 退路里第二次 `STATUS: DOD` 文本相同，脚本不发 `status` | T8 | 采纳：退路里 B 在 `STATUS:` 行末加写入时间 |
| O-6 收尾第 1 条不重跑必做用例，新读取条目不触发 | T9 | 部分采纳：读取条目改成「收尾时」，收尾判断 DoD 时逐条对照必做用例、缺记录的先跑。不对齐 b.md「和 full.md 不一样的地方」第 3 条：它只会让 B 多跑一遍，不造成失败 |
| O-7 先跑慢验收才查 open 的 P1 | T10 | 采纳：独立验收开始前先查 `batch.md`，有 open 的 P1 直接撤销 DoD |
| O-8 退路里换 B 没停旧聊天 | T11 | 采纳：「换 B」条加退路写法，T6 第 2 步改为引用它 |
| O-9 停手的旧 B 留下半步改动 | T11 | 采纳，换做法：在 b.md「冷启动」让接手的 B 先把前任留下的改动 commit 成 `Flow: wip`，覆盖全部换 B 路径 |
| O-10 S0 期间已打 tag，复现不符回第 3 步后 tag 冲突 | T12 | 采纳：冻结要等用户确认和 S0-DONE 核对都到位，后到的一到就冻结。B 本来就停在 S0-DONE，不多等 |
| O-11 方案升版后 B 不重读 | T13 | 采纳：重读条目改成「收到开始 S1 或方案升版的指令时」，并加上 `handover.md` |
| O-12 评审意见轮次收到 `DELIVERED` 就停脚本，没亲验 | T15 | 采纳：这一轮先亲验 fix commit，通过再停脚本 |

主 agent 另做一处调整：T13 的游标问题改为按编号记（`rulings.md` 到 `<最后读到的 R-n>`），不挪 files.md 模板顺序。改动更小，也不依赖文件布局。

## 9. 最终方案

| 文件 | 条目 |
|---|---|
| `SKILL.md` | T1 退路第 2 条写出两种启动写法；T2 豁免先 commit 再审、审后修复重跑验证；T3 `-d` 报错时核对 tip 再 `-D`；T7 短名查重扩到分支、flow 子目录、归档、tag；T12 冻结等用户确认和 S0 核对都到位；T14 开 B 那句写明之后每次 resume 也带 `run_in_background: true` |
| `b.md` | T5 转抄说法改为验收时；T9、T10、T13 读取清单加三条；T13 定点读和游标按编号；T10「A 的消息」加第 5 种「DoD 撤销」；T11 冷启动加接手时提交前任改动；T12 S0 第 4、7 条；T8 退路 `STATUS:` 行末加时间；T9 收尾对照全部必做用例；T15 评审意见轮次 push 并回 `DELIVERED` |
| `supervise.md` | T8 首段限定 `commit`、`request`，「B 本轮结束」行每轮处理一次；T12 S0-DONE 行；T6 heartbeat 行和退路段落；T10 P1 送达、resume 清单、验收前查 open 的 P1、撤销条件；T11「换 B」条和「卡住」第 2 条；T5 第 7、8 步完成条件；T15 第 8 步第 5 条和末段 |
| `scripts/watch.sh` | T4 第 56 行条件改为 `[ -n "$transcript" ]` |
| `README.md` | 用法前提第 2 条补退路卡住时的做法 |
| `review.md`、`files.md`、`watch.ps1` | 不改 |

验证方法（按 fixing-bugs）：T1、T4 用沙箱脚本先复现失败、改后再跑同一脚本；其余文字改动逐条用 `rg` 确认原句已换、新句在位，再照文件走查原失败场景。

## 10. 执行与验收

2026-10-10 改动落地，改前备份在系统临时目录，验收通过后已删除。

- T1：沙箱脚本 `t1.sh` 照旧写法起 `watch.sh`，只有 `DUO_READY` 行，没有 `status` 事件；照新写法（`DUO_WATCH_STATUS=1`）起，输出 `DUO_WAKE_t1 1 status STATUS: DOD`。改 `watch.sh` 后重跑，结果不变。
- T4：沙箱脚本 `t4.sh` 让转录缺失 5 秒，之后没有任何活动。修前输出 `DUO_WAKE_t4 1 heartbeat`，没有 `stall`；修后输出 `DUO_WAKE_t4 1 stall`。`bash -n` 语法检查通过。
- 其余条目：54 项文字核对里 53 项通过；未通过的一项是检查写得太宽，命中了 `watch.sh` 循环里本该保留的 `if [ "$t" != -1 ]`，不是缺陷。
- 改动范围：`SKILL.md`、`b.md`、`supervise.md`、`scripts/watch.sh`、`README.md`；`review.md`、`files.md`、`watch.ps1` 的哈希和改前一致；`git diff --check` 无输出。
- 落地过程中，替换脚本因 PowerShell 逗号优先级漏改了 4 处、误删了 `supervise.md` 的 `### 汇报` 标题。逐条 diff 时发现，已手工补回，并纳入上面的核对。

待确认：
- T14 只做了文字核对。要在下一次真开子 agent 的试跑里，确认每次 resume B 都带 `run_in_background: true`，且 A 这一轮随即结束。
- T6、T10、T11、T12、T15 这类流程分支只做了照文件走查，没有真实跑到。