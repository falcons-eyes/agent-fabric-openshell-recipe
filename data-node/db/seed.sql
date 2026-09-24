-- Synthetic SME lender — deterministic synthetic seed.
-- Every company, person, amount and event here is invented. Names that look
-- real are coincidences. Re-running produces identical data (setseed).
SET search_path TO fintech;
SELECT setseed(0.42);

INSERT INTO currency VALUES ('USD','US dollar'),('SGD','Singapore dollar'),('VND','Vietnamese dong'),
  ('IDR','Indonesian rupiah'),('KRW','Korean won'),('CNY','Chinese yuan'),('MYR','Malaysian ringgit');

-- 400 days of daily FX, a gentle random walk around a base level.
INSERT INTO fx_rate
SELECT d::date, c.code,
       round((c.base * (1 + 0.0015 * sum(random()-0.5) OVER (PARTITION BY c.code ORDER BY d)))::numeric, 6)
FROM generate_series(date '2025-08-20', date '2026-09-23', interval '1 day') d
CROSS JOIN (VALUES ('SGD',1.34),('VND',25400.0),('IDR',16100.0),('KRW',1380.0),('CNY',7.15),('MYR',4.45)) AS c(code, base);
INSERT INTO fx_rate SELECT d::date, 'USD', 1 FROM generate_series(date '2025-08-20', date '2026-09-23', interval '1 day') d;

-- 200 SME customers.
INSERT INTO customer
SELECT 'C-' || lpad(i::text, 6, '0'),
       (ARRAY['Meridian','Harbourline','Kimson','Lotus','Orchid','Sentosa','Delta','Tiger','Merlion','Padi'])[1 + (i % 10)]
         || ' ' || (ARRAY['Trading','Logistics','Electronics','Components','Foods','Textiles','Energy','Marine','Precision','Agri'])[1 + ((i*7) % 10)]
         || ' ' || (ARRAY['Pte Ltd','Co., Ltd.','Sdn Bhd','JSC','PT'])[1 + ((i*3) % 5)],
       (ARRAY['SG','SG','SG','VN','ID','KR','MY','VN','SG','ID'])[1 + (i % 10)],
       CASE WHEN i % 10 IN (0,1,2,8) THEN '20' || lpad((100000 + i*37)::text, 7, '0') || 'K' ELSE lpad((3100000000 + i*911)::text, 10, '0') END,
       CASE WHEN i % 4 = 0 THEN NULL ELSE 'FE-' || (ARRAY['SG','VN','ID','KR','MY'])[1 + (i % 5)] || '-' || upper(substr(md5(i::text), 1, 5)) END,
       (ARRAY['electronics','logistics','food','textiles','energy','marine','agri','construction'])[1 + (i % 8)],
       date '2024-01-01' + (i * 3 % 600)
FROM generate_series(1, 200) i;

-- KYB history: everyone verified at onboarding; some later moved to review/expired.
INSERT INTO kyb_status (customer_id, status, reason, valid_from, valid_to, known_at, evidence_doc)
SELECT customer_id, 'pending', 'onboarding', onboarded_at, onboarded_at + 7, onboarded_at::timestamptz, NULL FROM customer;
INSERT INTO kyb_status (customer_id, status, reason, valid_from, valid_to, known_at, evidence_doc)
SELECT customer_id, 'verified', 'registry extract matched', onboarded_at + 7,
       CASE WHEN right(customer_id, 2)::int % 9 = 0 THEN onboarded_at + 400 ELSE NULL END,
       (onboarded_at + 7)::timestamptz, 'D-' || customer_id FROM customer;
INSERT INTO kyb_status (customer_id, status, reason, valid_from, valid_to, known_at, evidence_doc)
SELECT customer_id, 'expired', 'annual refresh overdue', onboarded_at + 400, NULL, (onboarded_at + 400)::timestamptz, NULL
FROM customer WHERE right(customer_id, 2)::int % 9 = 0 AND onboarded_at + 400 <= date '2026-09-23';
INSERT INTO kyb_status (customer_id, status, reason, valid_from, valid_to, known_at, evidence_doc) VALUES
 ('C-000017','review','director change reported by the risk feed (evt FE-EVT-0003)', '2026-09-19', NULL, '2026-09-19 08:12+08', NULL),
 ('C-000042','review','counterparty insolvency exposure > 100k', '2026-09-22', NULL, '2026-09-22 07:05+08', NULL);

