# zcode-snapblock

> 在本地按 **URL 路径**精准拦截 ZCode 客户端的「工作区快照上传」（repo snapshot），
> 不影响登录与对话；附 30 秒周期监控告警。Linux / Windows 双平台，无需管理员权限。
>
> **English TL;DR:** A local mitmproxy-based shield that blocks ZCode's workspace
> snapshot upload endpoints by URL path (leaving login/chat traffic untouched),
> with a 30s monitor that alerts on any local snapshot artifacts. Runs entirely
> on your machine, no admin rights required.

## 背景

ZCode 3.12.3 引入了 repo snapshot 机制：每次 prompt / 每轮对话结束后扫描工作区，
增量打包并 AES-256-CTR 加密，经
`https://zcode.z.ai/api/v1/snapshot/upload-credential` 获取凭证后直传阿里云 OSS。
该行为**没有用户开关**——代码路径为「拿不到凭证则静默跳过」，这正是本工具的切入点。

## 工作原理

利用 ZCode **原生代理设置**（`setting.json` 的 `httpProxy` / `httpProxyCaCertPath`
两个官方配置键，zcode-host 网络层据此构建 undici ProxyAgent），把 Host API 流量引到
本地 mitmproxy，按路径精准拦截：

| 规则 | 匹配 | 动作 |
|---|---|---|
| `snapshot-api` | 任意域名 + 路径前缀 `/api/v1/snapshot/` | 403（覆盖 zcode.z.ai 与回退域 zcode.chatglm.site） |
| `oss-artifact` | PUT 且路径含 `repo_snapshot_`（OSS 对象 key 前缀） | 403（兜底直传） |
| 放行 | 其余全部流量 | 原样转发 |

- 拦截发生在**本地**（addon 直接应答，不出网），同域的 OAuth、对话、工具接口不受影响
- 拦截事件追加写入安装目录 `blocked.log`（超 10MB 自动滚动）
- `httpProxy` 只作用于 zcode-host 的 Host API 通道，不改系统全局代理
- 仅当 ZCode 重启后读取到代理键才生效——因此启用/禁用脚本都要求先完全退出 ZCode
- ZCode 保存设置时会从内存模型整体回写 `setting.json`，注入的代理键会被丢弃（无论保存由用户操作还是
  客户端自动触发）；监控每 30 秒自动补写（仅在代理端口确认监听时，避免把 ZCode 指向死端口）

## 功能特性

- 路径级拦截，而非整个域名封杀（登录/对话/工具零影响）
- 后台运行**无窗口、无闪屏**（Windows 通过 wscript 启动器；Linux systemd 用户服务）
- 崩溃自愈：Windows 30 秒看门狗 + 任务计划重启双保险；登录触发延迟 30s，启动器对登录期瞬时失败
  （0x800704C7）静默重试 6 次，仅持续失败才弹窗告警；Linux `Restart=always`
- 代理键自愈：ZCode 回写 `setting.json` 丢弃代理键后，监控 30 秒内自动补写（下次启动 ZCode 生效）；
  `disable-proxy` 置 `proxy-disabled.flag` 暂停自愈，`enable-proxy` 清除该标记恢复
- 30 秒监控告警（Toast / notify-send + alerts.log，按指纹去重）：
  快照产物文件（`*.tar.gz.enc` / `*.envelope.json`）、`v2/checkpoints` / `v2/repo-snapshots`
  目录出现、当日日志出现 `upload-credential`、拦截证据提示
- 一键安装 / 启用 / 禁用 / 卸载，幂等可重入；编辑 `setting.json` 前自动校验 JSON 并备份
- 启用前置检查：CA 存在、代理端口在监听、ZCode 是否正在运行均有明确提示
- 安装器自带端到端自检（真实请求 snapshot 端点确认 403 才提示可启用）
- 全程无 root / 管理员权限；所有路径安装时在本机解析，仓库不含任何写死路径

## 目录结构

```
mitm-addon.py                       mitmproxy 拦截插件（跨平台，双平台共用）
linux/
  install.sh                        一键安装（复制文件 + 渲染注册 systemd 用户服务）
  uninstall.sh                      卸载（--remove-files 同时删除安装目录）
  enable-proxy.sh / disable-proxy.sh 启用拦截 / 恢复直连（安全编辑 setting.json）
  zcode-snapshot-watch.sh           监控脚本（30s 周期）
  systemd/                          unit 模板（__占位符__ 由 install.sh 本机渲染）
windows/
  setup-zcode-shield.ps1            一键安装（找/装 mitmproxy + 注册 2 个计划任务）
  uninstall-zcode-shield.ps1        卸载（-RemoveFiles 同时删除安装目录）
  enable-proxy.ps1 / .cmd           启用拦截（.cmd 可在 cmd/PowerShell/双击运行）
  disable-proxy.ps1 / .cmd          恢复直连
  ZcodeSnapshotWatch.ps1            监控脚本（Toast + alerts.log + 看门狗）
```

