#!/usr/bin/env python3
"""
TD POC State Manager
====================
Tracks POC state, workflow sessions, and enables recovery across Claude sessions.

Usage:
    python state_manager.py status              # Show current POC status
    python state_manager.py start <poc-name>    # Start a new POC
    python state_manager.py stage <stage-name>  # Update current stage
    python state_manager.py complete <stage>    # Mark stage as completed
    python state_manager.py fail <stage> <err>  # Mark stage as failed
    python state_manager.py session <id>        # Track TD session
    python state_manager.py resume              # Get resume point
"""

import json
import os
import sys
from datetime import datetime
from pathlib import Path
from typing import Dict, List, Optional, Any
import argparse

# Try to import optional dependencies
try:
    from rich.console import Console
    from rich.table import Table
    RICH_AVAILABLE = True
except ImportError:
    RICH_AVAILABLE = False

# Constants
STATE_DIR = Path(__file__).parent.parent.parent / ".poc-state"
CONFIG_FILE = STATE_DIR / "config.json"
CURRENT_POC_FILE = STATE_DIR / "current-poc.json"
SESSIONS_DIR = STATE_DIR / "sessions"


class StateManager:
    """Manages POC state and enables cross-session recovery."""

    def __init__(self):
        self.state_dir = STATE_DIR
        self.state_dir.mkdir(parents=True, exist_ok=True)
        SESSIONS_DIR.mkdir(parents=True, exist_ok=True)
        self.config = self._load_config()
        self.state = self._load_state()

    def _load_config(self) -> Dict:
        """Load configuration from config.json."""
        if CONFIG_FILE.exists():
            with open(CONFIG_FILE) as f:
                return json.load(f)
        return {
            "project_name": "retail-poc",
            "max_retries": 10,
            "retry_delay_seconds": 300,
            "poll_interval_seconds": 60,
        }

    def _load_state(self) -> Dict:
        """Load current POC state."""
        if CURRENT_POC_FILE.exists():
            with open(CURRENT_POC_FILE) as f:
                return json.load(f)
        return self._default_state()

    def _default_state(self) -> Dict:
        """Return default POC state structure."""
        return {
            "poc_id": None,
            "created_at": None,
            "stage": "init",
            "stages": {
                "init": {"status": "pending"},
                "profiling": {"status": "pending"},
                "staging": {"status": "pending"},
                "unification": {"status": "pending"},
                "golden": {"status": "pending"},
                "segment": {"status": "pending"},
            },
            "active_td_session": None,
            "td_sessions": [],
            "errors": [],
            "yaml_changes": [],
            "config": {}
        }

    def _save_state(self):
        """Persist current state to disk."""
        with open(CURRENT_POC_FILE, "w") as f:
            json.dump(self.state, f, indent=2)

    def start_poc(self, poc_name: str, raw_db: str = None, stg_db: str = None) -> Dict:
        """Initialize a new POC."""
        self.state = self._default_state()
        self.state["poc_id"] = poc_name
        self.state["created_at"] = datetime.now().isoformat()
        self.state["stage"] = "init"
        self.state["stages"]["init"]["status"] = "in_progress"
        self.state["stages"]["init"]["started_at"] = datetime.now().isoformat()

        if raw_db:
            self.state["config"]["raw_db"] = raw_db
        if stg_db:
            self.state["config"]["stg_db"] = stg_db

        self._save_state()
        return {"status": "created", "poc_id": poc_name}

    def get_status(self) -> Dict:
        """Get current POC status."""
        if not self.state.get("poc_id"):
            return {"status": "no_active_poc", "message": "No POC in progress. Run /poc-start to begin."}

        completed = sum(1 for s in self.state["stages"].values() if s["status"] == "completed")
        total = len(self.state["stages"])

        return {
            "poc_id": self.state["poc_id"],
            "created_at": self.state["created_at"],
            "current_stage": self.state["stage"],
            "progress": f"{completed}/{total} stages",
            "progress_percent": round(completed / total * 100),
            "stages": self.state["stages"],
            "active_td_session": self.state.get("active_td_session"),
            "errors": self.state.get("errors", [])[-5:],  # Last 5 errors
        }

    def set_stage(self, stage: str, status: str = "in_progress") -> Dict:
        """Update current stage."""
        if stage not in self.state["stages"]:
            return {"error": f"Invalid stage: {stage}"}

        self.state["stage"] = stage
        self.state["stages"][stage]["status"] = status
        self.state["stages"][stage][f"{status}_at"] = datetime.now().isoformat()

        if status == "in_progress":
            self.state["stages"][stage]["retry_count"] = 0

        self._save_state()
        return {"status": "updated", "stage": stage, "stage_status": status}

    def complete_stage(self, stage: str) -> Dict:
        """Mark a stage as completed."""
        return self.set_stage(stage, "completed")

    def fail_stage(self, stage: str, error: str) -> Dict:
        """Mark a stage as failed and record error."""
        self.state["stages"][stage]["status"] = "failed"
        self.state["stages"][stage]["failed_at"] = datetime.now().isoformat()

        retry_count = self.state["stages"][stage].get("retry_count", 0)
        self.state["stages"][stage]["retry_count"] = retry_count + 1

        self.state["errors"].append({
            "stage": stage,
            "error": error,
            "timestamp": datetime.now().isoformat(),
            "retry_count": retry_count + 1
        })

        self._save_state()

        max_retries = self.config.get("max_retries", 10)
        can_retry = retry_count + 1 < max_retries

        return {
            "status": "failed",
            "stage": stage,
            "error": error,
            "retry_count": retry_count + 1,
            "can_retry": can_retry,
            "max_retries": max_retries
        }

    def track_td_session(self, session_id: str, workflow_name: str = None) -> Dict:
        """Track an active TD workflow session."""
        self.state["active_td_session"] = session_id

        session_info = {
            "session_id": session_id,
            "workflow": workflow_name,
            "stage": self.state["stage"],
            "started_at": datetime.now().isoformat(),
            "status": "running"
        }

        if "td_sessions" not in self.state:
            self.state["td_sessions"] = []
        self.state["td_sessions"].append(session_info)

        # Also save to sessions directory for history
        session_file = SESSIONS_DIR / f"{session_id}.json"
        with open(session_file, "w") as f:
            json.dump(session_info, f, indent=2)

        self._save_state()
        return {"status": "tracked", "session_id": session_id}

    def update_td_session(self, session_id: str, status: str, error: str = None) -> Dict:
        """Update TD session status."""
        for session in self.state.get("td_sessions", []):
            if session["session_id"] == session_id:
                session["status"] = status
                session["updated_at"] = datetime.now().isoformat()
                if error:
                    session["error"] = error
                break

        if status in ["success", "error", "killed"]:
            if self.state.get("active_td_session") == session_id:
                self.state["active_td_session"] = None

        self._save_state()
        return {"status": "updated", "session_id": session_id, "session_status": status}

    def get_resume_point(self) -> Dict:
        """Get information needed to resume POC after interruption."""
        if not self.state.get("poc_id"):
            return {"can_resume": False, "message": "No POC to resume"}

        # Find the last completed stage
        stage_order = ["init", "profiling", "staging", "unification", "golden", "segment"]
        last_completed = None
        next_stage = None

        for stage in stage_order:
            status = self.state["stages"][stage]["status"]
            if status == "completed":
                last_completed = stage
            elif status in ["in_progress", "failed", "pending"]:
                next_stage = stage
                break

        return {
            "can_resume": True,
            "poc_id": self.state["poc_id"],
            "last_completed_stage": last_completed,
            "next_stage": next_stage,
            "active_td_session": self.state.get("active_td_session"),
            "has_errors": len(self.state.get("errors", [])) > 0,
            "last_error": self.state.get("errors", [])[-1] if self.state.get("errors") else None
        }

    def record_yaml_change(self, file_path: str, change_type: str, approved: bool) -> Dict:
        """Record a YAML file change that required human approval."""
        change = {
            "file": file_path,
            "type": change_type,
            "approved": approved,
            "timestamp": datetime.now().isoformat(),
            "stage": self.state["stage"]
        }

        if "yaml_changes" not in self.state:
            self.state["yaml_changes"] = []
        self.state["yaml_changes"].append(change)

        self._save_state()
        return {"status": "recorded", "change": change}

    def reset(self) -> Dict:
        """Reset POC state (use with caution)."""
        self.state = self._default_state()
        self._save_state()
        return {"status": "reset", "message": "POC state has been reset"}


