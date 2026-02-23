# ClawFeed 研发规范

> 目标：保证线上稳定，同时保持小团队的迭代速度。

## 核心原则

1. **Production 是红线** — 任何改动先过 staging，线上不能挂
2. **PRD 先行** — 新功能先出产品方案，Kevin 确认再写代码
3. **改动可回滚** — 每次部署前确认能快速回退

## 角色

| 角色 | 人 | 职责 |
|------|-----|------|
| PM / Product | Kevin | 需求定义、PRD 审批、上线审批 |
| Dev | Lisa | 架构、编码、部署 |
| QA | Jessie（待 onboard） | 测试用例、验收测试 |

## 工作流程

```
需求 → PRD → Review → 开发 → Staging 验证 → 上线审批 → Production
```

### 1. 需求 & PRD
- 新功能/大改动：先写 PRD 发到 research hub，Kevin review
- Bug 修复/小调整：可跳过 PRD，但要说清楚改了什么
- PRD 模板：问题 → 方案 → 影响范围 → 测试要点

### 2. 开发
- 所有改动在本地开发完成
- **不直接改 production 数据库**（config 等通过 API）
- 涉及 DB schema 变更必须写 migration 文件

### 3. Staging 验证（必须）
- 部署到 staging 环境：`https://lisa.kevinhe.io/staging/clawfeed/`
- ClawMark 标注问题，直接在页面上反馈
- 验证清单：
  - [ ] 页面正常加载（无白屏/JS 报错）
  - [ ] 新功能按预期工作
  - [ ] 已有功能未受影响（登录、digest 列表、marks）
  - [ ] 移动端正常
  - [ ] 未登录用户视角正常

### 4. 上线审批
- Lisa 在 Feishu 通知 Kevin：改了什么 + staging 验证结果
- Kevin 确认后部署 production
- 紧急 hotfix（线上挂了）：先修后报，但必须事后补说明

### 5. 部署
- Production 部署步骤：
  1. 停 staging 测试（确认没有进行中的验证）
  2. 重启 production server：`launchctl unload/load com.openclaw.clawfeed.plist`
  3. 验证 production 正常：`curl https://clawfeed.kevinhe.io/api/digests?type=4h&limit=1`
  4. 通知 Kevin 已上线

## 分支/版本策略

- 当前：单文件直接改（`web/index.html` + `src/server.mjs`）
- 每次重要功能上线：更新 `CHANGELOG.md`，bump version
- Git tag 标记版本：`git tag v0.x.x && git push --tags`

## 环境

| 环境 | URL | Port | DB | 用途 |
|------|-----|------|-----|------|
| Production | clawfeed.kevinhe.io | 8767 | digest.db | 线上服务 |
| Staging | lisa.kevinhe.io/staging/clawfeed | 8768 | digest-staging.db | 功能验证 |

## 事故响应

1. **发现线上异常** → 立即排查（不等指令）
2. **能快速修复** → 修复并通知 Kevin
3. **不确定原因** → 回滚到上一个工作版本，再慢慢排查
4. **事后** → 记录到 `docs/INCIDENTS.md`：时间、影响、原因、修复、预防措施

## 代码质量检查（上线前）

- [ ] `async/await` 匹配（今天的教训 🔥）
- [ ] 新加的 `fetch` 有 error handling
- [ ] 前端改动在 Chrome DevTools Console 无报错
- [ ] 数据库 migration 幂等（可重复执行）
- [ ] 环境变量改动同步到 `.env` 和 launchd plist

## 今日教训记录

**2026-02-23 Production 白屏事故**
- 原因：feedback IIFE 用 `await` 但没有 `async`，导致 JS 语法错误，整页崩溃
- 影响：线上白屏约 10 分钟
- 修复：`(function()` → `(async function()`
- 预防：上线前必须过 staging + console 无报错检查
