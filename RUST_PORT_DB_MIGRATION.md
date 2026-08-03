# FocusFlow → Rust: Database Migration — SQLite Schema & Data Port

> **Companion to:** `FOCUSFLOW_RUST_PORT_MASTER.md`  
> **JVM Reference:** `data/Database.kt` (1281 lines), `data/models/Models.kt`

---

## 1. Schema Overview

FocusFlow's SQLite in `~/.focusflow/focusflow.db` defined identical to JVM version. All tables, columns, indexes, and defaults stay the exact same.

## 2. Full DDL (Identical to Kolin Database.create)

```sql
-- ============================================================================
-- TABLE: focus_sessions
-- ============================================================================
CREATE TABLE IF NOT EXISTS focus_sessions (
    id                       TEXT PRIMARY KEY,
    title                    TEXT NOT NULL DEFAULT '',
    start_time               TEXT NOT NULL,
    end_time                 TEXT,
    duration_seconds         INTEGER NOT NULL DEFAULT 0,
    survived_nuclear_mode    INTEGER NOT NULL DEFAULT 0,
    nuclear_mode_activated   INTEGER NOT NULL DEFAULT 0,
    date                     TEXT NOT NULL
);

-- ============================================================================
-- TABLE: temptation_logs
-- ============================================================================
CREATE TABLE IF NOT EXISTS temptation_logs (
    id                TEXT PRIMARY KEY,
    app_name          TEXT NOT NULL,
    window_title      TEXT,
    process_path      TEXT,
    timestamp         TEXT NOT NULL,
    duration_seconds  INTEGER DEFAULT 0,
    date              TEXT NOT NULL,
    session_id        TEXT
);

-- ============================================================================
-- TABLE: blocked_apps
-- ============================================================================
CREATE TABLE IF NOT EXISTS blocked_apps (
    id            TEXT PRIMARY KEY,
    name          TEXT NOT NULL,
    path          TEXT NOT NULL,
    icon          BLOB,
    is_keyword    INTEGER NOT NULL DEFAULT 0,
    block_mode    TEXT NOT NULL DEFAULT 'FILE',
    enabled       INTEGER NOT NULL DEFAULT 1,
    date_added    TEXT NOT NULL
);

-- ============================================================================
-- TABLE: blocked_keywords
-- ============================================================================
CREATE TABLE IF NOT EXISTS blocked_keywords (
    id          TEXT PRIMARY KEY,
    keyword     TEXT NOT NULL UNIQUE,
    enabled     INTEGER NOT NULL DEFAULT 1,
    date_added  TEXT NOT NULL
);

-- ============================================================================
-- TABLE: preferences
-- ============================================================================
CREATE TABLE IF NOT EXISTS preferences (
    key         TEXT PRIMARY KEY,
    value       TEXT NOT NULL
);

-- ============================================================================
-- TABLE: nuclear_mode_logs
-- ============================================================================
CREATE TABLE IF NOT EXISTS nuclear_mode_logs (
    id                TEXT PRIMARY KEY,
    escaped_process   TEXT NOT NULL,
    escape_path       TEXT,
    timestamp         TEXT NOT NULL,
    date              TEXT NOT NULL,
    session_id        TEXT
);

-- ============================================================================
-- TABLE: schema_version (migration tracking)
-- ============================================================================
CREATE TABLE IF NOT EXISTS schema_version (
    version   INTEGER PRIMARY KEY,
    applied   TEXT NOT NULL,
    checksum  TEXT
);
```

## 3. Rust Model Structs — Each Kotlin `data class` equivalent

```rust
// focusflow-db/src/models.rs
use serde::{Serialize, Deserialize};
use time::OffsetDateTime;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FocusSession {
    pub id: String,
    pub title: String,
    pub start_time: OffsetDateTime,
    pub end_time: Option<OffsetDateTime>,
    pub duration_seconds: i64,
    pub survived_nuclear_mode: bool,
    pub nuclear_mode_activated: bool,
    pub date: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TemptationLog {
    pub id: String,
    pub app_name: String,
    pub window_title: Option<String>,
    pub process_path: Option<String>,
    pub timestamp: OffsetDateTime,
    pub duration_seconds: Option<i64>,
    pub date: String,
    pub session_id: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BlockedApp {
    pub id: String,
    pub name: String,
    pub path: String,
    pub icon: Option<Vec<u8>>,
    pub is_keyword: bool,
    pub block_mode: BlockMode,
    pub enabled: bool,
    pub date_added: OffsetDateTime,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub enum BlockMode {
    #[serde(rename = "FILE")]
    FileBacked,
    #[serde(rename = "KEYWORD")]
    Keyword,
    #[serde(rename = "PATH")]
    PathBlocked,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BlockedKeyword {
    pub id: String,
    pub keyword: String,
    pub enabled: bool,
    pub date_added: OffsetDateTime,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct NuclearModeLogs {
    pub id: String,
    pub escaped_process: String,
    pub escape_path: Option<String>,
    pub timestamp: OffsetDateTime,
    pub date: String,
    pub session_id: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Preference {
    pub key: String,
    pub value: String,
}
```

