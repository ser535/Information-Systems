BEGIN;

CREATE OR REPLACE FUNCTION fn_set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at := now();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_leads_updated
    BEFORE UPDATE ON leads
    FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();

CREATE TRIGGER trg_clients_updated
    BEFORE UPDATE ON clients
    FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();

CREATE TRIGGER trg_rules_updated
    BEFORE UPDATE ON business_rules
    FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();

CREATE OR REPLACE FUNCTION fn_set_priority_expires()
RETURNS TRIGGER AS $$
DECLARE
    v_days INT;
BEGIN
    SELECT COALESCE(
        (definition->>'days')::INT,
        90
    )
    INTO v_days
    FROM business_rules
    WHERE rule_type = 'agent_priority_duration_days'
      AND is_active = TRUE
    LIMIT 1;

    NEW.priority_expires_at := now() + (v_days || ' days')::INTERVAL;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_set_priority_expires
    BEFORE INSERT ON agent_offers
    FOR EACH ROW
    WHEN (NEW.priority_expires_at IS NULL)
    EXECUTE FUNCTION fn_set_priority_expires();


CREATE OR REPLACE FUNCTION fn_prevent_client_delete()
RETURNS TRIGGER AS $$
DECLARE
    v_cnt INT;
BEGIN
    SELECT COUNT(*) INTO v_cnt
    FROM leads
    WHERE client_id = OLD.id
      AND status IN ('new', 'checking', 'active');

    IF v_cnt > 0 THEN
        RAISE EXCEPTION
            'Нельзя удалить клиента: есть % активных лидов',
            v_cnt
            USING ERRCODE = '23503';
    END IF;
    RETURN OLD;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_prevent_client_delete
    BEFORE DELETE ON clients
    FOR EACH ROW EXECUTE FUNCTION fn_prevent_client_delete();


COMMIT;