安装位置：Linux `~/.zcode-shield/`，Windows `%USERPROFILE%\.zcode-shield\`。

## 环境要求

- **Linux**：systemd 用户服务（主流发行版均带）、mitmproxy、python3、curl
- **Windows**：Win10/11、winget（或已自行安装的 mitmproxy）、PowerShell 5.1+、curl.exe（系统自带）

## 快速开始（Linux）

```bash
./linux/install.sh     # 复制文件到 ~/.zcode-shield 并注册 systemd 用户服务（含自检）
# 完全退出 ZCode 后：
~/.zcode-shield/enable-proxy.sh      # 写入 httpProxy 两键（自动备份 setting.json）
# 启动 ZCode 即生效
```

## 快速开始（Windows）

```powershell
# 若提示脚本被禁止运行:
#   powershell -NoProfile -ExecutionPolicy Bypass -File .\windows\setup-zcode-shield.ps1
.\windows\setup-zcode-shield.ps1     # 找/装 mitmproxy，复制文件，注册 2 个计划任务（含自检）
```

完全退出 ZCode 后，任选一种方式启用（`.cmd` 在 cmd / PowerShell / 资源管理器双击均可）：

```powershell
& "$env:USERPROFILE\.zcode-shield\enable-proxy.ps1"
```

```cmd
%USERPROFILE%\.zcode-shield\enable-proxy.cmd
```

启动 ZCode 即生效。若 ZCode 工作区跑在 WSL remote runtime：官方代码含 wsl-host-gateway
解析，`127.0.0.1:18080` 会被自动改写为宿主机地址，无需额外配置。

## 验证

```bash
# Linux（期望 403）
curl -x http://127.0.0.1:18080 --cacert ~/.mitmproxy/mitmproxy-ca-cert.pem \
  -o /dev/null -w '%{http_code}\n' \
  'https://zcode.z.ai/api/v1/snapshot/upload-credential'
```

```powershell
# Windows（期望 403；--ssl-no-revoke 用于规避 schannel 对 mitmproxy 证书的吊销检查误报）
curl.exe --ssl-no-revoke -x http://127.0.0.1:18080 --cacert "$env:USERPROFILE\.mitmproxy\mitmproxy-ca-cert.pem" `
  -o NUL -w "%{http_code}`n" https://zcode.z.ai/api/v1/snapshot/upload-credential
```

真实流量生效后，`blocked.log` 会出现带真实 `workspace_id` 的拦截记录（区别于手动验证），
`mitmdump.log` / journal 会出现持续的 `client connect` 与 `GET|POST` 行。

## 恢复直连 / 卸载

- **恢复直连**（保留拦截服务）：完全退出 ZCode → `disable-proxy.ps1|.cmd` / `disable-proxy.sh` → 重启 ZCode
  （Windows 端同时置 `proxy-disabled.flag` 暂停代理键自动补写，重新 enable 后恢复）
- **Linux 卸载**：先 disable，然后 `./linux/uninstall.sh`（加 `--remove-files` 同时删除 `~/.zcode-shield`）
- **Windows 卸载**：先 disable，然后 `.\windows\uninstall-zcode-shield.ps1`（加 `-RemoveFiles` 同时删除安装目录）
- 卸载脚本会在 `setting.json` 仍含 `httpProxy` 时**拒绝执行**，防止把 ZCode 留在断网状态
- 两个卸载脚本都不会卸载 mitmproxy 本体；CA 证书（`~/.mitmproxy/`）也不会被删除

## 更换端口

默认 `18080`：

- **Linux**：编辑 `~/.zcode-shield/proxy.env` 后重跑 `install.sh`（unit 内嵌端口字面量），再重跑 `enable-proxy.sh`
- **Windows**：重跑 setup 时加 `-ProxyPort <端口>`，enable 时传同样参数

## 升级 / 重跑

安装器幂等，直接重跑 `install.sh` / `setup-zcode-shield.ps1` 会刷新文件并重启拦截服务
（已启用代理时会有数秒中断，建议在无活跃对话时执行）。

## 故障排查

- **代理进程挂掉且已启用** → Host API 请求全断（登录/对话失败）。看门狗/systemd 会在
  30 秒 / 5 秒内拉起；应急：按「恢复直连」操作后重启 ZCode。
- **`no proxy listening on 127.0.0.1:18080`**（enable 拒绝）→ 先跑 `setup` / `install.sh`，
  或检查 `Get-ScheduledTask zcode-shield-mitm` / `systemctl --user status zcode-shield-mitm`。
- **enable 警告 "ZCode is currently running"** → 设置仅启动时读取且 ZCode 回写时会丢弃代理键：
  按提示退出 ZCode → 重跑 enable → 再启动。首次启用后无需重复操作——键被丢弃时监控 30 秒内自动补写，
  重启 ZCode 即恢复代理（若退出后 30 秒内立即重开可能赶在补写前，稍等片刻即可）。
- **判断是否生效**：`~/.zcode-shield/blocked.log` 有新行 = 拦截在工作；
  Linux 另看 `journalctl --user -u zcode-shield-mitm -f`（info 级 `server connect` / `GET|POST`
  行可直接确认流量走了代理），Windows 看 `%USERPROFILE%\.zcode-shield\mitmdump.log`。
- **事件日志通道**：Windows 事件日志（来源 `zcode-shield`）仅当管理员预先注册过来源时生效，
  普通权限自动跳过；Toast 与 alerts.log 始终可用。
- `systemctl --user` 服务需要用户会话在线（GNOME Wayland 下默认即如此）。

## 局限与已验证版本

- 针对 ZCode 3.12.3（app.asar 逆向确认）的 snapshot 端点与 OSS 对象 key 前缀；ZCode 更新后
  若路径变化，需同步修改 `mitm-addon.py` 中的两条规则（规则集中在文件顶部常量）。
- 依赖 ZCode 原生代理设置；若后续版本移除 `httpProxy` 支持或启用证书固定（certificate pinning），本方案失效。
- 监控只读取 `~/.zcode` 并在本机告警，不删除任何 ZCode 数据。

## 隐私说明

本工具**完全运行在你自己的机器上**：不收集、不上传任何数据；mitmproxy CA 证书仅存于本机；
`blocked.log` / `alerts.log` 仅记录被拦截请求的 方法+域名+路径 与告警文本，保存在安装目录。

## License

[MIT](LICENSE)

## 免责声明

本项目仅供学习研究与个人管理自己账号/设备的网络行为使用，与 Z.ai 无关联。