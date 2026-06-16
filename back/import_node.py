#!/usr/bin/env python3
# https://github.com/oneclickvirt/pterodactyl
# 2025.04.15
# curl -slk https://raw.githubusercontent.com/oneclickvirt/pterodactyl/main/back/import_node.py -o import_node.py && chmod 777 import_node.py && python3 import_node.py

import os
import sys
import json
import time
import subprocess
import urllib.parse
import requests
import ipaddress
import re
import shutil
import shlex
from typing import Tuple, Optional

PANEL_DIR = "/var/www/pterodactyl"
USER_FILE = f"{PANEL_DIR}/auto_users.txt"
SESSION = requests.Session()
try:
    REQUEST_TIMEOUT = int(os.environ.get("REQUEST_TIMEOUT", "30"))
except ValueError:
    REQUEST_TIMEOUT = 30

def session_get(url: str, **kwargs: object) -> requests.Response:
    kwargs.setdefault("timeout", REQUEST_TIMEOUT)
    return SESSION.get(url, **kwargs)

def session_post(url: str, **kwargs: object) -> requests.Response:
    kwargs.setdefault("timeout", REQUEST_TIMEOUT)
    return SESSION.post(url, **kwargs)

def check_root() -> None:
    if os.geteuid() != 0:
        sudo_path = shutil.which("sudo")
        if sudo_path:
            print("正在使用 sudo 重新执行 / Re-running with sudo")
            os.execv(sudo_path, ["sudo", "-E", sys.executable, *sys.argv])
        print("错误：脚本必须以root权限运行，或由具备 sudo 权限的用户运行！/ Error: root or sudo is required.")
        sys.exit(1)

def is_private_ipv4(ip_address: str) -> bool:
    if not ip_address:
        return True 
    try:
        ip = ipaddress.ip_address(ip_address)
        if not isinstance(ip, ipaddress.IPv4Address):
            return True
        return (
            ip.is_private or
            ip.is_loopback or
            ip.is_multicast or
            ip.is_unspecified or
            (ip.packed[0] == 100 and 64 <= ip.packed[1] <= 127)  # RFC 6598
        )
    except ValueError:
        return True 

def get_ipv4() -> str:
    try:
        ip_output = subprocess.check_output(["ip", "-4", "addr", "show"], text=True)
        output = ""
        for line in ip_output.splitlines():
            stripped = line.strip()
            if stripped.startswith("inet ") and " scope global " in stripped:
                output = stripped.split()[1].split("/", 1)[0]
                break
        if output and not is_private_ipv4(output):
            print(f"检测到公网IPv4地址: {output}")
            return output
        else:
            if output:
                print(f"检测到内网IPv4地址: {output}，将尝试通过API获取公网IP")
            else:
                print("无法获取本机IPv4地址，将尝试通过API获取")
    except:
        print("获取本地IP时出错，将尝试通过API获取公网IP")
    api_list = [
        "https://ipv4.ip.sb", 
        "https://ipget.net",
        "https://ip.ping0.cc",
        "https://ip4.seeip.org",
        "https://api.my-ip.io/ip",
        "https://ipv4.icanhazip.com",
        "https://api.ipify.org"
    ]
    for api_url in api_list:
        try:
            print(f"尝试通过 {api_url} 获取公网IP...")
            response = requests.get(api_url, timeout=8)
            if response.status_code == 200 and not "error" in response.text.lower():
                ip = response.text.strip()
                print(f"成功获取到公网IP: {ip} (通过 {api_url})")
                return ip
            time.sleep(1)
        except Exception as e:
            print(f"通过 {api_url} 获取IP失败: {e}")
            continue
    print("警告：无法获取公网IP地址，请手动设置")
    return "127.0.0.1" 

def read_panel_config() -> Tuple[str, str, str]:
    if not os.path.isfile(USER_FILE):
        print(f"错误：找不到文件 {USER_FILE}，请确保面板已正确安装并生成用户信息文件。")
        sys.exit(1)
    panel_url = ""
    admin_email = ""
    admin_password = ""
    try:
        with open(USER_FILE, 'r') as f:
            lines = f.readlines()
            for line in lines:
                if "登录页面" in line:
                    match = re.search(r'https?://\S+', line)
                    if match:
                        panel_url = match.group(0)
                elif "用户名" in line:
                    admin_email = line.split(':', 1)[1].strip()
                elif "密码" in line:
                    admin_password = line.split(':', 1)[1].strip()
    except Exception as e:
        print(f"读取面板配置文件时出错: {e}")
        sys.exit(1)
    if not panel_url or not admin_email or not admin_password:
        print(f"错误：无法从文件 {USER_FILE} 中读取面板信息，请检查文件格式！")
        sys.exit(1)
    if not panel_url.startswith("http"):
        panel_url = "http://" + panel_url
    panel_url = panel_url.rstrip('/')
    return panel_url, admin_email, admin_password

