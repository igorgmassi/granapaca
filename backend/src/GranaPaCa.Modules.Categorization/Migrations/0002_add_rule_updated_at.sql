ALTER TABLE categorization.rule
    ADD COLUMN updated_at timestamptz NOT NULL DEFAULT now();

UPDATE categorization.rule
SET updated_at = created_at;

CREATE INDEX ix_rule_household_updated
    ON categorization.rule (household_id, updated_at, id);