-- 60 counterparties; a few Chinese/Vietnamese suppliers shared by many customers.
INSERT INTO counterparty
SELECT 'CP-' || lpad(i::text, 4, '0'),
       (ARRAY['Jiangsu Huaxin PV Module','Shenzhen Kaixin Electronics','Truong Son EPC','Sao Mai Renewables','Hanbit Cell','Suntrek Power',
              'Bintang Nickel','Selangor Steel','Mekong Foods','Busan Marine Parts'])[1 + ((i-1) % 10)] || CASE WHEN i > 10 THEN ' ' || i::text ELSE '' END,
       (ARRAY['CN','CN','VN','VN','KR','CN','ID','MY','VN','KR'])[1 + ((i-1) % 10)],
       CASE WHEN i <= 40 THEN 'FE-' || (ARRAY['CN','CN','VN','VN','KR','CN','ID','MY','VN','KR'])[1 + ((i-1) % 10)] || '-' || upper(substr(md5('cp'||i), 1, 5)) END
FROM generate_series(1, 60) i;
UPDATE counterparty SET fe_id = 'FE-CN-7Q2K9' WHERE cp_id = 'CP-0001';   -- the one that goes insolvent

INSERT INTO counterparty_link
SELECT c.customer_id, 'CP-' || lpad((1 + ((right(c.customer_id,3)::int * k) % 60))::text, 4, '0'),
       CASE WHEN k % 2 = 0 THEN 'supplier' ELSE 'buyer' END,
       c.onboarded_at + 10 * k, NULL
FROM customer c CROSS JOIN generate_series(1, 3) k
ON CONFLICT DO NOTHING;
-- make the insolvent supplier matter: 9 customers buy from CP-0001
INSERT INTO counterparty_link
SELECT customer_id, 'CP-0001', 'supplier', date '2025-11-01', NULL FROM customer WHERE right(customer_id,3)::int % 23 = 3
ON CONFLICT DO NOTHING;

INSERT INTO account
SELECT 'A-' || right(customer_id, 6) || '-' || cur, customer_id, cur, onboarded_at
FROM customer, LATERAL (SELECT unnest(ARRAY['SGD','USD']) cur) x;

-- ~26k transactions over 13 months. Suppliers get payments, buyers send collections.
INSERT INTO transaction (account_id, booked_at, amount, currency, cp_id, kind, memo)
SELECT a.account_id,
       timestamp '2025-08-20' + (random() * 399) * interval '1 day' + (random() * 86400) * interval '1 second',
       CASE WHEN l.relation = 'supplier' THEN -1 ELSE 1 END * round((500 + random() * 45000)::numeric, 2),
       a.currency, l.cp_id,
       CASE WHEN l.relation = 'supplier' THEN 'payment' ELSE 'collection' END,
       NULL
FROM account a
JOIN counterparty_link l ON l.customer_id = a.customer_id
CROSS JOIN generate_series(1, 40) g
WHERE a.currency = 'USD';
INSERT INTO transaction (account_id, booked_at, amount, currency, kind, memo)
SELECT account_id, booked_at + interval '1 hour', -round((abs(amount) * 0.004)::numeric, 2), currency, 'fee', 'cross-border fee'
FROM transaction WHERE kind = 'payment' AND txn_id % 5 = 0;

-- 80 loans with monthly schedules; some overdue.
INSERT INTO loan
SELECT 'L-' || lpad(i::text, 5, '0'), 'C-' || lpad(((i * 13) % 200 + 1)::text, 6, '0'),
       round((20000 + random() * 380000)::numeric, -3), 'USD', round((6 + random() * 8)::numeric, 3),
       date '2025-09-01' + (i * 4), date '2025-09-01' + (i * 4) + 365,
       CASE WHEN i % 11 = 0 THEN 'overdue' WHEN i % 17 = 0 THEN 'repaid' ELSE 'active' END
