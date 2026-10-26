"""SFS catalog protocol 1. Python 3.11+ standard library only; no network or AI.

The caller supplies an isolated root. Only metadata is indexed; editable art remains
in the project files. Every request is a single SQLite transaction.
"""
from __future__ import annotations
import argparse
import json
import os
import sqlite3
from contextlib import closing
from pathlib import Path

SCHEMA = """
CREATE TABLE IF NOT EXISTS projects (
 id TEXT PRIMARY KEY, name TEXT NOT NULL, path TEXT NOT NULL,
 hash TEXT NOT NULL, bible_version INTEGER NOT NULL, updated TEXT DEFAULT CURRENT_TIMESTAMP
);
CREATE TABLE IF NOT EXISTS refs (
 id TEXT NOT NULL, project_id TEXT NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
 hash TEXT NOT NULL, state TEXT NOT NULL, metadata TEXT NOT NULL,
 PRIMARY KEY(id, project_id)
);
CREATE TABLE IF NOT EXISTS dependencies (
 source TEXT NOT NULL, target TEXT NOT NULL, project_id TEXT NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
 stale INTEGER NOT NULL CHECK(stale IN (0,1)), PRIMARY KEY(source,target,project_id)
);
CREATE TABLE IF NOT EXISTS audit (
 id INTEGER PRIMARY KEY, operation TEXT NOT NULL, project_id TEXT,
 created TEXT DEFAULT CURRENT_TIMESTAMP
);
PRAGMA user_version=1;
"""

def text(value, name, limit=4096):
    if not isinstance(value, str) or len(value) > limit:
        raise ValueError(f"Invalid {name}")
    return value

def dispatch(database: Path, request: dict) -> dict:
    if not isinstance(request, dict) or request.get("schema") != 1:
        raise ValueError("Unsupported protocol")
    with closing(sqlite3.connect(database, timeout=5)) as connection, connection:
        connection.execute("PRAGMA foreign_keys=ON")
        connection.executescript(SCHEMA)
        command = request.get("command")
        if command == "index":
            project = request["project"]
            project_id = text(project["id"], "project id", 128)
            name = text(project["name"], "name")
            path = text(project.get("path", ""), "path")
            digest = text(project.get("hash", ""), "hash", 128)
            version = project.get("bible_version", 1)
            if type(version) is not int or version < 1:
                raise ValueError("Invalid Art Bible version")
            connection.execute(
                "INSERT INTO projects(id,name,path,hash,bible_version) VALUES(?,?,?,?,?) "
                "ON CONFLICT(id) DO UPDATE SET name=excluded.name,path=excluded.path,"
                "hash=excluded.hash,bible_version=excluded.bible_version,updated=CURRENT_TIMESTAMP",
                (project_id, name, path, digest, version),
            )
            connection.execute("DELETE FROM refs WHERE project_id=?", (project_id,))
            connection.execute("DELETE FROM dependencies WHERE project_id=?", (project_id,))
            references = project.get("references", [])
            relations = project.get("dependencies", [])
            if not isinstance(references, list) or len(references) > 64 or not isinstance(relations, list) or len(relations) > 4096:
                raise ValueError("Metadata limit exceeded")
            for reference in references:
                ref_id = text(reference["id"], "reference id", 128)
                state = text(reference["state"], "state", 32)
                if state not in ("imported", "analyzed", "review", "approved", "partial", "archived", "rejected"):
                    raise ValueError("Invalid reference state")
                # Explicit allowlist: original bytes, thumbnails, credentials and prompts never enter the index.
                metadata = {k: reference[k] for k in ("name", "source", "license", "features", "confidence", "dimensions") if k in reference}
                connection.execute("INSERT INTO refs VALUES(?,?,?,?,?)", (ref_id, project_id, text(reference["sha256"], "reference hash", 128), state, json.dumps(metadata, ensure_ascii=False)))
            for relation in relations:
                if type(relation.get("stale")) is not bool:
                    raise ValueError("Invalid dependency state")
                connection.execute("INSERT INTO dependencies VALUES(?,?,?,?)", (text(relation["source"], "source", 128), text(relation["target"], "target", 128), project_id, int(relation["stale"])))
            connection.execute("INSERT INTO audit(operation,project_id) VALUES('index',?)", (project_id,))
            return {"ok": True, "projects": 1, "references": len(references), "dependencies": len(relations)}
        if command == "list":
            rows = connection.execute("SELECT id,name,path,hash,bible_version FROM projects ORDER BY updated DESC,id").fetchall()
            return {"ok": True, "projects": [dict(zip(("id", "name", "path", "hash", "bible_version"), row)) for row in rows]}
        raise ValueError("Unknown command")

def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", required=True, type=Path)
    parser.add_argument("--request", required=True, type=Path)
    parser.add_argument("--result", required=True, type=Path)
    args = parser.parse_args()
    root = args.root.resolve()
    root.mkdir(parents=True, exist_ok=True)
    request_path = args.request.resolve()
    result_path = args.result.resolve()
    if not request_path.is_relative_to(root) or not result_path.is_relative_to(root):
        return 2
    try:
        if request_path.stat().st_size > 8 * 1024 * 1024:
            raise ValueError("Request exceeds 8 MiB")
        result = dispatch(root / "catalog.sqlite", json.loads(request_path.read_text(encoding="utf-8")))
    except (OSError, ValueError, KeyError, TypeError, sqlite3.Error) as error:
        result = {"ok": False, "error": str(error)[:500]}
    temporary = result_path.with_suffix(".tmp")
    temporary.write_text(json.dumps({"schema": 1, **result}, ensure_ascii=False), encoding="utf-8")
    os.replace(temporary, result_path)
    return 0 if result["ok"] else 1

if __name__ == "__main__":
    raise SystemExit(main())
