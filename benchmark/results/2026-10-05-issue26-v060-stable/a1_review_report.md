[entrypoint] headless: exec dsh --profile 'headless_lc' 对代码库 https://github.com/snailium/mqtt2ha 做安全性审查。请列出发现的安全问题，说明风险等级和理由，并给出修复建议。
(node:20) ExperimentalWarning: SQLite is an experimental feature and might change at any time
(Use `node --trace-warnings ...` to show where the warning was created)
# mqtt2ha 安全审查报告

**审查对象**:https://github.com/snailium/mqtt2ha @ `main` (`2c289f6`,v1.1.4) · 约 4,500 行 Go + Dockerfile + 配置

总体印象:这是一个已经过多轮内部审计的项目,常见基础项做得不错(参数化 SQL、模板自动转义、CSRF token、常量时间比较、组件白名单、导入体大小限制、非 root 容器)。以下按风险等级列出仍然存在的问题。

---

## 🔴 高危

### H1. Web UI/API 默认无认证,且监听所有接口
**位置**: `config.go:46`(`DefaultConfig` 中 `HTTP: ":8080"`、`WebToken: ""`)、`websec.go:86-131`(`requireAuth` 在 `WebToken == ""` 时直接放行)、`main.go:62-71`

**风险**:默认配置下,UI 和全部 API(包括导出/导入/删除设备)暴露在本机所有网络接口上且**零认证**。任何能到达 8080 端口的方(同网段设备、NAT 后的邻居、路由器 UPnP 映射、误开的云安全组)都可以:
- 通过 `/api/import` **整体替换注册表**(可植入伪造的 `state_topic`/实体,劫持 HA 中的传感器读数);
- 批准/拒绝/拉黑任意设备;
- 通过 `/api/export` 读取完整拓扑(所有 MQTT topic、设备名、型号、序列号)。

**理由**:这是"默认安全"原则的直接违反——默认值把服务暴露到 `0.0.0.0:8080` 且无凭据。LAN 场景下攻击面包括 IoT 设备、访客网络等,不可视为可信。

**修复建议**:
1. 默认 `HTTP` 改为 `"127.0.0.1:8080"`(或空字符串禁用),需要远程访问时显式配置;
2. 当 `WebToken == ""` 且监听非回环地址时,启动时打印醒目警告甚至拒绝启动;
3. README 中把"设置 web_token"列为暴露到 LAN 的**强制项**。

---

### H2. MQTT 凭据以明文存于配置文件
**位置**: `config.go:24-25`(`MQTTConfig.Username/Password`)、`mqtt.go:55`(`SetPassword`)

**风险**:broker 密码以明文写在 `config.yaml`(Docker 场景下挂载在 `/app/data` volume)。任何能读该文件或容器的进程/用户都获得 broker 凭据;结合 H1,无认证的攻击者拿到 `/api/export` 虽不泄露 MQTT 密码,但运维层面(备份、git、日志)都会扩散明文密码。

**修复建议**:
- 支持从环境变量(`MQTT_PASSWORD`)或文件读取密码,配置文件中留空时回退;
- Docker 文档示例改用 `env_file`/secret;
- 至少对配置文件做 `0600` 权限提示(程序无法控制挂载权限,需在 README 强调)。

---

## 🟠 中危

### M1. Bearer token 无速率限制之外的"可离线爆破"特性 + 弱 token 默认示例
**位置**: `websec.go:93-128`、`config.example.yaml:27-29`

**风险**:认证仅靠一个静态 bearer token,且限流是**按源 IP**(`clientIPOf` 用 `RemoteAddr`)。攻击者可通过代理池/多出口 IP 绕过限流;若用户使用了弱 token(示例中 `change-me` 风格的短口令),可被离线字典爆破。token 一旦泄露无轮换机制(只能改配置重启)。

**修复建议**:
- 启动时校验 `WebToken` 熵(如 < 32 字节或常见弱值)并警告;
- 支持 token 文件 + SIGHUP 热加载,便于轮换;
- 文档明确:暴露到非受控网络时必须配合反向代理(TLS + IP 白名单)。

### M2. CSRF token 为进程级单例,且 UI 无会话概念
**位置**: `mqtt.go:43`(`NewBridge` 中生成一次)、`websec.go:45-81`

