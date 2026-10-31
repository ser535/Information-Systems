BEGIN;

CREATE OR REPLACE PROCEDURE register_lead(
    p_client_id          INTEGER,
    p_opponent_id        INTEGER,
    p_description        TEXT,
    p_amount             NUMERIC(14,2),
    p_created_by         INTEGER,
    p_agent_id           INTEGER,
    p_offer_amount       NUMERIC(14,2),
    p_commission         NUMERIC(14,2),
    INOUT p_lead_id      INTEGER
)
LANGUAGE plpgsql
AS $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM clients
        WHERE id = p_client_id
          AND merged_into_id IS NULL
    ) THEN
        RAISE EXCEPTION
            'Клиент % не найден или уже объединён с другим клиентом',
            p_client_id;
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM opponents
        WHERE id = p_opponent_id
    ) THEN
        RAISE EXCEPTION
            'Оппонент % не найден',
            p_opponent_id;
    END IF;

    INSERT INTO leads (
        client_id,
        opponent_id,
        description,
        amount,
        status,
        created_by,
        updated_by
    )
    VALUES (
        p_client_id,
        p_opponent_id,
        p_description,
        p_amount,
        'new',
        p_created_by,
        p_created_by
    )
    RETURNING id INTO p_lead_id;

    IF p_agent_id IS NOT NULL THEN
        IF p_offer_amount IS NULL AND p_amount IS NULL THEN
            RAISE EXCEPTION
                'Для предложения агента должна быть указана сумма';
        END IF;

        INSERT INTO agent_offers (
            lead_id,
            agent_id,
            amount,
            commission,
            created_by
        )
        VALUES (
            p_lead_id,
            p_agent_id,
            COALESCE(p_offer_amount, p_amount),
            COALESCE(p_commission, 0),
            p_created_by
        );
    END IF;
END;
$$;