def print_status_rich(status: Dict):
    """Print status using rich library for nice formatting."""
    console = Console()

    if status.get("status") == "no_active_poc":
        console.print(f"[yellow]{status['message']}[/yellow]")
        return

    console.print(f"\n[bold blue]POC: {status['poc_id']}[/bold blue]")
    console.print(f"Created: {status['created_at']}")
    console.print(f"Progress: {status['progress']} ({status['progress_percent']}%)")

    # Create stages table
    table = Table(title="Pipeline Stages")
    table.add_column("Stage", style="cyan")
    table.add_column("Status", style="magenta")
    table.add_column("Details")

    status_colors = {
        "completed": "green",
        "in_progress": "yellow",
        "failed": "red",
        "pending": "dim"
    }

    for stage, info in status["stages"].items():
        stage_status = info["status"]
        color = status_colors.get(stage_status, "white")
        details = ""
        if stage_status == "completed" and "completed_at" in info:
            details = f"at {info['completed_at']}"
        elif stage_status == "failed" and "retry_count" in info:
            details = f"retries: {info['retry_count']}"

        table.add_row(stage, f"[{color}]{stage_status}[/{color}]", details)

    console.print(table)

    if status.get("active_td_session"):
        console.print(f"\n[yellow]Active TD Session: {status['active_td_session']}[/yellow]")

    if status.get("errors"):
        console.print("\n[red]Recent Errors:[/red]")
        for err in status["errors"]:
            console.print(f"  - {err['stage']}: {err['error'][:50]}...")


