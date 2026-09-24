-- Synthetic SME lender — sample schema (PostgreSQL 14+)
--
-- A Singapore-based SME lender / payments company. Everything here lives on the
-- customer's own node: Agent-Fabric provisions the database and the agents that
-- query it; no outside party sees these rows. Only derived, bucketed facts leave.
--
-- Design rules that matter for finance:
--   * bitemporal where the business needs "as of": kyb_status, counterparty_link
--   * append-only ledgers: transactions, agent_log
--   * documents are metadata + hash + local path; contents stay on disk
--   * every external fact carries fe_id (external risk-feed entity id) as the join key

CREATE SCHEMA IF NOT EXISTS fintech;
SET search_path TO fintech;

-- ---------------------------------------------------------------- reference
CREATE TABLE currency (
  code        char(3) PRIMARY KEY,
  name        text NOT NULL
);

CREATE TABLE fx_rate (                       -- daily close, quote per 1 USD
  day         date NOT NULL,
  code        char(3) NOT NULL REFERENCES currency,
  per_usd     numeric(18,6) NOT NULL,
  PRIMARY KEY (day, code)
);

-- ---------------------------------------------------------------- customers (SMEs)
CREATE TABLE customer (
  customer_id   text PRIMARY KEY,           -- C-000123
  legal_name    text NOT NULL,
  country       char(2) NOT NULL,
  registration_no text,                     -- UEN / 사업자등록번호 / MST ...
  fe_id         text,                       -- external risk-feed entity id (join key), may be null until resolved
  industry      text NOT NULL,
  onboarded_at  date NOT NULL
);

-- KYB status is bitemporal: what was true (valid_*) and when we knew it (known_at).
CREATE TABLE kyb_status (
  customer_id   text NOT NULL REFERENCES customer,
  status        text NOT NULL CHECK (status IN ('pending','verified','review','rejected','expired')),
  reason        text,
  valid_from    date NOT NULL,
  valid_to      date,                       -- null = current
  known_at      timestamptz NOT NULL DEFAULT now(),
  evidence_doc  text                        -- document.doc_id
);
CREATE INDEX ON kyb_status (customer_id, valid_from);

-- Counterparties a customer pays / is paid by (their suppliers and buyers).
CREATE TABLE counterparty (
  cp_id         text PRIMARY KEY,           -- CP-0001
  name          text NOT NULL,
  country       char(2) NOT NULL,
  fe_id         text                        -- resolved against the external risk feed; null = unresolved
);

CREATE TABLE counterparty_link (            -- customer <-> counterparty relation, with validity
  customer_id   text NOT NULL REFERENCES customer,
  cp_id         text NOT NULL REFERENCES counterparty,
  relation      text NOT NULL CHECK (relation IN ('supplier','buyer')),
  valid_from    date NOT NULL,
  valid_to      date,
  PRIMARY KEY (customer_id, cp_id, relation, valid_from)
);

-- ---------------------------------------------------------------- money
CREATE TABLE account (
  account_id    text PRIMARY KEY,
  customer_id   text NOT NULL REFERENCES customer,
  currency      char(3) NOT NULL REFERENCES currency,
  opened_at     date NOT NULL
);

CREATE TABLE transaction (                  -- append-only ledger
  txn_id        bigserial PRIMARY KEY,
  account_id    text NOT NULL REFERENCES account,
  booked_at     timestamptz NOT NULL,
  amount        numeric(18,2) NOT NULL,     -- signed; negative = outflow
  currency      char(3) NOT NULL REFERENCES currency,
  cp_id         text REFERENCES counterparty,
  kind          text NOT NULL CHECK (kind IN ('payment','collection','fee','fx','loan_disbursement','loan_repayment')),
  memo          text
);
CREATE INDEX ON transaction (account_id, booked_at);
CREATE INDEX ON transaction (cp_id, booked_at);

CREATE TABLE loan (
  loan_id       text PRIMARY KEY,
  customer_id   text NOT NULL REFERENCES customer,
  principal     numeric(18,2) NOT NULL,
  currency      char(3) NOT NULL REFERENCES currency,
  rate_pct      numeric(6,3) NOT NULL,
  disbursed_at  date NOT NULL,
  maturity_at   date NOT NULL,
  status        text NOT NULL CHECK (status IN ('active','repaid','overdue','written_off'))
);

CREATE TABLE loan_schedule (
  loan_id       text NOT NULL REFERENCES loan,
  due_at        date NOT NULL,
  amount_due    numeric(18,2) NOT NULL,
  amount_paid   numeric(18,2) NOT NULL DEFAULT 0,
  paid_at       date,
  PRIMARY KEY (loan_id, due_at)
);

-- ---------------------------------------------------------------- documents (metadata only)
CREATE TABLE document (
  doc_id        text PRIMARY KEY,
  customer_id   text REFERENCES customer,
  kind          text NOT NULL,              -- registry_extract | bank_statement | invoice | contract | id
  sha256        char(64) NOT NULL,
  local_path    text NOT NULL,              -- on the customer node; never leaves
  pages         int,
  received_at   timestamptz NOT NULL,
  extracted     jsonb                       -- fields the local agent pulled out (with page/bbox provenance)
);

-- ---------------------------------------------------------------- external intelligence (from an external risk feed, derived facts only)
CREATE TABLE fe_event (
  event_id      text PRIMARY KEY,
  fe_id         text NOT NULL,
  type          text NOT NULL,              -- officer_change | insolvency | litigation | permit_revoked | ...
  severity      text NOT NULL,
  event_time    timestamptz,
  published_at  timestamptz,
  known_time    timestamptz NOT NULL,       -- when the feed first observed it
  confidence    numeric(4,3) NOT NULL,
  source_ref    text NOT NULL               -- source id + content hash, not the content
);

-- ---------------------------------------------------------------- agents (audit)
CREATE TABLE agent_log (                    -- append-only; every NL request and what it became
  log_id        bigserial PRIMARY KEY,
  at            timestamptz NOT NULL DEFAULT now(),
  actor         text NOT NULL,              -- user or agent name
  nl_input      text NOT NULL,
  intent        jsonb NOT NULL,             -- {domain, goal, slots, confidence, as_of}
  executed      text,                       -- CLI command or SQL actually run
  risk_tier     smallint NOT NULL,          -- 1 read .. 4 forbidden
  approved_by   text,
  rows_out      int,
  bytes_out     int,                        -- what left the node (0 for local-only answers)
  status        text NOT NULL CHECK (status IN ('ok','denied','needs_approval','error'))
);

-- ---------------------------------------------------------------- alerts (what the analyst sees)
CREATE TABLE alert (
  alert_id      bigserial PRIMARY KEY,
  created_at    timestamptz NOT NULL DEFAULT now(),
  event_id      text REFERENCES fe_event,
  customer_id   text REFERENCES customer,
  cp_id         text REFERENCES counterparty,
  path          text NOT NULL,              -- "event → counterparty → customer exposure"
  exposure_bucket text NOT NULL,            -- '<10k' | '10k-100k' | '100k-1M' | '>1M'  (bucketed, never raw)
  attention     text NOT NULL CHECK (attention IN ('log','notify','act')),
  acknowledged_by text,
  acknowledged_at timestamptz
);
