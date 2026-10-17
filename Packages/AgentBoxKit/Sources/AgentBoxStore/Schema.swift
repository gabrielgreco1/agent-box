import GRDB

/// Migração nomeada. Migração publicada nunca é editada (08 AR-320).
struct StoreMigration: Sendable {
    let id: String
    let run: @Sendable (Database) throws -> Void
}

enum StoreMigrations {
    /// `v1_initial`: só as tabelas da Fatia 1 mais `setting` e `ui_state` (08 AR-311).
    /// `agent_run` e demais tabelas entram em `v2_activity` e seguintes.
    static let v1Initial = StoreMigration(id: "v1_initial") { db in
        try db.execute(sql: """
        CREATE TABLE project (
            id TEXT PRIMARY KEY NOT NULL,
            name TEXT NOT NULL,
            kind TEXT NOT NULL CHECK (kind IN ('git','folder')),
            root_path TEXT NOT NULL UNIQUE,
            git_remote_url TEXT,
            default_branch TEXT,
            worktree_root TEXT,
            branch_prefix TEXT,
            default_profile_id TEXT REFERENCES launch_profile(id) ON DELETE SET NULL,
            color TEXT,
            source TEXT NOT NULL DEFAULT 'manual' CHECK (source IN ('manual','orca_import')),
            import_source_id TEXT,
            sort_index INTEGER NOT NULL DEFAULT 0,
            created_at INTEGER NOT NULL,
            archived_at INTEGER
        ) STRICT;

        CREATE TABLE launch_profile (
            id TEXT PRIMARY KEY NOT NULL,
            name TEXT NOT NULL,
            provider TEXT NOT NULL CHECK (provider IN ('claude','codex','opencode','shell','custom')),
            model TEXT,
            effort TEXT,
            permission_mode TEXT,
            add_dirs_json TEXT NOT NULL DEFAULT '[]' CHECK (json_valid(add_dirs_json)),
            extra_args_json TEXT NOT NULL DEFAULT '[]' CHECK (json_valid(extra_args_json)),
            env_json TEXT NOT NULL DEFAULT '{}' CHECK (json_valid(env_json)),
            scope TEXT NOT NULL DEFAULT 'global' CHECK (scope IN ('global','project')),
            project_id TEXT REFERENCES project(id) ON DELETE CASCADE,
            is_default INTEGER NOT NULL DEFAULT 0 CHECK (is_default IN (0,1)),
            source TEXT NOT NULL DEFAULT 'manual' CHECK (source IN ('manual','orca_import')),
            created_at INTEGER NOT NULL,
            updated_at INTEGER NOT NULL
        ) STRICT;

        CREATE TABLE worktree (
            id TEXT PRIMARY KEY NOT NULL,
            project_id TEXT NOT NULL REFERENCES project(id) ON DELETE CASCADE,
            path TEXT NOT NULL UNIQUE,
            branch TEXT NOT NULL,
            base_ref TEXT,
            is_main INTEGER NOT NULL DEFAULT 0 CHECK (is_main IN (0,1)),
            created_by_app INTEGER NOT NULL DEFAULT 0 CHECK (created_by_app IN (0,1)),
            source TEXT NOT NULL DEFAULT 'manual' CHECK (source IN ('manual','orca_import')),
            created_at INTEGER NOT NULL,
            last_seen_at INTEGER,
            archived_at INTEGER
        ) STRICT;
        CREATE INDEX worktree_project ON worktree(project_id);

        CREATE TABLE session (
            id TEXT PRIMARY KEY NOT NULL,
            kind TEXT NOT NULL CHECK (kind IN ('worktree','checkout','folder','clean')),
            project_id TEXT REFERENCES project(id) ON DELETE RESTRICT,
            worktree_id TEXT REFERENCES worktree(id) ON DELETE RESTRICT,
            folder_path TEXT NOT NULL,
            managed_folder INTEGER NOT NULL DEFAULT 0 CHECK (managed_folder IN (0,1)),
            title TEXT NOT NULL,
            status_note TEXT,
            status_note_author TEXT,
            status_note_at INTEGER,
            unread INTEGER NOT NULL DEFAULT 0 CHECK (unread IN (0,1)),
            last_viewed_at INTEGER,
            lifecycle TEXT NOT NULL DEFAULT 'active' CHECK (lifecycle IN ('active','archived')),
            sort_index INTEGER NOT NULL DEFAULT 0,
            pinned INTEGER NOT NULL DEFAULT 0 CHECK (pinned IN (0,1)),
            created_at INTEGER NOT NULL,
            last_active_at INTEGER,
            archived_at INTEGER,
            CHECK (((kind IN ('worktree','checkout')) = (worktree_id IS NOT NULL))
                   AND ((kind = 'clean') = (project_id IS NULL)))
        ) STRICT;
        CREATE INDEX session_project ON session(project_id, archived_at);

        CREATE TABLE tab (
            id TEXT PRIMARY KEY NOT NULL,
            session_id TEXT NOT NULL REFERENCES session(id) ON DELETE CASCADE,
            title TEXT NOT NULL,
            title_locked INTEGER NOT NULL DEFAULT 0 CHECK (title_locked IN (0,1)),
            sort_index INTEGER NOT NULL DEFAULT 0,
            layout_json TEXT NOT NULL CHECK (json_valid(layout_json)),
            focused_terminal_id TEXT,
            created_at INTEGER NOT NULL,
            closed_at INTEGER
        ) STRICT;
        CREATE INDEX tab_session ON tab(session_id);

        CREATE TABLE terminal (
            id TEXT PRIMARY KEY NOT NULL,
            tab_id TEXT NOT NULL REFERENCES tab(id) ON DELETE CASCADE,
            provider TEXT NOT NULL CHECK (provider IN ('claude','codex','opencode','shell','custom')),
            profile_id TEXT REFERENCES launch_profile(id) ON DELETE SET NULL,
            title TEXT NOT NULL,
            title_source TEXT NOT NULL DEFAULT 'auto' CHECK (title_source IN ('user','osc','auto')),
            cwd TEXT NOT NULL,
            add_dirs_json TEXT NOT NULL DEFAULT '[]' CHECK (json_valid(add_dirs_json)),
            launch_spec_json TEXT NOT NULL CHECK (json_valid(launch_spec_json)),
            resolved_argv_json TEXT CHECK (resolved_argv_json IS NULL OR json_valid(resolved_argv_json)),
            env_keys_json TEXT NOT NULL DEFAULT '[]' CHECK (json_valid(env_keys_json)),
            cold_log INTEGER NOT NULL DEFAULT 1 CHECK (cold_log IN (0,1)),
            pty_session_id TEXT,
            daemon_major INTEGER,
            current_run_id TEXT,
            native_conversation_id TEXT,
            state TEXT NOT NULL DEFAULT 'not_started' CHECK (state IN
                ('not_started','launching','running','exited','killed','failed_to_start','interrupted','container_stopped')),
            exit_code INTEGER,
            exit_signal INTEGER,
            last_message TEXT CHECK (last_message IS NULL OR length(last_message) <= 500),
            font_size REAL,
            created_at INTEGER NOT NULL,
            started_at INTEGER,
            ended_at INTEGER,
            deleted_at INTEGER
        ) STRICT;
        CREATE INDEX terminal_tab ON terminal(tab_id);
        CREATE INDEX terminal_pty ON terminal(pty_session_id);

        CREATE TABLE setting (
            key TEXT PRIMARY KEY NOT NULL,
            value_json TEXT NOT NULL CHECK (json_valid(value_json)),
            updated_at INTEGER NOT NULL
        ) STRICT;

        CREATE TABLE ui_state (
            key TEXT PRIMARY KEY NOT NULL,
            value_json TEXT NOT NULL CHECK (json_valid(value_json)),
            updated_at INTEGER NOT NULL
        ) STRICT;
        """)
    }

    static let all: [StoreMigration] = [v1Initial]

    static func migrator(_ migrations: [StoreMigration]) -> DatabaseMigrator {
        var m = DatabaseMigrator()
        for migration in migrations { m.registerMigration(migration.id, migrate: migration.run) }
        return m
    }
}