def print_status_plain(status: Dict):
    """Print status using plain text."""
    if status.get("status") == "no_active_poc":
        print(status['message'])
        return

    print(f"\nPOC: {status['poc_id']}")
    print(f"Created: {status['created_at']}")
    print(f"Progress: {status['progress']} ({status['progress_percent']}%)")
    print(f"Current Stage: {status['current_stage']}")
    print("\nStages:")

    for stage, info in status["stages"].items():
        print(f"  {stage}: {info['status']}")

    if status.get("active_td_session"):
        print(f"\nActive TD Session: {status['active_td_session']}")


def main():
    parser = argparse.ArgumentParser(description="TD POC State Manager")
    subparsers = parser.add_subparsers(dest="command", help="Commands")

    # Status command
    subparsers.add_parser("status", help="Show current POC status")

    # Start command
    start_parser = subparsers.add_parser("start", help="Start a new POC")
    start_parser.add_argument("name", help="POC name")
    start_parser.add_argument("--raw-db", help="Raw database name")
    start_parser.add_argument("--stg-db", help="Staging database name")

    # Stage command
    stage_parser = subparsers.add_parser("stage", help="Update current stage")
    stage_parser.add_argument("name", help="Stage name")
    stage_parser.add_argument("--status", default="in_progress", help="Stage status")

    # Complete command
    complete_parser = subparsers.add_parser("complete", help="Mark stage as completed")
    complete_parser.add_argument("stage", help="Stage name")

    # Fail command
    fail_parser = subparsers.add_parser("fail", help="Mark stage as failed")
    fail_parser.add_argument("stage", help="Stage name")
    fail_parser.add_argument("error", help="Error message")

    # Session command
    session_parser = subparsers.add_parser("session", help="Track TD session")
    session_parser.add_argument("session_id", help="TD session ID")
    session_parser.add_argument("--workflow", help="Workflow name")

    # Resume command
    subparsers.add_parser("resume", help="Get resume point")

    # Reset command
    subparsers.add_parser("reset", help="Reset POC state")

    args = parser.parse_args()
    manager = StateManager()

    if args.command == "status":
        status = manager.get_status()
        if RICH_AVAILABLE:
            print_status_rich(status)
        else:
            print_status_plain(status)

    elif args.command == "start":
        result = manager.start_poc(args.name, args.raw_db, args.stg_db)
        print(json.dumps(result, indent=2))

    elif args.command == "stage":
        result = manager.set_stage(args.name, args.status)
        print(json.dumps(result, indent=2))

    elif args.command == "complete":
        result = manager.complete_stage(args.stage)
        print(json.dumps(result, indent=2))

    elif args.command == "fail":
        result = manager.fail_stage(args.stage, args.error)
        print(json.dumps(result, indent=2))

    elif args.command == "session":
        result = manager.track_td_session(args.session_id, args.workflow)
        print(json.dumps(result, indent=2))

    elif args.command == "resume":
        result = manager.get_resume_point()
        print(json.dumps(result, indent=2))

    elif args.command == "reset":
        result = manager.reset()
        print(json.dumps(result, indent=2))

    else:
        parser.print_help()


if __name__ == "__main__":
    main()
