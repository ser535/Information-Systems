BEGIN;

-- ============================================================
-- Очистка тестовых данных
-- ============================================================

TRUNCATE TABLE
    conflict_checks,
    agent_offers,
    leads,
    affiliations,
    license_activations,
    llm_settings,
    business_rules,
    opponents,
    agents,
    clients,
    users,
    roles
RESTART IDENTITY CASCADE;


-- ============================================================
-- Роли
-- ============================================================

INSERT INTO roles (code, name, description) VALUES
(
    'ADMIN',
    'Администратор',
    'Управление пользователями, правилами, LLM и лицензией'
),
(
    'MANAGER',
    'Менеджер по продажам',
    'Работа с клиентами, лидами, агентами и конфликтами'
);


-- ============================================================
-- Пользователи
--
-- BYTEA ниже -- тестовые заглушки.
-- Реальное хеширование пароля выполняется приложением.
-- ============================================================

INSERT INTO users (
    email,
    password_hash,
    full_name,
    role_id
)
VALUES
(
    'admin@lawfirm.test',
    decode('01020304', 'hex'),
    'Кобик Никита',
    (SELECT id FROM roles WHERE code = 'ADMIN')
),
(
    'manager1@lawfirm.test',
    decode('05060708', 'hex'),
    'Иван Гладышев',
    (SELECT id FROM roles WHERE code = 'MANAGER')
),
(
    'manager2@lawfirm.test',
    decode('090a0b0c', 'hex'),
    'Сергей Хлопцов',
    (SELECT id FROM roles WHERE code = 'MANAGER')
);


-- ============================================================
-- Бизнес-правила
-- ============================================================

INSERT INTO business_rules (
    rule_type,
    name,
    definition,
    is_active,
    created_by,
    updated_by
)
VALUES
(
    'agent_priority_duration_days',
    'Срок приоритета агента',
    '{"days": 90}'::jsonb,
    TRUE,
    (SELECT id FROM users WHERE email = 'admin@lawfirm.test'),
    (SELECT id FROM users WHERE email = 'admin@lawfirm.test')
),
(
    'conflict_of_interest',
    'Проверка текущих и недавних клиентов',
    '{"archive_years": 5}'::jsonb,
    TRUE,
    (SELECT id FROM users WHERE email = 'admin@lawfirm.test'),
    (SELECT id FROM users WHERE email = 'admin@lawfirm.test')
),
(
    'commission_max_percent',
    'Максимальная комиссия агента',
    '{"max_percent": 50}'::jsonb,
    TRUE,
    (SELECT id FROM users WHERE email = 'admin@lawfirm.test'),
    (SELECT id FROM users WHERE email = 'admin@lawfirm.test')
);


-- ============================================================
-- Агенты
-- ============================================================

INSERT INTO agents (
    full_name,
    phone,
    email,
    commission_default,
    created_by
)
VALUES
(
    'Агентик мой любимый.',
    '+79001168333',
    'lalala@agent.test',
    10.00,
    (SELECT id FROM users WHERE email = 'manager1@lawfirm.test')
),
(
    'ООО "ЮрПосредник"',
    '+79004445566',
    'info@jurposred.test',
    15.00,
    (SELECT id FROM users WHERE email = 'manager1@lawfirm.test')
),
(
    'ИП "Иванова М.И."',
    '+79007778899',
    'ivanova@agent.test',
    12.00,
    (SELECT id FROM users WHERE email = 'manager2@lawfirm.test')
);


-- ============================================================
-- Клиенты
-- ============================================================

-- Обычный физический клиент.
INSERT INTO clients (
    client_type,
    full_name,
    phone,
    email,
    created_by,
    updated_by
)
VALUES
(
    'individual',
    'Смирнов Андрей',
    '+79111234567',
    'zirota@test.ru',
    (SELECT id FROM users WHERE email = 'manager1@lawfirm.test'),
    (SELECT id FROM users WHERE email = 'manager1@lawfirm.test')
);

-- Намеренный дубликат Смирнова:
-- совпадает телефон, имя и почта записаны иначе.
INSERT INTO clients (
    client_type,
    full_name,
    phone,
    email,
    created_by,
    updated_by
)
VALUES
(
    'individual',
    'Смирнов А. П.',
    '+79111234567',
    'a.smirnov@test.ru',
    (SELECT id FROM users WHERE email = 'manager2@lawfirm.test'),
    (SELECT id FROM users WHERE email = 'manager2@lawfirm.test')
);

