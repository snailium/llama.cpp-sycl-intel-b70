# mqtt2ha 安全审查报告

**仓库**: https://github.com/snailium/mqtt2ha (main, v1.1.4) · **规模**: ~3.9k 行 Go + Dockerfile/CI
**范围**: 全部源码逐文件审读(web.go / websec.go / store.go / yamlstore.go / mqtt.go / discovery.go / infer.go / config.go / main.go)+ Dockerfile、CI。

> 先说结论:这个项目已经过多轮自我加固(CSRF、组件白名单、body 上限、auth 限速、SHA 固定的 CI actions),没有发现注入类(SQL/XSS)漏洞——SQL 全部参数化,HTML 用 `html/template` 自动转义。剩余问题集中在**默认配置面**(无认证 + 全量订阅)、**MQTT 信任边界**和 **yaml 后端的本地文件攻击面**。

---

## 高危 (High)

### H1. Web UI/API 默认零认证,且默认监听所有接口
- **位置**: `config.go:46` (`DefaultConfig` → `HTTP: ":8080"`,无 `WebToken`)、`websec.go:93-129` (token 为空时直接放行)、`main.go:62-71`
- **风险**: 默认配置下,任何能到达该主机的网络路径(局域网任意设备、同网段恶意 IoT 设备、云主机公网 IP)都能:批准/拒绝设备、**改写并重新发布 HA discovery**(把 `state_topic` 指向攻击者 topic,篡改传感器读数)、执行 `/api/import` **整体替换注册表**(数据破坏/DoS)、删除黑名单条目。CSRF token 只防同源网页劫持,**不防同网段直接访问**,对"LAN 默认"场景是无效防线。
- **理由**: 攻击面 = 整个局域网;影响 = HA 实体被静默篡改(监控数据可信度)+ 注册表可被整体替换。
- **修复建议**:
  1. 把 `web_token` 从 optional 改为**默认生成**:未配置时启动时随机生成并打印到日志,或干脆 fail-fast 要求显式配置;
  2. 默认 `http: "127.0.0.1:8080"`(localhost),需要 LAN 访问时显式改 `:8080`;
  3. README/`config.example.yaml` 中把"无认证"标注为高风险默认值。

### H2. MQTT broker 被当作完全可信输入:任意发布者可在 HA 中植入实体并自动获批
- **位置**: `mqtt.go:163-277` (`onData`)、`config.example.yaml:5` (`subscribe: ["#"]`)
- **风险**: mqtt2ha 以 QoS0 订阅 `#`,对**任何** topic 上的 JSON 消息都自动推断实体,`auto` 模式下 3 条消息即 auto-approve 并发布 retained discovery。broker 上任意一个能发布的客户端(被攻破的设备、误配的集成、恶意节点)都可以:
  - 往 HA 里注入伪造传感器/设备卡(名称取自 payload 的 `tags.name`,可任意字符串);
  - **覆盖同名 topic 的合法设备**(UpsertDevice 按 topic upsert,`applyInferred` 用新消息的 name/model/serial 覆盖已存元数据——攻击者向同一 topic 发一条带恶意 tags 的消息即可篡改设备卡);
  - 通过 `homeassistant/<component>/<object_id>/config` 发布**伪造的"自发现"消息**,触发 `onSelfDiscovery` (mqtt.go:104-160) 自动删除 pending 设备并写黑名单——即对 mqtt2ha 自身的持久化状态做未授权写。
- **理由**: MQTT over TCP/TLS 默认无 ACL 时 broker 是共享总线;本工具把"总线上的任何 JSON"映射为 HA 实体,信任边界完全依赖 broker ACL,而默认配置 `#` + auto 模式没有任何本地过滤。
- **修复建议**:
  1. 文档与示例中强烈要求 broker 端 ACL(订阅/发布最小权限),并在 README 安全章节列为前提条件;
  2. 提供**白名单 topic 前缀**配置(如 `watch: ["home/#"]`),默认拒绝而非全量观察;
  3. `onSelfDiscovery` 的 retire+blacklist 动作改为只记日志 + 可选开关(`auto_retire: false`),避免 broker 消息直接驱动持久化删除;
  4. auto 模式增加"同 topic 元数据突变"告警(已批准设备的 name/model/serial 被新消息覆盖时打 warning)。

### H3. yaml 后端:`devices_dir` 下任意文件被信任解析,且写入目录权限过宽
- **位置**: `yamlstore.go:148-271` (`load()` 读取 `dir/*.yaml`)、`yamlstore.go:77` (`MkdirAll(dir, 0o755)`)、`main.go:25`
- **风险**:
  - 任何能写 `devices_dir` 的本地用户/进程可以投放恶意 yaml(任意 `topic:`、重复 id、超长字段),重启后 mqtt2ha 以**服务账号身份**解析并把它作为权威配置发布 discovery;配合 H1(无认证 Web UI)或同主机低权限进程,等于一条"写文件 → 改 HA"的本地提权链。
  - `MkdirAll` 用 `0o755`:在多用户机器上目录对**其他用户可写**(umask 影响下至少可读),任何本机用户都能投放/篡改设备 yaml。
  - `ReloadDevice` (yamlstore.go:573) 由 Web UI 的 `/api/reload` 触发,重新读取磁盘文件——无认证时等于把"读任意 `devices_dir/*.yaml` + 重发布"暴露给 LAN(受 H1 约束)。