**风险**:token 在整个进程生命周期不变,任何曾打开过页面的脚本/扩展(或 XSS 受害者)持有的 token 长期有效;若未来引入静态资源缓存,token 也可能被持久化。更关键的是:**没有真正的"会话"**,CSRF 只防浏览器自动提交,不防持有 token 的任意客户端——它本质上是第二个弱秘密。

**修复建议**:
- 将 CSRF token 与认证绑定:未设置 `WebToken` 时,CSRF 应要求同源 + `Origin/Referer` 校验(当前完全缺失);
- 或引入 per-session token(配合 cookie),使 UI 具备真正的会话隔离。

### M3. MQTT 数据可被用于"投毒"设备元数据并自动发布(auto 模式)
**位置**: `mqtt.go:162-277`(`onData`)、`infer.go:20-69`、`discovery.go:87-133`

**风险**:在 `mode: auto`(默认)+ `subscribe: ["#"]`(默认)下,任何能向 broker 发布 JSON 消息的客户端(同一 LAN 上的任意设备/脚本)只需 3 条消息(`observe_count: 3`)即可让 mqtt2ha **自动批准并发布** HA discovery。攻击者可:
- 伪造 `name`/`manufacturer`/`model`/`serial`(写入 UI 和 discovery);
- 构造字段名操纵 `device_class`/`unit`(如 `voltage`、`power`)制造误导性实体;
- 通过 `state_topic` 指向自己的 topic,让 HA 显示任意数值。

这本质上是 **MQTT broker 的认证边界**问题——mqtt2ha 信任了 broker 上的一切。虽然这是设计使然,但默认配置(`#` + auto)放大了风险。

**修复建议**:
- README 明确警告:broker 必须启用 ACL/认证,mqtt2ha 不验证发布者身份;
- 考虑默认 `mode: approval`(需人工批准),或至少对 `subscribe` 为 `"#"` 时打印警告;
- 可选:支持"仅允许特定前缀自动批准"的白名单。

### M4. 导入接口可整体替换注册表(含黑名单清空)
**位置**: `web.go:446-547`(`handleImport`)、`store.go:405-446` / `yamlstore.go:730-797`(`ImportSnapshot`)

**风险**:`/api/import` 会 **DELETE 全部 devices/entities/blacklist** 再写入快照。即使有 CSRF + auth,一次误操作(或 token 泄露)即可清空所有黑名单和已批准设备,且无确认步骤、无回滚(导入前不自动备份)。yaml 后端下还会删除磁盘上的旧 yaml 文件(`yamlstore.go:790-795`)。

**修复建议**:
- 导入前自动生成带时间戳的备份(导出到 `backups/`);
- UI 增加"确认替换 N 个设备"步骤;
- API 支持 `?dry_run=true` 预览差异。

### M5. YAML 后端:topic 直接映射文件名,存在路径穿越风险(低概率)
**位置**: `yamlstore.go:103-110`(`sanitizeTopic` + `fileFor`)

**风险**:`sanitizeTopic` 只替换 `/ \ # + *` 为 `_`,但 **不处理 `..`、空字节、或绝对路径字符**。MQTT topic 是任意字符串,若攻击者发布到 topic `../../etc/cron.d/evil`(经 sanitize 变为 `...._.._etc_cron_d_evil.yaml`)——实际上 `.` 被保留,`/` 变 `_`,所以结果是 `...._.._...yaml`,**不会穿越**。但 `sanitizeTopic` 未处理 **空字符串 topic**(生成 `.yaml` 隐藏文件)和 **超长 topic**(文件名 > 255 字节导致 `ENAMETOOLONG`,拒绝服务)。更关键的是:`topicForFile` 通过遍历匹配,若两个不同 topic sanitize 后同名(如 `a/b` 和 `a_b`),会静默覆盖/混淆。

**修复建议**:
- 在 `fileFor` 中校验最终文件名不含 `..`、不以 `.` 开头、长度 ≤ 200;
- 对 sanitize 碰撞追加短哈希(类似 `discovery.go` 的 `topicHash`)。

---

## 🟡 低危 / 加固建议

### L1. HTTP 服务器缺少基础安全头与超时
**位置**: `main.go:65`(`http.Server{Addr, Handler}`)

