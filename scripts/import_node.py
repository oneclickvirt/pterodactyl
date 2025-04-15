#!/usr/bin/env python3
# https://github.com/oneclickvirt/pterodactyl
# 2025.04.15

import os
import sys
import json
import time
import socket
import subprocess
import urllib.parse
import requests
import ipaddress
import re
from getpass import getpass
from typing import Dict, Tuple, Optional, List, Any, Union

# 全局变量定义
PANEL_DIR = "/var/www/pterodactyl"
USER_FILE = f"{PANEL_DIR}/auto_users.txt"
COOKIES_FILE = "/tmp/pterodactyl_cookies.txt"
SESSION = requests.Session()

def check_root() -> None:
    """检查是否有root权限"""
    if os.geteuid() != 0:
        print("错误：脚本必须以root权限运行！")
        sys.exit(1)

def is_private_ipv4(ip_address: str) -> bool:
    """检查IP是否为私有IPv4"""
    if not ip_address:
        return True  # 输入为空
    
    try:
        ip = ipaddress.ip_address(ip_address)
        if not isinstance(ip, ipaddress.IPv4Address):
            return True  # 不是IPv4地址
        
        return (
            ip.is_private or
            ip.is_loopback or
            ip.is_multicast or
            ip.is_unspecified or
            (ip.packed[0] == 100 and 64 <= ip.packed[1] <= 127)  # RFC 6598
        )
    except ValueError:
        return True  # 无效IP地址

def get_ipv4() -> str:
    """获取本机IPv4地址，优先获取公网IP"""
    # 尝试从本地网络接口获取IP
    try:
        output = subprocess.check_output("ip -4 addr show | grep global | awk '{print $2}' | cut -d '/' -f1 | head -n 1", shell=True).decode("utf-8").strip()
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
    
    # 通过API获取公网IP
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
            time.sleep(1)  # 避免过于频繁的请求
        except Exception as e:
            print(f"通过 {api_url} 获取IP失败: {e}")
            continue
    
    print("警告：无法获取公网IP地址，请手动设置")
    return "127.0.0.1"  # 返回默认值

def read_panel_config() -> Tuple[str, str, str]:
    """读取面板配置信息"""
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
                    panel_url = line.split(":")[2].replace("//", "")
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
    
    # 确保URL格式正确
    if not panel_url.startswith("http"):
        panel_url = "http://" + panel_url
    
    # 去除末尾的斜杠
    panel_url = panel_url.rstrip('/')
    
    return panel_url, admin_email, admin_password

def create_node(node_name: str, node_memory: int, node_over_memory: int, 
                node_disk: int, node_over_disk: int, ipv4: str) -> bool:
    """创建Pterodactyl节点"""
    print(f"开始创建节点: {node_name}")
    print(f"节点IP地址: {ipv4}")
    print(f"节点配置: 内存={node_memory}MB(超分配{node_over_memory}%) 磁盘={node_disk}MB(超分配{node_over_disk}%)")
    
    # 使用Pterodactyl的artisan命令创建节点
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
    """模拟登录面板并返回CSRF Token"""
    print(f"正在登录Pterodactyl面板: {panel_url}")
    try:
        SESSION.cookies.clear()
        SESSION.get(f"{panel_url}/sanctum/csrf-cookie")
        xsrf_token = SESSION.cookies.get("XSRF-TOKEN")
        if not xsrf_token:
            print("获取不到XSRF-TOKEN")
            return None
        xsrf_token = urllib.parse.unquote(xsrf_token)
        print(f"解码后的XSRF-TOKEN: {xsrf_token}")
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
        login_response = SESSION.post(
            f"{panel_url}/auth/login", 
            json=login_data, 
            headers=headers
        )
        admin_check_status = SESSION.get(f"{panel_url}/admin").status_code
        print(f"{panel_url}/admin 登录响应状态码：{admin_check_status}")
        login_json = login_response.json()
        print(f"登录响应文本：{login_response.text[:200]}")
        if not login_json.get("data", {}).get("complete", False):
            print("错误：面板登录失败，请检查用户名和密码是否正确！")
            return None
        updated_token = SESSION.cookies.get("XSRF-TOKEN")
        updated_xsrf_token = urllib.parse.unquote(updated_token)
        print(f"登录成功，获取到CSRF Token: {updated_xsrf_token}")
        return updated_xsrf_token
    except Exception as e:
        print(f"登录面板时出错: {e}")
        return None

