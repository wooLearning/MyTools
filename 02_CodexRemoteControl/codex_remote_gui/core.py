from __future__ import annotations

import json
import sqlite3
import subprocess
import time
from contextlib import closing
from dataclasses import dataclass
from pathlib import Path


FEATURE_TABLE = "local_app_server_feature_enablement"
REMOTE_CONTROL = "remote_control"


@dataclass(frozen=True)
class RuntimeStatus:
    app_server_running: bool
    app_server_pids: tuple[int, ...]
    cloud_connected: bool
    connected_pids: tuple[int, ...]
    error: str | None = None


def default_codex_dir() -> Path:
    return Path.home() / ".codex"


def normalize_codex_dir(codex_dir: str | Path) -> Path:
    return Path(codex_dir).expanduser()


def db_path_for_codex_dir(codex_dir: str | Path) -> Path:
    return normalize_codex_dir(codex_dir) / "sqlite" / "codex-dev.db"


def ensure_feature_table(con: sqlite3.Connection) -> None:
    con.execute(
        f"""
        create table if not exists {FEATURE_TABLE} (
            feature_name TEXT PRIMARY KEY,
            enabled INTEGER NOT NULL,
            updated_at INTEGER NOT NULL
        )
        """
    )


def set_remote_control(codex_dir: str | Path, enabled: bool) -> Path:
    db_path = db_path_for_codex_dir(codex_dir)
    db_path.parent.mkdir(parents=True, exist_ok=True)

    with closing(sqlite3.connect(db_path)) as con:
        ensure_feature_table(con)
        con.execute(
            f"""
            insert into {FEATURE_TABLE}(feature_name, enabled, updated_at)
            values (?, ?, ?)
            on conflict(feature_name) do update set
                enabled = excluded.enabled,
                updated_at = excluded.updated_at
            """,
            (REMOTE_CONTROL, 1 if enabled else 0, int(time.time() * 1000)),
        )
        con.commit()

    return db_path


def init_remote_control(codex_dir: str | Path) -> Path:
    return set_remote_control(codex_dir, True)


def read_remote_control(codex_dir: str | Path) -> int | None:
    db_path = db_path_for_codex_dir(codex_dir)
    if not db_path.exists():
        return None

    with closing(sqlite3.connect(db_path)) as con:
        ensure_feature_table(con)
        row = con.execute(
            f"select enabled from {FEATURE_TABLE} where feature_name = ?",
            (REMOTE_CONTROL,),
        ).fetchone()

    if row is None:
        return None
    return int(row[0])


def _run_powershell_json(script: str) -> object:
    result = subprocess.run(
        [
            "powershell",
            "-NoProfile",
            "-ExecutionPolicy",
            "Bypass",
            "-Command",
            script,
        ],
        capture_output=True,
        text=True,
        timeout=8,
        check=False,
    )
    if result.returncode != 0:
        raise RuntimeError((result.stderr or result.stdout).strip())

    text = result.stdout.strip()
    if not text:
        return None
    return json.loads(text)


def inspect_runtime_status() -> RuntimeStatus:
    script = r"""
$appServers = @(Get-CimInstance Win32_Process |
  Where-Object {
    $_.Name -ieq 'codex.exe' -and
    $_.CommandLine -like '*app-server --analytics-default-enabled*' -and
    $_.ExecutablePath -like '*\WindowsApps\OpenAI.Codex_*\app\resources\codex.exe'
  } |
  ForEach-Object { [int]$_.ProcessId })

$connected = @(Get-NetTCPConnection -State Established -ErrorAction SilentlyContinue |
  Where-Object { $appServers -contains $_.OwningProcess -and $_.RemotePort -eq 443 } |
  ForEach-Object { [int]$_.OwningProcess } |
  Sort-Object -Unique)

[pscustomobject]@{
  app_server_pids = $appServers
  connected_pids = $connected
} | ConvertTo-Json -Compress
"""
    try:
        data = _run_powershell_json(script)
        if not isinstance(data, dict):
            raise RuntimeError("Unexpected PowerShell status output.")

        app_server_pids = tuple(int(pid) for pid in _as_list(data.get("app_server_pids")))
        connected_pids = tuple(int(pid) for pid in _as_list(data.get("connected_pids")))
        return RuntimeStatus(
            app_server_running=bool(app_server_pids),
            app_server_pids=app_server_pids,
            cloud_connected=bool(connected_pids),
            connected_pids=connected_pids,
        )
    except Exception as exc:
        return RuntimeStatus(
            app_server_running=False,
            app_server_pids=(),
            cloud_connected=False,
            connected_pids=(),
            error=str(exc),
        )