def extract_meta_token(html_content: str) -> Optional[str]:
    patterns = [
        r'<meta[^>]*name=["\']_token["\'][^>]*content=["\']([^"\']+)["\']',
        r'<meta[^>]*content=["\']([^"\']+)["\'][^>]*name=["\']_token["\']',
    ]
    for pattern in patterns:
        match = re.search(pattern, html_content, re.IGNORECASE)
        if match:
            return match.group(1)
    return None

def create_node(node_name: str, node_memory: int, node_over_memory: int, 
                node_disk: int, node_over_disk: int, ipv4: str) -> bool:
    """创建Pterodactyl节点"""
    print(f"开始创建节点: {node_name}")
    print(f"节点IP地址: {ipv4}")
    print(f"节点配置: 内存={node_memory}MB(超分配{node_over_memory}%) 磁盘={node_disk}MB(超分配{node_over_disk}%)")
    try:
        os.chdir(PANEL_DIR)
        cmd = [
            "php", "artisan", "p:node:make",
            f"--name={node_name}",
            "--description=Auto Generate",
            "--locationId=1",
            f"--fqdn={ipv4}",
            "--public=1",
            "--scheme=http",
            "--proxy=0",
            "--maintenance=0",
            f"--maxMemory={node_memory}",
            f"--overallocateMemory={node_over_memory}",
            f"--maxDisk={node_disk}",
            f"--overallocateDisk={node_over_disk}",
            "--uploadSize=1024",
            "--daemonListeningPort=8080",
            "--daemonSFTPPort=2022",
            "--daemonBase=/var/lib/pterodactyl",
            "--no-interaction"
        ]
        process = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        if process.returncode != 0:
            print(f"错误：节点创建失败，错误信息：{process.stderr}")
            return False
        print("节点创建成功！")
        return True
    except Exception as e:
        print(f"创建节点时出错: {e}")
        return False

def login_panel(panel_url: str, admin_email: str, admin_password: str) -> Optional[str]:
    print(f"正在登录Pterodactyl面板: {panel_url}")
    try:
        SESSION.cookies.clear()
        session_get(f"{panel_url}/sanctum/csrf-cookie")
        xsrf_token = SESSION.cookies.get("XSRF-TOKEN")
        if not xsrf_token:
            print("获取不到XSRF-TOKEN")
            return None
        xsrf_token = urllib.parse.unquote(xsrf_token)
        print("已获取 XSRF-TOKEN / XSRF token acquired")
        login_data = {
            "user": admin_email,
            "password": admin_password,
            "g-recaptcha-response": ""
        }
        headers = {
            "Content-Type": "application/json",
            "X-XSRF-TOKEN": xsrf_token,
            "Referer": f"{panel_url}/auth/login",
            "X-Requested-With": "XMLHttpRequest",
            "Accept": "application/json"
        }
        login_response = session_post(
            f"{panel_url}/auth/login", 
            json=login_data, 
            headers=headers
        )
        admin_check_status = session_get(f"{panel_url}/admin").status_code
        print(f"{panel_url}/admin 登录响应状态码：{admin_check_status}")
        login_json = login_response.json()
        print(f"登录响应文本：{login_response.text[:200]}")
        if not (login_json.get("data", {}).get("complete", False) or login_json.get("complete", False)):
            print("错误：面板登录失败，请检查用户名和密码是否正确！")
            return None
        updated_token = SESSION.cookies.get("XSRF-TOKEN")
        updated_xsrf_token = urllib.parse.unquote(updated_token)
        print("登录成功，CSRF Token 已更新 / Login succeeded and CSRF token was refreshed")
        return updated_xsrf_token
    except Exception as e:
        print(f"登录面板时出错: {e}")
        return None

def get_latest_node_id() -> int:
    print("获取最新创建的节点ID...")
    try:
        result = subprocess.run(
            ["php", "/var/www/pterodactyl/artisan", "p:node:list", "--format=json"],
            capture_output=True,
            text=True,
        )
        if result.returncode != 0:
            print(f"执行 PHP 命令时出错: {result.stderr}")
            return 1
        nodes_json = result.stdout
        if nodes_json:
            nodes = json.loads(nodes_json)
            if nodes:
                latest_node_id = nodes[-1]["id"]
                print(f"获取到最新节点ID: {latest_node_id}")
                return int(latest_node_id)
        print("警告：无法获取最新节点ID，将使用默认值1")
        return 1
    except Exception as e:
        print(f"获取节点ID时出错: {e}")
        return 1

