-- Cash wallet support (provider = 'cash', account kind = 'cash')
ALTER TABLE banking.connection
    DROP CONSTRAINT connection_provider_check,
    ADD CONSTRAINT connection_provider_check CHECK (provider IN ('pluggy', 'synthetic', 'file', 'cash'));

ALTER TABLE banking.account
    DROP CONSTRAINT account_kind_check,
    ADD CONSTRAINT account_kind_check CHECK (kind IN ('checking', 'savings', 'credit_card', 'cash'));

-- Payment method (RF-22) and atypical expense flag on transaction versions
ALTER TABLE banking.transaction_version
    ADD COLUMN payment_method text CHECK (
        payment_method IS NULL OR payment_method IN ('pix', 'debit', 'credit', 'cash', 'boleto', 'transfer', 'other')
    ),
    ADD COLUMN is_atypical boolean NOT NULL DEFAULT false;

-- Allow manual append-only adjustments for payment_method and is_atypical
ALTER TABLE banking.adjustment
    DROP CONSTRAINT adjustment_field_name_check,
    ADD CONSTRAINT adjustment_field_name_check CHECK (
        field_name IN ('category', 'essentiality', 'brand', 'kind', 'description', 'payment_method', 'is_atypical')
    );

-- Custom household tags (RF-23)
CREATE TABLE banking.tag (
    id           uuid PRIMARY KEY,
    household_id uuid NOT NULL,
    name         text NOT NULL,
    color        text NOT NULL DEFAULT '#A0521A',
    created_at   timestamptz NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX ux_tag_household_name
    ON banking.tag (household_id, lower(name));

CREATE INDEX ix_tag_household
    ON banking.tag (household_id);

CREATE TABLE banking.transaction_tag (
    transaction_id uuid NOT NULL REFERENCES banking.transaction(id) ON DELETE CASCADE,
    tag_id         uuid NOT NULL REFERENCES banking.tag(id) ON DELETE CASCADE,
    tagged_at      timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (transaction_id, tag_id)
);

CREATE INDEX ix_transaction_tag_tag
    ON banking.transaction_tag (tag_id);

-- Transaction splits (RN-24, ADR-013)
CREATE TABLE banking.transaction_split (
    id             uuid PRIMARY KEY,
    transaction_id uuid NOT NULL REFERENCES banking.transaction(id) ON DELETE CASCADE,
    part_index     int NOT NULL,
    description    text NOT NULL,
    amount_cents   bigint NOT NULL,
    category       text,
    essentiality   text CHECK (essentiality IS NULL OR essentiality IN ('essential', 'important', 'flexible')),
    created_at     timestamptz NOT NULL DEFAULT now(),
    UNIQUE (transaction_id, part_index)
);

CREATE INDEX ix_transaction_split_tx
    ON banking.transaction_split (transaction_id, part_index);

-- Extend transaction_effective view keeping every existing column name & order intact
CREATE OR REPLACE VIEW banking.transaction_effective AS
WITH latest_version AS (
    SELECT DISTINCT ON (v.transaction_id)
        v.id AS version_id,
        v.transaction_id,
        v.version_number,
        v.content_hash,
        v.occurred_on,
        v.purchase_on,
        v.description AS original_description,
        v.merchant_cnpj,
        v.amount_cents,
        v.currency,
        v.status,
        v.bill_id,
        v.installment_number,
        v.installment_total,
        v.is_removed,
        v.ingested_at,
        v.payment_method AS original_payment_method,
        v.is_atypical
    FROM banking.transaction_version v
    ORDER BY v.transaction_id, v.version_number DESC
)
SELECT
    t.id,
    t.household_id,
    t.account_id,
    a.connection_id,
    a.name AS account_name,
    a.kind AS account_kind,
    a.last_four_digits,
    c.institution_name,
    c.brand_color,
    lv.version_id,
    lv.version_number,
    lv.occurred_on,
    lv.purchase_on,
    lv.original_description,
    lv.merchant_cnpj,
    lv.amount_cents,
    lv.currency,
    lv.status,
    lv.bill_id,
    lv.installment_number,
    lv.installment_total,
    lv.ingested_at,
    COALESCE(adj_desc.new_value, lv.original_description) AS effective_description,
    COALESCE(adj_kind.new_value, cl.tx_kind, CASE WHEN lv.amount_cents < 0 THEN 'expense' ELSE 'income' END) AS effective_kind,
    COALESCE(adj_cat.new_value, cl.category) AS effective_category,
    COALESCE(adj_ess.new_value, cl.essentiality) AS effective_essentiality,
    COALESCE(adj_brand.new_value, cl.brand) AS effective_brand,
    cl.tx_kind AS classified_kind,
    cl.category AS classified_category,
    cl.essentiality AS classified_essentiality,
    cl.brand AS classified_brand,
    COALESCE(cl.deciding_layer, 'none') AS deciding_layer,
    cl.deciding_rule_id,
    cl.deciding_rule_name,
    COALESCE(cl.explanation, 'Nenhuma regra alcançou esta transação; enviada para revisão.') AS explanation,
    (
        (adj_cat.id IS NOT NULL AND adj_cat.new_value IS NOT NULL AND (adj_cat.undoes_id IS NULL OR adj_cat.new_value IS DISTINCT FROM cl.category))
        OR (adj_ess.id IS NOT NULL AND adj_ess.new_value IS NOT NULL AND (adj_ess.undoes_id IS NULL OR adj_ess.new_value IS DISTINCT FROM cl.essentiality))
        OR (adj_brand.id IS NOT NULL AND adj_brand.new_value IS NOT NULL AND (adj_brand.undoes_id IS NULL OR adj_brand.new_value IS DISTINCT FROM cl.brand))
        OR (adj_kind.id IS NOT NULL AND adj_kind.new_value IS NOT NULL AND (adj_kind.undoes_id IS NULL OR adj_kind.new_value IS DISTINCT FROM cl.tx_kind))
        OR (adj_desc.id IS NOT NULL AND adj_desc.new_value IS NOT NULL AND (adj_desc.undoes_id IS NULL OR adj_desc.new_value IS DISTINCT FROM lv.original_description))
        OR (adj_pm.id IS NOT NULL AND adj_pm.new_value IS NOT NULL AND (adj_pm.undoes_id IS NULL OR adj_pm.new_value IS DISTINCT FROM lv.original_payment_method))
        OR (adj_atyp.id IS NOT NULL AND adj_atyp.new_value IS NOT NULL AND (adj_atyp.undoes_id IS NULL OR adj_atyp.new_value IS DISTINCT FROM CASE WHEN lv.is_atypical THEN 'true' ELSE 'false' END))
    ) AS has_manual_adjustments,
    lv.original_payment_method,
    COALESCE(adj_pm.new_value, lv.original_payment_method) AS effective_payment_method,
    CASE
        WHEN adj_atyp.new_value IS NOT NULL THEN lower(adj_atyp.new_value) IN ('true', '1', 't', 'yes')
        ELSE lv.is_atypical
    END AS effective_is_atypical
FROM banking.transaction t
JOIN latest_version lv ON lv.transaction_id = t.id AND lv.is_removed = false
JOIN banking.account a ON a.id = t.account_id
JOIN banking.connection c ON c.id = a.connection_id
LEFT JOIN banking.classification cl ON cl.transaction_id = t.id
LEFT JOIN LATERAL (
    SELECT a1.id, a1.new_value, a1.undoes_id
    FROM banking.adjustment a1
    WHERE a1.transaction_id = t.id AND a1.field_name = 'category'
    ORDER BY a1.created_at DESC, a1.id DESC
    LIMIT 1
) adj_cat ON true
LEFT JOIN LATERAL (
    SELECT a2.id, a2.new_value, a2.undoes_id
    FROM banking.adjustment a2
    WHERE a2.transaction_id = t.id AND a2.field_name = 'essentiality'
    ORDER BY a2.created_at DESC, a2.id DESC
    LIMIT 1
) adj_ess ON true
LEFT JOIN LATERAL (
    SELECT a3.id, a3.new_value, a3.undoes_id
    FROM banking.adjustment a3
    WHERE a3.transaction_id = t.id AND a3.field_name = 'brand'
    ORDER BY a3.created_at DESC, a3.id DESC
    LIMIT 1
) adj_brand ON true
LEFT JOIN LATERAL (
    SELECT a4.id, a4.new_value, a4.undoes_id
    FROM banking.adjustment a4
    WHERE a4.transaction_id = t.id AND a4.field_name = 'kind'
    ORDER BY a4.created_at DESC, a4.id DESC
    LIMIT 1
) adj_kind ON true
LEFT JOIN LATERAL (
    SELECT a5.id, a5.new_value, a5.undoes_id
    FROM banking.adjustment a5
    WHERE a5.transaction_id = t.id AND a5.field_name = 'description'
    ORDER BY a5.created_at DESC, a5.id DESC
    LIMIT 1
) adj_desc ON true
LEFT JOIN LATERAL (
    SELECT a6.id, a6.new_value, a6.undoes_id
    FROM banking.adjustment a6
    WHERE a6.transaction_id = t.id AND a6.field_name = 'payment_method'
    ORDER BY a6.created_at DESC, a6.id DESC
    LIMIT 1
) adj_pm ON true
LEFT JOIN LATERAL (
    SELECT a7.id, a7.new_value, a7.undoes_id
    FROM banking.adjustment a7
    WHERE a7.transaction_id = t.id AND a7.field_name = 'is_atypical'
    ORDER BY a7.created_at DESC, a7.id DESC
    LIMIT 1
) adj_atyp ON true;