CREATE OR REPLACE FUNCTION check_conflict_of_interest(
    p_lead_id     INTEGER,
    p_checked_by  INTEGER DEFAULT NULL
)
RETURNS TABLE (
    result VARCHAR(16),
    reason TEXT
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_opponent_id   INTEGER;
    v_archive_years INTEGER := 5;
    v_client_name   VARCHAR(512);
    v_depth         INTEGER;
    v_reason        TEXT;
BEGIN
    SELECT l.opponent_id
    INTO v_opponent_id
    FROM leads l
    WHERE l.id = p_lead_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Лид % не найден', p_lead_id;
    END IF;


    SELECT COALESCE(
        (br.definition ->> 'archive_years')::INTEGER,
        5
    )
    INTO v_archive_years
    FROM business_rules br
    WHERE br.rule_type = 'conflict_of_interest'
      AND br.is_active = TRUE
    ORDER BY br.id DESC
    LIMIT 1;

    IF NOT FOUND THEN
        v_archive_years := 5;
    END IF;


    WITH RECURSIVE related_opponents(id, depth) AS (
        -- Сам оппонент.
        SELECT v_opponent_id, 0

        UNION

        -- Его материнские/дочерние организации.
        SELECT
            CASE
                WHEN a.parent_id = ro.id THEN a.child_id
                ELSE a.parent_id
            END,
            ro.depth + 1
        FROM related_opponents ro
        JOIN affiliations a
          ON a.parent_id = ro.id
          OR a.child_id = ro.id
        WHERE ro.depth < 5
    )
    SELECT
        COALESCE(c.full_name, c.short_name),
        ro.depth
    INTO
        v_client_name,
        v_depth
    FROM related_opponents ro
    JOIN opponents o
      ON o.id = ro.id
    JOIN clients c
      ON c.inn IS NOT NULL
     AND o.inn IS NOT NULL
     AND c.inn = o.inn
    WHERE c.merged_into_id IS NULL
      AND EXISTS (
          SELECT 1
          FROM leads old_lead
          WHERE old_lead.client_id = c.id
            AND old_lead.id <> p_lead_id
            AND (
                old_lead.status IN ('new', 'checking', 'active')
                OR old_lead.updated_at >=
                    now() - make_interval(years => v_archive_years)
            )
      )
    ORDER BY ro.depth
    LIMIT 1;


    IF FOUND THEN
        IF v_depth = 0 THEN
            v_reason :=
                format(
                    'Оппонент является текущим или недавним клиентом: %s',
                    v_client_name
                );
        ELSE
            v_reason :=
                format(
                    'Аффилированная организация является текущим или недавним клиентом: %s',
                    v_client_name
                );
        END IF;

        INSERT INTO conflict_checks (
            lead_id,
            opponent_id,
            result,
            reason,
            checked_by
        )
        VALUES (
            p_lead_id,
            v_opponent_id,
            'blocked',
            v_reason,
            p_checked_by
        );

        RETURN QUERY
        SELECT
            'blocked'::VARCHAR(16),
            v_reason;

        RETURN;
    END IF;


    v_reason := 'Конфликтов интересов не обнаружено';

    INSERT INTO conflict_checks (
        lead_id,
        opponent_id,
        result,
        reason,
        checked_by
    )
    VALUES (
        p_lead_id,
        v_opponent_id,
        'ok',
        v_reason,
        p_checked_by
    );

    RETURN QUERY
    SELECT
        'ok'::VARCHAR(16),
        v_reason;
END;
$$;

CREATE OR REPLACE FUNCTION find_client_duplicates(
    p_client_id       INTEGER,
    p_min_similarity  NUMERIC DEFAULT 0.55
)
RETURNS TABLE (
    candidate_id    INTEGER,
    candidate_name  VARCHAR(512),
    match_type      VARCHAR(128),
    match_score     NUMERIC
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_phone VARCHAR(64);
    v_email VARCHAR(255);
    v_inn   VARCHAR(32);
    v_name  VARCHAR(512);
BEGIN
    SELECT
        c.phone,
        c.email,
        c.inn,
        COALESCE(c.full_name, c.short_name)
    INTO
        v_phone,
        v_email,
        v_inn,
        v_name
    FROM clients c
    WHERE c.id = p_client_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Клиент % не найден', p_client_id;
    END IF;


    RETURN QUERY
    SELECT
        c.id,

        COALESCE(
            c.full_name,
            c.short_name,
            '(без имени)'
        )::VARCHAR(512),

        concat_ws(
            ', ',
            CASE
                WHEN v_inn IS NOT NULL
                 AND c.inn = v_inn
                THEN 'ИНН'
            END,
            CASE
                WHEN v_phone IS NOT NULL
                 AND c.phone = v_phone
                THEN 'телефон'
            END,
            CASE
                WHEN v_email IS NOT NULL
                 AND lower(c.email) = lower(v_email)
                THEN 'e-mail'
            END,
            CASE
                WHEN v_name IS NOT NULL
                 AND similarity(
                        COALESCE(c.full_name, c.short_name, ''),
                        v_name
                     ) >= p_min_similarity
                THEN 'похожее имя'
            END
        )::VARCHAR(128),

        GREATEST(
            CASE
                WHEN v_inn IS NOT NULL AND c.inn = v_inn
                THEN 1.00
                ELSE 0
            END,

            CASE
                WHEN v_phone IS NOT NULL AND c.phone = v_phone
                THEN 0.95
                ELSE 0
            END,

            CASE
                WHEN v_email IS NOT NULL
                 AND lower(c.email) = lower(v_email)
                THEN 0.95
                ELSE 0
            END,

            CASE
                WHEN v_name IS NOT NULL
                THEN similarity(
                    COALESCE(c.full_name, c.short_name, ''),
                    v_name
                )
                ELSE 0
            END
        )::NUMERIC AS score

    FROM clients c

    WHERE c.id <> p_client_id
      AND c.merged_into_id IS NULL
      AND (
            (v_inn IS NOT NULL AND c.inn = v_inn)

         OR (v_phone IS NOT NULL AND c.phone = v_phone)

         OR (
             v_email IS NOT NULL
             AND lower(c.email) = lower(v_email)
         )

         OR (
             v_name IS NOT NULL
             AND similarity(
                 COALESCE(c.full_name, c.short_name, ''),
                 v_name
             ) >= p_min_similarity
         )
      )

    ORDER BY 4 DESC;
END;
$$;

CREATE OR REPLACE PROCEDURE merge_clients(
    p_target_id  INTEGER,
    p_source_id  INTEGER,
    p_updated_by INTEGER DEFAULT NULL
)
LANGUAGE plpgsql
AS $$
BEGIN
    IF p_target_id = p_source_id THEN
        RAISE EXCEPTION
            'Нельзя объединить клиента с самим собой';
    END IF;


    IF NOT EXISTS (
        SELECT 1
        FROM clients
        WHERE id = p_target_id
          AND merged_into_id IS NULL
    ) THEN
        RAISE EXCEPTION
            'Целевой клиент % не найден или уже объединён',
            p_target_id;
    END IF;


    IF NOT EXISTS (
        SELECT 1
        FROM clients
        WHERE id = p_source_id
          AND merged_into_id IS NULL
    ) THEN
        RAISE EXCEPTION
            'Исходный клиент % не найден или уже объединён',
            p_source_id;
    END IF;


    -- Все лиды дубликата теперь принадлежат основной записи.
    UPDATE leads
    SET
        client_id = p_target_id,
        updated_by = COALESCE(p_updated_by, updated_by)
    WHERE client_id = p_source_id;


    -- Если какие-либо записи раньше уже были объединены
    -- в source, перенаправляем их сразу на target.
    UPDATE clients
    SET
        merged_into_id = p_target_id,
        updated_by = COALESCE(p_updated_by, updated_by)
    WHERE merged_into_id = p_source_id;


    -- Сам source остаётся в БД для истории,
    -- но помечается как объединённый.
    UPDATE clients
    SET
        merged_into_id = p_target_id,
        updated_by = COALESCE(p_updated_by, updated_by)
    WHERE id = p_source_id;
END;
$$;

CREATE OR REPLACE FUNCTION compare_agent_offers(
    p_lead_id INTEGER
)
RETURNS TABLE (
    offer_id             INTEGER,
    agent_id             INTEGER,
    agent_name           VARCHAR(255),
    amount               NUMERIC,
    commission           NUMERIC,
    net_profit           NUMERIC,
    priority_valid       BOOLEAN,
    priority_expires_at  TIMESTAMPTZ,
    is_selected          BOOLEAN
)
LANGUAGE plpgsql
AS $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM leads
        WHERE id = p_lead_id
    ) THEN
        RAISE EXCEPTION 'Лид % не найден', p_lead_id;
    END IF;


    RETURN QUERY
    SELECT
        o.id,
        a.id,
        a.full_name,
        o.amount,
        o.commission,

        o.amount - o.commission
            AS net_profit,

        COALESCE(
            o.priority_expires_at > now(),
            FALSE
        ) AS priority_valid,

        o.priority_expires_at,
        o.is_selected

    FROM agent_offers o

    JOIN agents a
      ON a.id = o.agent_id

    WHERE o.lead_id = p_lead_id

    ORDER BY
        COALESCE(
            o.priority_expires_at > now(),
            FALSE
        ) DESC,

        (o.amount - o.commission) DESC;
END;
$$;

CREATE OR REPLACE PROCEDURE select_best_offer(
    p_lead_id  INTEGER,
    p_offer_id INTEGER
)
LANGUAGE plpgsql
AS $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM agent_offers
        WHERE id = p_offer_id
          AND lead_id = p_lead_id
    ) THEN
        RAISE EXCEPTION
            'Предложение % не относится к лиду %',
            p_offer_id,
            p_lead_id;
    END IF;


    UPDATE agent_offers
    SET is_selected = FALSE
    WHERE lead_id = p_lead_id;


    UPDATE agent_offers
    SET is_selected = TRUE
    WHERE id = p_offer_id;
END;
$$;

CREATE OR REPLACE PROCEDURE revoke_expired_priorities()
LANGUAGE plpgsql
AS $$
DECLARE
    v_count INTEGER;
BEGIN
    UPDATE agent_offers
    SET priority_expires_at = NULL
    WHERE priority_expires_at IS NOT NULL
      AND priority_expires_at <= now();

    GET DIAGNOSTICS v_count = ROW_COUNT;

    RAISE NOTICE
        'Снято просроченных приоритетов: %',
        v_count;
END;
$$;

COMMIT;