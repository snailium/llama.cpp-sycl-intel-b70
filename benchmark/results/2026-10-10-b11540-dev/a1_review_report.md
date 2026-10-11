[entrypoint] headless: exec dsh --profile 'headless_lc' 对代码库 https://github.com/snailium/mqtt2ha 做安全性审查。请列出发现的安全问题，说明风险等级和理由，并给出修复建议。
(node:20) ExperimentalWarning: SQLite is an experimental feature and might change at any time
(Use `node --trace-warnings ...` to show where the warning was created)
# mqtt2ha 安全审查报告

**对象**:https://github.com/snailium/mqtt2ha @ `main` (`2c289f6`) · **代码量**:~4,250 行 Go + Dockerfile + 迁移脚本 · **方法**:全量人工审计(已克隆至本地逐文件审阅)

先说结论:这个项目已经历多轮自我加固(CSRF、组件白名单、导入校验、限流等注释可见),基础面不错。但仍有若干真实问题,按风险等级列出:

---

## 🔴 高危

### H-1 Web UI 默认无认证 + 绑定 `:8080` 所有网卡
**位置**:`config.go:33-48`(`DefaultConfig`),`websec.go:86-129`,`main.go:62-78`

`http` 默认为 `":8080"`(所有接口),而 `WebToken` 默认空。代码明确设计为"空 token = 不做任何认证"(`requireAuth` 直接放行)。Dockerfile 还 `EXPOSE 8080`、README 引导用户直接打开 UI。

**风险**:任何能到达该主机的网络参与者(同网段设备、恶意 IoT 设备、ARP 欺骗、路由器管理页)可:
- **批准/拒绝任意待审设备** → 向 HA broker 注入伪造 discovery(retained QoS1);
- **`POST /api/import` 整体替换注册表**(全量删除+重写,sqlite/yaml 两个后端都是);
- 篡改实体元数据、增删黑名单。

**放大因素**:broker 侧默认订阅 `"#"` 且无 TLS(见 M-2),意味着 mqtt2ha 的 MQTT 凭据往往拥有 broker 全量读写权;Web UI 失陷 ≈ 获得以该身份向 `homeassistant/#` 发布任意 retained discovery 的能力,HA 会照单全收。

**修复建议**:
1. **默认 fail-closed**:`http` 非空且 `web_token` 为空时启动失败(或至少降级为仅监听 loopback 并打大日志);
2. 默认绑定 `127.0.0.1:8080`,需要 LAN 访问时显式配置;
3. README/Dockerfile 中把"设置 web_token"列为启用 UI 的前置步骤,而非已知限制。

---

## 🟠 中危

### M-1 Web 服务无任何 TLS 支持,token 明文传输
**位置**:`main.go:65`(`&http.Server{Addr: cfg.HTTP, Handler: mux}`)

整个 HTTP 栈没有 `TLSConfig`/证书配置项。一旦按 H-1 的建议设置 `web_token`,该 token 在 LAN 上以明文 `Authorization: Bearer` 头传输,可被同网段抓包直接复用;CSRF token 同理(渲染进页面、随表单提交)。

**修复建议**:增加 `tls_cert`/`tls_key` 配置项启用 HTTPS;或在文档中明确要求经反向代理终结 TLS,并给出 `ProxyHeaders` 安全处理示例。

### M-2 MQTT 连接无 TLS 选项
**位置**:`mqtt.go:50-67`(`Start()`)

未调用 paho 的 `SetTLSConfig`,broker URL 只能是明文 `host:1883`。配置里存有 broker 用户名/密码,在跨网段部署时凭据和全部订阅数据(含设备序列号、厂商等元数据)均明文传输;MQTT 侧无 TLS 也意味着任何能注入消息的节点都可以向 mqtt2ha 推送伪造 discovery。

**修复建议**:支持 `broker: "mqtts://..."` 并映射到 `tls.Config`(CA/客户端证书可配置),至少提供 `mqtt.use_tls` 开关 + CA 路径。

### M-3 认证限流可被 X-Forwarded-For 绕过(DoS 面)
**位置**:`websec.go:100-127, 179-185`

限流键是 `r.RemoteAddr`(直连时正确)。但经反向代理部署时(README 自己推荐的方式),所有客户端共享代理 IP,攻击者可反复触发 401 使**整个 UI 对所有用户锁定 5 分钟**;且锁定期内无重试上限语义——配合 M-1 的明文 token,这是可被主动利用的拒绝服务向量。

**修复建议**:
- 支持显式 `trusted_proxies` 配置,仅从可信代理读取 XFF 末位;
- 锁定期间对已锁定 IP 直接快速返回(现已做到),但应把阈值/TTL 做成可配置项,并在日志中区分"锁定命中"与"新失败"。

### M-4 导入接口:黑名单无校验 + 整体替换语义
**位置**:`web.go:446-547`(`handleImport`),`store.go:405-446`,`yamlstore.go:730-797`

