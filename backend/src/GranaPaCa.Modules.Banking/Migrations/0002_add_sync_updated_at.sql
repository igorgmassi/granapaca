ALTER TABLE banking.connection
    ADD COLUMN updated_at timestamptz NOT NULL DEFAULT now();

UPDATE banking.connection
SET updated_at = GREATEST(
    created_at,
    COALESCE(last_synced_at, created_at),
    COALESCE(first_failure_at, created_at)
);

ALTER TABLE banking.account
    ADD COLUMN updated_at timestamptz NOT NULL DEFAULT now();

UPDATE banking.account a
SET updated_at = GREATEST(
    a.created_at,
    COALESCE(
        (SELECT MAX(bs.captured_at) FROM banking.balance_snapshot bs WHERE bs.account_id = a.id),
        a.created_at
    )
);

CREATE INDEX ix_connection_household_updated
    ON banking.connection (household_id, updated_at, id);

CREATE INDEX ix_account_household_updated
    ON banking.account (household_id, updated_at, id);