- **理由**: 本地文件 → 持久化状态 → MQTT 发布,是典型的本地信任链;目录权限 0755 在多用户主机上是实际可利用的。
- **修复建议**:
  1. `MkdirAll(dir, 0o700)`、yaml 文件写入 `0o600`;
  2. 解析时校验 topic 字符集(拒绝含 `\0`、超长 >128 字节、非预期分隔符的 topic),实体 field 名同样限长;
  3. 文档明确:yaml 后端要求 `devices_dir` 仅服务账号可写,且该目录应视为**机密/可信输入**。

---

## 中危 (Medium)

### M1. CSRF token 为进程级单值,且无 session 概念 → 跨用户/跨会话混淆
- **位置**: `websec.go:32-38`、`mqtt.go:43` (`NewBridge` 时一次性生成),渲染进每个页面 (`web.go:57` 等)
- **风险**: token 对所有客户端相同且重启才变化。若将来引入多用户(或多人共享 UI),A 的浏览器里缓存的旧页面携带的 token 在 B 登录后依然有效,CSRF 防护退化为"知道这个进程启动后任意一个渲染过的页面即可"。另外 token 通过 GET 响应明文下发、无 `HttpOnly`/cookie 机制,同源 XSS(当前模板已转义,风险低)一旦存在即可直接读走。
- **理由**: 单用户 LAN 场景下影响有限,但这是架构性弱点;token 还出现在 URL 可分享的 HTML 里。
- **修复建议**: 每会话签发 token(cookie `HttpOnly; SameSite=Strict` + 随机值),或至少按 IP+UA 绑定;文档注明"单用户 UI"假设。

### M2. auth 限速基于 `RemoteAddr`,NAT/代理后失效,且锁存可被攻击者自伤
- **位置**: `websec.go:179-185` (`clientIPOf`)、`websec.go:143-175`
- **风险**: 反向代理后所有请求共享代理 IP——一个用户连续失败 8 次会把**所有人**锁 5 分钟(README 已承认,属已知限制);攻击者也可故意打满计数造成对管理员的拒绝服务。另外 `authFails` map 以任意 `RemoteAddr` 为 key:无 token 时不触发,有 token 时恶意客户端可用不同源 IP(云环境易得)绕过限速——限速只是摩擦,不是边界。
- **修复建议**: 文档强调"限速是辅助,token 强度才是主防线"(README 已部分做到);若部署在代理后,支持 `X-Forwarded-For` 的**显式可信代理配置**(默认关闭),并在锁定时返回 `429 + Retry-After`。

### M3. `/api/import` 整体替换注册表,破坏半径大且无确认/备份
- **位置**: `web.go:446-547`、`store.go:405-446` (`ImportSnapshot` 先 DELETE 全表)、`yamlstore.go:730-797`
- **风险**: 验证做得不错(版本/重复 id/topic/component 白名单),但语义是**全量覆盖**:一次误操作或恶意 token 泄露即可清空全部设备/黑名单(yaml 后端还会删除磁盘上所有旧文件,虽然有 write-then-delete 缓解)。没有"导入前自动导出备份"、没有 dry-run。
- **修复建议**: 导入前自动生成带时间戳的备份(export 到 `backups/`);提供 `?dry_run=true`;考虑支持增量合并模式替代全量替换。

### M4. Web 服务无 TLS,token 走明文 HTTP
- **位置**: `main.go:65` (`ListenAndServe`)、`config.go` (无 TLS 字段)
- **风险**: `web_token` 通过 `Authorization` 头在局域网明文传输;同网段任意设备可嗅探获得永久 token,之后完全控制 UI。CSRF 防护在 token 泄露后毫无意义。
- **修复建议**: 支持 `tls_cert`/`tls_key` 配置(`ListenAndServeTLS`)或至少文档强烈要求反代终结 TLS;README Docker 示例已暴露 `-p 8080:8080`,应补一句"务必置于 TLS 反代后"。