def generate_install_token(panel_url: str, panel_email: str, panel_password: str, node_id: int) -> Optional[str]:
    print(f"正在为节点ID {node_id} 生成安装令牌...")
    try:
        config_url = f"{panel_url}/admin/nodes/view/{node_id}/configuration"
        print(f"获取配置页面: {config_url}")
        response = session_get(config_url)
        if response.status_code != 200:
            print(f"获取配置页面失败，状态码: {response.status_code}")
            return None
        html_content = response.text
        csrf_token = extract_meta_token(html_content)
        if not csrf_token:
            print("无法从页面中解析CSRF Token")
            return None
        print("已从配置页面获取 CSRF Token / CSRF token acquired from configuration page")
        headers = {
            "X-CSRF-TOKEN": csrf_token,
            "Accept": "*/*",
            "X-Requested-With": "XMLHttpRequest",
            "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/135.0.0.0 Safari/537.36",
            "Origin": panel_url,
            "Referer": f"{panel_url}/admin/nodes/view/{node_id}/configuration",
            "Content-Length": "0"
        }
        token_url = f"{panel_url}/admin/nodes/view/{node_id}/settings/token"
        print(f"请求生成令牌URL: {token_url}")
        print("使用当前会话 Cookie 请求令牌 / Requesting token with current session cookies")
        token_response = session_post(token_url, headers=headers)
        if token_response.status_code != 200:
            print(f"错误：请求失败，状态码: {token_response.status_code}")
            print(f"响应内容: {token_response.text}")
            return None
        token_json = token_response.json()
        install_token = token_json.get("token")
        if not install_token:
            print(f"错误：生成安装令牌失败！响应内容: {token_response.text}")
            return None
        print("安装令牌生成成功")
        return install_token
    except Exception as e:
        print(f"生成安装令牌时出错: {e}")
        return None

def show_wings_install_command(panel_url: str, install_token: str, node_id: int) -> None:
    command = (
        f"(cd /etc/pterodactyl && sudo wings configure "
        f"--panel-url {shlex.quote(panel_url)} "
        f"--token {shlex.quote(install_token)} "
        f"--node {int(node_id)})"
    )
    print("在 Wings 端一键导入配置的命令 / Command to import config on the Wings host:")
    print(command)
    with open("wings_cmd.txt", "w", encoding="utf-8") as file:
        file.write(command + "\n")
    os.chmod("wings_cmd.txt", 0o600)

def read_default(prompt: str, default: str, env_name: str) -> str:
    env_value = os.environ.get(env_name)
    if env_value:
        return env_value
    if sys.stdin.isatty():
        return input(prompt).strip() or default
    print(f"非交互环境，使用默认值: {default} / Non-interactive mode uses default: {default}")
    return default

def read_int_default(prompt: str, default: int, env_name: str) -> int:
    value = read_default(prompt, str(default), env_name)
    try:
        return int(value)
    except ValueError:
        print(f"输入必须是数字，将使用默认值 {default} / Number required, using default {default}")
        return default

def main() -> None:
    check_root()
    node_name = read_default("请输入节点名称 / Node name [默认/default: auto-node]: ", "auto-node", "NODE_NAME")
    node_memory = read_int_default("请输入节点内存 (MB) / Node memory [默认/default: 1024]: ", 1024, "NODE_MEMORY")
    node_over_memory = read_int_default("请输入内存超分配百分比 / Memory overallocation percent [默认/default: 0]: ", 0, "NODE_OVER_MEMORY")
    node_disk = read_int_default("请输入节点磁盘 (MB) / Node disk [默认/default: 10240]: ", 10240, "NODE_DISK")
    node_over_disk = read_int_default("请输入磁盘超分配百分比 / Disk overallocation percent [默认/default: 0]: ", 0, "NODE_OVER_DISK")
    ipv4 = get_ipv4()
    if not create_node(node_name, node_memory, node_over_memory, node_disk, node_over_disk, ipv4):
        print("节点创建失败，脚本中断")
        sys.exit(1)
    panel_url, admin_email, admin_password = read_panel_config()
    print(f"面板地址: {panel_url}")
    print(f"管理员邮箱: {admin_email}")
    csrf_token = login_panel(panel_url, admin_email, admin_password)
    if not csrf_token:
        print("面板登录失败，脚本中断")
        sys.exit(1)
    node_id = get_latest_node_id()
    print(f"将使用节点ID: {node_id}")
    node_id = read_int_default(f"请确认节点ID / Confirm node ID [默认/default: {node_id}]: ", node_id, "NODE_ID")
    install_token = generate_install_token(panel_url, admin_email, admin_password, node_id)
    if not install_token:
        print("安装令牌生成失败，脚本中断")
        sys.exit(1)
    show_wings_install_command(panel_url, install_token, node_id)

if __name__ == "__main__":
    main()