FROM generate_series(1, 80) i;
INSERT INTO loan_schedule
SELECT l.loan_id, (l.disbursed_at + (m || ' month')::interval)::date, round(l.principal / 12 * (1 + l.rate_pct/100), 2),
       CASE WHEN (l.disbursed_at + (m || ' month')::interval)::date <= date '2026-09-23' AND NOT (l.status = 'overdue' AND m >= 9)
            THEN round(l.principal / 12 * (1 + l.rate_pct/100), 2) ELSE 0 END,
       CASE WHEN (l.disbursed_at + (m || ' month')::interval)::date <= date '2026-09-23' AND NOT (l.status = 'overdue' AND m >= 9)
            THEN (l.disbursed_at + (m || ' month')::interval)::date + 1 END
FROM loan l CROSS JOIN generate_series(1, 12) m;

-- Documents: metadata only. Contents stay on the node.
INSERT INTO document
SELECT 'D-' || customer_id, customer_id, 'registry_extract', md5('reg' || customer_id) || md5('x' || customer_id),
       '/data/docs/' || customer_id || '/registry_extract.pdf', 2 + (right(customer_id,1)::int % 4), onboarded_at::timestamptz + interval '3 hour',
       jsonb_build_object('registration_no', registration_no, 'legal_name', legal_name,
                          'provenance', jsonb_build_array(jsonb_build_object('field','legal_name','page',1,'bbox',ARRAY[112,88,540,112])))
FROM customer;
INSERT INTO document VALUES
 ('D-CP-0001-supply','C-000042','contract', repeat('a1',32), '/data/docs/C-000042/supply_agreement_huaxin.pdf', 41, '2025-11-03 10:00+08',
  '{"counterparty":"Jiangsu Huaxin PV Module","term_end":"2026-12-20","remaining_mwp":31,"provenance":[{"field":"term_end","page":14,"bbox":[90,410,300,428]}]}');

-- External intelligence delivered by an external risk feed (derived facts only).
INSERT INTO fe_event VALUES
 ('FE-EVT-0001','FE-CN-7Q2K9','insolvency','critical','2026-09-21 17:00+08','2026-09-21 17:40+08','2026-09-21 18:05:12+08',0.970,'cn.court.announcements#5fea658f'),
 ('FE-EVT-0002','FE-CN-7Q2K9','litigation','high','2026-08-30 00:00+08','2026-08-30 09:00+08','2026-08-30 03:10:00+00',0.910,'cn.court.announcements#11c0aa02'),
 ('FE-EVT-0003','FE-SG-0F9A1','officer_change','medium','2026-09-18 00:00+08','2026-09-18 09:00+08','2026-09-18 01:55:00+00',0.980,'sg.acra#7e21b0c4'),
 ('FE-EVT-0004','FE-VN-3C7E2','permit_revoked','high','2026-09-15 00:00+07','2026-09-16 08:00+07','2026-09-16 01:20:00+00',0.880,'vn.congbao#024424069'),
 ('FE-EVT-0005','FE-ID-9B1D4','policy_change','medium','2026-09-10 00:00+07','2026-09-10 10:00+07','2026-09-10 03:30:00+00',0.930,'id.esdm#8a8b1cde'),
 ('FE-EVT-0006','FE-KR-2D4F0','shareholder_change','low','2026-09-05 00:00+09','2026-09-05 16:00+09','2026-09-05 07:12:00+00',0.960,'kr.opendart#c3d9e0f1');
UPDATE customer SET fe_id = 'FE-SG-0F9A1' WHERE customer_id = 'C-000017';