def _as_list(value: object) -> list[object]:
    if value is None:
        return []
    if isinstance(value, list):
        return value
    return [value]


def build_prompt_text(codex_dir: str | Path) -> str:
    return r"""# Codex Mobile Remote Control on Windows

Windows PC에서 Codex Mobile Remote Control이 재시작 후에도 유지되게 켜는 방법입니다.

## 핵심 요약

- `config.toml`의 `[features] remote_control = true`는 재시작하면 사라질 수 있습니다.
- Windows Codex Desktop은 로컬 SQLite DB의 `local_app_server_feature_enablement` 값을 봅니다.
- 기본 대상 폴더는 현재 Windows 사용자의 `%USERPROFILE%\.codex`입니다.
- 직접 다른 `.codex` 폴더를 지정해야 한다면 `$codexDir` 값만 바꾸면 됩니다.
- Codex Desktop과 ChatGPT/Codex mobile은 같은 계정으로 로그인되어 있어야 합니다.

## 1. Codex Desktop 준비

1. Windows에서 Codex Desktop을 설치합니다.
2. Codex Desktop을 한 번 실행하고 ChatGPT 계정으로 로그인합니다.
3. 가능하면 Codex Desktop을 완전히 종료한 뒤 아래 명령을 실행합니다.

새 PC에서는 한 번 실행해서 `.codex` 상태 폴더가 만들어진 뒤 적용하는 쪽이 깔끔합니다.

## 2. Remote Control 활성화

PowerShell에서 실행:

```powershell
$codexDir = Join-Path $env:USERPROFILE '.codex'
$dir = Join-Path $codexDir 'sqlite'
New-Item -ItemType Directory -Force -Path $dir | Out-Null
$db = Join-Path $dir 'codex-dev.db'
python -c 'import sqlite3,time,sys; con=sqlite3.connect(sys.argv[1]); con.execute("create table if not exists local_app_server_feature_enablement (feature_name TEXT PRIMARY KEY, enabled INTEGER NOT NULL, updated_at INTEGER NOT NULL)"); con.execute("insert into local_app_server_feature_enablement(feature_name,enabled,updated_at) values (?,?,?) on conflict(feature_name) do update set enabled=excluded.enabled, updated_at=excluded.updated_at", ("remote_control",1,int(time.time()*1000))); con.commit(); con.close()' $db
```

`python` 명령이 없으면 마지막 줄의 `python`만 `py -3`로 바꿉니다.

직접 다른 `.codex` 폴더를 지정해야 한다면 첫 줄만 이렇게 바꿉니다:

```powershell
$codexDir = 'C:\Path\To\.codex'
```

## 3. 적용 확인

```powershell
$codexDir = Join-Path $env:USERPROFILE '.codex'
$db = Join-Path $codexDir 'sqlite\codex-dev.db'
python -c 'import sqlite3,sys; con=sqlite3.connect(sys.argv[1]); print(con.execute("select feature_name, enabled, updated_at from local_app_server_feature_enablement").fetchall()); con.close()' $db
```

정상 예시:

```text
[('remote_control', 1, 1779249183805)]
```

`enabled` 값이 `1`이면 켜진 상태입니다.

## 4. Codex 다시 실행

Codex Desktop을 다시 켭니다.

이후 프로세스에 아래 형태가 떠 있으면 정상입니다.

```text
codex.exe app-server --analytics-default-enabled
```

확인 명령:

```powershell
Get-CimInstance Win32_Process |
  Where-Object { $_.Name -match 'Codex|codex' } |
  Select-Object ProcessId,ParentProcessId,Name,ExecutablePath,CommandLine |
  Format-Table -Wrap
```

## 5. 실제 연결 확인

Codex app-server가 `443` 포트로 연결되어 있는지 확인:

```powershell
$codexPids = @(Get-CimInstance Win32_Process |
  Where-Object { $_.Name -match 'Codex|codex' } |
  ForEach-Object { [int]$_.ProcessId })

Get-NetTCPConnection -State Established -ErrorAction SilentlyContinue |
  Where-Object { $codexPids -contains $_.OwningProcess -and $_.RemotePort -eq 443 } |
  Select-Object OwningProcess,LocalAddress,LocalPort,RemoteAddress,RemotePort,State |
  Sort-Object OwningProcess,RemotePort |
  Format-Table -AutoSize
```

`RemotePort`가 `443`이고 `State`가 `Established`이면 서버와 연결된 상태입니다.

로그에서 웹소켓 ack까지 확인하려면:

```powershell
$logdb = Join-Path $env:USERPROFILE '.codex\logs_2.sqlite'
python -c 'import sqlite3,sys,datetime; con=sqlite3.connect(sys.argv[1]); rows=con.execute("select ts, level, target, feedback_log_body from logs order by ts desc, ts_nanos desc limit 40").fetchall(); [print("---", datetime.datetime.fromtimestamp(r[0]).isoformat(), r[1], r[2], "\n", (r[3] or "")[:500].replace("\n","\\n")) for r in rows]; con.close()' $logdb
```

최신 로그에 `WebSocketStream`, `Sending frame`, `Received message`, `ack` 같은 항목이 보일 수 있습니다.

## 6. Mobile에서 연결

1. 모바일 ChatGPT/Codex 앱을 엽니다.
2. Windows Codex Desktop과 같은 계정인지 확인합니다.
3. Codex Remote Control / local desktop 목록에서 해당 PC 이름을 선택합니다.

PC 이름은 보통 Windows 장치 이름으로 보입니다.

## 7. 주의할 점

`codex features enable remote_control`은 Windows Desktop 재시작 후 유지되지 않을 수 있습니다.

아래처럼 `config.toml`에 직접 들어간 값은 앱이 다시 쓰면서 사라질 수 있습니다.

```toml
[features]
remote_control = true
```

따라서 Windows에서는 SQLite의 `local_app_server_feature_enablement` 값을 기준으로 확인합니다.

중복으로 수동 app-server를 띄우면 충돌할 수 있습니다.

```powershell
codex app-server --listen ws://127.0.0.1:14555
```

중복 서버 확인:

```powershell
Get-CimInstance Win32_Process |
  Where-Object { $_.Name -ieq 'codex.exe' -and $_.CommandLine -like '*app-server --listen ws://*' } |
  Select-Object ProcessId,CommandLine |
  Format-Table -Wrap
```

필요할 때만 해당 테스트 서버를 종료합니다.

```powershell
Get-CimInstance Win32_Process |
  Where-Object { $_.Name -ieq 'codex.exe' -and $_.CommandLine -like '*app-server --listen ws://*' } |
  ForEach-Object { Stop-Process -Id $_.ProcessId -Force }
```

Codex Desktop이 직접 띄운 아래 프로세스는 건드리지 않습니다.

```text
codex.exe app-server --analytics-default-enabled
```

## 빠른 복붙용

활성화:

```powershell
$codexDir = Join-Path $env:USERPROFILE '.codex'; $dir = Join-Path $codexDir 'sqlite'; New-Item -ItemType Directory -Force -Path $dir | Out-Null; $db = Join-Path $dir 'codex-dev.db'; python -c 'import sqlite3,time,sys; con=sqlite3.connect(sys.argv[1]); con.execute("create table if not exists local_app_server_feature_enablement (feature_name TEXT PRIMARY KEY, enabled INTEGER NOT NULL, updated_at INTEGER NOT NULL)"); con.execute("insert into local_app_server_feature_enablement(feature_name,enabled,updated_at) values (?,?,?) on conflict(feature_name) do update set enabled=excluded.enabled, updated_at=excluded.updated_at", ("remote_control",1,int(time.time()*1000))); con.commit(); con.close()' $db
```

확인:

```powershell
$codexDir = Join-Path $env:USERPROFILE '.codex'; $db = Join-Path $codexDir 'sqlite\codex-dev.db'; python -c 'import sqlite3,sys; con=sqlite3.connect(sys.argv[1]); print(con.execute("select feature_name, enabled, updated_at from local_app_server_feature_enablement").fetchall()); con.close()' $db
```
"""