-- Юридическое лицо.
INSERT INTO clients (
    client_type,
    short_name,
    inn,
    ogrn,
    phone,
    email,
    created_by,
    updated_by
)
VALUES
(
    
    'legal',
    'ООО "Бнал".',
    '7701234567',
    '1027700000001',
    '+79001112233',
    'info@stroyinvest.test',
    (SELECT id FROM users WHERE email = 'manager1@lawfirm.test'),
    (SELECT id FROM users WHERE email = 'manager1@lawfirm.test')
);

-- Второй намеренный дубликат:
-- тот же ИНН, другое написание.
INSERT INTO clients (
    client_type,
    short_name,
    inn,
    created_by,
    updated_by
)
VALUES
(
    'legal',
    'компания обнал',
    '7701234567',
    (SELECT id FROM users WHERE email = 'manager2@lawfirm.test'),
    (SELECT id FROM users WHERE email = 'manager2@lawfirm.test')
);

-- Эта организация является действующим клиентом фирмы
-- и будет использоваться для проверки конфликта.
INSERT INTO clients (
    client_type,
    short_name,
    inn,
    ogrn,
    phone,
    email,
    created_by,
    updated_by
)
VALUES
(
    'legal',
    'ПАО Сбербанк',
    '7707083893',
    '1027700132195',
    '+74950000000',
    'client@sber.test',
    (SELECT id FROM users WHERE email = 'manager1@lawfirm.test'),
    (SELECT id FROM users WHERE email = 'manager1@lawfirm.test')
);

-- Клиент с неполными данными:
-- e-mail и телефон отсутствуют.
INSERT INTO clients (
    client_type,
    short_name,
    inn,
    created_by,
    updated_by
)
VALUES
(
    'legal',
    'ООО "БезПочты"',
    '7812345678',
    (SELECT id FROM users WHERE email = 'manager1@lawfirm.test'),
    (SELECT id FROM users WHERE email = 'manager1@lawfirm.test')
);


-- ============================================================
-- Оппоненты
-- ============================================================

INSERT INTO opponents (
    name,
    normalized_name,
    inn,
    ogrn,
    is_individual,
    created_by
)
VALUES
(
    'ПАО Сбербанк',
    'сбербанк',
    '7707083893',
    '1027700132195',
    FALSE,
    (SELECT id FROM users WHERE email = 'manager1@lawfirm.test')
),
(
    'АО "СберЛогистика"',
    'сберлогистика',
    '7707000001',
    '1027700000002',
    FALSE,
    (SELECT id FROM users WHERE email = 'manager1@lawfirm.test')
),
(
    'ООО "Конкурент-1"',
    'конкурент 1',
    '7799887766',
    '1027700000003',
    FALSE,
    (SELECT id FROM users WHERE email = 'manager1@lawfirm.test')
),
(
    'Николаев Виктор Сергеевич',
    'николаев виктор сергеевич',
    NULL,
    NULL,
    TRUE,
    (SELECT id FROM users WHERE email = 'manager2@lawfirm.test')
);


-- ============================================================
-- Аффилированность организаций
--
-- СберЛогистика является дочерней организацией Сбербанка.
-- При этом СберЛогистика сама НЕ находится в clients.
-- Поэтому конфликт по ней будет именно конфликтом
-- через аффилированность, а не прямым совпадением.
-- ============================================================

INSERT INTO affiliations (
    parent_id,
    child_id,
    relation_type,
    created_by
)
VALUES
(
    (SELECT id
       FROM opponents
      WHERE normalized_name = 'сбербанк'),

    (SELECT id
       FROM opponents
      WHERE normalized_name = 'сберлогистика'),

    'subsidiary',

    (SELECT id
       FROM users
      WHERE email = 'admin@lawfirm.test')
);


-- ============================================================
-- Лиды
-- ============================================================

-- Существующий активный лид Сбербанка.
-- Он показывает, что Сбербанк является текущим клиентом фирмы.
INSERT INTO leads (
    client_id,
    opponent_id,
    description,
    amount,
    status,
    created_by,
    updated_by,
    created_at,
    updated_at
)
VALUES
(
    (SELECT id FROM clients
      WHERE short_name = 'ПАО Сбербанк'),

    (SELECT id FROM opponents
      WHERE normalized_name = 'конкурент 1'),

    'Текущее юридическое сопровождение Сбербанка',
    1000000.00,
    'active',

    (SELECT id FROM users
      WHERE email = 'manager1@lawfirm.test'),

    (SELECT id FROM users
      WHERE email = 'manager1@lawfirm.test'),

    now() - INTERVAL '30 days',
    now() - INTERVAL '1 day'
);