## 4. DB Open / Migration System

```rust
// focusflow-db/src/lib.rs
use rusqlite::{Connection, params};
use std::sync::Mutex;
use directories::ProjectDirs;

pub struct Database {
    conn: Mutex<Connection>,
}

impl Database {
    pub fn open() -> Result<Self> {
        let proj_dirs = ProjectDirs::from("com", "focusflow", "FocusFlow")
            .expect("No home directory?");
        let data_dir = proj_dirs.data_dir();
        std::fs::create_dir_all(data_dir)?;

        let db_path = data_dir.join("focusflow.db");
        let conn = Connection::open(&db_path)?;
        conn.execute_batch("PRAGMA journal_mode = WAL; PRAGMA busy_timeout = 10000;")?;

        let db = Database { conn: Mutex::new(conn) };
        db.migrate()?;
        Ok(db)
    }

    fn migrate(&self) -> Result<()> {
        let conn = self.conn.lock().unwrap();

        // Read current version
        let current: i32 = conn.pragma_query_value(None, "user_version", |row| row.get(0))
            .unwrap_or(0);

        // Run each migration sequentially
        let migrations: Vec<fn(&Connection) -> Result<()>> = vec![
            migration_v1_create_tables,
            migration_v2_add_process_path,
        ];

        for (i, migration) in migrations.iter().enumerate() {
            let version = (i + 1) as i32;
            if current < version {
                migration(&conn)?;
                conn.pragma_update(None, "user_version", version)?;
            }
        }
        Ok(())
    }
}
```

## 5. Query Patterns (exact JVM parity)

```rust
impl Database {
    // Sessions
    pub fn insert_focus_session(&self, session: &FocusSession) -> Result<()> { ... }
    pub fn get_today_sessions(&self) -> Result<Vec<FocusSession>> { ... }
    pub fn get_weekly_sessions(&self) -> Result<u64> { ... }
    pub fn get_total_focus_hours(&self) -> Result<f64> { ... }
    pub fn get_average_session_seconds(&self) -> Result<f64> { ... }

    // Temptation Logs
    pub fn insert_temptation_log(&self, log: &TemptationLog) -> Result<()> { ... }
    pub fn get_today_temptations(&self) -> Result<u64> { ... }
    pub fn get_temptations_by_app(&self) -> Result<Vec<(String, u64)>> { ... }

    // Blocked Apps
    pub fn get_blocked_apps(&self) -> Result<Vec<BlockedApp>> { ... }
    pub fn add_blocked_app(&self, app: &BlockedApp) -> Result<()> { ... }
    pub fn remove_blocked_app(&self, id: &str) -> Result<()> { ... }

    // Nuclear Mode
    pub fn upsert_escape_count(&self, process: &str, count: u32) -> Result<()> { ... }
    pub fn get_nuclear_escape_attempts(&self) -> Result<Vec<(String, u32)>> { ... }

    // Preferences (key-value)
    pub fn get_pref(&self, key: &str) -> Result<Option<String>> { ... }
    pub fn set_pref(&self, key: &str, value: &str) -> Result<()> { ... }
}
```

## 6. Converting String-Based Dates to OffsetDateTime

JVM stores all dates in ISO 8601 strings (same as Rust `OffsetDateTime`). No conversion in formatters needed.

```rust
// We store as `time::OffsetDateTime` to .sqlite but use serde
use time::format_description::well_known::Rfc3339;
Ok(OffsetDateTime::parse(&stored_string, &Rfc3339)?)
```

## 7. Summary — No JVM Migration Code Needed

Since the Rust DB schema is 100% identical to the JVM schema, any existing JVM database will be directly load and used by the Rust binary with zero data conversion needed. The file path stays `~/.focusflow/focusflow.db`.

---

**Next Document:** `RUST_PORT_CICD.md`