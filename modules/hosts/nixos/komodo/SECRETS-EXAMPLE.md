# Komodo Periphery Secrets Configuration

## SOPS Secrets File Example

在你的 `nix-secrets/secrets/${hostname}.yaml` 文件中添加以下内容：

```yaml
# Komodo Periphery Configuration
komodo:
  # Passkeys for API authentication
  # 可以是单个 passkey 或多个 passkey（逗号分隔）
  passkeys: "your-secure-passkey-here"
  
  # SSL 证书（如果启用 SSL）
  ssl_key: |
    -----BEGIN PRIVATE KEY-----
    YOUR_SSL_PRIVATE_KEY_CONTENT
    -----END PRIVATE KEY-----
  
  ssl_cert: |
    -----BEGIN CERTIFICATE-----
    YOUR_SSL_CERTIFICATE_CONTENT
    -----END CERTIFICATE-----
  
  # 可选：GitHub token（如果需要访问私有仓库）
  # github_token: "ghp_xxxxxxxxxxxx"
```

## 加密 Secrets 文件

使用 sops 加密你的 secrets 文件：

```bash
# 进入 nix-secrets 目录
cd nix-secrets/secrets

# 编辑并加密 secrets 文件
sops ${hostname}.yaml
```

## 配置说明

### 1. **passkeys** (必需)
- 用于 Core 与 Periphery 之间的 API 认证
- 建议使用强随机密码，例如：
  ```bash
  openssl rand -base64 32
  ```

### 2. **ssl_key / ssl_cert** (推荐)
- 用于 HTTPS 通信
- 可以使用自签名证书或 Let's Encrypt 证书
- 生成自签名证书：
  ```bash
  openssl req -x509 -newkey rsa:4096 -keyout key.pem -out cert.pem -days 365 -nodes
  ```

### 3. **github_token** (可选)
- 仅在需要访问私有 GitHub 仓库时使用
- 在 GitHub Settings → Developer settings → Personal access tokens 生成

## 配置流程

1. **创建/编辑 secrets 文件**
   ```bash
   cd nix-secrets/secrets
   sops Pseudomugil.yaml  # 替换为你的主机名
   ```

2. **添加 komodo 配置**（参考上面的 YAML 示例）

3. **在 network.nix 中启用服务**
   ```nix
   serviceInfo.Pseudomugil.komodo = {
     enable = true;
     port = 8120;
     allowedIps = [ "10.0.0.0/24" ];  # 可选：IP 白名单
     sslEnabled = true;
     logLevel = "info";
   };
   ```

4. **重新构建系统**
   ```bash
   sudo nixos-rebuild switch --flake .#Pseudomugil
   ```

## 安全最佳实践

1. ✅ **始终使用 sops 加密 secrets 文件**
2. ✅ **不要将未加密的 secrets 提交到 git**
3. ✅ **定期轮换 passkeys**
4. ✅ **使用 allowedIps 限制访问来源**
5. ✅ **启用 SSL/TLS 加密通信**
6. ✅ **最小权限原则：只授予必要的权限**

## 故障排查

### Passkeys 未生效
```bash
# 检查 secret 是否被正确加载
sudo systemctl status komodo-periphery
journalctl -u komodo-periphery -f

# 检查配置文件是否包含 passkeys
cat /run/secrets/rendered/komodo-periphery-config | grep passkeys
```

### SSL 证书问题
```bash
# 检查证书路径
ls -la /var/lib/komodo-periphery/ssl/

# 验证证书有效性
openssl x509 -in /var/lib/komodo-periphery/ssl/cert.pem -text -noout
```

## 相关文档

- [sops-nix 文档](https://github.com/Mic92/sops-nix)
- [Komodo 官方文档](https://komo.do/docs/)
- 主模块：`modules/hosts/nixos/komodo/default.nix`
- 项目集成：`hosts/common/optional/services/komodo-periphery.nix`