-- UC-2: прямой конфликт.
INSERT INTO leads (
    client_id,
    opponent_id,
    description,
    amount,
    status,
    created_by,
    updated_by
)
VALUES
(
    (SELECT id FROM clients
      WHERE ogrn = '1027700000001'),

    (SELECT id FROM opponents
      WHERE normalized_name = 'сбербанк'),

    'Спор против Сбербанка',
    300000.00,
    'checking',

    (SELECT id FROM users
      WHERE email = 'manager1@lawfirm.test'),

    (SELECT id FROM users
      WHERE email = 'manager1@lawfirm.test')
);


-- UC-2: конфликт через аффилированность.
INSERT INTO leads (
    client_id,
    opponent_id,
    description,
    amount,
    status,
    created_by,
    updated_by
)
VALUES
(
    (SELECT id FROM clients
      WHERE ogrn = '1027700000001'),

    (SELECT id FROM opponents
      WHERE normalized_name = 'сберлогистика'),

    'Спор против дочерней структуры клиента',
    1500000.00,
    'checking',

    (SELECT id FROM users
      WHERE email = 'manager1@lawfirm.test'),

    (SELECT id FROM users
      WHERE email = 'manager1@lawfirm.test')
);


-- UC-2: конфликта нет.
-- Этот же лид используется для UC-4.
INSERT INTO leads (
    client_id,
    opponent_id,
    description,
    amount,
    status,
    created_by,
    updated_by
)
VALUES
(
    (SELECT id FROM clients
      WHERE full_name = 'Смирнов Андрей'),

    (SELECT id FROM opponents
      WHERE normalized_name = 'конкурент 1'),

    'Защита товарного знака',
    500000.00,
    'new',

    (SELECT id FROM users
      WHERE email = 'manager2@lawfirm.test'),

    (SELECT id FROM users
      WHERE email = 'manager2@lawfirm.test')
);


-- ============================================================
-- Предложения агентов
-- ============================================================

-- Действующий приоритет.
-- priority_expires_at заполнит триггер
INSERT INTO agent_offers (
    lead_id,
    agent_id,
    amount,
    commission,
    is_selected,
    created_by
)
VALUES
(
    (SELECT id FROM leads
      WHERE description = 'Защита товарного знака'),

    (SELECT id FROM agents
      WHERE email = 'lalala@agent.test'),

    500000.00,
    40000.00,
    TRUE,

    (SELECT id FROM users
      WHERE email = 'manager2@lawfirm.test')
);


-- Второе действующее предложение.
INSERT INTO agent_offers (
    lead_id,
    agent_id,
    amount,
    commission,
    is_selected,
    created_by
)
VALUES
(
    (SELECT id FROM leads
      WHERE description = 'Защита товарного знака'),

    (SELECT id FROM agents
      WHERE email = 'info@jurposred.test'),

    520000.00,
    80000.00,
    FALSE,

    (SELECT id FROM users
      WHERE email = 'manager2@lawfirm.test')
);


-- Намеренно просроченный приоритет.
-- Чистая прибыль здесь самая высокая,
-- но приоритет агента уже недействителен.
INSERT INTO agent_offers (
    lead_id,
    agent_id,
    amount,
    commission,
    priority_expires_at,
    is_selected,
    created_by
)
VALUES
(
    (SELECT id FROM leads
      WHERE description = 'Защита товарного знака'),

    (SELECT id FROM agents
      WHERE email = 'ivanova@agent.test'),

    510000.00,
    10000.00,
    now() - INTERVAL '1 day',
    FALSE,

    (SELECT id FROM users
      WHERE email = 'manager2@lawfirm.test')
);


-- ============================================================
-- Настройки LLM
-- ============================================================

INSERT INTO llm_settings (
    provider,
    base_url,
    model,
    api_token_encrypted,
    is_active,
    updated_by
)
VALUES
(
    'yandexgpt',
    'https://example.invalid/llm',
    'test-model',
    decode('746573742d746f6b656e', 'hex'),
    TRUE,
    (SELECT id FROM users
      WHERE email = 'admin@lawfirm.test')
);


-- ============================================================
-- Лицензия
-- ============================================================

INSERT INTO license_activations (
    installation_id,
    license_key_hash,
    activation_secret,
    token,
    token_expires_at,
    activated_by_user_id
)
VALUES
(
    'a1b2c3d4-e5f6-7890-abcd-ef1234567890',
    decode('0102030405060708', 'hex'),
    decode('1112131415161718', 'hex'),
    decode('2122232425262728', 'hex'),
    now() + INTERVAL '24 hours',
    (SELECT id FROM users
      WHERE email = 'admin@lawfirm.test')
);

COMMIT;