def get_latest_node_id() -> int:
    """获取最新创建的节点ID"""
    print("获取最新创建的节点ID...")
    try:
        # 执行 PHP 命令获取节点列表并以 JSON 格式返回
        php_command = "php /var/www/pterodactyl/artisan p:node:list --format=json"
        result = subprocess.run(php_command, shell=True, capture_output=True, text=True)
        
        if result.returncode != 0:
            print(f"执行 PHP 命令时出错: {result.stderr}")
            return 1
        
        # 解析 JSON 输出
        nodes_json = result.stdout
        if nodes_json:
            nodes = json.loads(nodes_json)
            if nodes:
                # 获取最后一个节点的ID
                latest_node_id = nodes[-1]["id"]
                print(f"获取到最新节点ID: {latest_node_id}")
                return int(latest_node_id)
        
        print("警告：无法获取最新节点ID，将使用默认值1")
        return 1
    except Exception as e:
        print(f"获取节点ID时出错: {e}")
        return 1

def generate_install_token(panel_url: str, panel_email: str, panel_password: str, node_id: int) -> Optional[str]:
    """为节点生成安装令牌，并确保重新获取 CSRF Token 和 Cookies"""
    print(f"正在为节点ID {node_id} 生成安装令牌...")
    try:
        SESSION.get(f"{panel_url}/sanctum/csrf-cookie")
        updated_token = SESSION.cookies.get("XSRF-TOKEN")
        csrf_token = urllib.parse.unquote(updated_token)
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
        print(f"请求URL: {token_url}")
        print(f"使用Cookie: {SESSION.cookies.get_dict()}")
        token_response = SESSION.post(token_url, headers=headers)
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
    """显示Wings安装命令"""
    print("\n一键导入命令：\n")
    print(f"cd /etc/pterodactyl && sudo wings configure --panel-url {panel_url} --token {install_token} --node {node_id}")

def main() -> None:
    """主函数"""
    check_root()
    
    # 获取节点配置信息
    node_name = input("请输入节点名称 [默认: auto-node]: ").strip() or "auto-node"
    
    try:
        node_memory = int(input("请输入节点内存 (MB) [默认: 1024]: ").strip() or "1024")
        node_over_memory = int(input("请输入内存超分配百分比 [默认: 0]: ").strip() or "0")
        node_disk = int(input("请输入节点磁盘 (MB) [默认: 10240]: ").strip() or "10240")
        node_over_disk = int(input("请输入磁盘超分配百分比 [默认: 0]: ").strip() or "0")
    except ValueError:
        print("输入必须是数字，将使用默认值")
        node_memory = 1024
        node_over_memory = 0
        node_disk = 10240
        node_over_disk = 0
    
    # 获取IP地址
    ipv4 = get_ipv4()
    
    # 创建节点
    if not create_node(node_name, node_memory, node_over_memory, node_disk, node_over_disk, ipv4):
        print("节点创建失败，脚本中断")
        sys.exit(1)
    
    # 读取面板配置
    panel_url, admin_email, admin_password = read_panel_config()
    print(f"面板地址: {panel_url}")
    print(f"管理员邮箱: {admin_email}")
    
    # 登录面板
    csrf_token = login_panel(panel_url, admin_email, admin_password)
    if not csrf_token:
        print("面板登录失败，脚本中断")
        sys.exit(1)
    
    # 获取最新节点ID
    node_id = get_latest_node_id()
    print(f"将使用节点ID: {node_id}")
    
    # 确认节点ID
    try:
        input_node_id = input(f"请确认节点ID [默认: {node_id}]: ").strip()
        if input_node_id:
            node_id = int(input_node_id)
    except ValueError:
        print(f"输入无效，将使用默认节点ID: {node_id}")
    
    # 生成安装令牌
    install_token = generate_install_token(panel_url, admin_email, admin_password, node_id)
    if not install_token:
        print("安装令牌生成失败，脚本中断")
        sys.exit(1)
    
    # 显示Wings安装命令
    show_wings_install_command(panel_url, install_token, node_id)

if __name__ == "__main__":
    main()
