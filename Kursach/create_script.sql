DROP DATABASE IF EXISTS lawfirm_db;
CREATE DATABASE lawfirm_db;
\c lawfirm_db

CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE EXTENSION IF NOT EXISTS pg_trgm;

CREATE TABLE roles (
  id SERIAL PRIMARY KEY,
  code VARCHAR(32) NOT NULL UNIQUE,
  name VARCHAR(128) NOT NULL,
  description TEXT
);

CREATE TABLE users (
  id SERIAL PRIMARY KEY,
  email VARCHAR(255) NOT NULL UNIQUE,
  password_hash BYTEA NOT NULL,
  full_name VARCHAR(255) NOT NULL,
  role_id INTEGER NOT NULL REFERENCES roles(id) ON DELETE RESTRICT,
  is_active BOOLEAN NOT NULL DEFAULT TRUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_users_email ON users (email);
CREATE INDEX idx_users_role ON users (role_id);

CREATE TABLE clients (
  id SERIAL PRIMARY KEY,
  client_type VARCHAR(16) NOT NULL CHECK (client_type IN ('individual', 'legal')),
  full_name VARCHAR(512),
  short_name VARCHAR(255),
  inn VARCHAR(32),
  ogrn VARCHAR(32),
  phone VARCHAR(64),
  email VARCHAR(255),
  address TEXT,
  birth_date DATE,
  merged_into_id INTEGER REFERENCES clients(id) ON DELETE SET NULL,
  created_by INTEGER REFERENCES users(id) ON DELETE SET NULL,
  updated_by INTEGER REFERENCES users(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_clients_phone ON clients (phone) WHERE phone IS NOT NULL;
CREATE INDEX idx_clients_email ON clients (email) WHERE email IS NOT NULL;
CREATE INDEX idx_clients_inn ON clients (inn) WHERE inn IS NOT NULL;
CREATE INDEX idx_clients_full_name ON clients (full_name);
CREATE INDEX idx_clients_merged ON clients (merged_into_id) WHERE merged_into_id IS NOT NULL;
CREATE INDEX idx_clients_created_by ON clients (created_by);
CREATE INDEX idx_clients_updated_by ON clients (updated_by);

CREATE TABLE agents (
  id SERIAL PRIMARY KEY,
  full_name VARCHAR(255) NOT NULL,
  phone VARCHAR(64),
  email VARCHAR(255),
  commission_default NUMERIC(6,2) NOT NULL DEFAULT 0,
  is_active BOOLEAN NOT NULL DEFAULT TRUE,
  created_by INTEGER REFERENCES users(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_agents_phone ON agents (phone) WHERE phone IS NOT NULL;
CREATE INDEX idx_agents_email ON agents (email) WHERE email IS NOT NULL;
CREATE INDEX idx_agents_created ON agents (created_by);

CREATE TABLE opponents (
  id SERIAL PRIMARY KEY,
  name VARCHAR(512) NOT NULL,
  normalized_name VARCHAR(512),
  inn VARCHAR(32),
  ogrn VARCHAR(32),
  is_individual BOOLEAN NOT NULL DEFAULT FALSE,
  created_by INTEGER REFERENCES users(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_opponents_inn ON opponents (inn) WHERE inn IS NOT NULL;
CREATE INDEX idx_opponents_norm ON opponents (normalized_name);
CREATE INDEX idx_opponents_created ON opponents (created_by);

CREATE TABLE affiliations (
  id SERIAL PRIMARY KEY,
  parent_id INTEGER NOT NULL REFERENCES opponents(id) ON DELETE CASCADE,
  child_id INTEGER NOT NULL REFERENCES opponents(id) ON DELETE CASCADE,
  relation_type VARCHAR(64) NOT NULL DEFAULT 'subsidiary',
  created_by INTEGER REFERENCES users(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT uq_affiliation UNIQUE (parent_id, child_id),
  CONSTRAINT chk_no_self_affil CHECK (parent_id <> child_id)
);
CREATE INDEX idx_affiliations_parent ON affiliations (parent_id);
CREATE INDEX idx_affiliations_child ON affiliations (child_id);
CREATE INDEX idx_affiliations_created ON affiliations (created_by);

CREATE TABLE leads (
  id SERIAL PRIMARY KEY,
  client_id INTEGER NOT NULL REFERENCES clients(id) ON DELETE RESTRICT,
  opponent_id INTEGER NOT NULL REFERENCES opponents(id) ON DELETE RESTRICT,
  description TEXT,
  amount NUMERIC(14,2),
  status VARCHAR(32) NOT NULL DEFAULT 'new' CHECK (status IN ('new', 'checking', 'active', 'closed', 'cancelled')),
  created_by INTEGER REFERENCES users(id) ON DELETE SET NULL,
  updated_by INTEGER REFERENCES users(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_leads_client ON leads (client_id);
CREATE INDEX idx_leads_opponent ON leads (opponent_id);
CREATE INDEX idx_leads_status ON leads (status);
CREATE INDEX idx_leads_created ON leads (created_at DESC);
CREATE INDEX idx_leads_created_by ON leads (created_by);
CREATE INDEX idx_leads_updated_by ON leads (updated_by);

CREATE TABLE agent_offers (
  id SERIAL PRIMARY KEY,
  lead_id INTEGER NOT NULL REFERENCES leads(id) ON DELETE CASCADE,
  agent_id INTEGER NOT NULL REFERENCES agents(id) ON DELETE RESTRICT,
  amount NUMERIC(14,2) NOT NULL,
  commission NUMERIC(14,2) NOT NULL DEFAULT 0,
  priority_expires_at TIMESTAMPTZ,
  is_selected BOOLEAN NOT NULL DEFAULT FALSE,
  created_by INTEGER REFERENCES users(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT uq_offer_per_lead_agent UNIQUE (lead_id, agent_id)
);
CREATE INDEX idx_offers_lead ON agent_offers (lead_id);
CREATE INDEX idx_offers_agent ON agent_offers (agent_id);
CREATE INDEX idx_offers_expires ON agent_offers (priority_expires_at) WHERE priority_expires_at IS NOT NULL;
CREATE INDEX idx_offers_selected ON agent_offers (lead_id) WHERE is_selected = TRUE;
CREATE INDEX idx_offers_created ON agent_offers (created_by);

CREATE TABLE conflict_checks (
  id SERIAL PRIMARY KEY,
  lead_id INTEGER NOT NULL REFERENCES leads(id) ON DELETE CASCADE,
  opponent_id INTEGER NOT NULL REFERENCES opponents(id) ON DELETE RESTRICT,
  result VARCHAR(16) NOT NULL CHECK (result IN ('ok', 'warning', 'blocked')),
  reason TEXT,
  checked_by INTEGER REFERENCES users(id) ON DELETE SET NULL,
  checked_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_conflicts_lead ON conflict_checks (lead_id);
CREATE INDEX idx_conflicts_opponent ON conflict_checks (opponent_id);
CREATE INDEX idx_conflicts_at ON conflict_checks (checked_at DESC);
CREATE INDEX idx_conflicts_checked ON conflict_checks (checked_by);

CREATE TABLE business_rules (
  id SERIAL PRIMARY KEY,
  rule_type VARCHAR(64) NOT NULL,
  name VARCHAR(255) NOT NULL,
  definition JSONB NOT NULL,
  is_active BOOLEAN NOT NULL DEFAULT TRUE,
  created_by INTEGER REFERENCES users(id) ON DELETE SET NULL,
  updated_by INTEGER REFERENCES users(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_rules_type ON business_rules (rule_type);
CREATE INDEX idx_rules_active ON business_rules (is_active) WHERE is_active = TRUE;
CREATE INDEX idx_rules_def ON business_rules USING GIN (definition);
CREATE INDEX idx_rules_created ON business_rules (created_by);
CREATE INDEX idx_rules_updated ON business_rules (updated_by);

CREATE TABLE llm_settings (
  id SERIAL PRIMARY KEY,
  provider VARCHAR(64) NOT NULL,
  base_url VARCHAR(512) NOT NULL,
  model VARCHAR(128) NOT NULL,
  api_token_encrypted BYTEA NOT NULL,
  is_active BOOLEAN NOT NULL DEFAULT FALSE,
  updated_by INTEGER REFERENCES users(id) ON DELETE SET NULL,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_llm_updated ON llm_settings (updated_by);

CREATE TABLE license_activations (
  id SERIAL PRIMARY KEY,
  installation_id UUID NOT NULL UNIQUE,
  license_key_hash BYTEA NOT NULL,
  activation_secret BYTEA NOT NULL,
  token BYTEA NOT NULL,
  token_expires_at TIMESTAMPTZ NOT NULL,
  activated_by_user_id INTEGER REFERENCES users(id) ON DELETE SET NULL,
  activated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_license_expires ON license_activations (token_expires_at);
CREATE INDEX idx_license_user ON license_activations (activated_by_user_id);