# Pterodactyl

## 说明

目前支持的系统

| 系统类型    | 版本范围                    | 备注         |
|-------------|----------------------------|--------------|
| Ubuntu      | 20.04, 22.04, 24.04        | 已支持       |
| Debian      | 10 (Buster), 11 (Bullseye) | 未支持       |
| CentOS      | 7                          | 未支持       |
| AlmaLinux   | 8, 9                       | 未支持       |
| Rocky Linux | 8, 9                       | 未支持       |

> ⚠️ 注意：Pterodactyl 面板（Panel）需要运行在支持 PHP 8.1+ 和 MySQL 5.7+/MariaDB 10.2+ 的环境中，守护进程 Wings 需要 Docker 环境支持。

## 更新

2025.04.13

- 测试修复panel安装

## Panel

```shell
curl -slk https://raw.githubusercontent.com/oneclickvirt/pterodactyl/main/scripts/install_pterodactyl.sh -o install_pterodactyl.sh && chmod 777 install_pterodactyl.sh && bash install_pterodactyl.sh
```

## Wings

```shell
curl -slk https://raw.githubusercontent.com/oneclickvirt/pterodactyl/main/scripts/install_wings.sh -o install_wings.sh && chmod 777 install_wings.sh && bash install_wings.sh
```

## Thanks

https://pterodactyl.io/