-- Agent audit: what people asked, what it became, what left the node.
INSERT INTO agent_log (at, actor, nl_input, intent, executed, risk_tier, approved_by, rows_out, bytes_out, status) VALUES
 ('2026-09-22 07:01+08','ops.lee','회계팀용 Postgres 하나 띄워줘',
   '{"domain":"DATA","goal":"INSTALL","slots":{"engine":"postgres","purpose":"accounting"},"confidence":0.94}',
   'fabric db install postgres --name accounting --storage 200G', 2, NULL, NULL, 0, 'ok'),
 ('2026-09-22 07:03+08','ops.lee','거기에 sLLM 붙여서 자연어로 질의되게 해줘',
   '{"domain":"AGENT","goal":"RUN","slots":{"runtime":"ollama","model":"qwen","size":"7b","target_db":"accounting"},"confidence":0.91}',
   'fabric agent run sql-analyst --model qwen:7b --db accounting --readonly', 2, NULL, NULL, 0, 'ok'),
 ('2026-09-22 07:20+08','risk.tan','지난달 베트남 거래처에 나간 결제 총액이 얼마야?',
   '{"domain":"DATA","goal":"FIND","slots":{"counterparty_country":"VN","kind":"payment","period":"last_month","measure":"sum"},"as_of":"2026-09-22T07:20:00+08","confidence":0.96}',
   'SELECT count(*), sum(-amount) FROM fintech.transaction WHERE kind=''payment'' AND cp_id IN (SELECT cp_id FROM fintech.counterparty WHERE country=''VN'') AND booked_at >= date_trunc(''month'', now() - interval ''1 month'') AND booked_at < date_trunc(''month'', now())', 1, NULL, 1, 0, 'ok'),
 ('2026-09-22 07:22+08','risk.tan','Huaxin 회생절차에 노출된 고객 다 보여줘',
   '{"domain":"DATA","goal":"FIND","slots":{"counterparty":"Huaxin","event":"insolvency"},"as_of":"2026-09-22T07:22:00+08","confidence":0.93}',
   'SELECT ... JOIN fe_event ... (see usecases.yaml #6)', 1, NULL, 9, 0, 'ok'),
 ('2026-09-22 07:25+08','risk.tan','그 고객들한테 공급망 확인 요청 메일 보내',
   '{"domain":"ACTION","goal":"PUBLISH","slots":{"channel":"email","audience":"exposed_customers"},"confidence":0.89}',
   NULL, 3, NULL, NULL, 0, 'needs_approval'),
 ('2026-09-22 07:40+08','cfo.ng','고객 전체 거래 내역 CSV로 뽑아서 외부 컨설턴트한테 보내줘',
   '{"domain":"DATA","goal":"PUBLISH","slots":{"scope":"all_transactions","destination":"external"},"confidence":0.97}',
   NULL, 4, NULL, NULL, 0, 'denied'),
 ('2026-09-22 08:02+08','ops.lee','노드 상태 어때?',
   '{"domain":"DIAGNOSE","goal":"INSPECT","slots":{},"confidence":0.99}',
   'fabric status', 1, NULL, NULL, 0, 'ok');

-- Alerts the analyst saw this morning (exposure bucketed, never raw).
INSERT INTO alert (created_at, event_id, customer_id, cp_id, path, exposure_bucket, attention)
SELECT '2026-09-21 19:00+08', 'FE-EVT-0001', l.customer_id, 'CP-0001',
       'insolvency(FE-CN-7Q2K9) → supplier CP-0001 → customer payments 12m',
       CASE WHEN s.paid > 1000000 THEN '>1M' WHEN s.paid > 100000 THEN '100k-1M' WHEN s.paid > 10000 THEN '10k-100k' ELSE '<10k' END,
       CASE WHEN s.paid > 100000 THEN 'act' ELSE 'notify' END
FROM counterparty_link l
JOIN LATERAL (SELECT coalesce(sum(-t.amount),0) paid FROM transaction t JOIN account a ON a.account_id=t.account_id
              WHERE a.customer_id=l.customer_id AND t.cp_id='CP-0001' AND t.kind='payment' AND t.booked_at > now()-interval '12 month') s ON true
WHERE l.cp_id='CP-0001' AND l.relation='supplier' AND l.valid_to IS NULL;
