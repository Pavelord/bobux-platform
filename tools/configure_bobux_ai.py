#!/usr/bin/env python3
"""Activate server-only Bobux AI credentials without exposing them to clients."""

from __future__ import annotations

import os
import re
import stat
import time
from pathlib import Path

import paramiko


ENV_PATH = "/opt/bobux-api/.env"
SAFE_VALUE = re.compile(r"^[A-Za-z0-9_.-]+$")


def require_safe(name: str, *, optional: bool = False) -> str:
    value = os.environ.get(name, "").strip()
    if not value and not optional:
        raise RuntimeError(f"{name} is not configured.")
    if value and SAFE_VALUE.fullmatch(value) is None:
        raise RuntimeError(f"{name} contains unsupported dotenv characters.")
    return value


def update_environment(sftp: paramiko.SFTPClient, api_key: str, folder_id: str) -> None:
    try:
        with sftp.open(ENV_PATH, "r") as source:
            existing = source.read().decode("utf-8", errors="replace")
    except FileNotFoundError:
        existing = ""

    is_gemini = api_key.startswith("AIza")
    values = {
        "BOBUX_AI_API_KEY": api_key,
        "BOBUX_AI_PROVIDER": "gemini" if is_gemini else "yandex",
        "BOBUX_AI_FOLDER_ID": folder_id,
        "BOBUX_AI_MODEL": "gemini-3.6-flash" if is_gemini else "",
        "BOBUX_AI_BASE_URL": "",
    }
    lines = [
        line for line in existing.splitlines()
        if line.split("=", 1)[0].strip() not in values
    ]
    lines.extend(f"{name}={value}" for name, value in values.items())
    temporary = f"{ENV_PATH}.uploading"
    with sftp.open(temporary, "w") as destination:
        destination.write(("\n".join(lines).rstrip() + "\n").encode("utf-8"))
    sftp.chmod(temporary, stat.S_IRUSR | stat.S_IWUSR)
    try:
        sftp.remove(ENV_PATH)
    except FileNotFoundError:
        pass
    sftp.rename(temporary, ENV_PATH)


def run_remote(client: paramiko.SSHClient, command: str) -> str:
    stdin, stdout, stderr = client.exec_command(command, timeout=60)
    stdin.close()
    output = stdout.read().decode("utf-8", errors="replace")
    error = stderr.read().decode("utf-8", errors="replace")
    status = stdout.channel.recv_exit_status()
    if status != 0:
        raise RuntimeError(error.strip() or f"Remote command failed with status {status}.")
    return output.strip()


def main() -> int:
    api_key = require_safe("BOBUX_AI_API_KEY")
    folder_id = require_safe("BOBUX_AI_FOLDER_ID", optional=True)
    key_file = Path(os.environ["BOBUX_DEPLOY_KEY_FILE"])
    known_hosts = Path(os.environ["BOBUX_DEPLOY_KNOWN_HOSTS"])

    client = paramiko.SSHClient()
    client.load_host_keys(str(known_hosts))
    client.set_missing_host_key_policy(paramiko.RejectPolicy())
    client.connect(
        "109.71.245.162",
        username="root",
        key_filename=str(key_file),
        allow_agent=False,
        look_for_keys=False,
        timeout=20,
    )
    try:
        sftp = client.open_sftp()
        try:
            update_environment(sftp, api_key, folder_id)
        finally:
            sftp.close()
        result = run_remote(
            client,
            "cd /opt/bobux-api && set -a && . ./.env && set +a && "
            "pm2 restart bobux-api --update-env >/dev/null && sleep 2 && "
            "curl -fsS http://127.0.0.1:3000/api/health",
        )
        print(f"Bobux AI activated. API health: {result}")
    finally:
        client.close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