设备/实体字段校验较严格(topic 非空、id 唯一、组件白名单、status 枚举),但 `blacklist` 数组**只做去空白过滤**,任意字符串可入库;且导入是"先全删后重写"(sqlite 在单事务内原子,yaml 后端是先写新文件再删旧文件——非原子,中途失败会留下混合状态,注释自己也承认 "stale file survives a restart")。

**风险**:攻击者(需过 H-1)或误操作可:清空黑名单重新注入、用超大设备数/实体数耗尽内存与磁盘(yaml 后端每个 topic 一个文件,可制造大量文件)、使 yaml 后端进入不一致状态。

**修复建议**:
- 对 blacklist 条目做格式校验(非空、无控制字符、长度上限);
- 限制单次导入的 devices/entities 数量上限;
- yaml 后端导入改为"写临时目录 → 原子切换"(symlink/rename)或至少失败时回滚已删文件。

### M-5 CSRF token 为进程级单例,且无会话隔离
**位置**:`websec.go:32-38, 45-81`

CSRF token 每进程一个、所有客户端共享、重启才变化。它只能防"跨站表单提交",不能防已持有 UI 访问权的多用户互相操作(本应用无多用户概念,影响有限),但更实际的问题是:**token 渲染在页面 HTML 里并随每个表单提交**,配合 M-1(无 TLS)意味着任何能读页面的中间人都能重放写操作。

**修复建议**:若引入会话/用户体系,改为 per-session token;短期至少与 H-1/M-1 联动——启用 UI 即强制 token + TLS。

---

## 🟡 低危 / 加固项

### L-1 MQTT 客户端 ID 可预测
**位置**:`mqtt.go:53`(`randSuffix()` 用 `time.Now().UnixNano()%100000`)

若 broker 启用"相同 client ID 互踢",知道启动时间的攻击者可伪造同 ID 连接把 mqtt2ha 踢下线(短暂 DoS,且其 auto-reconnect 会反复被踢)。改用 `crypto/rand` 生成 8 字节 hex 即可。

### L-2 `onSelfDiscovery` 的黑名单写入可被 MQTT 消息操纵
**位置**:`mqtt.go:104-160`

任何能向 `homeassistant/+/+/config` 发布合法 JSON(含 `state_topic`)的节点,都能让 mqtt2ha **自动把该 state_topic 加入黑名单并删除对应 pending 设备**。这是设计意图(识别自发现节点),但黑名单表无上限、无来源审计——恶意/故障节点可批量污染黑名单。建议:记录触发源 topic、对单次 burst 内的自动黑名单写入加日志告警或数量阈值。

### L-3 YAML 后端文件名注入面
**位置**:`yamlstore.go:102-110`(`sanitizeTopic`)

替换表只覆盖 `/ \ # + * 空格`,但 MQTT topic 可以是任意 UTF-8(含 `..`、`/` 已被替换所以无路径穿越,但 `.` 保留 → 理论上可构造 `.yaml` 结尾或隐藏文件名)。实际危害小(文件内容仍被 yaml 解析校验),但建议对生成的 basename 做最终白名单校验(`^[A-Za-z0-9._-]+$`)并拒绝空/`.`/`..`。

### L-4 SQLite DSN 拼接
**位置**:`store.go:89`

`path + "?_pragma=..."` —— 若 `database` 配置路径含 `?` 或 `&`,DSN 语义会被破坏(非注入,但属健壮性问题)。建议用 `url.Values` 构造。

### L-5 错误信息回显
**位置**:`web.go:130,135,230,258,…`

多处 `http.Error(w, err.Error(), 500)` 把内部错误(含文件路径、SQL 细节)直接返回给客户端。建议生产环境只回显通用 500,详情进日志。

### L-6 依赖与构建
- `go.mod` 依赖较新(paho v1.5.1、gorilla/websocket v1.5.3),未见已知 CVE;但**仓库内未看到 govulncheck 实际运行的产物/配置**(README 声称 CI 有,本次浅克隆无法验证)。建议保留并公开 CI 状态徽章。
- Dockerfile 以非 root 运行、多阶段构建、`-trimpath`,实践良好 ✅。

---

## ✅ 做得好的地方(避免误报)

- SQL 全部参数化,无拼接注入;
- `subtle.ConstantTimeCompare` 用于 token/CSRF 比较;
- 请求体有 1 MiB 上限(multipart/urlencoded/import 三处都做了);
- 组件白名单 + 导入字段级校验(fail-closed)思路正确;
- 限流用 `RemoteAddr` 而非 XFF(直连场景下是对的);
- yaml 写盘用 temp+rename,崩溃安全。

## 优先级建议

| 顺序 | 事项 | 理由 |
|---|---|---|
| 1 | H-1:默认启用认证或仅 loopback | 当前最大暴露面,一行配置即可利用 |
| 2 | M-1 + M-2:TLS(web + mqtt) | 凭据与 discovery 注入的传输层根因 |
| 3 | M-4:导入黑名单校验 + 数量上限 | 整体替换接口的最后缺口 |
| 4 | M-3 / L-1~L-5 | 加固项,可随版本迭代 |

需要的话我可以把 H-1 和 M-4 的修复直接写成补丁。