- 无 `ReadTimeout`/`WriteTimeout`/`IdleTimeout` → 慢连接可耗尽 goroutine(资源 DoS);
- `requireAuth` 设置了 CSP/nosniff/referrer-policy,但 **未设置** `X-Frame-Options: DENY`(UI 可被 iframe 嵌入,配合钓鱼)和 `Strict-Transport-Security`(若经 TLS 代理)。

**修复**:在 `main.go` 补齐三个 timeout(如 30s/30s/120s),在 `requireAuth` 加 `X-Frame-Options: DENY`。

### L2. 错误信息泄露内部细节
**位置**: `web.go:130,199,456,467` 等多处 `http.Error(w, err.Error(), ...)`

SQLite/YAML 错误(含文件路径、表名)直接回显给客户端。应记录到日志,对外返回通用 "internal error"。

### L3. `randSuffix()` 用于 MQTT ClientID 非密码学随机
**位置**: `mqtt.go:343-345`(`time.Now().UnixNano()%100000`)

ClientID 可预测 → 若 broker 未强制唯一 ClientID,攻击者可**顶替** mqtt2ha 的连接(断开其订阅)。风险低(需同 broker + 知道前缀),但应改用 `crypto/rand`。

### L4. MQTT 不支持 TLS
**位置**: `mqtt.go:51-60`(无 `SetTLSConfig`)

broker URL 仅支持 `tcp://`,无法加密传输。LAN 场景可接受,但文档应明确;若用户填 `mqtts://` 会静默失败或回退明文。建议支持 `tls: true` + CA 配置。

### L5. 限流 map 无全局上限
**位置**: `websec.go:100-128`(`authFails map[string]authFailEntry`)

按 IP 计数,但 map 本身无大小限制。攻击者用大量随机源 IP(如通过 NAT 端口扫描)可让 map 增长 → 内存 DoS。TTL 5 分钟会逐步清理,但突发流量下仍可膨胀。建议加 `len(authFails) > 10000` 时强制全量清理或 LRU 淘汰。

### L6. 日志中记录完整 topic / 错误
**位置**: `mqtt.go:245`、`websec.go:191` 等

topic 和错误信息直接进日志,若日志被集中收集(Syslog/ELK),可能泄露内网拓扑。建议对日志做脱敏或级别控制。

### L7. Dockerfile 使用 `alpine:3.20`(固定版本)
**位置**: `Dockerfile:15`

固定 alpine 版本不会自动获得安全更新。建议用 `alpine:3` 滚动 tag,或在 CI 中定期重建;同时可考虑 `distroless/static` 进一步减小攻击面(当前镜像已无 shell,风险有限)。

### L8. `handleExport` 无认证时的信息泄露
与 H1 联动:未设置 `web_token` 时,`/api/export` 直接返回全部设备 topic、型号、序列号——等于把内网 IoT 清单公开。修复 H1 后此项自动缓解。

---

## ✅ 做得好的地方(避免误报)

| 项 | 说明 |
|---|---|
| SQL 注入 | 全部使用参数化查询(`store.go`),无拼接 |
| XSS | `html/template` 自动转义,UI 无 `unsafe` |
| CSRF | 有 token + POST-only + 常量时间比较 |
| 认证比较 | `subtle.ConstantTimeCompare`,防时序侧信道 |
| 导入限制 | body cap 1 MiB、multipart buffer 预限、组件白名单、status 白名单、topic/field 去重校验 |
| 容器安全 | 非 root 用户、无 shell、`-trimpath -ldflags "-s -w"` |
| 优雅关闭 | SIGINT/SIGTERM 处理,SQLite WAL checkpoint |
| 黑名单匹配 | 精确 topic + 路径边界前缀,避免误杀(`home/ups/ups` ≠ `home/ups/upstream`) |

---

## 优先级排序(建议修复顺序)

1. **H1** — 默认监听地址改回环 / 无 token 时警告(10 行改动,收益最大)
2. **H2** — MQTT 密码支持环境变量注入
3. **M4** — 导入前自动备份 + dry-run
4. **M3** — README 强制要求 broker ACL;考虑默认 approval 模式
5. **L1** — HTTP timeout + X-Frame-Options(防慢连接 DoS)
6. 其余按迭代节奏处理

如需,我可以直接提交一个修复 H1 + L1 的 patch。
