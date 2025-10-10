# Komodo Periphery NixOS Module

NixOS 模块定义，用于管理 Komodo Periphery Agent 服务。

## 特点

- ✅ 纯粹的 NixOS 模块（不依赖 sops、networkInfo、nix-secrets）
- ✅ 支持多种配置方式
- ✅ 可贡献回 nixpkgs
- ✅ 使用 unstable channel 的 komodo 包

## 使用方法

### 方法 1：通过项目集成层（推荐）

在你的主机配置中：

```nix
# hosts/nixos/${hostname}/default.nix
{
  imports = [
    (lib.custom.relativeToRoot "hosts/common/optional/services/komodo-periphery.nix")
  ];
}
```

然后在 nix-secrets 中配置：

```nix
# nix-secrets/network.nix
networkInfo.hosts.${hostName}.komodo = {
  enable = true;
  port = 8120;
  sslEnabled = true;
  logLevel = "info";
};
```

### 方法 2：直接使用模块

```nix
# hosts/nixos/${hostname}/default.nix
{
  imports = [
    (lib.custom.relativeToRoot "modules/hosts/nixos/komodo")
  ];
  
  services.komodo-periphery = {
    enable = true;
    port = 8120;
    rootDirectory = "/root/.config/komodo-periphery";
    ssl.enable = true;
    logging.level = "info";
  };
  
  virtualisation.docker.enable = true;
}
```

### 方法 3：使用自定义配置文件

```nix
{
  imports = [
    (lib.custom.relativeToRoot "modules/hosts/nixos/komodo")
  ];
  
  services.komodo-periphery = {
    enable = true;
    configFile = "/etc/komodo/custom.toml";
  };
  
  environment.etc."komodo/custom.toml".text = ''
    port = 8120
    root_directory = "/root/.config/komodo-periphery"
    ssl_enabled = true
    # ... 完整配置
  '';
  
  virtualisation.docker.enable = true;
}
```

## 配置选项

### services.komodo-periphery

| 选项 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `enable` | bool | `false` | 启用服务 |
| `package` | package | `pkgs.komodo` | 使用的包 |
| `configFile` | path\|null | `null` | 配置文件路径 |
| `port` | port | `8120` | 监听端口 |
| `bindIp` | string | `[::]` | 绑定 IP |
| `rootDirectory` | path | `$HOME/.config/komodo-periphery` | 数据目录 |
| `ssl.enable` | bool | `true` | 启用 SSL |
| `ssl.keyFile` | path | `${rootDirectory}/ssl/key.pem` | SSL 密钥文件 |
| `ssl.certFile` | path | `${rootDirectory}/ssl/cert.pem` | SSL 证书文件 |
| `logging.level` | enum | `info` | 日志级别 |
| `logging.stdio` | enum | `standard` | 日志格式 |
| `extraConfig` | lines | `""` | 额外配置 |
| `user` | string | `root` | 运行用户 |
| `group` | string | `root` | 运行组 |

## 目录结构

运行时会创建以下目录：

```
$HOME/.config/komodo-periphery/
├── repos/          # Git 仓库
├── stacks/         # Docker compose 文件
└── ssl/            # SSL 证书
    ├── key.pem
    └── cert.pem
```

- Root 用户：`/root/.config/komodo-periphery/`
- 其他用户：`/home/${user}/.config/komodo-periphery/`

## systemd 服务

模块会创建 `komodo-periphery.service`：

```bash
# 查看状态
sudo systemctl status komodo-periphery

# 查看日志
sudo journalctl -u komodo-periphery -f

# 重启服务
sudo systemctl restart komodo-periphery
```

## 依赖

- ✅ Docker 必需（模块会检查 `virtualisation.docker.enable`）
- ✅ 运行用户必须在 `docker` 组中（自动处理）

## 项目集成

此模块有一个配套的项目集成层：
- 文件：`hosts/common/optional/services/komodo-periphery.nix`
- 功能：
  - sops-nix 集成
  - networkInfo 配置读取
  - Docker 自动启用
  - 使用 pkgs.unstable.komodo

推荐使用项目集成层，除非你需要完全自定义配置。

## 示例

完整示例请参考：
- `hosts/common/optional/services/komodo-periphery.nix` - 项目集成示例

## 贡献

此模块设计为通用的 NixOS 模块，可以贡献回 nixpkgs。它不依赖任何项目特定的功能。

## 更多信息

- [Komodo Documentation](https://komo.do/docs/)
- [Komodo GitHub](https://github.com/moghtech/komodo)
- [nixpkgs komodo package](https://github.com/NixOS/nixpkgs/blob/master/pkgs/by-name/ko/komodo/package.nix)

