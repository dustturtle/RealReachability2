# RealReachability2 调研 Checklist

## 1. 调研范围
- Swift 主实现：`/Users/llzz/Desktop/gitprojs/RealReachability2/Sources/RealReachability2`
- Objective-C 主实现：`/Users/llzz/Desktop/gitprojs/RealReachability2/Sources/RealReachability2ObjC`
- 测试：`/Users/llzz/Desktop/gitprojs/RealReachability2/Tests`
- 构建与 CI：`/Users/llzz/Desktop/gitprojs/RealReachability2/Package.swift`、`/Users/llzz/Desktop/gitprojs/RealReachability2/.github/workflows/ci.yml`
- 文档：`/Users/llzz/Desktop/gitprojs/RealReachability2/README.md`

## 2. 当前状态基线（已验证）
- `swift build -v`：通过。
- Swift 单元测试：通过（`RealReachability2Tests.RealReachability2Tests`，43/43）。
- ObjC 单元测试：通过（`RRReachabilityTests`，46/46）。
- HTTP 集成测试抽样：通过（`testHTTPProberWithShortTimeout`）。
- Swift ICMP 集成测试抽样：出现挂起（`testICMPPingerWithShortTimeout`，需手动终止）。

## 3. 架构结论（简版）
- 设计方向正确：`NWPathMonitor + HTTP + ICMP` 的混合探测模型。
- Swift 使用 async/await + `AsyncStream`；ObjC 使用通知回调模型。
- 双栈结构清晰，便于独立演进与对比验证。

## 4. 关键风险清单（按优先级）

### P0（先修）
- [ ] **Swift ICMP 可能悬挂**
  - 位置：`/Users/llzz/Desktop/gitprojs/RealReachability2/Sources/RealReachability2/Prober/ICMPPinger.swift:45`
  - 说明：`PingOperation` 为局部对象，切主线程时 `[weak self]`，可能导致生命周期提前结束、continuation 不 resume。

- [ ] **ObjC 一次性检查在未启动 monitor 时可能误判不可达**
  - 位置：`/Users/llzz/Desktop/gitprojs/RealReachability2/Sources/RealReachability2ObjC/RRReachability.m:129`
  - 说明：`checkReachabilityWithCompletion` 直接依赖 `pathMonitor.isSatisfied`，而 monitor 默认未启动。

### P1（第二阶段）
- [ ] **Swift 6 并发兼容风险（async 上下文里直接 lock/unlock）**
  - 位置：`/Users/llzz/Desktop/gitprojs/RealReachability2/Sources/RealReachability2/RealReachability.swift:162`
  - 说明：当前是 warning，后续 Swift 6 语言模式会升级为 error。

- [ ] **PathMonitor 可重启语义风险**
  - 位置：`/Users/llzz/Desktop/gitprojs/RealReachability2/Sources/RealReachability2/Monitor/PathMonitorWrapper.swift:15`
  - 说明：`NWPathMonitor` 被 cancel 后复用存在行为不确定性。

- [ ] **流模型仅单订阅，可能互相覆盖**
  - 位置：`/Users/llzz/Desktop/gitprojs/RealReachability2/Sources/RealReachability2/RealReachability.swift:95`、`/Users/llzz/Desktop/gitprojs/RealReachability2/Sources/RealReachability2/Monitor/PathMonitorWrapper.swift:27`
  - 说明：当前 continuation 单实例，多个订阅者会相互抢占。

- [ ] **README 与 SPM 平台声明不一致**
  - 位置：`/Users/llzz/Desktop/gitprojs/RealReachability2/README.md:10`、`/Users/llzz/Desktop/gitprojs/RealReachability2/Package.swift:8`
  - 说明：README 声称 ObjC iOS 12+，但 package 平台全局 iOS 13+。

- [ ] **CI 过滤策略不精确**
  - 位置：`/Users/llzz/Desktop/gitprojs/RealReachability2/.github/workflows/ci.yml:34`、`/Users/llzz/Desktop/gitprojs/RealReachability2/.github/workflows/ci.yml:52`
  - 说明：`--filter RealReachability2Tests` 会包含集成测试；ObjC 过滤名当前可能匹配不到目标。

## 5. 下一步执行顺序（建议）
- [ ] 第 1 步：修复 P0（Swift ICMP 生命周期/超时兜底、ObjC 一次性检查路径获取逻辑）。
- [ ] 第 2 步：修复并发与流模型（Swift 6 兼容、monitor 重启语义、多订阅广播）。
- [ ] 第 3 步：修复工程面（CI 过滤、文档与平台声明统一）。
- [ ] 第 4 步：补齐针对性回归测试（尤其是 ICMP 超时与挂起场景）。

## 6. 每步完成后的验收标准
- [ ] 构建：`swift build -v` 通过且无新增 warning。
- [ ] 单测：Swift/ObjC 单测全绿。
- [ ] 集成测试：HTTP 与 ICMP 关键用例可在限定超时内结束，不出现挂起。
- [ ] CI：测试分层明确（unit/integration 可控运行），结果可复现。
- [ ] 文档：README 与 `Package.swift` 平台声明一致。