### M5. 自发现检测的自消息过滤依赖命名约定,可被绕过
- **位置**: `mqtt.go:116-124` (仅检查 `unique_id`/`identifiers` 前缀 `mqtt2ha_`)
- **风险**: mqtt2ha 自己发布的 discovery 用 `mqtt2ha_*` 前缀来识别"这是自己的消息"。但攻击者(或另一实例)发布一条 `state_topic` 指向合法数据 topic、且**不带** `mqtt2ha_` 前缀的 config 消息,就会被当作"节点自发现",触发 pending 设备删除 + 黑名单写入(见 H2)。过滤机制是约定而非身份绑定。
- **修复建议**: 记录自己发布的 discovery topic 集合(发布时登记),用精确匹配替代前缀启发式;或要求自发现消息携带 mqtt2ha 无法伪造的 broker 侧凭证(不现实)——至少把 retire 行为降级为日志(H2 第 3 条)。

---

## 低危 (Low)

### L1. `randSuffix()` 用时间取模,ClientID 可预测
- **位置**: `mqtt.go:343-345` (`time.Now().UnixNano()%100000`)
- **风险**: MQTT ClientID 碰撞/被预测本身影响小(broker 通常踢掉重复 client),但同秒内两个实例(如 docker restart + 旧进程残留)有较高碰撞概率,导致**新实例把旧实例踢下线**(broker 对重复 clientid 的常见行为),造成订阅抖动。
- **修复**: 用 `crypto/rand` 或 `uuid`(go.mod 已有 google/uuid)生成后缀。

### L2. 错误信息回显内部细节
- **位置**: `web.go:130,199,467,541` 等 (`http.Error(w, err.Error(), ...)`)
- **风险**: SQLite/yaml 错误(含文件路径、SQL 片段)直接返回给未认证/低权限客户端,泄露目录结构。
- **修复**: 对外返回通用错误,细节只写日志。

### L3. `handleImport` 的 multipart 分支:先解码失败再回退 FormFile,逻辑依赖隐式状态
- **位置**: `web.go:454-470`
- **风险**: 不是漏洞(有 1MiB 上限),但 `dec.Decode(&data)` 失败后 body 已被部分消费,`r.FormFile` 回退路径实际只在 Content-Type 为 multipart 时工作;若攻击者发送混合内容,行为依赖 Go 内部实现。属于健壮性问题。
- **修复**: 按 `Content-Type` 显式分支,不要靠"先试 JSON 再试 form"的回退。

### L4. yaml 文件写入固定 `.tmp` 后缀,并发/多进程下竞态
- **位置**: `yamlstore.go:312-317` (`tmp := f + ".tmp"`)
- **风险**: 两个 mqtt2ha 实例共享同一 `devices_dir`(Docker 卷误配)时,tmp 文件互相覆盖,可能 rename 到错误内容。README 已提示 last-writer-wins,但 tmp 名固定放大了问题。
- **修复**: `os.CreateTemp(dir, base+".*.tmp")` 随机化临时名。

### L5. `value_template` 由字段名插值构造(低风险,已有约束)
- **位置**: `discovery.go:29-38` (`fmt.Sprintf("{{ value_json.fields.%s ...", field)`)
- **风险**: 字段名来自 MQTT payload key。Jinja2 模板注入需要字段名含 `}}` 之类字符——MQTT topic/JSON key 理论上可以是任意 UTF-8,极端情况下恶意字段名可构造出改变模板语义的 payload(影响仅限该实体自身读数解析,不逃逸到 HA 其他部分)。
- **修复**: 对进入模板的 field 做 `[A-Za-z0-9_.]` 白名单过滤,非法字段直接跳过并告警。

### L6. `web_token` 支持非 Bearer 裸头匹配
- **位置**: `websec.go:110-115`
- **风险**: 除 `Bearer x` 外,`Authorization: x`(任意 scheme)也接受——若前端误发其他 scheme(如 Basic),token 可能意外匹配。无实际危害但属多余攻击面。
- **修复**: 仅接受 `Bearer ` 前缀(大小写不敏感)。

---

## 做得好的方面(供参考)

- SQL 全部参数化,无注入;HTML 用 `html/template` 自动转义,无 XSS;
- CSRF:POST-only + 常量时间比较 + crypto/rand 失败时 fail-hard(`websec.go:32-38`);
- 组件白名单限制 discovery 输出面(`websec.go:22-27`),body/multipart/urlencoded 均有 1MiB 上限;
- CI 全 SHA 固定 actions、`go vet` + `-race` + `govulncheck`,release 前强制测试;
- Docker 非 root 运行;auth 限速有 TTL 自愈,无内存无限增长;
- import 校验 fail-closed,write-then-delete 防止半截状态。

## 修复优先级建议

1. **立即**: H1(默认生成 token + 默认 localhost)、H2 第 1/2 条(broker ACL 文档 + topic 白名单);
2. **下一版本**: H3(目录/文件权限收紧 + topic 校验)、M4(TLS 支持)、M5+H2 第 3 条(retire 行为降级为日志/开关);
3. **后续**: M1/M3/M2 及低危项。

需要的话,我可以直接在克隆的仓库里提交一个修复 PR(先做 H1 + H3 权限收紧这两个改动小、收益大的)。