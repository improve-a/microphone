"""Run deterministic offline gates and save machine-readable evidence."""

from __future__ import annotations

import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys


ROOT = Path(__file__).resolve().parents[1]


def find_tool(name: str, candidates: list[Path]) -> str | None:
    located = shutil.which(name)
    if located:
        return located
    for candidate in candidates:
        if candidate.exists():
            return str(candidate)
    return None


def git_output(*arguments: str) -> str:
    result = subprocess.run(
        ["git", *arguments], cwd=ROOT, text=True, stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT, errors="replace", check=False
    )
    return result.stdout.strip()


def source_tree_hash() -> str:
    digest = hashlib.sha256()
    excluded = {".git", "__pycache__", "build", "generated", "runs"}
    for path in sorted(ROOT.rglob("*")):
        if not path.is_file() or any(part in excluded for part in path.parts):
            continue
        relative = path.relative_to(ROOT).as_posix()
        digest.update(relative.encode("utf-8"))
        digest.update(b"\0")
        digest.update(path.read_bytes())
        digest.update(b"\0")
    return digest.hexdigest()


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--skip-full-vivado", action="store_true")
    parser.add_argument("--skip-vivado-rtl", action="store_true")
    parser.add_argument("--skip-sdk", action="store_true")
    parser.add_argument("--skip-matlab", action="store_true")
    args = parser.parse_args()

    vivado = find_tool("vivado", [Path(r"E:\vivado\Vivado\2019.1\bin\vivado.bat")])
    xsct = find_tool("xsct", [Path(r"E:\vivado\SDK\2019.1\bin\xsct.bat")])
    matlab = find_tool("matlab", [Path(r"C:\Program Files\MATLAB\R2024a\bin\matlab.exe")])
    gcc = find_tool("gcc", [])
    if not vivado or not gcc:
        print("MIC_REGRESSION_FAIL missing Vivado or GCC", flush=True)
        return 2
    if not args.skip_sdk and not xsct:
        print("MIC_REGRESSION_FAIL missing XSCT", flush=True)
        return 2
    if not args.skip_matlab and not matlab:
        print("MIC_REGRESSION_FAIL missing MATLAB", flush=True)
        return 2

    timestamp = datetime.now(timezone.utc).strftime("%Y%m%d_%H%M%S_utc")
    head = git_output("rev-parse", "--short=12", "HEAD") or "nohead"
    run_id = f"mic_offline_{timestamp}_{head}"
    run_dir = ROOT / "evidence" / "runs" / run_id
    run_dir.mkdir(parents=True, exist_ok=False)
    print(f"RUN_ID={run_id}", flush=True)

    steps: list[tuple[str, list[str], str, dict[str, str] | None]] = [
        (
            "python_tests",
            [sys.executable, "-m", "unittest", "discover", "-s", "tests", "-v"],
            "OK",
            None,
        ),
        (
            "host_c_build",
            [
                gcc, "-std=c11", "-Wall", "-Wextra", "-Werror",
                "-I", "sw/include", "sw/src/dma_contract.c",
                "sw/src/mic_udp_protocol.c", "sw/tests/test_contracts.c",
                "-o", str(run_dir / "test_contracts.exe"),
            ],
            "",
            None,
        ),
        (
            "host_c_test",
            [str(run_dir / "test_contracts.exe")],
            "MIC_SW_HOST_BUILD_PASS",
            None,
        ),
        (
            "vivado_ooc",
            [vivado, "-mode", "batch", "-nojournal", "-nolog", "-notrace",
             "-source", "vivado/run_ooc.tcl"],
            "MIC_DMA_OOC_PASS",
            None,
        ),
    ]
    if not args.skip_vivado_rtl:
        steps.insert(3, (
            "vivado_rtl",
            [vivado, "-mode", "batch", "-nojournal", "-nolog", "-notrace",
             "-source", "vivado/run_rtl_tests.tcl"],
            "MIC_RTL_SUITE_PASS",
            None,
        ))
    if not args.skip_full_vivado:
        steps.append((
            "vivado_full",
            [vivado, "-mode", "batch", "-nojournal", "-nolog", "-notrace",
             "-source", "vivado/build_mic_dma.tcl"],
            "MIC_DMA_VIVADO_PASS",
            None,
        ))
    if not args.skip_sdk:
        sdk_env = os.environ.copy()
        sdk_env["MIC_SDK_WORKSPACE"] = str(ROOT / "sw" / "build" / run_id)
        steps.append(("sdk_build", [xsct, "sw/build_sdk.tcl"], "MIC_SDK_BUILD_PASS", sdk_env))
    if not args.skip_matlab:
        command = "cd('D:/microphone'); addpath('matlab'); run_all_tests"
        matlab_env = os.environ.copy()
        matlab_env["MATLAB_PREFDIR"] = str(run_dir / "matlab_pref")
        (run_dir / "matlab_pref").mkdir(parents=True, exist_ok=True)
        steps.append(("matlab", [matlab, "-batch", command], "MIC_GCC_PHAT_DOA_PASS", matlab_env))

    summary = {
        "run_id": run_id,
        "utc_started": datetime.now(timezone.utc).isoformat(),
        "git_head": git_output("rev-parse", "HEAD"),
        "git_branch": git_output("branch", "--show-current"),
        "git_status": git_output("status", "--short"),
        "source_tree_sha256": source_tree_hash(),
        "tools": {"python": sys.executable, "gcc": gcc, "vivado": vivado,
                  "xsct": xsct, "matlab": matlab},
        "steps": [],
        "status": "FAIL",
    }
    for name, command, required_token, environment in steps:
        print(f"STEP_START={name}", flush=True)
        try:
            completed = subprocess.run(
                command, cwd=ROOT, env=environment, text=True,
                stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                errors="replace", check=False, timeout=600
            )
            output = completed.stdout
        except subprocess.TimeoutExpired as timeout:
            output = (timeout.stdout or "") + "\nMIC_REGRESSION_TOOL_TIMEOUT\n"
            completed = subprocess.CompletedProcess(command, 124, output)
        (run_dir / f"{name}.log").write_text(output, encoding="utf-8", errors="replace")
        token_ok = not required_token or required_token in output
        passed = completed.returncode == 0 and token_ok
        summary["steps"].append({
            "name": name, "command": command, "returncode": completed.returncode,
            "required_token": required_token, "token_found": token_ok,
            "status": "PASS" if passed else "FAIL",
        })
        print(f"STEP_{'PASS' if passed else 'FAIL'}={name}", flush=True)
        if not passed:
            (run_dir / "summary.json").write_text(
                json.dumps(summary, indent=2), encoding="utf-8"
            )
            print(f"MIC_REGRESSION_FAIL step={name} RUN_ID={run_id}", flush=True)
            return 1

    summary["status"] = "PASS"
    summary["utc_finished"] = datetime.now(timezone.utc).isoformat()
    (run_dir / "summary.json").write_text(json.dumps(summary, indent=2), encoding="utf-8")
    print(f"MIC_REGRESSION_PASS RUN_ID={run_id}", flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
