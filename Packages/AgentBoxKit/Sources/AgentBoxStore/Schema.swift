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

    /// `v3_computers` (Fatia 3, 08 §3.2): computadores no modo leve, fila, perfis de browser, pedidos de ajuda e proxies.
    /// `v2_activity` (agent_run, secret) ainda não existe: `owner_run_id`, `help_request.run_id` e `proxy.secret_id` ficam
    /// sem FK, como `batch_id` (R1 D-06). Sem colunas de limite ou orçamento no proxy (P13).
    static let v3Computers = StoreMigration(id: "v3_computers") { db in
        try db.execute(sql: """
        CREATE TABLE proxy (
            id TEXT PRIMARY KEY NOT NULL,
            name TEXT NOT NULL UNIQUE,
            preset TEXT NOT NULL DEFAULT 'custom' CHECK (preset IN ('custom','zyte')),
            scheme TEXT NOT NULL CHECK (scheme IN ('http','https','socks5')),
            host TEXT NOT NULL,
            port INTEGER NOT NULL CHECK (port BETWEEN 1 AND 65535),
            username TEXT,
            secret_id TEXT,
            geo TEXT,
            api_mode INTEGER NOT NULL DEFAULT 0 CHECK (api_mode IN (0,1)),
            is_default INTEGER NOT NULL DEFAULT 0 CHECK (is_default IN (0,1)),
            created_at INTEGER NOT NULL,
            updated_at INTEGER NOT NULL
        ) STRICT;

        CREATE TABLE browser_profile (
            id TEXT PRIMARY KEY NOT NULL,
            name TEXT NOT NULL UNIQUE,
            volume TEXT NOT NULL,
            sites_json TEXT NOT NULL DEFAULT '[]' CHECK (json_valid(sites_json)),
            locked_by_computer_id TEXT REFERENCES computer(id) ON DELETE SET NULL,
            created_at INTEGER NOT NULL,
            last_used_at INTEGER
        ) STRICT;

        CREATE TABLE computer (
            id TEXT PRIMARY KEY NOT NULL,
            owner_run_id TEXT,
            session_id TEXT REFERENCES session(id) ON DELETE SET NULL,
            name TEXT NOT NULL,
            mode TEXT NOT NULL DEFAULT 'light' CHECK (mode IN ('light','isolated')),
            display TEXT NOT NULL CHECK (display IN ('http','headless','desktop')),
            persistent INTEGER NOT NULL DEFAULT 0 CHECK (persistent IN (0,1)),
            proxy_id TEXT REFERENCES proxy(id) ON DELETE SET NULL,
            browser_profile_id TEXT REFERENCES browser_profile(id) ON DELETE SET NULL,
            image_ref TEXT,
            image_digest TEXT,
            network_name TEXT,
            runtime_container_id TEXT,
            egress_container_id TEXT,
            work_container_id TEXT,
            api_port INTEGER,
            vnc_port INTEGER,
            egress_admin_port INTEGER,
            generation INTEGER NOT NULL DEFAULT 0,
            state TEXT NOT NULL DEFAULT 'queued' CHECK (state IN
                ('queued','provisioning','ready','in_use','stopped','failed','removing','removed','orphan')),
            created_at INTEGER NOT NULL,
            last_used_at INTEGER,
            expires_at INTEGER,
            removed_at INTEGER
        ) STRICT;
        CREATE INDEX computer_state ON computer(state);

        CREATE TABLE computer_queue (
            id TEXT PRIMARY KEY NOT NULL,
            computer_id TEXT NOT NULL UNIQUE REFERENCES computer(id) ON DELETE CASCADE,
            position INTEGER NOT NULL,
            requested_at INTEGER NOT NULL,
            reason TEXT NOT NULL DEFAULT 'memory'
        ) STRICT;
        CREATE INDEX computer_queue_position ON computer_queue(position);

        CREATE TABLE help_request (
            id TEXT PRIMARY KEY NOT NULL,
            computer_id TEXT NOT NULL REFERENCES computer(id) ON DELETE CASCADE,
            run_id TEXT,
            kind TEXT NOT NULL CHECK (kind IN ('captcha','login','mfa','download','choice','permission','other')),
            reason TEXT NOT NULL,
            state TEXT NOT NULL DEFAULT 'open' CHECK (state IN
                ('open','taken_over','resolved','declined','cancelled','expired')),
            created_at INTEGER NOT NULL,
            resolved_at INTEGER
        ) STRICT;
        CREATE INDEX help_request_computer ON help_request(computer_id, state);

        CREATE TABLE proxy_usage (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            proxy_id TEXT NOT NULL REFERENCES proxy(id) ON DELETE CASCADE,
            computer_id TEXT REFERENCES computer(id) ON DELETE SET NULL,
            period_start INTEGER NOT NULL,
            requests INTEGER NOT NULL DEFAULT 0,
            bytes INTEGER NOT NULL DEFAULT 0,
            cost_micros INTEGER,
            updated_at INTEGER NOT NULL
        ) STRICT;
        -- Único por (proxy, computador, período); linhas sem computador (agregado, ou computador removido) podem repetir: somar.
        CREATE UNIQUE INDEX proxy_usage_key ON proxy_usage(proxy_id, computer_id, period_start) WHERE computer_id IS NOT NULL;
        """)
    }

    static let all: [StoreMigration] = [v1Initial, v3Computers]

    static func migrator(_ migrations: [StoreMigration]) -> DatabaseMigrator {
        var m = DatabaseMigrator()
        for migration in migrations { m.registerMigration(migration.id, migrate: migration.run) }
        return m
    }
}
