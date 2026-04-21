CREATE TABLE IF NOT EXISTS users (
    id SERIAL PRIMARY KEY,
    name TEXT,
    email TEXT,
    role TEXT,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS users_audit (
    id SERIAL PRIMARY KEY,
    user_id INTEGER,
    changed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    changed_by TEXT,
    field_changed TEXT,
    old_value TEXT,
    new_value TEXT
);

CREATE OR REPLACE FUNCTION log_user_changes()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;

    IF OLD.name IS DISTINCT FROM NEW.name THEN
        INSERT INTO users_audit (user_id, changed_by, field_changed, old_value, new_value)
        VALUES (NEW.id, CURRENT_USER, 'name', OLD.name, NEW.name);
    END IF;

    IF OLD.email IS DISTINCT FROM NEW.email THEN
        INSERT INTO users_audit (user_id, changed_by, field_changed, old_value, new_value)
        VALUES (NEW.id, CURRENT_USER, 'email', OLD.email, NEW.email);
    END IF;

    IF OLD.role IS DISTINCT FROM NEW.role THEN
        INSERT INTO users_audit (user_id, changed_by, field_changed, old_value, new_value)
        VALUES (NEW.id, CURRENT_USER, 'role', OLD.role, NEW.role);
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trigger_log_user_changes ON users;
CREATE TRIGGER trigger_log_user_changes
BEFORE UPDATE ON users
FOR EACH ROW
EXECUTE FUNCTION log_user_changes();

CREATE EXTENSION IF NOT EXISTS pg_cron;

CREATE OR REPLACE FUNCTION export_yesterday_audit()
RETURNS TEXT AS $$
DECLARE
    yesterday_date DATE;
    filename TEXT;
    export_path TEXT;
BEGIN
    yesterday_date := CURRENT_DATE - 1;
    filename := 'users_audit_export_' || to_char(yesterday_date, 'YYYY-MM-DD') || '.csv';
    export_path := '/tmp/' || filename;

    EXECUTE format('
        COPY (
            SELECT
                ua.id,
                ua.user_id,
                u.name,
                u.email,
                u.role,
                ua.changed_at,
                ua.changed_by,
                ua.field_changed,
                ua.old_value,
                ua.new_value
            FROM users_audit ua
            LEFT JOIN users u ON ua.user_id = u.id
            WHERE DATE(ua.changed_at) = %L
            ORDER BY ua.changed_at DESC
        ) TO %L WITH (FORMAT CSV, HEADER true, DELIMITER '','', ENCODING ''UTF8'')
    ', yesterday_date, export_path);

    RETURN 'Экспорт выполнен: ' || export_path || ' за ' || yesterday_date;
EXCEPTION
    WHEN OTHERS THEN
        RETURN 'Ошибка экспорта: ' || SQLERRM;
END;
$$ LANGUAGE plpgsql;

SELECT cron.unschedule('export-audit-job');
SELECT cron.schedule('export-audit-job', '0 3 * * *', 'SELECT export_yesterday_audit();');