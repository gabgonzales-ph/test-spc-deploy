--
-- PostgreSQL database dump
--

\restrict vvVeTqdkgejtKKZKGiQossZQEnLzcciDmlBfkrG3LW2CkSMAkJwxngG509sIFVJ

-- Dumped from database version 17.6
-- Dumped by pg_dump version 18.4

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET transaction_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: public; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA public;


--
-- Name: SCHEMA public; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON SCHEMA public IS 'standard public schema';


--
-- Name: disclosure_category; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.disclosure_category AS ENUM (
    'city-ordinance',
    'city-resolution',
    'executive-order',
    'bids-awards',
    'financial-aid',
    'full-disclosure',
    'city-ordinance-&-resolution'
);


--
-- Name: sector_id; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.sector_id AS ENUM (
    'social',
    'economic',
    'infrastructure',
    'environment',
    'institutional',
    'legislative'
);


--
-- Name: audit_summary(timestamp with time zone, timestamp with time zone); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.audit_summary(from_date timestamp with time zone, to_date timestamp with time zone) RETURNS json
    LANGUAGE sql
    AS $$
  SELECT json_build_object(
    'by_action',      (SELECT json_object_agg(action, count) FROM (SELECT action, COUNT(*) FROM audit_log WHERE created_at BETWEEN from_date AND to_date GROUP BY action) t),
    'by_entity_type', (SELECT json_object_agg(entity_type, count) FROM (SELECT entity_type, COUNT(*) FROM audit_log WHERE created_at BETWEEN from_date AND to_date AND entity_type IS NOT NULL GROUP BY entity_type) t),
    'by_user',        (SELECT json_object_agg(user_id, count) FROM (SELECT user_id, COUNT(*) FROM audit_log WHERE created_at BETWEEN from_date AND to_date AND user_id IS NOT NULL GROUP BY user_id) t)
  )
$$;


--
-- Name: csm_response_date_range(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.csm_response_date_range(p_office_id uuid DEFAULT NULL::uuid) RETURNS json
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  select json_build_object(
    'date_from', to_char(min(transaction_date), 'YYYY-MM-DD'),
    'date_to',   to_char(max(transaction_date), 'YYYY-MM-DD')
  )
  from csm_response
  where (p_office_id is null or office_id = p_office_id);
$$;


--
-- Name: csm_response_set_control_no(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.csm_response_set_control_no() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
 v_office_no SMALLINT;
 v_year      SMALLINT := EXTRACT(YEAR FROM NEW.created_at);
 v_month     SMALLINT := EXTRACT(MONTH FROM NEW.created_at);
 v_counter   INTEGER;
BEGIN
 IF NEW.office_id IS NOT NULL THEN
   SELECT office_no INTO v_office_no FROM offices WHERE id = NEW.office_id;
 END IF;
 
 IF v_office_no IS NULL THEN
   NEW.control_no := NULL;
   RETURN NEW;
 END IF;
 
 -- Serializes concurrent inserts for the same office+month so counters
 -- never collide; releases automatically at transaction end.
 PERFORM pg_advisory_xact_lock(
   hashtext('csm_control:' || v_office_no || ':' || v_year || ':' || v_month)
 );
 
 SELECT count(*) + 1 INTO v_counter
 FROM csm_response
 WHERE office_id = NEW.office_id
   AND EXTRACT(YEAR FROM created_at) = v_year
   AND EXTRACT(MONTH FROM created_at) = v_month
   AND id IS DISTINCT FROM NEW.id;
 
 NEW.control_no :=
   to_char(NEW.created_at, 'YYYY/MM/') ||
   lpad(v_office_no::text, 2, '0') ||
   '-' ||
   lpad(v_counter::text, 3, '0');
 
 RETURN NEW;
END;
$$;


--
-- Name: csm_response_stats(uuid, date, date); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.csm_response_stats(p_office_id uuid DEFAULT NULL::uuid, p_date_from date DEFAULT NULL::date, p_date_to date DEFAULT NULL::date) RETURNS jsonb
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  result JSONB;
BEGIN
  WITH filtered AS (
    SELECT *,
      CASE
        WHEN client_type IN ('citizen', 'business') THEN 'external'
        WHEN client_type = 'government' THEN 'internal'
        ELSE 'unspecified'
      END AS respondent_group
    FROM csm_response
    WHERE (p_office_id IS NULL OR office_id = p_office_id)
      AND (p_date_from IS NULL OR transaction_date >= p_date_from)
      AND (p_date_to IS NULL OR transaction_date <= p_date_to)
  ),

  totals AS (
    SELECT
      count(*) AS total_responses,
      count(*) FILTER (WHERE cc1 IN (1, 2)) AS cc_aware_count,
      count(DISTINCT office_id) AS offices_reporting
    FROM filtered
  ),

  overall_sat AS (
    SELECT
      count(*) FILTER (WHERE sqd0 IN ('Strongly Agree', 'Agree')) AS positive,
      count(*) FILTER (WHERE sqd0 <> 'Not Applicable') AS eligible
    FROM filtered
  ),

  age_agg AS (
    SELECT jsonb_agg(row_to_json(a)) AS rows FROM (
      SELECT
        bucket,
        count(*) FILTER (WHERE respondent_group = 'external') AS external,
        count(*) FILTER (WHERE respondent_group = 'internal') AS internal,
        count(*) AS total
      FROM (
        SELECT
          CASE
            WHEN age IS NULL THEN 'unspecified'
            WHEN age <= 19 THEN '19_lower'
            WHEN age BETWEEN 20 AND 34 THEN '20_34'
            WHEN age BETWEEN 35 AND 49 THEN '35_49'
            WHEN age BETWEEN 50 AND 64 THEN '50_64'
            ELSE '65_higher'
          END AS bucket,
          respondent_group
        FROM filtered
      ) x
      GROUP BY bucket
    ) a
  ),

  sex_agg AS (
    SELECT jsonb_agg(row_to_json(s)) AS rows FROM (
      SELECT
        coalesce(sex, 'unspecified') AS sex,
        count(*) FILTER (WHERE respondent_group = 'external') AS external,
        count(*) FILTER (WHERE respondent_group = 'internal') AS internal,
        count(*) AS total
      FROM filtered
      GROUP BY coalesce(sex, 'unspecified')
    ) s
  ),

  customer_type_agg AS (
    SELECT jsonb_agg(row_to_json(c)) AS rows FROM (
      SELECT
        coalesce(client_type, 'unspecified') AS client_type,
        count(*) FILTER (WHERE respondent_group = 'external') AS external,
        count(*) FILTER (WHERE respondent_group = 'internal') AS internal,
        count(*) AS total
      FROM filtered
      GROUP BY coalesce(client_type, 'unspecified')
    ) c
  ),

  cc1_agg AS (
    SELECT jsonb_agg(row_to_json(x)) AS rows FROM (
      SELECT coalesce(cc1::text, 'no_answer') AS code, count(*) AS n
      FROM filtered GROUP BY coalesce(cc1::text, 'no_answer')
    ) x
  ),
  cc2_agg AS (
    SELECT jsonb_agg(row_to_json(x)) AS rows FROM (
      SELECT coalesce(cc2::text, 'no_answer') AS code, count(*) AS n
      FROM filtered GROUP BY coalesce(cc2::text, 'no_answer')
    ) x
  ),
  cc3_agg AS (
    SELECT jsonb_agg(row_to_json(x)) AS rows FROM (
      SELECT coalesce(cc3::text, 'no_answer') AS code, count(*) AS n
      FROM filtered GROUP BY coalesce(cc3::text, 'no_answer')
    ) x
  ),

  sqd_agg AS (
    SELECT jsonb_agg(row_to_json(d)) AS rows FROM (
      SELECT
        dim,
        count(*) FILTER (WHERE val = 'Strongly Agree')             AS strongly_agree,
        count(*) FILTER (WHERE val = 'Agree')                       AS agree,
        count(*) FILTER (WHERE val = 'Neither Agree nor Disagree')  AS neutral,
        count(*) FILTER (WHERE val = 'Disagree')                    AS disagree,
        count(*) FILTER (WHERE val = 'Strongly Disagree')           AS strongly_disagree,
        count(*) FILTER (WHERE val = 'Not Applicable')              AS not_applicable,
        count(*) AS total,
        CASE WHEN count(*) FILTER (WHERE val <> 'Not Applicable') = 0 THEN NULL
          ELSE round(
            100.0 * count(*) FILTER (WHERE val IN ('Strongly Agree', 'Agree'))
            / count(*) FILTER (WHERE val <> 'Not Applicable'), 2
          )
        END AS overall_rating
      FROM (
        SELECT 'sqd0' AS dim, sqd0 AS val FROM filtered
        UNION ALL SELECT 'sqd1', sqd1 FROM filtered
        UNION ALL SELECT 'sqd2', sqd2 FROM filtered
        UNION ALL SELECT 'sqd3', sqd3 FROM filtered
        UNION ALL SELECT 'sqd4', sqd4 FROM filtered
        UNION ALL SELECT 'sqd5', sqd5 FROM filtered
        UNION ALL SELECT 'sqd6', sqd6 FROM filtered
        UNION ALL SELECT 'sqd7', sqd7 FROM filtered
        UNION ALL SELECT 'sqd8', sqd8 FROM filtered
      ) u
      GROUP BY dim
    ) d
  ),

  services_agg AS (
    SELECT jsonb_agg(row_to_json(v) ORDER BY (v.overall_rating) DESC NULLS LAST) AS rows FROM (
      SELECT
        service,
        count(*) AS total_responses,
        CASE WHEN count(*) FILTER (WHERE sqd0 <> 'Not Applicable') = 0 THEN NULL
          ELSE round(
            100.0 * count(*) FILTER (WHERE sqd0 IN ('Strongly Agree', 'Agree'))
            / count(*) FILTER (WHERE sqd0 <> 'Not Applicable'), 2
          )
        END AS overall_rating
      FROM filtered
      WHERE service IS NOT NULL AND service <> ''
      GROUP BY service
    ) v
  )

  SELECT jsonb_build_object(
    'total_responses', t.total_responses,
    'offices_reporting', t.offices_reporting,
    'cc_awareness_pct', CASE WHEN t.total_responses = 0 THEN NULL
      ELSE round(100.0 * t.cc_aware_count / t.total_responses, 2) END,
    'overall_satisfaction_pct', CASE WHEN o.eligible = 0 THEN NULL
      ELSE round(100.0 * o.positive / o.eligible, 2) END,
    'age', coalesce(a.rows, '[]'::jsonb),
    'sex', coalesce(s.rows, '[]'::jsonb),
    'customer_type', coalesce(c.rows, '[]'::jsonb),
    'cc1', coalesce(cc1.rows, '[]'::jsonb),
    'cc2', coalesce(cc2.rows, '[]'::jsonb),
    'cc3', coalesce(cc3.rows, '[]'::jsonb),
    'sqd', coalesce(sq.rows, '[]'::jsonb),
    'services', coalesce(sv.rows, '[]'::jsonb)
  ) INTO result
  FROM totals t, overall_sat o, age_agg a, sex_agg s, customer_type_agg c,
       cc1_agg cc1, cc2_agg cc2, cc3_agg cc3, sqd_agg sq, services_agg sv;

  RETURN result;
END;
$$;


--
-- Name: csm_response_sync_office_name(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.csm_response_sync_office_name() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    IF NEW.office_id IS NULL THEN
        NEW.office_name := NULL;

    ELSIF TG_OP = 'INSERT'
       OR NEW.office_id IS DISTINCT FROM OLD.office_id THEN

        SELECT name
        INTO NEW.office_name
        FROM offices
        WHERE id = NEW.office_id;
    END IF;

    RETURN NEW;
END;
$$;


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: csm_response; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.csm_response (
    id integer NOT NULL,
    control_no text,
    client_type text NOT NULL,
    transaction_date date NOT NULL,
    sex text,
    age smallint,
    region text NOT NULL,
    service text NOT NULL,
    cc1 smallint NOT NULL,
    cc2 smallint NOT NULL,
    cc3 smallint NOT NULL,
    sqd0 text NOT NULL,
    sqd1 text NOT NULL,
    sqd2 text NOT NULL,
    sqd3 text NOT NULL,
    sqd4 text NOT NULL,
    sqd5 text NOT NULL,
    sqd6 text NOT NULL,
    sqd7 text NOT NULL,
    sqd8 text NOT NULL,
    comments text,
    email_address text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    office_id uuid,
    office_name text,
    CONSTRAINT csm_response_age_check CHECK (((age > 0) AND (age < 130))),
    CONSTRAINT csm_response_cc1_check CHECK (((cc1 >= 1) AND (cc1 <= 4))),
    CONSTRAINT csm_response_cc2_check CHECK (((cc2 >= 1) AND (cc2 <= 5))),
    CONSTRAINT csm_response_cc3_check CHECK (((cc3 >= 1) AND (cc3 <= 4))),
    CONSTRAINT csm_response_client_type_check CHECK ((client_type = ANY (ARRAY['citizen'::text, 'business'::text, 'government'::text]))),
    CONSTRAINT csm_response_sex_check CHECK ((sex = ANY (ARRAY['male'::text, 'female'::text]))),
    CONSTRAINT csm_response_sqd0_check CHECK ((sqd0 = ANY (ARRAY['Strongly Disagree'::text, 'Disagree'::text, 'Neither Agree nor Disagree'::text, 'Agree'::text, 'Strongly Agree'::text, 'Not Applicable'::text]))),
    CONSTRAINT csm_response_sqd1_check CHECK ((sqd1 = ANY (ARRAY['Strongly Disagree'::text, 'Disagree'::text, 'Neither Agree nor Disagree'::text, 'Agree'::text, 'Strongly Agree'::text, 'Not Applicable'::text]))),
    CONSTRAINT csm_response_sqd2_check CHECK ((sqd2 = ANY (ARRAY['Strongly Disagree'::text, 'Disagree'::text, 'Neither Agree nor Disagree'::text, 'Agree'::text, 'Strongly Agree'::text, 'Not Applicable'::text]))),
    CONSTRAINT csm_response_sqd3_check CHECK ((sqd3 = ANY (ARRAY['Strongly Disagree'::text, 'Disagree'::text, 'Neither Agree nor Disagree'::text, 'Agree'::text, 'Strongly Agree'::text, 'Not Applicable'::text]))),
    CONSTRAINT csm_response_sqd4_check CHECK ((sqd4 = ANY (ARRAY['Strongly Disagree'::text, 'Disagree'::text, 'Neither Agree nor Disagree'::text, 'Agree'::text, 'Strongly Agree'::text, 'Not Applicable'::text]))),
    CONSTRAINT csm_response_sqd5_check CHECK ((sqd5 = ANY (ARRAY['Strongly Disagree'::text, 'Disagree'::text, 'Neither Agree nor Disagree'::text, 'Agree'::text, 'Strongly Agree'::text, 'Not Applicable'::text]))),
    CONSTRAINT csm_response_sqd6_check CHECK ((sqd6 = ANY (ARRAY['Strongly Disagree'::text, 'Disagree'::text, 'Neither Agree nor Disagree'::text, 'Agree'::text, 'Strongly Agree'::text, 'Not Applicable'::text]))),
    CONSTRAINT csm_response_sqd7_check CHECK ((sqd7 = ANY (ARRAY['Strongly Disagree'::text, 'Disagree'::text, 'Neither Agree nor Disagree'::text, 'Agree'::text, 'Strongly Agree'::text, 'Not Applicable'::text]))),
    CONSTRAINT csm_response_sqd8_check CHECK ((sqd8 = ANY (ARRAY['Strongly Disagree'::text, 'Disagree'::text, 'Neither Agree nor Disagree'::text, 'Agree'::text, 'Strongly Agree'::text, 'Not Applicable'::text])))
);


--
-- Name: insert_csm_response(uuid, text, date, text, smallint, text, text, smallint, smallint, smallint, text, text, text, text, text, text, text, text, text, text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.insert_csm_response(p_office_id uuid, p_client_type text, p_transaction_date date, p_sex text, p_age smallint, p_region text, p_service text, p_cc1 smallint, p_cc2 smallint, p_cc3 smallint, p_sqd0 text, p_sqd1 text, p_sqd2 text, p_sqd3 text, p_sqd4 text, p_sqd5 text, p_sqd6 text, p_sqd7 text, p_sqd8 text, p_comments text, p_email_address text) RETURNS public.csm_response
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
    v_office_no text;
    v_count int;
    v_control_no text;
    v_row csm_response;
BEGIN
    SELECT office_no::text
    INTO v_office_no
    FROM offices
    WHERE id = p_office_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'office_not_found'
            USING ERRCODE = 'P0002';
    END IF;

    SELECT count(*)
    INTO v_count
    FROM csm_response
    WHERE office_id = p_office_id;

    INSERT INTO csm_response (
        office_id,
        client_type,
        transaction_date,
        sex,
        age,
        region,
        service,
        cc1,
        cc2,
        cc3,
        sqd0,
        sqd1,
        sqd2,
        sqd3,
        sqd4,
        sqd5,
        sqd6,
        sqd7,
        sqd8,
        comments,
        email_address
    )
    VALUES (
        p_office_id,
        p_client_type,
        p_transaction_date,
        p_sex,
        p_age,
        p_region,
        p_service,
        p_cc1,
        p_cc2,
        p_cc3,
        p_sqd0,
        p_sqd1,
        p_sqd2,
        p_sqd3,
        p_sqd4,
        p_sqd5,
        p_sqd6,
        p_sqd7,
        p_sqd8,
        p_comments,
        p_email_address
    )
    RETURNING *
    INTO v_row;

    v_control_no :=
        to_char(now(), 'YYYY-MM')
        || '-'
        || v_office_no
        || '-'
        || lpad((v_count + 1)::text, 3, '0');

    UPDATE csm_response
    SET control_no = v_control_no
    WHERE id = v_row.id
    RETURNING *
    INTO v_row;

    RETURN v_row;
END;
$$;


--
-- Name: offices_cascade_name_to_csm_response(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.offices_cascade_name_to_csm_response() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    IF NEW.name IS DISTINCT FROM OLD.name THEN
        UPDATE csm_response
        SET office_name = NEW.name
        WHERE office_id = NEW.id;
    END IF;

    RETURN NEW;
END;
$$;


--
-- Name: offices_set_slug(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.offices_set_slug() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
    candidate TEXT;
    suffix INT := 0;
BEGIN
    IF NEW.slug IS NOT NULL
       AND NEW.slug <> ''
       AND (TG_OP = 'INSERT' OR NEW.slug <> OLD.slug) THEN
        RETURN NEW;
    END IF;

    candidate := slugify(NEW.name);

    WHILE EXISTS (
        SELECT 1
        FROM offices
        WHERE slug = candidate ||
            CASE WHEN suffix = 0 THEN '' ELSE '-' || suffix END
        AND id IS DISTINCT FROM NEW.id
    ) LOOP
        suffix := suffix + 1;
    END LOOP;

    NEW.slug := candidate ||
        CASE WHEN suffix = 0 THEN '' ELSE '-' || suffix END;

    RETURN NEW;
END;
$$;


--
-- Name: set_tourism_updated_at(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.set_tourism_updated_at() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
begin
  new.updated_at = now();
  return new;
end;
$$;


--
-- Name: set_updated_at(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.set_updated_at() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
begin
  new.updated_at = now();
  return new;
end;
$$;


--
-- Name: slugify(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.slugify(input text) RETURNS text
    LANGUAGE sql IMMUTABLE
    AS $$
    SELECT trim(
        both '-' FROM regexp_replace(
            lower(regexp_replace(input, '''', '', 'g')),
            '[^a-z0-9]+',
            '-',
            'g'
        )
    );
$$;


--
-- Name: update_updated_at_column(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.update_updated_at_column() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  IF TG_TABLE_NAME IN ('ba_account', 'ba_session', 'ba_totp', 'ba_user') THEN
    NEW."updatedAt" = now();
  ELSE
    NEW.updated_at = now();
  END IF;
  RETURN NEW;
END;
$$;


--
-- Name: about_us; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.about_us (
    photo_id uuid DEFAULT gen_random_uuid() NOT NULL,
    file_path text NOT NULL,
    caption text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: articles; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.articles (
    article_id integer NOT NULL,
    title character varying(255) NOT NULL,
    slug character varying(255) NOT NULL,
    excerpt text,
    body text,
    featured_media_id integer,
    category_id integer,
    status character varying(20) DEFAULT 'draft'::character varying,
    published_at timestamp without time zone,
    created_at timestamp without time zone DEFAULT now(),
    updated_at timestamp without time zone DEFAULT now(),
    author character varying(255),
    CONSTRAINT articles_status_check CHECK (((status)::text = ANY ((ARRAY['draft'::character varying, 'review'::character varying, 'published'::character varying, 'archived'::character varying])::text[])))
);


--
-- Name: articles_article_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.articles_article_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: articles_article_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.articles_article_id_seq OWNED BY public.articles.article_id;


--
-- Name: audit_log; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.audit_log (
    log_id integer NOT NULL,
    user_id integer,
    action character varying(50) NOT NULL,
    entity_type character varying(50),
    entity_id integer,
    changes jsonb,
    ip_address character varying(45),
    created_at timestamp with time zone DEFAULT now(),
    user_agent text
);


--
-- Name: audit_logs_log_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.audit_logs_log_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: audit_logs_log_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.audit_logs_log_id_seq OWNED BY public.audit_log.log_id;


--
-- Name: ba_account; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ba_account (
    id text NOT NULL,
    "accountId" text NOT NULL,
    "providerId" text NOT NULL,
    "userId" text NOT NULL,
    "accessToken" text,
    "refreshToken" text,
    "idToken" text,
    "accessTokenExpiresAt" timestamp without time zone,
    "refreshTokenExpiresAt" timestamp without time zone,
    scope text,
    password text,
    "createdAt" timestamp without time zone DEFAULT now() NOT NULL,
    "updatedAt" timestamp without time zone DEFAULT now() NOT NULL
);


--
-- Name: ba_rate_limit; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ba_rate_limit (
    id text NOT NULL,
    key text NOT NULL,
    count integer DEFAULT 0 NOT NULL,
    last_request timestamp without time zone DEFAULT now() NOT NULL
);


--
-- Name: ba_session; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ba_session (
    id text NOT NULL,
    "expiresAt" timestamp without time zone NOT NULL,
    token text NOT NULL,
    "ipAddress" text,
    "userAgent" text,
    "userId" text NOT NULL,
    "createdAt" timestamp without time zone DEFAULT now() NOT NULL,
    "updatedAt" timestamp without time zone DEFAULT now() NOT NULL
);


--
-- Name: ba_totp; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ba_totp (
    id text NOT NULL,
    "userId" text NOT NULL,
    secret text NOT NULL,
    enabled boolean DEFAULT false NOT NULL,
    "createdAt" timestamp without time zone DEFAULT now() NOT NULL,
    "updatedAt" timestamp without time zone DEFAULT now() NOT NULL,
    "backupCodes" text,
    verified boolean DEFAULT false NOT NULL,
    "twoFactorEnabled" boolean DEFAULT false NOT NULL
);


--
-- Name: ba_user; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ba_user (
    id text NOT NULL,
    name text NOT NULL,
    email text NOT NULL,
    "emailVerified" boolean DEFAULT false NOT NULL,
    image text,
    "createdAt" timestamp without time zone DEFAULT now() NOT NULL,
    "updatedAt" timestamp without time zone DEFAULT now() NOT NULL,
    username text,
    role text DEFAULT 'uploader'::text NOT NULL,
    permissions text[] DEFAULT '{}'::text[] NOT NULL,
    "isActive" boolean DEFAULT true NOT NULL,
    "twoFactorEnabled" boolean DEFAULT false NOT NULL
);


--
-- Name: ba_verification; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ba_verification (
    id text NOT NULL,
    identifier text NOT NULL,
    value text NOT NULL,
    "expiresAt" timestamp without time zone NOT NULL,
    "createdAt" timestamp without time zone DEFAULT now() NOT NULL,
    "updatedAt" timestamp without time zone DEFAULT now() NOT NULL
);


--
-- Name: banners; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.banners (
    banner_id integer NOT NULL,
    title character varying(255),
    file_path character varying(500),
    is_active boolean DEFAULT true,
    created_at timestamp without time zone DEFAULT now(),
    updated_at timestamp without time zone DEFAULT now(),
    description text,
    image_media_id integer,
    link_url character varying(255),
    order_index integer DEFAULT 0,
    active boolean DEFAULT true
);


--
-- Name: banners_banner_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.banners_banner_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: banners_banner_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.banners_banner_id_seq OWNED BY public.banners.banner_id;


--
-- Name: categories; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.categories (
    category_id integer NOT NULL,
    name character varying(100) NOT NULL,
    slug character varying(100) NOT NULL,
    description text,
    parent_category_id integer,
    created_at timestamp without time zone DEFAULT now(),
    updated_at timestamp without time zone DEFAULT now()
);


--
-- Name: categories_category_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.categories_category_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: categories_category_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.categories_category_id_seq OWNED BY public.categories.category_id;


--
-- Name: conversations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.conversations (
    id bigint NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    full_name text NOT NULL,
    email text,
    phone text,
    subject text NOT NULL,
    message text NOT NULL,
    source_node text,
    status text DEFAULT 'unread'::text NOT NULL,
    ip_address inet,
    closed_at timestamp with time zone,
    assigned_to integer,
    visitor_token text,
    CONSTRAINT conversations_status_check CHECK ((status = ANY (ARRAY['open'::text, 'assigned'::text, 'closed'::text])))
);


--
-- Name: chat_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.conversations ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.chat_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: chat_messages; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.chat_messages (
    id bigint NOT NULL,
    conversation_id bigint NOT NULL,
    sender_type text NOT NULL,
    content text NOT NULL,
    is_read boolean DEFAULT false NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    sender_id integer,
    attachment_url text,
    attachment_type text,
    attachment_size integer,
    CONSTRAINT chat_messages_attachment_size_check CHECK (((attachment_size IS NULL) OR (attachment_size <= 10485760))),
    CONSTRAINT chat_messages_attachment_type_check CHECK (((attachment_type IS NULL) OR (attachment_type = ANY (ARRAY['image/jpeg'::text, 'image/png'::text, 'image/webp'::text, 'application/pdf'::text])))),
    CONSTRAINT chat_messages_sender_type_check CHECK ((sender_type = ANY (ARRAY['visitor'::text, 'agent'::text])))
);

ALTER TABLE ONLY public.chat_messages REPLICA IDENTITY FULL;


--
-- Name: chat_messages_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.chat_messages_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: chat_messages_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.chat_messages_id_seq OWNED BY public.chat_messages.id;


--
-- Name: csm_response_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.csm_response_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: csm_response_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.csm_response_id_seq OWNED BY public.csm_response.id;


--
-- Name: transparency; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.transparency (
    document_id integer NOT NULL,
    category public.disclosure_category NOT NULL,
    title character varying(500) NOT NULL,
    date_passed date,
    document_path text,
    status character varying(10) DEFAULT 'active'::character varying NOT NULL,
    uploaded_by integer,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    is_archived boolean DEFAULT false NOT NULL,
    archived_at timestamp with time zone,
    CONSTRAINT disclosure_documents_status_check CHECK (((status)::text = ANY ((ARRAY['active'::character varying, 'repealed'::character varying])::text[])))
);


--
-- Name: disclosure_documents_document_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.disclosure_documents_document_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: disclosure_documents_document_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.disclosure_documents_document_id_seq OWNED BY public.transparency.document_id;


--
-- Name: epacd_rate_limit; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.epacd_rate_limit (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    ip_address text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: events; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.events (
    event_id integer NOT NULL,
    title character varying(255) NOT NULL,
    description text,
    start_date timestamp without time zone,
    end_date timestamp without time zone,
    location character varying(255),
    created_at timestamp without time zone DEFAULT now(),
    updated_at timestamp without time zone DEFAULT now()
);


--
-- Name: events_event_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.events_event_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: events_event_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.events_event_id_seq OWNED BY public.events.event_id;


--
-- Name: faqs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.faqs (
    faq_id integer NOT NULL,
    question text NOT NULL,
    answer text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: faqs_faq_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.faqs_faq_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: faqs_faq_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.faqs_faq_id_seq OWNED BY public.faqs.faq_id;


--
-- Name: forms; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.forms (
    id bigint NOT NULL,
    title text NOT NULL,
    date_issued date,
    file_url text,
    status text DEFAULT 'active'::text,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    category text,
    is_archived boolean DEFAULT false NOT NULL,
    archived_at timestamp with time zone,
    CONSTRAINT forms_status_check CHECK ((status = ANY (ARRAY['active'::text, 'repealed'::text])))
);


--
-- Name: forms_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.forms_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: forms_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.forms_id_seq OWNED BY public.forms.id;


--
-- Name: map; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.map (
    id text NOT NULL,
    name text NOT NULL,
    lat double precision,
    lng double precision,
    address text,
    contact text,
    hours text,
    image text,
    sort_order integer DEFAULT 0,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    offices text[] DEFAULT '{}'::text[] NOT NULL
);


--
-- Name: TABLE map; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.map IS 'City office locations shown on the public Explore map.';


--
-- Name: COLUMN map.offices; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.map.offices IS 'IDs of other map rows located inside this destination (e.g. offices inside a building). Those rows are hidden as separate markers and shown instead in a dropdown on this destination''s sidebar.';


--
-- Name: media; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.media (
    media_id integer NOT NULL,
    file_path character varying(500) NOT NULL,
    media_type character varying(20),
    caption text,
    uploaded_by integer,
    related_article_id integer,
    related_event_id integer,
    related_banner_id integer,
    order_index integer DEFAULT 0,
    created_at timestamp without time zone DEFAULT now(),
    updated_at timestamp without time zone DEFAULT now(),
    CONSTRAINT media_media_type_check CHECK (((media_type)::text = ANY ((ARRAY['image'::character varying, 'video'::character varying, 'audio'::character varying])::text[])))
);


--
-- Name: media_media_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.media_media_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: media_media_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.media_media_id_seq OWNED BY public.media.media_id;


--
-- Name: offices; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.offices (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    sector public.sector_id NOT NULL,
    name text NOT NULL,
    head text DEFAULT 'N/A'::text NOT NULL,
    contact_info jsonb DEFAULT '{}'::jsonb NOT NULL,
    address text DEFAULT 'N/A'::text NOT NULL,
    sort_order integer DEFAULT 0 NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    slug text NOT NULL,
    services text[] DEFAULT '{}'::text[],
    office_no integer
);


--
-- Name: publications; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.publications (
    publication_id integer NOT NULL,
    filename character varying(255) NOT NULL,
    file_path character varying(500) NOT NULL,
    uploaded_by integer,
    created_at timestamp without time zone DEFAULT now(),
    updated_at timestamp without time zone DEFAULT now(),
    is_archived boolean DEFAULT false NOT NULL,
    archived_at timestamp with time zone
);


--
-- Name: publications_publication_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.publications_publication_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: publications_publication_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.publications_publication_id_seq OWNED BY public.publications.publication_id;


--
-- Name: service_standard; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.service_standard (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    description text NOT NULL,
    order_index integer NOT NULL,
    file_path text,
    "timestamp" timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: services; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.services (
    service_id integer NOT NULL,
    name character varying(255) NOT NULL,
    slug character varying(255) NOT NULL,
    description text,
    requirements text,
    fees text,
    processing_time character varying(100),
    online_application_url character varying(255),
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: services_service_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.services_service_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: services_service_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.services_service_id_seq OWNED BY public.services.service_id;


--
-- Name: tourism; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.tourism (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    name text NOT NULL,
    tagline text NOT NULL,
    date text,
    href text NOT NULL,
    image text,
    category text DEFAULT 'festival'::text NOT NULL,
    sort_order integer DEFAULT 0 NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT tourism_category_check CHECK ((category = ANY (ARRAY['festival'::text, 'program'::text])))
);


--
-- Name: TABLE tourism; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.tourism IS 'City highlight cards shown in the Tourism section (festivals, programs, portals).';


--
-- Name: COLUMN tourism.image; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.tourism.image IS 'Filename only, e.g. "coco-festival.png" — stored in the "media" storage bucket under tourism/.';


--
-- Name: COLUMN tourism.category; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.tourism.category IS 'Drives the card''s icon + gradient preset in the frontend: festival | program.';


--
-- Name: user_accounts; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.user_accounts (
    user_id integer NOT NULL,
    username character varying(100) NOT NULL,
    password_hash character varying(255) NOT NULL,
    role character varying(50) DEFAULT 'uploader'::character varying NOT NULL,
    is_active boolean DEFAULT true,
    last_login timestamp without time zone,
    created_at timestamp without time zone DEFAULT now() NOT NULL,
    updated_at timestamp without time zone DEFAULT now() NOT NULL,
    permissions text[] DEFAULT '{}'::text[] NOT NULL,
    ba_user_id text,
    CONSTRAINT valid_permissions CHECK ((permissions <@ ARRAY['dashboard'::text, 'banners'::text, 'news'::text, 'transparency'::text, 'downloadable-forms'::text, 'publications'::text, 'chatbot'::text, 'csm'::text, 'categories'::text, 'activity-logs'::text, 'user-management'::text]))
);


--
-- Name: user_accounts_user_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.user_accounts_user_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: user_accounts_user_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.user_accounts_user_id_seq OWNED BY public.user_accounts.user_id;


--
-- Name: articles article_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.articles ALTER COLUMN article_id SET DEFAULT nextval('public.articles_article_id_seq'::regclass);


--
-- Name: audit_log log_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.audit_log ALTER COLUMN log_id SET DEFAULT nextval('public.audit_logs_log_id_seq'::regclass);


--
-- Name: banners banner_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.banners ALTER COLUMN banner_id SET DEFAULT nextval('public.banners_banner_id_seq'::regclass);


--
-- Name: categories category_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.categories ALTER COLUMN category_id SET DEFAULT nextval('public.categories_category_id_seq'::regclass);


--
-- Name: chat_messages id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.chat_messages ALTER COLUMN id SET DEFAULT nextval('public.chat_messages_id_seq'::regclass);


--
-- Name: csm_response id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.csm_response ALTER COLUMN id SET DEFAULT nextval('public.csm_response_id_seq'::regclass);


--
-- Name: events event_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.events ALTER COLUMN event_id SET DEFAULT nextval('public.events_event_id_seq'::regclass);


--
-- Name: faqs faq_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.faqs ALTER COLUMN faq_id SET DEFAULT nextval('public.faqs_faq_id_seq'::regclass);


--
-- Name: forms id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.forms ALTER COLUMN id SET DEFAULT nextval('public.forms_id_seq'::regclass);


--
-- Name: media media_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.media ALTER COLUMN media_id SET DEFAULT nextval('public.media_media_id_seq'::regclass);


--
-- Name: publications publication_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.publications ALTER COLUMN publication_id SET DEFAULT nextval('public.publications_publication_id_seq'::regclass);


--
-- Name: services service_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.services ALTER COLUMN service_id SET DEFAULT nextval('public.services_service_id_seq'::regclass);


--
-- Name: transparency document_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.transparency ALTER COLUMN document_id SET DEFAULT nextval('public.disclosure_documents_document_id_seq'::regclass);


--
-- Name: user_accounts user_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_accounts ALTER COLUMN user_id SET DEFAULT nextval('public.user_accounts_user_id_seq'::regclass);


--
-- Data for Name: about_us; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.about_us (photo_id, file_path, caption, created_at, updated_at) FROM stdin;
6c683bbc-2a35-4c0d-9ef0-f72abc61fd5c	about-us/bonifacio-monument.webp	The Andres Bonifacio Monument	2026-05-12 01:26:48.221543+00	2026-05-13 05:22:42.121663+00
0b7a253a-6809-4ee1-81cc-056a4c4e5616	about-us/hagdang-bato.webp	Hagdang Bato	2026-05-12 01:26:48.221543+00	2026-05-13 05:27:21.602093+00
545933de-b4cf-44af-be59-637b25e943f8	about-us/city-hall.webp	City Hall of San Pablo	2026-05-12 01:26:48.221543+00	2026-05-13 05:27:24.51476+00
595e5b4a-59e2-420b-b7f1-2304a66de19c	about-us/sampalok-lake.webp	Sampaloc Lake	2026-05-12 01:26:48.221543+00	2026-05-13 05:27:28.192706+00
6aea729b-2739-4e5f-8223-80892d314f25	about-us/welcome-sanpablo.webp	Welcome to San Pablo City	2026-05-12 00:44:09.193834+00	2026-05-13 05:27:30.912847+00
e0544fe5-4f30-4654-98d5-3a14fb037949	about-us/cathedral.webp	Saint Paul the First Hermit Cathedral	2026-05-12 01:26:48.221543+00	2026-05-13 05:27:33.602008+00
\.


--
-- Data for Name: articles; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.articles (article_id, title, slug, excerpt, body, featured_media_id, category_id, status, published_at, created_at, updated_at, author) FROM stdin;
43	PARANGAL KAY MAYOR NAJIE AY PARANGAL SA TAUMBAYAN	parangal-kay-mayor-najie-ay-parangal-sa-taumbayan	"Ang PARANGAL na aking natanggap bilang kasapi ng Mayors for Good Governance ay bunga ng malakas na pagtitiwala at supporta ng TAUMBAYAN at mga kawani ng Pamahalaang Lungsod. \nSa pamamagitan po ninyo at unti-unti nating naibabalik ang San Pablo bilang  pangunahing Lungsod.\nIpagpatuloy po natin ang pagbabago at kaunlaran.\nMARAMING SALAMAT PO!"\n\n- MAYOR NAJIE	"Ang PARANGAL na aking natanggap bilang kasapi ng Mayors for Good Governance ay bunga ng malakas na pagtitiwala at supporta ng TAUMBAYAN at mga kawani ng Pamahalaang Lungsod. \n\nSa pamamagitan po ninyo at unti-unti nating naibabalik ang San Pablo bilang  pangunahing Lungsod.\n\nIpagpatuloy po natin ang pagbabago at kaunlaran.\nMARAMING SALAMAT PO!"\n\n- MAYOR NAJIE	94	13	published	2026-06-25 03:58:51.133	2026-06-25 03:58:51.133	2026-07-10 02:50:52.802612	40
39	ALAMINOS–SAN PABLO BYPASS ROAD, AAKSYUNAN NA	alaminos-san-pablo-bypass-road-aaksyunan-na	Nagkaroon ng panibagong pag-asa ang matagal nang nakabimbing Alaminos–San Pablo Bypass Road matapos personal na inspeksyunin ni Department of Public Works and Highways (DPWH) Secretary Vince Dizon ang proyekto, sa kahilingan ni San Pablo City Mayor Najie B. Gapangada.	Nagkaroon ng panibagong pag-asa ang matagal nang nakabimbing Alaminos–San Pablo Bypass Road matapos personal na inspeksyunin ni Department of Public Works and Highways (DPWH) Secretary Vince Dizon ang proyekto, sa kahilingan ni San Pablo City Mayor Najie B. Gapangada.\n\nKasama sina DPWH Regional Director, Engr. Carolina C. Pastrana, Mayor Najie  at Alaminos Mayor Eric Lopez at Vice Mayor Victor Mitra, binisita ni DPWH Secretary Dizon ang kasalukuyang kalagayan ng bypass road at ang mga natitirang balakid sa pagpapatapos nito, kabilang ang mga usapin sa right-of-way na naging dahilan ng matagal na pagkaantala ng proyekto.\n\nAyon kay Mayor Najie, mahalagang maipagpatuloy at makumpleto ang bypass road upang mabawasan ang pagsisikip ng trapiko at mapabilis ang biyahe ng mga motorista na bumibiyahe sa pagitan ng Laguna, Quezon, at mga karatig na lalawigan.\n\nSi Mayor Eric ay nagpahayag din ng suporta sa pagpapatuloy ng proyekto bilang mahalagang imprastraktura para sa pag-unlad ng rehiyon.\n\nInaasahang magiging daan ang isinagawang pagbisita at pagsusuri upang mapabilis ang pagresolba sa mga natitirang isyu at tuluyang maisakatuparan ang proyektong matagal nang hinihintay ng mga residente at mga biyahero sa lalawigan.	92	15	published	2026-06-11 03:39:15.243	2026-06-11 03:39:15.243	2026-07-10 02:50:52.802612	40
45	LIBRENG BIGAS SA MGA SOLO PARENT NG SAN PABLO CITY 	libreng-bigas-sa-mga-solo-parent-ng-san-pablo-city	(San Pablo City, Hunyo 26, 2026) – Ang San Pablo City Social Welfare and Development Office (CSWDO), kasama ang Laguna Provincial Social Welfare and Development Office (PSWDO), ay nagkaroon ng 1st and 2nd Cycle Rice Distribution sa Evacuation Center, Brgy. San Gregorio, San Pablo City.	(San Pablo City, Hunyo 26, 2026) – Ang San Pablo City Social Welfare and Development Office (CSWDO), kasama ang Laguna Provincial Social Welfare and Development Office (PSWDO), ay nagkaroon ng 1st and 2nd Cycle Rice Distribution sa Evacuation Center, Brgy. San Gregorio, San Pablo City.\n\nMahigit 650 Registered Solo Parent mula sa 80 barangay ang nabigyan ng tig-20 kilong bigas. Nagbigay ng mensahe ang kinatawan ni Governor Sol Aragones, si Vice Mayor ng Rizal, Laguna Antonino A. Aurelio, DPA. Kasama rin ang OIC ng AICS Division sa ilalim ng PSWDO na si G. Paul Erick Ubaldo.  \n\nAng libreng bigas ay bahagi ng programa nina Mayor Najie B. Gapangada at Governor Sol Aragones upang matulungan ang mga Solo Parent. (Wilbert Ociana, CIO News and Public Affairs)	96	\N	published	2026-06-30 02:35:51.186	2026-06-30 02:35:51.186	2026-07-10 02:50:52.802612	40
35	PHILHEALTH YAKAP, IPINAKILALA SA LIGA NG MGA BARANGAY NG SAN PABLO	philhealth-yakap-ipinakilala-sa-liga-ng-mga-barangay-ng-san-pablo	Upang mapadali ang pagpaparehistro at agarang pag-avail ng mga benepisyo, hinihikayat ng City Health Office (CHO) ang mga mamamayan na magtungo sa mga accredited government health facilities tulad ng mga Rural Health Unit sa mga barangay ng Bagong Pook, II-D, Concepcion, Del Remedio, Sta. Maria, at Sto. Cristo. Magbibigay naman ang CHO ng iskedyul ng pagbaba sa bawat barangay upang mas maraming mamamayan ang makapagparehistro at makinabang sa programang PhilHealth YAKAP. (Nancy Vidal, CIO)	Ipinaliwanag ni Dr. Mercydina Caponpon, San Pablo City Health Officer, ang programang PhilHealth YAKAP sa pagpupulong ng Liga ng mga Barangay noong Mayo 26 bilang bahagi ng kampanya ng Pamahalaang Lungsod na palawakin ang pamayanang naaabot ng serbisyong pangkalusugan. Ito ay bahagi ng programang TEK (Trabaho, Edukasyon at Kalusugan) ni Mayor Najie B. Gapangada. \n\nAyon kay Dr. Caponpon, layunin ng PhilHealth YAKAP na matiyak na ang bawat Pilipino ay may pagkakataong makatanggap ng kinakailangang serbisyong medikal upang maiwasan ang paglala ng mga karamdaman. \n\nKabilang sa mga benepisyong maaaring mapakinabangan ay ang primary care check-up, mga laboratory examination, kinakailangang gamot, at cancer screening tests ayon sa rekomendasyon ng doktor. Ang mga serbisyong ito ay maaaring makuha sa mga accredited health facilities sa buong bansa. \n\nIpinaliwanag din ni Dr. Caponpon ang mga hakbang upang makapag-avail ng programa. Kailangan munang tiyakin ng miyembro na aktibo ang kanyang PhilHealth membership at may PhilHealth Identification Number (PIN). Maaaring piliin ang YAKAP PhilHealth provider sa pamamagitan ng eGovPH App, PhilHealth Member Portal, o sa pinakamalapit na tanggapan ng PhilHealth. \n\nKasunod nito, kinakailangang sumailalim sa First Patient Encounter (FPE) para sa medical history taking, health screening, at health education. Pipirma rin ang miyembro sa kaukulang form bilang pagsang-ayon sa patuloy na pangangalaga ng napiling YAKAP clinic. Ang regular na konsultasyon ay mahalaga upang mabigyan ng reseta para sa gamot, referral para sa laboratoryo o cancer screening kung kinakailangan, at masubaybayan ang kalagayan ng pasyente sa pamamagitan ng follow-up check-up. \n\nUpang mapadali ang pagpaparehistro at agarang pag-avail ng mga benepisyo, hinihikayat ng City Health Office (CHO) ang mga mamamayan na magtungo sa mga accredited government health facilities tulad ng mga Rural Health Unit sa mga barangay ng Bagong Pook, II-D, Concepcion, Del Remedio, Sta. Maria, at Sto. Cristo. Magbibigay naman ang CHO ng iskedyul ng pagbaba sa bawat barangay upang mas maraming mamamayan ang makapagparehistro at makinabang sa programang PhilHealth YAKAP. (Nancy Vidal, CIO)\n	85	13	published	2026-06-05 03:21:55.863	2026-06-05 03:21:55.863	2026-07-10 02:50:52.802612	40
44	6,000 MAGSASAKA NG SAN PABLO CITY, MAKIKINABANG SA ACCIDENT AND DISMEMBERMENT INSURANCE PROGRAM	6-000-magsasaka-ng-san-pablo-city-makikinabang-sa-accident-and-dismemberment-insurance-program	Sa patuloy na pagsusulong ng kapakanan ng mga magsasaka, lumagda ang Pamahalaang Lungsod ng San Pablo sa pamumuno ni Mayor Arcadio “Najie” F. Gapangada Jr. at ang Philippine Crop Insurance Corporation (PCIC) sa isang Memorandum of Agreement (MOA) para sa pagpapatupad ng Accident and Dismemberment Insurance Program.	Sa patuloy na pagsusulong ng kapakanan ng mga magsasaka, lumagda ang Pamahalaang Lungsod ng San Pablo sa pamumuno ni Mayor Arcadio “Najie” F. Gapangada Jr. at ang Philippine Crop Insurance Corporation (PCIC) sa isang Memorandum of Agreement (MOA) para sa pagpapatupad ng Accident and Dismemberment Insurance Program.\n\nSa ilalim ng kasunduang ito, tinatayang 6,000 benepisyaryo mula sa lungsod ang mabibigyan ng insurance coverage na magsisilbing proteksiyon laban sa mga hindi inaasahang aksidente.\n\nAng Accident and Dismemberment Insurance ay nagbibigay ng benepisyong pinansyal sa mga magsasaka sakaling sila ay pumanaw o magkaroon ng permanenteng kapansanan dulot ng aksidente. \n\nLayunin ng programa na mapagaan ang pinansyal na pasanin ng mga benepisyaryo at kanilang pamilya sa oras ng pangangailangan.\n\nIpinakikita ng inisyatibong ito ang patuloy na malasakit ng Pamahalaang Lungsod at ng PCIC sa pagpapalakas ng seguridad at kapakanan ng sektor ng agrikultura, bilang pagkilala sa mahalagang papel ng mga magsasaka sa pag-unlad ng San Pablo City.	95	15	published	2026-06-30 02:33:19.32	2026-06-30 02:33:19.32	2026-07-10 02:50:52.802612	40
38	SPC VOLLEYBALL TEAM, KINILALA NG LGU	spc-volleyball-team-kinilala-ng-lgu	Binigyang-diin ng alkalde ang kahalagahan ng patuloy na pagpapalakas ng mga programang pangpalakasan sa lungsod upang higit pang mahubog ang kakayahan ng mga kabataang atleta at maitaguyod ang kultura ng kahusayan sa larangan ng sports sa San Pablo. (Aera Diaz, CIO)	(San Pablo City - Hunyo 8, 2026) - Kinilala sa isinagawang programa ng pagtataas ng watawat ngayong araw sa Pamana Hall ang Men's at Women's Volleyball Team ng San Pablo Colleges matapos nilang masungkit ang kampeonato sa 1st LGU Inter-Collegiate Volleyball Tournament na inorganisa ng San Pablo City Sports Office.\n\nNilahukan ang nasabing torneo ng iba't ibang kolehiyo sa Lungsod ng San Pablo, kabilang ang Laguna State Polytechnic University (LSPU), Lyceum de San Pablo, STI College San Pablo, at CARD MRI Development Institute, Inc. – San Pablo (CMDI San Pablo).\n\nSa kanyang mensahe, binati rin ni Mayor Najie B. Gapangada si Filipino tennis sensation Alexandra Eala at ang kanyang pamilya matapos nitong makamit ang kampeonato sa katatapos lamang na Lexus Birmingham Open 2026.\n\nBinigyang-diin ng alkalde ang kahalagahan ng patuloy na pagpapalakas ng mga programang pangpalakasan sa lungsod upang higit pang mahubog ang kakayahan ng mga kabataang atleta at maitaguyod ang kultura ng kahusayan sa larangan ng sports sa San Pablo. (Aera Diaz, CIO)	88	\N	published	2026-06-08 03:35:11.59	2026-06-08 03:35:11.59	2026-07-10 02:50:52.802612	40
41	CALABARZON STRENGTHENS EARTHQUAKE READINESS THROUGH FULL-SCALE NSED EXERCISE IN SAN PABLO CITY	calabarzon-strengthens-earthquake-readiness-through-full-scale-nsed-exercise-in-san-pablo-city	As part of strengthening the preparedness and response capabilities of local government units in CALABARZON, the Office of Civil Defense (OCD) CALABARZON facilitated the conduct of the 2nd Quarter Nationwide Simultaneous Earthquake Drill (NSED) on 18 June 2026, with the City Government of San Pablo, Laguna serving as the Regional Ceremonial Venue for the full-scale exercise.	As part of strengthening the preparedness and response capabilities of local government units in CALABARZON, the Office of Civil Defense (OCD) CALABARZON facilitated the conduct of the 2nd Quarter Nationwide Simultaneous Earthquake Drill (NSED) on 18 June 2026, with the City Government of San Pablo, Laguna serving as the Regional Ceremonial Venue for the full-scale exercise.\nThe drill simulated a magnitude 6.9 earthquake that triggered multiple emergency scenarios, including collapsed structures, mass casualty incidents, water rescue operations, traffic management challenges, and the activation of evacuation centers. The exercise tested the interoperability of response agencies, activation of the Mobile Emergency Operations Center (EOC), Incident Management Team (IMT), response clusters, and emergency response protocols in a complex disaster setting.\n\nParticipating agencies and responders demonstrated coordinated actions in search, rescue, medical response, emergency communications, and incident command operations. The exercise highlighted the importance of a whole-of-government and whole-of-society approach in managing emergencies and ensuring the safety of communities during disasters.\n\nIn his message, OCD CALABARZON Officer-in-Charge Reyan Derrick C. Marquez emphasized that the purpose of the drill is to continuously strengthen and capacitate local government units down to the barangay level in disaster preparedness and response. He also expressed his gratitude to the City Government of San Pablo and all participating agencies for their commitment and active support in promoting a culture of preparedness, reminding everyone that resilience begins with readiness and coordinated action.\n\nPhoto credits to: Cio San Pablo 	91	\N	published	2026-06-18 03:49:05.465	2026-06-18 03:49:05.465	2026-07-10 02:50:52.802612	40
42	MAYOR NAJIE, SUPORTADO NG NETIZENS SA PANAWAGANG TAPUSIN ANG SAN PABLO-ALAMINOS BYPASS ROAD	mayor-najie-suportado-ng-netizens-sa-panawagang-tapusin-ang-san-pablo-alaminos-bypass-road	SAN PABLO CITY, Laguna — Nagpahayag ng suporta ang maraming residente at netizens kay San Pablo City Mayor Najie B. Gapangada matapos nitong himukin ang Department of Public Works and Highways (DPWH) na pabilisin ang pagkumpleto ng matagal nang nakabinbing San Pablo-Alaminos Bypass Road Project.	SAN PABLO CITY, Laguna — Nagpahayag ng suporta ang maraming residente at netizens kay San Pablo City Mayor Najie B. Gapangada matapos nitong himukin ang Department of Public Works and Highways (DPWH) na pabilisin ang pagkumpleto ng matagal nang nakabinbing San Pablo-Alaminos Bypass Road Project.\n\nNoong Hunyo 8, sa pamamagitan ng national media, ay nanawagan si Mayor Najie kay DPWH Secretary Vince Dizon na tugunan ang problema. Kinabukasan, kasunod ng panawagan ng alkalde, ay nagsagawa ng pagbisita sa San Pablo City si Secretary Dizon kasama ang mga opisyal ng DPWH Region IV-A upang suriin ang kalagayan ng proyekto at talakayin ang mga kinakailangang hakbang para sa pagpapatuloy nito.\n\n Sa mga nakalipas na araw, umani ng positibong reaksiyon sa social media ang alkalde mula sa iba't ibang sektor ng komunidad dahil sa kanyang paninindigan na maisakatuparan ang proyekto, na matagal nang itinuturing na mahalagang solusyon sa lumalalang suliranin ng trapiko sa lungsod.\n\nAyon sa mga netizens, malaki ang maitutulong ng bypass road sa pagpapagaan ng daloy ng sasakyan at pagbibigay ng alternatibong ruta para sa mga motorista. Inaasahan din na mapapabilis nito ang transportasyon ng mga produkto at serbisyo. Ito ay makapag-aambag sa paglago ng ekonomiya ng San Pablo City at mga kalapit na bayan.\n\nMarami rin ang nagpahayag ng pag-asa na sa pamamagitan ng mas pinaigting na koordinasyon sa pagitan ng lokal na pamahalaan at ng DPWH ay mas mapapabilis ang pagpapatapos ng proyekto.\n\nBinigyang-diin ni Mayor Najie na ang San Pablo Bypass Road ay isang mahalagang imprastraktura na magdudulot ng pangmatagalang benepisyo sa mga residente, motorista, at negosyo sa lugar. Aniya, ang proyekto ay makatutulong sa pagpapabuti ng transportasyon at sa pagpapalakas ng kabuuang kaunlaran ng lungsod sa pamamagitan ng mabilis na pagpasok ng mga investors.\n\nNagpasalamat ang alkalde kay Pangulong Bongbong Marcos at Secretary Dizon sa mabilis na pagtugon sa hinaing ng taumbayan.\n\nPatuloy namang umaasa ang publiko na magiging daan ang mga inisyatibong ito upang maisakatuparan ang matagal nang inaabangang bypass road. (CIO News and Public Affairs)	93	\N	published	2026-06-22 03:54:30.097	2026-06-22 03:54:30.097	2026-07-10 02:50:52.802612	40
34	28 PWD SA SAN PABLO, TUMANGGAP NG MOBILITY DEVICES	28-pwd-sa-san-pablo-tumanggap-ng-mobility-devices	Bilang bahagi ng pagtataguyod sa kapakanan ng mga Person with Disability (PWDs), 28 benepisyaryo ang nabigyan ng iba't ibang mobility devices tulad ng prosthesis, braces, at customized wheelchairs noong Mayo 22, 2026 sa San Pablo City General Hospital. Ang tulong sa mga PWD ay bahagi ng programa ni Mayor Najie B. Gapangada na maging kabalikat ang pribadong sektor upang matulungan ang mga nangangailangan.	Bilang bahagi ng pagtataguyod sa kapakanan ng mga Person with Disability (PWDs), 28 benepisyaryo ang nabigyan ng iba't ibang mobility devices tulad ng prosthesis, braces, at customized wheelchairs noong Mayo 22, 2026 sa San Pablo City General Hospital. Ang tulong sa mga PWD ay bahagi ng programa ni Mayor Najie B. Gapangada na maging kabalikat ang pribadong sektor upang matulungan ang mga nangangailangan.\n\nNaisakatuparan ang programa sa pangunguna ng Alpha Phi Omega (APO) Laguna Chapter, APO San Pablo sa pamumuno ni Joseph Ciolo, APO Nagcarlan sa pangunguna ni Jasmin Salamat, CIAP, San Pablo City General Hospital, City Social Welfare and Development Office, at PBF Prosthesis and Brace Center sa pangunguna ni G. Fernando F. Santos, Presidential Action Center (PACe), kabalikat ang Persons with Disability Affairs Office (PDAO) sa pamumuno ni Gng. Jemaima Adao.\n\nLubos naman ang pasasalamat ng mga tumanggap ng mobility devices dahil malaking tulong ang mga ito upang maging mas madali ang kanilang pang-araw-araw na gawain at magkaroon ng higit na kumpiyansa at kalayaan sa pagkilos.\n\nNagbigay ng mensahe si Deputy Administrator Paolo Jose C. Lopez, hepe ng Indigency Program, bilang kinatawan ni Mayor Najie B. Gapangada. Sa kanyang pahayag, tiniyak niya ang patuloy na suporta ng Pamahalaang Lungsod para sa sektor ng mga PWD at binigyang-diin ang hangarin ni Mayor Najie na magpatupad ng mga programang makatutulong sa kanilang pangangailangan at kapakanan. Ang proyetong pangkalusugan para sa mga PWD ay bahagi ng Programang TEK (Trabaho, Edukasyon at Kalusugan) ni Mayor Najie. (CIO, Dean Almanza)	84	\N	published	2026-06-01 03:17:07.984	2026-06-01 03:17:07.984	2026-07-10 02:50:52.802612	40
40	11,359 FOOD PACKS, NAIPAMAHAGI SA MGA PWD AT SOLO PARENT SA SAN PABLO CITY	11-359-food-packs-naipamahagi-sa-mga-pwd-at-solo-parent-sa-san-pablo-city	Umabot na 11,359 food packs ang naipamahagi ng Office of Barangay Affairs ng Pamahalaang Lungsod ng San Pablo mula Mayo 29 hanggang Hunyo 15, 2026 para sa mga validated beneficiaries na mga Persons with Disability (PWD) at Solo Parent, batay sa pinakahuling ulat ng tanggapan. Ang pamamahagi ay bahagi ng programa ni Mayor Najie B. Gapangada para matulungan ang mga mahihirap.	Umabot na 11,359 food packs ang naipamahagi ng Office of Barangay Affairs ng Pamahalaang Lungsod ng San Pablo mula Mayo 29 hanggang Hunyo 15, 2026 para sa mga validated beneficiaries na mga Persons with Disability (PWD) at Solo Parent, batay sa pinakahuling ulat ng tanggapan. Ang pamamahagi ay bahagi ng programa ni Mayor Najie B. Gapangada para matulungan ang mga mahihirap.\n\nIsinagawa ang pamamahagi  upang mabigyan ng ayuda ang mga sektor na nangangailangan ng suporta. Ang opisyal na listahan ng mga beneficiaries ay batay sa datos na ibinigay at beripikado ng City Social Welfare and Development Office.\nNaitala ang pinakamataas na bilang ng food packs noong Hunyo 4 na umabot sa 1,898 packs, habang 1,710 naman ang naipamahagi noong Hunyo 9. Sa pinakahuling distribusyon noong Hunyo 15, may karagdagang 1,051 ang naihatid sa mga kwalipikadong benepisyaryo.\n\nAyon sa Office of Barangay Affairs, patuloy ang pamamahagi ng food packs hanggang sa maabot ang lahat na verified beneficiary na kabilang sa listahan ng CSWDO.\n\nBinanggit naman ni Mayor Najie na ang programa ay sa pagsisikap ng Pamahalaang Lokal upang matiyak na makakarating ang kinakailangang tulong sa mga PWD at Solo Parent na higit na nangangailangan ng suporta ng pamahalaan. (CIO News and Public Affairs)	90	\N	published	2026-06-16 03:42:51.681	2026-06-16 03:42:51.681	2026-07-10 02:50:52.802612	40
37	LIBRENG SCHOOL SUPPLIES PARA SA MGA MAG-AARAL NG SAN PABLO	libreng-school-supplies-para-sa-mga-mag-aaral-ng-san-pablo	Nasa 1,444 mag-aaral mula Kindergarten, Grade 1 at Grade 7 sa San Cristobal Elementary School, San Cristobal Integrated High School, Sto. Angel Elementary School, Sto. Angel National High School, Paaralang Pag-ibig at Pag-asa, Prudencia Fule Memorial Elementary School, Prudencia Fule Memorial Integrated High School, at San Roque Elementary School ang nakinabang sa proyekto. 	Ang DepEd San Pablo City, kabalikat ang Pamahalaang Lungsod, ay namahagi ng school supplies sa mga  elementary students.\n\nNasa 1,444 mag-aaral mula Kindergarten, Grade 1 at Grade 7 sa San Cristobal Elementary School, San Cristobal Integrated High School, Sto. Angel Elementary School, Sto. Angel National High School, Paaralang Pag-ibig at Pag-asa, Prudencia Fule Memorial Elementary School, Prudencia Fule Memorial Integrated High School, at San Roque Elementary School ang nakinabang sa proyekto. \n\nLayunin ng pamamahagi na matulungan ang mga mahihirap na magulang.\n\nPatuloy na isinusulong ng Pamahalaang Lungsod ng San Pablo, sa tagubilin ni Mayor Najie B. Gapangada, kasama ang DepEd San Pablo City, sa pamumuno ni Dr. Gerlie Ilagan, ang mga hakbang para maitaguyod ang edukasyon para sa magandang kinabukasan ng bawat kabataan.  Ito ay bahagi ng TEK (Trabaho, Edukasyon at Kalusugan) Program ni Mayor Najie. (Wilbert Ociana, CIO)	87	\N	published	2026-06-08 03:31:54.552	2026-06-08 03:31:54.552	2026-07-10 02:50:52.802612	40
36	STAINLESS NA BASURAHAN PARA SA MAS MALINIS NA SAMPALOK LAKE	stainless-na-basurahan-para-sa-mas-malinis-na-sampalok-lake	Sa tagubilin ni Mayor Najie B. Gapangada, naglagay ang San Pablo City Solid Waste Management Office (CSWMO), sa pamumuno ni Engr Ryla Nunag, ng tatlong \nstainless steel trash bins sa mga Barangay V-A, San Lucas I, at Concepcion na nakakasakop sa paligid ng Sampalok Lake.	Sa tagubilin ni Mayor Najie B. Gapangada, naglagay ang San Pablo City Solid Waste Management Office (CSWMO), sa pamumuno ni Engr Ryla Nunag, ng tatlong \nstainless steel trash bins sa mga Barangay V-A, San Lucas I, at Concepcion na nakakasakop sa paligid ng Sampalok Lake.\n\nAng mga basurahang ito ay mayroong magkahiwalay na lalagyan para sa nabubulok at di-nabubulok na basura upang mahikayat ang bawat isa na magsagawa ng wastong paghihiwalay ng basura.\n\nInilagay ang mga ito sa mga lugar na madalas puntahan ng mga mamamayan at bisita, lalo na sa mga bahagi ng lawa na maraming kainan at matataong lugar. \n\nSa pamamagitan ng simpleng pagtatapon ng basura sa tamang lalagyan, makatutulong ang lahat sa pagpapanatili ng kalinisan at kagandahan ng ating minamahal na Sampalok Lake.\n\nAng malinis na kapaligiran ay nagsisimula sa bawat isang mamamayan. Magtapon ng tama. \n"Mag-segregate. Makiisa sa pangangalaga ng ating kalikasan." (Ulat ni Bb. Juno P. Funtanilla, DIO- CSWMO)	86	15	published	2026-06-05 03:26:03.719	2026-06-05 03:26:03.719	2026-07-10 02:50:52.802612	40
\.


--
-- Data for Name: audit_log; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.audit_log (log_id, user_id, action, entity_type, entity_id, changes, ip_address, created_at, user_agent) FROM stdin;
1553	45	CREATE	user_account	47	{"role": "staff", "username": "miso.access", "created_by": 45, "permissions": ["banners", "activity-logs"]}	\N	2026-07-27 04:03:15.816+00	\N
1584	45	FILE_UPLOAD	image	\N	{"file_path": "banners/banner-1785130034176-1j4r6gfzmkn.webp", "webpQuality": 100, "originalSizeBytes": 2051139, "convertedSizeBytes": 759774}	\N	2026-07-27 05:27:16.747+00	\N
1610	47	UPDATE	banner	42	{"changes": {"active": true, "order_index": 2}, "updated_by": 47}	\N	2026-07-28 00:09:54.278+00	\N
1643	45	CREATE	publication	27	{"filename": "CS-Form-No.-9-Revised-2025-Request-for-Publication-of-Vacant-Positions-08.10.25.pdf", "created_by": 45}	\N	2026-08-10 09:01:28.049+00	\N
1680	45	UPDATE	banner	52	{"changes": {"active": false, "order_index": 0}, "updated_by": 45}	\N	2026-09-01 06:32:51.58+00	\N
1683	45	UPDATE	banner	42	{"changes": {"active": false, "order_index": 0}, "updated_by": 45}	\N	2026-09-01 06:33:32.474+00	\N
1686	45	UPDATE	banner	43	{"changes": {"active": false, "order_index": 0}, "updated_by": 45}	\N	2026-09-01 06:33:41.758+00	\N
1715	45	CREATE	media	117	{"file_path": "https://yljsclzmrxuhejgcesiv.supabase.co/storage/v1/object/public/media/banners/banner-1788253324007-vyy7cxicfz.webp", "created_by": 45, "media_type": "image"}	\N	2026-09-01 09:02:11.453+00	\N
1405	42	LOGIN_SUCCESS	user_account	42	{"username": "cio.access"}	160.20.40.74	2026-07-09 08:27:06.316+00	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/150.0.0.0 Safari/537.36
1406	42	LOGOUT	user_account	42	{"reason": "manual"}	\N	2026-07-09 08:27:10.331+00	\N
1724	45	UPDATE	banner	57	{"changes": {"active": false, "order_index": 0}, "updated_by": 45}	\N	2026-09-01 09:02:45.772+00	\N
1410	42	LOGIN_SUCCESS	user_account	42	{"username": "cio.access"}	160.20.40.74	2026-07-09 08:28:02.031+00	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/150.0.0.0 Safari/537.36
1411	42	LOGOUT	user_account	42	{"reason": "manual"}	\N	2026-07-09 08:28:04.725+00	\N
1728	45	UPDATE	banner	54	{"changes": {"active": true, "order_index": 4}, "updated_by": 45}	\N	2026-09-01 09:03:13.468+00	\N
1729	45	UPDATE	banner	56	{"changes": {"active": true, "order_index": 3}, "updated_by": 45}	\N	2026-09-01 09:03:13.492+00	\N
1733	45	UPDATE	banner	54	{"changes": {"active": false, "order_index": 0}, "updated_by": 45}	\N	2026-09-01 09:03:21.398+00	\N
1231	\N	LOGIN_SUCCESS	user_account	40	{"username": "admin"}	111.90.199.113	2026-06-18 06:28:13.498+00	Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/149.0.0.0 Mobile Safari/537.36
1274	\N	LOGIN_FAILED	user_account	40	{"username": "admin"}	27.49.15.151	2026-06-19 12:09:22.496+00	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/149.0.0.0 Safari/537.36
1297	\N	LOGOUT	user_account	40	{"reason": "manual"}	\N	2026-06-20 11:18:59.423+00	\N
1332	\N	PASSWORD_RESET	user_account	41	{"reset_by": 40, "target_username": "miso.access"}	\N	2026-07-07 07:04:57.073+00	\N
1368	\N	CREATE	media	87	{"file_path": "https://yljsclzmrxuhejgcesiv.supabase.co/storage/v1/object/sign/media/articles/ptjukr4tm-1783481504500.webp?token=eyJraWQiOiJzdG9yYWdlLXVybC1zaWduaW5nLWtleV83NGM0Nzc4My1kNGMzLTRlNDktOWUwYy01YjJlYmIxNzA2OGQiLCJhbGciOiJIUzI1NiJ9.eyJ1cmwiOiJtZWRpYS9hcnRpY2xlcy9wdGp1a3I0dG0tMTc4MzQ4MTUwNDUwMC53ZWJwIiwic2NvcGUiOiJkb3dubG9hZCIsImlhdCI6MTc4MzQ4MTUwOCwiZXhwIjoxODE1MDE3NTA4fQ.CbPTLCDFNbEc6qjT4kOY91ARnUXgiL4gxt6tkJNjgKo", "created_by": 40, "media_type": "image"}	\N	2026-07-08 03:31:51.048+00	\N
819	\N	LOGOUT	user_account	2	{"reason": "manual"}	\N	2026-05-21 08:23:21.586+00	\N
822	\N	LOGIN_SUCCESS	user_account	2	{"username": "admin"}	::1	2026-05-21 08:23:39.484+00	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/148.0.0.0 Safari/537.36
1370	\N	STATUS_CHANGE	article	37	{"new_status": "published", "old_status": "draft"}	\N	2026-07-08 03:31:54.646+00	\N
1403	\N	PASSWORD_RESET	user_account	42	{"reset_by": 40, "target_username": "cio.access"}	\N	2026-07-09 08:26:36.779+00	\N
1408	\N	PASSWORD_RESET	user_account	42	{"reset_by": 40, "target_username": "cio.access"}	\N	2026-07-09 08:27:47.87+00	\N
1493	\N	UPDATE	faq	10	{"changes": {"answer": "8am to 5pm", "question": "Ano ang office hours ng mga opisina?"}, "updated_by": 40}	\N	2026-07-22 07:34:54.907+00	\N
1528	\N	LOGOUT	user_account	43	{"reason": "manual"}	\N	2026-07-27 02:39:50.109+00	\N
1546	46	CREATE	media	104	{"file_path": "https://yljsclzmrxuhejgcesiv.supabase.co/storage/v1/object/sign/media/banners/banner-1785124765736-zp6d710hv2.webp?token=eyJraWQiOiJzdG9yYWdlLXVybC1zaWduaW5nLWtleV83NGM0Nzc4My1kNGMzLTRlNDktOWUwYy01YjJlYmIxNzA2OGQiLCJhbGciOiJIUzI1NiJ9.eyJ1cmwiOiJtZWRpYS9iYW5uZXJzL2Jhbm5lci0xNzg1MTI0NzY1NzM2LXpwNmQ3MTBodjIud2VicCIsInNjb3BlIjoiZG93bmxvYWQiLCJpYXQiOjE3ODUxMjQ3NjYsImV4cCI6MTc4NzcxNjc2Nn0.7690BqPhEWmTNbg4AIn22Q7ZWzaJ-jeeUOir0jfHg6o", "created_by": 46, "media_type": "image"}	\N	2026-07-27 03:59:31.024+00	\N
1550	46	LOGOUT	user_account	46	{"reason": "manual"}	\N	2026-07-27 04:00:39.782+00	\N
1334	\N	LOGIN_SUCCESS	user_account	41	{"username": "miso.access"}	160.20.40.74	2026-07-07 07:05:08.909+00	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/150.0.0.0 Safari/537.36
1445	\N	UPDATE	banner	39	{"changes": {"active": false, "order_index": 0}, "updated_by": 41}	\N	2026-07-21 08:53:24.635+00	\N
1446	\N	FILE_UPLOAD	image	97	{"file_path": "https://yljsclzmrxuhejgcesiv.supabase.co/storage/v1/object/sign/media/banners/n1ilxbmbl-1784624019508.png?token=eyJraWQiOiJzdG9yYWdlLXVybC1zaWduaW5nLWtleV83NGM0Nzc4My1kNGMzLTRlNDktOWUwYy01YjJlYmIxNzA2OGQiLCJhbGciOiJIUzI1NiJ9.eyJ1cmwiOiJtZWRpYS9iYW5uZXJzL24xaWx4Ym1ibC0xNzg0NjI0MDE5NTA4LnBuZyIsInNjb3BlIjoiZG93bmxvYWQiLCJpYXQiOjE3ODQ2MjQwMTcsImV4cCI6MTgxNjE2MDAxN30.T-pjYqBvCHlW4I_gAIYRkTnOcv6ESU0weRTjuu1S3PU"}	\N	2026-07-21 08:53:41.713+00	\N
1448	\N	CREATE	banner	41	{"title": null, "created_by": 41, "image_media_id": 97}	\N	2026-07-21 08:53:42.356+00	\N
1449	\N	FILE_UPLOAD	image	98	{"file_path": "https://yljsclzmrxuhejgcesiv.supabase.co/storage/v1/object/sign/media/banners/ohpe3vrzr-1784624032897.png?token=eyJraWQiOiJzdG9yYWdlLXVybC1zaWduaW5nLWtleV83NGM0Nzc4My1kNGMzLTRlNDktOWUwYy01YjJlYmIxNzA2OGQiLCJhbGciOiJIUzI1NiJ9.eyJ1cmwiOiJtZWRpYS9iYW5uZXJzL29ocGUzdnJ6ci0xNzg0NjI0MDMyODk3LnBuZyIsInNjb3BlIjoiZG93bmxvYWQiLCJpYXQiOjE3ODQ2MjQwMzAsImV4cCI6MTgxNjE2MDAzMH0.zTbuwDAn6B_BwxNjW1PaVO5VH2DjG-UsfzJiUqrAz6c"}	\N	2026-07-21 08:53:53.202+00	\N
1554	45	LOGOUT	user_account	45	{"reason": "manual"}	\N	2026-07-27 04:03:18.346+00	\N
1555	47	LOGOUT	user_account	47	{"reason": "manual"}	\N	2026-07-27 04:03:32.83+00	\N
1585	47	FILE_UPLOAD	image	\N	{"file_path": "banners/banner-1785130134386-ee5fx5dhk5u.webp", "webpQuality": 100, "originalSizeBytes": 282190, "convertedSizeBytes": 98804}	\N	2026-07-27 05:28:54.917+00	\N
1611	47	UPDATE	banner	46	{"changes": {"active": true, "order_index": 0}, "updated_by": 47}	\N	2026-07-28 00:09:54.358+00	\N
1612	47	UPDATE	banner	52	{"changes": {"active": true, "order_index": 1}, "updated_by": 47}	\N	2026-07-28 00:09:56.177+00	\N
1644	47	UPDATE	banner	42	{"changes": {"active": false, "order_index": 0}, "updated_by": 47}	\N	2026-08-17 05:24:25.298+00	\N
1646	47	UPDATE	banner	53	{"changes": {"active": false, "order_index": 0}, "updated_by": 47}	\N	2026-08-17 05:24:37.624+00	\N
1647	47	FILE_UPLOAD	image	\N	{"file_path": "banners/banner-1786944293490-hw174coxgwd.png", "originalSizeBytes": 2520233}	\N	2026-08-17 05:24:54.686+00	\N
1649	47	CREATE	media	113	{"file_path": "https://yljsclzmrxuhejgcesiv.supabase.co/storage/v1/object/sign/media/banners/banner-1786944293490-hw174coxgwd.png?token=eyJraWQiOiJzdG9yYWdlLXVybC1zaWduaW5nLWtleV83NGM0Nzc4My1kNGMzLTRlNDktOWUwYy01YjJlYmIxNzA2OGQiLCJhbGciOiJIUzI1NiJ9.eyJ1cmwiOiJtZWRpYS9iYW5uZXJzL2Jhbm5lci0xNzg2OTQ0MjkzNDkwLWh3MTc0Y294Z3dkLnBuZyIsInNjb3BlIjoiZG93bmxvYWQiLCJpYXQiOjE3ODY5NDQyOTQsImV4cCI6MTc4OTUzNjI5NH0.mqqM0HuQsdpgjOfvPUnzJgZXTFlJol7VjKx50-KvuEY", "created_by": 47, "media_type": "image"}	\N	2026-08-17 05:24:58.237+00	\N
1650	47	CREATE	banner	56	{"title": null, "created_by": 47, "image_media_id": 113}	\N	2026-08-17 05:24:58.794+00	\N
1652	47	FILE_UPLOAD	image	114	{"file_path": "https://yljsclzmrxuhejgcesiv.supabase.co/storage/v1/object/sign/media/banners/banner-1786944307262-cnbrkmyh7nf.png?token=eyJraWQiOiJzdG9yYWdlLXVybC1zaWduaW5nLWtleV83NGM0Nzc4My1kNGMzLTRlNDktOWUwYy01YjJlYmIxNzA2OGQiLCJhbGciOiJIUzI1NiJ9.eyJ1cmwiOiJtZWRpYS9iYW5uZXJzL2Jhbm5lci0xNzg2OTQ0MzA3MjYyLWNuYnJrbXloN25mLnBuZyIsInNjb3BlIjoiZG93bmxvYWQiLCJpYXQiOjE3ODY5NDQzMDgsImV4cCI6MTc4OTUzNjMwOH0.1OBYKEl28GJs9Y4AuFhN2ElRRRR7fsKwOJwM1--c648"}	\N	2026-08-17 05:25:11.177+00	\N
1656	47	UPDATE	banner	43	{"changes": {"active": true, "order_index": 2}, "updated_by": 47}	\N	2026-08-17 05:25:40.048+00	\N
1657	47	UPDATE	banner	56	{"changes": {"active": true, "order_index": 0}, "updated_by": 47}	\N	2026-08-17 05:25:40.16+00	\N
1658	47	UPDATE	banner	53	{"changes": {"active": true, "order_index": 4}, "updated_by": 47}	\N	2026-08-17 05:25:40.279+00	\N
1232	\N	CREATE	user_account	41	{"role": "staff", "username": "editor", "created_by": 40, "permissions": ["banners"]}	\N	2026-06-18 06:30:54.412+00	\N
1275	\N	LOGIN_FAILED	user_account	40	{"username": "admin"}	27.49.15.151	2026-06-19 12:36:20.213+00	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/149.0.0.0 Safari/537.36
1276	\N	LOGIN_FAILED	user_account	40	{"username": "admin"}	27.49.15.151	2026-06-19 12:36:24.595+00	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/149.0.0.0 Safari/537.36
1298	\N	LOGIN_FAILED	user_account	40	{"username": "admin"}	49.145.9.222	2026-06-20 11:21:03.873+00	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/149.0.0.0 Safari/537.36
1301	\N	LOGIN_FAILED	user_account	40	{"username": "admin"}	49.145.9.222	2026-06-20 11:21:06.824+00	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/149.0.0.0 Safari/537.36
820	\N	LOGIN_SUCCESS	user_account	36	{"username": "chatbot"}	::1	2026-05-21 08:23:27.2+00	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/148.0.0.0 Safari/537.36
821	\N	LOGOUT	user_account	36	{"reason": "manual"}	\N	2026-05-21 08:23:36.055+00	\N
1304	\N	LOGIN_FAILED	user_account	40	{"username": "admin"}	49.145.9.222	2026-06-20 11:21:09.19+00	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/149.0.0.0 Safari/537.36
1307	\N	LOGIN_FAILED	user_account	40	{"username": "admin"}	49.145.9.222	2026-06-20 11:21:10.744+00	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/149.0.0.0 Safari/537.36
1310	\N	LOGIN_FAILED	user_account	40	{"username": "admin"}	49.145.9.222	2026-06-20 11:21:12.341+00	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/149.0.0.0 Safari/537.36
1333	\N	LOGOUT	user_account	40	{"reason": "manual"}	\N	2026-07-07 07:05:00.298+00	\N
1371	\N	FILE_UPLOAD	image	88	{"file_path": "https://yljsclzmrxuhejgcesiv.supabase.co/storage/v1/object/sign/media/articles/g4dwlmf7x-1783481701729.webp?token=eyJraWQiOiJzdG9yYWdlLXVybC1zaWduaW5nLWtleV83NGM0Nzc4My1kNGMzLTRlNDktOWUwYy01YjJlYmIxNzA2OGQiLCJhbGciOiJIUzI1NiJ9.eyJ1cmwiOiJtZWRpYS9hcnRpY2xlcy9nNGR3bG1mN3gtMTc4MzQ4MTcwMTcyOS53ZWJwIiwic2NvcGUiOiJkb3dubG9hZCIsImlhdCI6MTc4MzQ4MTcwNSwiZXhwIjoxODE1MDE3NzA1fQ.llnf1zHwCN6l2wjlQFC8iT0iLXXOj8471Tp36oNmgJo"}	\N	2026-07-08 03:35:07.666+00	\N
1373	\N	CREATE	article	38	{"slug": "spc-volleyball-team-kinilala-ng-lgu", "title": "SPC VOLLEYBALL TEAM, KINILALA NG LGU"}	\N	2026-07-08 03:35:08.534+00	\N
1404	\N	LOGOUT	user_account	40	{"reason": "manual"}	\N	2026-07-09 08:26:39.911+00	\N
1407	\N	LOGIN_SUCCESS	user_account	40	{"username": "admin.CMS"}	160.20.40.74	2026-07-09 08:27:21.116+00	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/150.0.0.0 Safari/537.36
1155	\N	CREATE	chat_message	147	{"sent_by": 37, "conversation_id": 61}	\N	2026-06-16 12:45:23.724+00	\N
1409	\N	LOGOUT	user_account	40	{"reason": "manual"}	\N	2026-07-09 08:27:49.315+00	\N
1494	\N	LOGIN_SUCCESS	user_account	40	{"username": "admin.CMS"}	160.20.40.74	2026-07-23 01:13:11.425+00	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/150.0.0.0 Safari/537.36
1532	46	LOGOUT	user_account	46	{"reason": "manual"}	\N	2026-07-27 03:07:41.771+00	\N
1529	\N	LOGOUT	user_account	43	{"reason": "manual"}	\N	2026-07-27 03:06:43.15+00	\N
1547	46	CREATE	banner	48	{"title": "test", "created_by": 46, "image_media_id": 104}	\N	2026-07-27 03:59:31.664+00	\N
1234	\N	LOGIN_SUCCESS	user_account	41	{"username": "editor"}	111.90.199.113	2026-06-18 06:31:10.34+00	Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/149.0.0.0 Mobile Safari/537.36
1453	\N	CREATE	media	99	{"file_path": "https://yljsclzmrxuhejgcesiv.supabase.co/storage/v1/object/sign/media/banners/1d7o7xdh2-1784624045292.jpg?token=eyJraWQiOiJzdG9yYWdlLXVybC1zaWduaW5nLWtleV83NGM0Nzc4My1kNGMzLTRlNDktOWUwYy01YjJlYmIxNzA2OGQiLCJhbGciOiJIUzI1NiJ9.eyJ1cmwiOiJtZWRpYS9iYW5uZXJzLzFkN283eGRoMi0xNzg0NjI0MDQ1MjkyLmpwZyIsInNjb3BlIjoiZG93bmxvYWQiLCJpYXQiOjE3ODQ2MjQwNDMsImV4cCI6MTgxNjE2MDA0M30.oYQ_mJXKLSyWDAjptNIGG8hHmAei1EXUNaJ4CUr2bDQ", "created_by": 41, "media_type": "image"}	\N	2026-07-21 08:54:06.034+00	\N
1556	47	UPDATE	banner	48	{"changes": {"active": false, "order_index": 0}, "updated_by": 47}	\N	2026-07-27 04:07:07.225+00	\N
1559	47	CREATE	media	105	{"file_path": "https://yljsclzmrxuhejgcesiv.supabase.co/storage/v1/object/sign/media/banners/banner-1785125244580-eh659hi61sj.webp?token=eyJraWQiOiJzdG9yYWdlLXVybC1zaWduaW5nLWtleV83NGM0Nzc4My1kNGMzLTRlNDktOWUwYy01YjJlYmIxNzA2OGQiLCJhbGciOiJIUzI1NiJ9.eyJ1cmwiOiJtZWRpYS9iYW5uZXJzL2Jhbm5lci0xNzg1MTI1MjQ0NTgwLWVoNjU5aGk2MXNqLndlYnAiLCJzY29wZSI6ImRvd25sb2FkIiwiaWF0IjoxNzg1MTI1MjQ3LCJleHAiOjE3ODc3MTcyNDd9.WOeopMKsPJuwme_lUKmQcT5Dfikppkymeu9UhEFzx2E", "created_by": 47, "media_type": "image"}	\N	2026-07-27 04:07:33.952+00	\N
1561	47	DELETE	banner	48	{"title": "test", "deleted_by": 47}	\N	2026-07-27 04:08:14.11+00	\N
1562	47	DELETE	banner	49	{"title": null, "deleted_by": 47}	\N	2026-07-27 04:08:19.744+00	\N
1586	47	FILE_UPLOAD	image	\N	{"file_path": "banners/banner-1785130631818-91gggfpg9v4.webp", "webpQuality": 100, "originalSizeBytes": 282190, "convertedSizeBytes": 97428}	\N	2026-07-27 05:37:13.386+00	\N
1613	47	UPDATE	banner	43	{"changes": {"active": true, "order_index": 3}, "updated_by": 47}	\N	2026-07-28 00:09:56.474+00	\N
1645	47	UPDATE	banner	43	{"changes": {"active": false, "order_index": 0}, "updated_by": 47}	\N	2026-08-17 05:24:32.506+00	\N
1648	47	FILE_UPLOAD	image	113	{"file_path": "https://yljsclzmrxuhejgcesiv.supabase.co/storage/v1/object/sign/media/banners/banner-1786944293490-hw174coxgwd.png?token=eyJraWQiOiJzdG9yYWdlLXVybC1zaWduaW5nLWtleV83NGM0Nzc4My1kNGMzLTRlNDktOWUwYy01YjJlYmIxNzA2OGQiLCJhbGciOiJIUzI1NiJ9.eyJ1cmwiOiJtZWRpYS9iYW5uZXJzL2Jhbm5lci0xNzg2OTQ0MjkzNDkwLWh3MTc0Y294Z3dkLnBuZyIsInNjb3BlIjoiZG93bmxvYWQiLCJpYXQiOjE3ODY5NDQyOTQsImV4cCI6MTc4OTUzNjI5NH0.mqqM0HuQsdpgjOfvPUnzJgZXTFlJol7VjKx50-KvuEY"}	\N	2026-08-17 05:24:58.134+00	\N
1651	47	FILE_UPLOAD	image	\N	{"file_path": "banners/banner-1786944307262-cnbrkmyh7nf.png", "originalSizeBytes": 1267778}	\N	2026-08-17 05:25:08.189+00	\N
1653	47	CREATE	media	114	{"file_path": "https://yljsclzmrxuhejgcesiv.supabase.co/storage/v1/object/sign/media/banners/banner-1786944307262-cnbrkmyh7nf.png?token=eyJraWQiOiJzdG9yYWdlLXVybC1zaWduaW5nLWtleV83NGM0Nzc4My1kNGMzLTRlNDktOWUwYy01YjJlYmIxNzA2OGQiLCJhbGciOiJIUzI1NiJ9.eyJ1cmwiOiJtZWRpYS9iYW5uZXJzL2Jhbm5lci0xNzg2OTQ0MzA3MjYyLWNuYnJrbXloN25mLnBuZyIsInNjb3BlIjoiZG93bmxvYWQiLCJpYXQiOjE3ODY5NDQzMDgsImV4cCI6MTc4OTUzNjMwOH0.1OBYKEl28GJs9Y4AuFhN2ElRRRR7fsKwOJwM1--c648", "created_by": 47, "media_type": "image"}	\N	2026-08-17 05:25:11.438+00	\N
1412	42	LOGIN_SUCCESS	user_account	42	{"username": "cio.publisher"}	160.20.40.74	2026-07-09 08:28:40.545+00	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/150.0.0.0 Safari/537.36
1654	47	CREATE	banner	57	{"title": null, "created_by": 47, "image_media_id": 114}	\N	2026-08-17 05:25:11.919+00	\N
1655	47	UPDATE	banner	57	{"changes": {"active": true, "order_index": 1}, "updated_by": 47}	\N	2026-08-17 05:25:39.876+00	\N
1659	47	UPDATE	banner	54	{"changes": {"active": true, "order_index": 5}, "updated_by": 47}	\N	2026-08-17 05:25:41.576+00	\N
1660	47	UPDATE	banner	52	{"changes": {"active": true, "order_index": 6}, "updated_by": 47}	\N	2026-08-17 05:25:41.691+00	\N
1681	45	UPDATE	banner	54	{"changes": {"active": false, "order_index": 0}, "updated_by": 45}	\N	2026-09-01 06:32:57.036+00	\N
1233	\N	LOGOUT	user_account	40	{"reason": "manual"}	\N	2026-06-18 06:31:02.369+00	\N
1277	\N	LOGIN_FAILED	user_account	40	{"username": "admin"}	209.35.161.207	2026-06-19 13:24:39.86+00	Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36
1299	\N	LOGIN_FAILED	user_account	40	{"username": "admin"}	49.145.9.222	2026-06-20 11:21:04.92+00	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/149.0.0.0 Safari/537.36
1302	\N	LOGIN_FAILED	user_account	40	{"username": "admin"}	49.145.9.222	2026-06-20 11:21:07.684+00	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/149.0.0.0 Safari/537.36
1305	\N	LOGIN_FAILED	user_account	40	{"username": "admin"}	49.145.9.222	2026-06-20 11:21:09.72+00	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/149.0.0.0 Safari/537.36
1308	\N	LOGIN_FAILED	user_account	40	{"username": "admin"}	49.145.9.222	2026-06-20 11:21:11.329+00	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/149.0.0.0 Safari/537.36
1372	\N	CREATE	media	88	{"file_path": "https://yljsclzmrxuhejgcesiv.supabase.co/storage/v1/object/sign/media/articles/g4dwlmf7x-1783481701729.webp?token=eyJraWQiOiJzdG9yYWdlLXVybC1zaWduaW5nLWtleV83NGM0Nzc4My1kNGMzLTRlNDktOWUwYy01YjJlYmIxNzA2OGQiLCJhbGciOiJIUzI1NiJ9.eyJ1cmwiOiJtZWRpYS9hcnRpY2xlcy9nNGR3bG1mN3gtMTc4MzQ4MTcwMTcyOS53ZWJwIiwic2NvcGUiOiJkb3dubG9hZCIsImlhdCI6MTc4MzQ4MTcwNSwiZXhwIjoxODE1MDE3NzA1fQ.llnf1zHwCN6l2wjlQFC8iT0iLXXOj8471Tp36oNmgJo", "created_by": 40, "media_type": "image"}	\N	2026-07-08 03:35:07.786+00	\N
1374	\N	STATUS_CHANGE	article	38	{"new_status": "published", "old_status": "draft"}	\N	2026-07-08 03:35:11.695+00	\N
1496	\N	CREATE	chat_message	263	{"sent_by": 40, "conversation_id": 125}	\N	2026-07-23 01:14:02.583+00	\N
1497	\N	CREATE	chat_message	265	{"sent_by": 40, "conversation_id": 125}	\N	2026-07-23 01:14:42.187+00	\N
1530	45	CREATE	user_account	46	{"role": "staff", "username": "miso.staff", "created_by": 45, "permissions": ["banners", "news", "transparency", "downloadable-forms", "publications", "chatbot", "categories", "activity-logs"]}	\N	2026-07-27 03:07:20.033+00	\N
1551	45	PASSWORD_RESET	user_account	41	{"reset_by": 45, "target_username": "miso.access"}	\N	2026-07-27 04:01:34.944+00	\N
1335	\N	LOGOUT	user_account	41	{"reason": "manual"}	\N	2026-07-07 07:09:37.259+00	\N
1336	\N	LOGIN_SUCCESS	user_account	41	{"username": "miso.access"}	160.20.40.74	2026-07-07 07:09:51.981+00	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/150.0.0.0 Safari/537.36
1456	\N	UPDATE	banner	43	{"changes": {"active": true, "order_index": 0}, "updated_by": 41}	\N	2026-07-21 08:55:21.369+00	\N
1458	\N	UPDATE	banner	35	{"changes": {"active": true, "order_index": 6}, "updated_by": 41}	\N	2026-07-21 08:55:21.473+00	\N
1460	\N	UPDATE	banner	37	{"changes": {"active": true, "order_index": 7}, "updated_by": 41}	\N	2026-07-21 08:55:21.572+00	\N
1461	\N	UPDATE	banner	38	{"changes": {"active": true, "order_index": 5}, "updated_by": 41}	\N	2026-07-21 08:55:22.845+00	\N
1463	\N	UPDATE	banner	39	{"changes": {"active": true, "order_index": 4}, "updated_by": 41}	\N	2026-07-21 08:55:22.969+00	\N
1466	\N	DELETE	banner	39	{"title": null, "deleted_by": 41}	\N	2026-07-21 08:56:09.919+00	\N
1469	\N	DELETE	banner	37	{"title": null, "deleted_by": 41}	\N	2026-07-21 08:56:24.012+00	\N
1557	47	FILE_UPLOAD	image	\N	{"file_path": "banners/banner-1785125244580-eh659hi61sj.webp", "webpQuality": 100, "originalSizeBytes": 2051139, "convertedSizeBytes": 736572}	\N	2026-07-27 04:07:27.301+00	\N
1558	47	FILE_UPLOAD	image	105	{"file_path": "https://yljsclzmrxuhejgcesiv.supabase.co/storage/v1/object/sign/media/banners/banner-1785125244580-eh659hi61sj.webp?token=eyJraWQiOiJzdG9yYWdlLXVybC1zaWduaW5nLWtleV83NGM0Nzc4My1kNGMzLTRlNDktOWUwYy01YjJlYmIxNzA2OGQiLCJhbGciOiJIUzI1NiJ9.eyJ1cmwiOiJtZWRpYS9iYW5uZXJzL2Jhbm5lci0xNzg1MTI1MjQ0NTgwLWVoNjU5aGk2MXNqLndlYnAiLCJzY29wZSI6ImRvd25sb2FkIiwiaWF0IjoxNzg1MTI1MjQ3LCJleHAiOjE3ODc3MTcyNDd9.WOeopMKsPJuwme_lUKmQcT5Dfikppkymeu9UhEFzx2E"}	\N	2026-07-27 04:07:33.859+00	\N
1563	47	FILE_UPLOAD	image	\N	{"file_path": "banners/banner-1785125309890-iq3f6mwxsl.webp", "webpQuality": 100, "originalSizeBytes": 2051139, "convertedSizeBytes": 736572}	\N	2026-07-27 04:08:31.061+00	\N
1587	46	LOGOUT	user_account	46	{"reason": "idle_timeout"}	\N	2026-07-27 05:41:03.564+00	\N
1614	45	FILE_UPLOAD	image	\N	{"file_path": "banners/banner-1785726870413-laz2t0n0ran.png", "originalSizeBytes": 2051139}	\N	2026-08-03 03:14:31.152+00	\N
1661	47	UPDATE	banner	42	{"changes": {"active": true, "order_index": 3}, "updated_by": 47}	\N	2026-08-17 05:25:41.9+00	\N
1684	45	UPDATE	banner	56	{"changes": {"active": false, "order_index": 0}, "updated_by": 45}	\N	2026-09-01 06:33:35.185+00	\N
1687	45	UPDATE	banner	58	{"changes": {"active": true, "order_index": 0}, "updated_by": 45}	\N	2026-09-01 06:33:44.72+00	\N
1716	45	CREATE	banner	60	{"title": null, "created_by": 45, "image_media_id": 117}	\N	2026-09-01 09:02:12.481+00	\N
1717	45	UPDATE	banner	56	{"changes": {"active": true, "order_index": 5}, "updated_by": 45}	\N	2026-09-01 09:02:23.843+00	\N
1719	45	UPDATE	banner	43	{"changes": {"active": true, "order_index": 0}, "updated_by": 45}	\N	2026-09-01 09:02:23.988+00	\N
1721	45	UPDATE	banner	60	{"changes": {"active": true, "order_index": 1}, "updated_by": 45}	\N	2026-09-01 09:02:25.65+00	\N
1722	45	UPDATE	banner	59	{"changes": {"active": true, "order_index": 2}, "updated_by": 45}	\N	2026-09-01 09:02:25.853+00	\N
1725	45	UPDATE	banner	57	{"changes": {"active": true, "order_index": 0}, "updated_by": 45}	\N	2026-09-01 09:02:49.099+00	\N
1727	45	UPDATE	banner	43	{"changes": {"active": true, "order_index": 5}, "updated_by": 45}	\N	2026-09-01 09:03:13.302+00	\N
1731	45	UPDATE	banner	59	{"changes": {"active": true, "order_index": 1}, "updated_by": 45}	\N	2026-09-01 09:03:13.781+00	\N
1413	42	LOGOUT	user_account	42	{"reason": "manual"}	\N	2026-07-09 08:31:05.887+00	\N
1734	45	UPDATE	banner	43	{"changes": {"active": false, "order_index": 0}, "updated_by": 45}	\N	2026-09-01 09:03:24.319+00	\N
1236	\N	LOGIN_FAILED	user_account	40	{"username": "admin"}	111.90.199.113	2026-06-18 06:32:19.06+00	Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/149.0.0.0 Mobile Safari/537.36
1278	\N	LOGIN_FAILED	user_account	40	{"username": "admin"}	209.35.161.207	2026-06-19 13:24:50.759+00	Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36
1300	\N	LOGIN_FAILED	user_account	40	{"username": "admin"}	49.145.9.222	2026-06-20 11:21:05.959+00	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/149.0.0.0 Safari/537.36
1303	\N	LOGIN_FAILED	user_account	40	{"username": "admin"}	49.145.9.222	2026-06-20 11:21:08.397+00	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/149.0.0.0 Safari/537.36
1306	\N	LOGIN_FAILED	user_account	40	{"username": "admin"}	49.145.9.222	2026-06-20 11:21:10.223+00	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/149.0.0.0 Safari/537.36
1309	\N	LOGIN_FAILED	user_account	40	{"username": "admin"}	49.145.9.222	2026-06-20 11:21:11.837+00	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/149.0.0.0 Safari/537.36
1375	\N	CREATE	article	39	{"slug": "alaminos-san-pablo-bypass-road-aaksyunan-na", "title": "ALAMINOS–SAN PABLO BYPASS ROAD, AAKSYUNAN NA"}	\N	2026-07-08 03:37:37.696+00	\N
1531	45	LOGOUT	user_account	45	{"reason": "manual"}	\N	2026-07-27 03:07:27.524+00	\N
1552	45	LOGOUT	user_account	45	{"reason": "manual"}	\N	2026-07-27 04:01:36.565+00	\N
1235	\N	LOGOUT	user_account	41	{"reason": "manual"}	\N	2026-06-18 06:32:04.753+00	\N
1337	\N	LOGIN_SUCCESS	user_account	41	{"username": "miso.access"}	160.20.40.74	2026-07-07 07:10:49.403+00	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/150.0.0.0 Safari/537.36
1338	\N	LOGOUT	user_account	41	{"reason": "manual"}	\N	2026-07-07 07:11:05.946+00	\N
1339	\N	FILE_UPLOAD	image	83	{"file_path": "https://yljsclzmrxuhejgcesiv.supabase.co/storage/v1/object/sign/media/banners/be8a5j3eh-1783408291018.png?token=eyJraWQiOiJzdG9yYWdlLXVybC1zaWduaW5nLWtleV83NGM0Nzc4My1kNGMzLTRlNDktOWUwYy01YjJlYmIxNzA2OGQiLCJhbGciOiJIUzI1NiJ9.eyJ1cmwiOiJtZWRpYS9iYW5uZXJzL2JlOGE1ajNlaC0xNzgzNDA4MjkxMDE4LnBuZyIsInNjb3BlIjoiZG93bmxvYWQiLCJpYXQiOjE3ODM0MDgyNjYsImV4cCI6MTgxNDk0NDI2Nn0.fITDhrpt5br8a2_0gf3DgaXkQJjmlt3Vvj4lRG7TRnk"}	\N	2026-07-07 07:11:10.557+00	\N
1341	\N	CREATE	banner	40	{"title": null, "created_by": 41, "image_media_id": 83}	\N	2026-07-07 07:11:11.279+00	\N
1342	\N	UPDATE	banner	40	{"changes": {"active": true, "order_index": 0}, "updated_by": 41}	\N	2026-07-07 07:11:25.403+00	\N
1465	\N	DELETE	banner	36	{"title": null, "deleted_by": 41}	\N	2026-07-21 08:56:03.285+00	\N
1560	47	CREATE	banner	49	{"title": null, "created_by": 47, "image_media_id": 105}	\N	2026-07-27 04:07:34.621+00	\N
1588	45	LOGOUT	user_account	45	{"reason": "idle_timeout"}	\N	2026-07-27 06:05:48.368+00	\N
1615	45	LOGOUT	user_account	45	{"reason": "manual"}	\N	2026-08-03 03:17:02.936+00	\N
1662	47	UPDATE	banner	43	{"changes": {"active": false, "order_index": 0}, "updated_by": 47}	\N	2026-08-17 05:27:01.795+00	\N
1664	47	UPDATE	banner	53	{"changes": {"active": false, "order_index": 0}, "updated_by": 47}	\N	2026-08-17 05:27:17.08+00	\N
1688	45	UPDATE	banner	58	{"changes": {"active": false, "order_index": 0}, "updated_by": 45}	\N	2026-09-01 06:35:59.404+00	\N
1689	45	UPDATE	banner	58	{"changes": {"active": false, "order_index": 0}, "updated_by": 45}	\N	2026-09-01 06:35:59.752+00	\N
1690	45	DELETE	banner	58	{"title": null, "deleted_by": 45}	\N	2026-09-01 06:36:14.886+00	\N
1691	45	DELETE	banner	42	{"title": null, "deleted_by": 45}	\N	2026-09-01 06:36:27.812+00	\N
1692	45	DELETE	banner	52	{"title": null, "deleted_by": 45}	\N	2026-09-01 06:36:33.525+00	\N
1693	45	DELETE	banner	53	{"title": null, "deleted_by": 45}	\N	2026-09-01 06:36:39.949+00	\N
1696	45	CREATE	media	116	{"file_path": "https://yljsclzmrxuhejgcesiv.supabase.co/storage/v1/object/public/media/banners/banner-1788244605045-8ypdsqnnc6p.webp", "created_by": 45, "media_type": "image"}	\N	2026-09-01 06:36:49.891+00	\N
1720	45	UPDATE	banner	57	{"changes": {"active": true, "order_index": 4}, "updated_by": 45}	\N	2026-09-01 09:02:24.209+00	\N
1723	45	UPDATE	banner	54	{"changes": {"active": false, "order_index": 0}, "updated_by": 45}	\N	2026-09-01 09:02:42.575+00	\N
1726	45	UPDATE	banner	43	{"changes": {"active": false, "order_index": 0}, "updated_by": 45}	\N	2026-09-01 09:02:51.544+00	\N
1730	45	UPDATE	banner	60	{"changes": {"active": true, "order_index": 0}, "updated_by": 45}	\N	2026-09-01 09:03:13.605+00	\N
1237	\N	LOGIN_SUCCESS	user_account	40	{"username": "admin"}	111.90.199.113	2026-06-18 06:32:29.927+00	Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/149.0.0.0 Mobile Safari/537.36
1279	\N	LOGIN_FAILED	user_account	40	{"username": "admin"}	49.145.9.222	2026-06-20 09:10:02.41+00	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/149.0.0.0 Safari/537.36
1311	\N	LOGIN_SUCCESS	user_account	40	{"username": "admin"}	49.145.9.222	2026-06-20 12:18:20.479+00	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/149.0.0.0 Safari/537.36
1376	\N	FILE_UPLOAD	image	89	{"file_path": "https://yljsclzmrxuhejgcesiv.supabase.co/storage/v1/object/sign/media/articles/csh29skyy-1783481945812.webp?token=eyJraWQiOiJzdG9yYWdlLXVybC1zaWduaW5nLWtleV83NGM0Nzc4My1kNGMzLTRlNDktOWUwYy01YjJlYmIxNzA2OGQiLCJhbGciOiJIUzI1NiJ9.eyJ1cmwiOiJtZWRpYS9hcnRpY2xlcy9jc2gyOXNreXktMTc4MzQ4MTk0NTgxMi53ZWJwIiwic2NvcGUiOiJkb3dubG9hZCIsImlhdCI6MTc4MzQ4MTk0OSwiZXhwIjoxODE1MDE3OTQ5fQ.kxbz9i2TBfZaTzyYA-bu084wkZSqNaZ6hKYHYFfcn2Q"}	\N	2026-07-08 03:39:11.923+00	\N
1378	\N	UPDATE	article	39	{"changes": {"featured_media_id": 89}}	\N	2026-07-08 03:39:12.653+00	\N
1414	\N	LOGIN_SUCCESS	user_account	40	{"username": "admin.CMS"}	160.20.40.74	2026-07-10 02:29:14.662+00	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/150.0.0.0 Safari/537.36
1519	\N	CREATE	publication	26	{"filename": "BUSINESS-PERMIT-APPLICATION-FORM.pdf", "created_by": 43}	\N	2026-07-23 08:01:30.06+00	\N
1523	\N	ARCHIVE	transparency	28	{"archived_document": {"title": "test"}}	\N	2026-07-23 08:04:14.469+00	\N
1524	\N	LOGOUT	user_account	43	{"reason": "manual"}	\N	2026-07-23 12:14:07.906+00	\N
1451	\N	CREATE	banner	42	{"title": null, "created_by": 41, "image_media_id": 98}	\N	2026-07-21 08:53:54.178+00	\N
1452	\N	FILE_UPLOAD	image	99	{"file_path": "https://yljsclzmrxuhejgcesiv.supabase.co/storage/v1/object/sign/media/banners/1d7o7xdh2-1784624045292.jpg?token=eyJraWQiOiJzdG9yYWdlLXVybC1zaWduaW5nLWtleV83NGM0Nzc4My1kNGMzLTRlNDktOWUwYy01YjJlYmIxNzA2OGQiLCJhbGciOiJIUzI1NiJ9.eyJ1cmwiOiJtZWRpYS9iYW5uZXJzLzFkN283eGRoMi0xNzg0NjI0MDQ1MjkyLmpwZyIsInNjb3BlIjoiZG93bmxvYWQiLCJpYXQiOjE3ODQ2MjQwNDMsImV4cCI6MTgxNjE2MDA0M30.oYQ_mJXKLSyWDAjptNIGG8hHmAei1EXUNaJ4CUr2bDQ"}	\N	2026-07-21 08:54:05.771+00	\N
1454	\N	CREATE	banner	43	{"title": null, "created_by": 41, "image_media_id": 99}	\N	2026-07-21 08:54:06.725+00	\N
1455	\N	UPDATE	banner	38	{"changes": {"active": false, "order_index": 0}, "updated_by": 41}	\N	2026-07-21 08:54:21.534+00	\N
1345	\N	UPDATE	banner	37	{"changes": {"active": true, "order_index": 4}, "updated_by": 41}	\N	2026-07-07 07:11:25.412+00	\N
1346	\N	UPDATE	banner	36	{"changes": {"active": true, "order_index": 3}, "updated_by": 41}	\N	2026-07-07 07:11:27.292+00	\N
1347	\N	UPDATE	banner	38	{"changes": {"active": true, "order_index": 2}, "updated_by": 41}	\N	2026-07-07 07:11:27.507+00	\N
1457	\N	UPDATE	banner	36	{"changes": {"active": true, "order_index": 3}, "updated_by": 41}	\N	2026-07-21 08:55:21.38+00	\N
1459	\N	UPDATE	banner	42	{"changes": {"active": true, "order_index": 1}, "updated_by": 41}	\N	2026-07-21 08:55:21.668+00	\N
1462	\N	UPDATE	banner	41	{"changes": {"active": true, "order_index": 2}, "updated_by": 41}	\N	2026-07-21 08:55:22.877+00	\N
1468	\N	DELETE	banner	35	{"title": null, "deleted_by": 41}	\N	2026-07-21 08:56:19.536+00	\N
1340	\N	CREATE	media	83	{"file_path": "https://yljsclzmrxuhejgcesiv.supabase.co/storage/v1/object/sign/media/banners/be8a5j3eh-1783408291018.png?token=eyJraWQiOiJzdG9yYWdlLXVybC1zaWduaW5nLWtleV83NGM0Nzc4My1kNGMzLTRlNDktOWUwYy01YjJlYmIxNzA2OGQiLCJhbGciOiJIUzI1NiJ9.eyJ1cmwiOiJtZWRpYS9iYW5uZXJzL2JlOGE1ajNlaC0xNzgzNDA4MjkxMDE4LnBuZyIsInNjb3BlIjoiZG93bmxvYWQiLCJpYXQiOjE3ODM0MDgyNjYsImV4cCI6MTgxNDk0NDI2Nn0.fITDhrpt5br8a2_0gf3DgaXkQJjmlt3Vvj4lRG7TRnk", "created_by": 41, "media_type": "image"}	\N	2026-07-07 07:11:10.663+00	\N
1343	\N	UPDATE	banner	39	{"changes": {"active": true, "order_index": 1}, "updated_by": 41}	\N	2026-07-07 07:11:25.408+00	\N
1344	\N	UPDATE	banner	35	{"changes": {"active": true, "order_index": 5}, "updated_by": 41}	\N	2026-07-07 07:11:25.539+00	\N
1464	\N	UPDATE	banner	36	{"changes": {"active": false, "order_index": 0}, "updated_by": 41}	\N	2026-07-21 08:55:54.596+00	\N
1467	\N	DELETE	banner	38	{"title": null, "deleted_by": 41}	\N	2026-07-21 08:56:14.556+00	\N
1502	\N	CREATE	banner	46	{"title": null, "created_by": 41, "image_media_id": 102}	\N	2026-07-23 05:42:19.545+00	\N
1503	\N	UPDATE	banner	41	{"changes": {"active": true, "order_index": 3}, "updated_by": 41}	\N	2026-07-23 05:42:31.048+00	\N
1564	47	FILE_UPLOAD	image	\N	{"file_path": "banners/banner-1785125342986-tlb5lo8eg1n.webp", "webpQuality": 100, "originalSizeBytes": 282190, "convertedSizeBytes": 94534}	\N	2026-07-27 04:09:03.481+00	\N
1565	47	FILE_UPLOAD	image	106	{"file_path": "https://yljsclzmrxuhejgcesiv.supabase.co/storage/v1/object/sign/media/banners/banner-1785125342986-tlb5lo8eg1n.webp?token=eyJraWQiOiJzdG9yYWdlLXVybC1zaWduaW5nLWtleV83NGM0Nzc4My1kNGMzLTRlNDktOWUwYy01YjJlYmIxNzA2OGQiLCJhbGciOiJIUzI1NiJ9.eyJ1cmwiOiJtZWRpYS9iYW5uZXJzL2Jhbm5lci0xNzg1MTI1MzQyOTg2LXRsYjVsbzhlZzFuLndlYnAiLCJzY29wZSI6ImRvd25sb2FkIiwiaWF0IjoxNzg1MTI1MzQzLCJleHAiOjE3ODc3MTczNDN9.8cnXzBJY9mgJ1LF1l1iiO4Cm9D_3T-_u_GvunaGaGtY"}	\N	2026-07-27 04:09:08.874+00	\N
1567	47	CREATE	banner	50	{"title": null, "created_by": 47, "image_media_id": 106}	\N	2026-07-27 04:09:09.473+00	\N
1280	\N	LOGIN_SUCCESS	user_account	40	{"username": "admin"}	49.145.9.222	2026-06-20 09:10:07.602+00	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/149.0.0.0 Safari/537.36
1312	\N	LOGIN_SUCCESS	user_account	40	{"username": "admin.CMS@website"}	160.20.40.74	2026-06-29 06:25:46.069+00	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/149.0.0.0 Safari/537.36
1348	\N	LOGIN_SUCCESS	user_account	40	{"username": "admin.CMS"}	160.20.40.74	2026-07-08 03:02:38.448+00	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/150.0.0.0 Safari/537.36
1377	\N	CREATE	media	89	{"file_path": "https://yljsclzmrxuhejgcesiv.supabase.co/storage/v1/object/sign/media/articles/csh29skyy-1783481945812.webp?token=eyJraWQiOiJzdG9yYWdlLXVybC1zaWduaW5nLWtleV83NGM0Nzc4My1kNGMzLTRlNDktOWUwYy01YjJlYmIxNzA2OGQiLCJhbGciOiJIUzI1NiJ9.eyJ1cmwiOiJtZWRpYS9hcnRpY2xlcy9jc2gyOXNreXktMTc4MzQ4MTk0NTgxMi53ZWJwIiwic2NvcGUiOiJkb3dubG9hZCIsImlhdCI6MTc4MzQ4MTk0OSwiZXhwIjoxODE1MDE3OTQ5fQ.kxbz9i2TBfZaTzyYA-bu084wkZSqNaZ6hKYHYFfcn2Q", "created_by": 40, "media_type": "image"}	\N	2026-07-08 03:39:12.049+00	\N
1379	\N	STATUS_CHANGE	article	39	{"new_status": "published", "old_status": "draft"}	\N	2026-07-08 03:39:15.483+00	\N
1415	\N	FILE_UPLOAD	image	95	{"file_path": "https://yljsclzmrxuhejgcesiv.supabase.co/storage/v1/object/sign/media/articles/qnoob6mj6-1783650724833.webp?token=eyJraWQiOiJzdG9yYWdlLXVybC1zaWduaW5nLWtleV83NGM0Nzc4My1kNGMzLTRlNDktOWUwYy01YjJlYmIxNzA2OGQiLCJhbGciOiJIUzI1NiJ9.eyJ1cmwiOiJtZWRpYS9hcnRpY2xlcy9xbm9vYjZtajYtMTc4MzY1MDcyNDgzMy53ZWJwIiwic2NvcGUiOiJkb3dubG9hZCIsImlhdCI6MTc4MzY1MDcyNywiZXhwIjoxODE1MTg2NzI3fQ.8poux20-CAsj2-fFS3QKy6mRYH9ggQlS_s9FSCEv3uE"}	\N	2026-07-10 02:33:13.471+00	\N
1417	\N	CREATE	article	44	{"slug": "6-000-magsasaka-ng-san-pablo-city-makikinabang-sa-accident-and-dismemberment-insurance-program", "title": "6,000 MAGSASAKA NG SAN PABLO CITY, MAKIKINABANG SA ACCIDENT AND DISMEMBERMENT INSURANCE PROGRAM"}	\N	2026-07-10 02:33:14.228+00	\N
1471	\N	LOGIN_SUCCESS	user_account	40	{"username": "admin.CMS"}	160.20.40.74	2026-07-21 09:01:59.366+00	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/150.0.0.0 Safari/537.36
1533	45	LOGOUT	user_account	45	{"reason": "manual"}	\N	2026-07-27 03:11:30.441+00	\N
1470	\N	LOGIN_SUCCESS	user_account	41	{"username": "miso.access"}	160.20.40.74	2026-07-21 08:56:48.189+00	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/150.0.0.0 Safari/537.36
1498	\N	LOGIN_SUCCESS	user_account	41	{"username": "miso.access"}	160.20.40.74	2026-07-23 05:40:41.092+00	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/150.0.0.0 Safari/537.36
1499	\N	DELETE	banner	45	{"title": null, "deleted_by": 41}	\N	2026-07-23 05:40:50.829+00	\N
1500	\N	FILE_UPLOAD	image	102	{"file_path": "https://yljsclzmrxuhejgcesiv.supabase.co/storage/v1/object/sign/media/banners/hvvxikqqm-1784785333249.png?token=eyJraWQiOiJzdG9yYWdlLXVybC1zaWduaW5nLWtleV83NGM0Nzc4My1kNGMzLTRlNDktOWUwYy01YjJlYmIxNzA2OGQiLCJhbGciOiJIUzI1NiJ9.eyJ1cmwiOiJtZWRpYS9iYW5uZXJzL2h2dnhpa3FxbS0xNzg0Nzg1MzMzMjQ5LnBuZyIsInNjb3BlIjoiZG93bmxvYWQiLCJpYXQiOjE3ODQ3ODUzMzEsImV4cCI6MTgxNjMyMTMzMX0.1-vim5FczJv20kCjQOocDOut8fAp9rixiwVURYmgZCg"}	\N	2026-07-23 05:42:19.03+00	\N
1504	\N	UPDATE	banner	43	{"changes": {"active": true, "order_index": 1}, "updated_by": 41}	\N	2026-07-23 05:42:31.165+00	\N
1506	\N	UPDATE	banner	42	{"changes": {"active": true, "order_index": 2}, "updated_by": 41}	\N	2026-07-23 05:42:32.928+00	\N
1238	\N	LOGIN_SUCCESS	user_account	41	{"username": "editor"}	160.20.41.202	2026-06-18 06:37:43.22+00	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/149.0.0.0 Safari/537.36
1501	\N	CREATE	media	102	{"file_path": "https://yljsclzmrxuhejgcesiv.supabase.co/storage/v1/object/sign/media/banners/hvvxikqqm-1784785333249.png?token=eyJraWQiOiJzdG9yYWdlLXVybC1zaWduaW5nLWtleV83NGM0Nzc4My1kNGMzLTRlNDktOWUwYy01YjJlYmIxNzA2OGQiLCJhbGciOiJIUzI1NiJ9.eyJ1cmwiOiJtZWRpYS9iYW5uZXJzL2h2dnhpa3FxbS0xNzg0Nzg1MzMzMjQ5LnBuZyIsInNjb3BlIjoiZG93bmxvYWQiLCJpYXQiOjE3ODQ3ODUzMzEsImV4cCI6MTgxNjMyMTMzMX0.1-vim5FczJv20kCjQOocDOut8fAp9rixiwVURYmgZCg", "created_by": 41, "media_type": "image"}	\N	2026-07-23 05:42:19.13+00	\N
1505	\N	UPDATE	banner	46	{"changes": {"active": true, "order_index": 0}, "updated_by": 41}	\N	2026-07-23 05:42:31.128+00	\N
1252	\N	CREATE	media	81	{"file_path": "https://yljsclzmrxuhejgcesiv.supabase.co/storage/v1/object/sign/media/banners/ufo6pe965-1781764813178.png?token=eyJraWQiOiJzdG9yYWdlLXVybC1zaWduaW5nLWtleV83NGM0Nzc4My1kNGMzLTRlNDktOWUwYy01YjJlYmIxNzA2OGQiLCJhbGciOiJIUzI1NiJ9.eyJ1cmwiOiJtZWRpYS9iYW5uZXJzL3VmbzZwZTk2NS0xNzgxNzY0ODEzMTc4LnBuZyIsInNjb3BlIjoiZG93bmxvYWQiLCJpYXQiOjE3ODE3NjQ3OTgsImV4cCI6MTgxMzMwMDc5OH0.4NmlY6Dz1yDZufgHdCNa9qmP2iOmLHVyjtM5cf4bw_0", "created_by": 41, "media_type": "image"}	\N	2026-06-18 06:40:04.042+00	\N
1472	\N	FILE_UPLOAD	image	100	{"file_path": "https://yljsclzmrxuhejgcesiv.supabase.co/storage/v1/object/sign/media/banners/qrljo8sn3-1784624852768.png?token=eyJraWQiOiJzdG9yYWdlLXVybC1zaWduaW5nLWtleV83NGM0Nzc4My1kNGMzLTRlNDktOWUwYy01YjJlYmIxNzA2OGQiLCJhbGciOiJIUzI1NiJ9.eyJ1cmwiOiJtZWRpYS9iYW5uZXJzL3FybGpvOHNuMy0xNzg0NjI0ODUyNzY4LnBuZyIsInNjb3BlIjoiZG93bmxvYWQiLCJpYXQiOjE3ODQ2MjQ4NTEsImV4cCI6MTgxNjE2MDg1MX0.4mUHxUlxbvinCHfdc8X2NTWULdSmzFIyJ4AdiE0j6Gc"}	\N	2026-07-21 09:07:39.062+00	\N
1476	\N	UPDATE	banner	44	{"changes": {"active": true, "order_index": 0}, "updated_by": 41}	\N	2026-07-21 09:07:50.58+00	\N
1477	\N	UPDATE	banner	41	{"changes": {"active": true, "order_index": 3}, "updated_by": 41}	\N	2026-07-21 09:07:50.791+00	\N
1478	\N	UPDATE	banner	42	{"changes": {"active": true, "order_index": 2}, "updated_by": 41}	\N	2026-07-21 09:07:51.19+00	\N
1473	\N	CREATE	media	100	{"file_path": "https://yljsclzmrxuhejgcesiv.supabase.co/storage/v1/object/sign/media/banners/qrljo8sn3-1784624852768.png?token=eyJraWQiOiJzdG9yYWdlLXVybC1zaWduaW5nLWtleV83NGM0Nzc4My1kNGMzLTRlNDktOWUwYy01YjJlYmIxNzA2OGQiLCJhbGciOiJIUzI1NiJ9.eyJ1cmwiOiJtZWRpYS9iYW5uZXJzL3FybGpvOHNuMy0xNzg0NjI0ODUyNzY4LnBuZyIsInNjb3BlIjoiZG93bmxvYWQiLCJpYXQiOjE3ODQ2MjQ4NTEsImV4cCI6MTgxNjE2MDg1MX0.4mUHxUlxbvinCHfdc8X2NTWULdSmzFIyJ4AdiE0j6Gc", "created_by": 41, "media_type": "image"}	\N	2026-07-21 09:07:39.177+00	\N
1566	47	CREATE	media	106	{"file_path": "https://yljsclzmrxuhejgcesiv.supabase.co/storage/v1/object/sign/media/banners/banner-1785125342986-tlb5lo8eg1n.webp?token=eyJraWQiOiJzdG9yYWdlLXVybC1zaWduaW5nLWtleV83NGM0Nzc4My1kNGMzLTRlNDktOWUwYy01YjJlYmIxNzA2OGQiLCJhbGciOiJIUzI1NiJ9.eyJ1cmwiOiJtZWRpYS9iYW5uZXJzL2Jhbm5lci0xNzg1MTI1MzQyOTg2LXRsYjVsbzhlZzFuLndlYnAiLCJzY29wZSI6ImRvd25sb2FkIiwiaWF0IjoxNzg1MTI1MzQzLCJleHAiOjE3ODc3MTczNDN9.8cnXzBJY9mgJ1LF1l1iiO4Cm9D_3T-_u_GvunaGaGtY", "created_by": 47, "media_type": "image"}	\N	2026-07-27 04:09:08.967+00	\N
977	\N	FILE_UPLOAD	image	57	{"file_path": "https://yljsclzmrxuhejgcesiv.supabase.co/storage/v1/object/sign/media/banners/61436ghe4-1780053864765.png?token=eyJraWQiOiJzdG9yYWdlLXVybC1zaWduaW5nLWtleV83NGM0Nzc4My1kNGMzLTRlNDktOWUwYy01YjJlYmIxNzA2OGQiLCJhbGciOiJIUzI1NiJ9.eyJ1cmwiOiJtZWRpYS9iYW5uZXJzLzYxNDM2Z2hlNC0xNzgwMDUzODY0NzY1LnBuZyIsImlhdCI6MTc4MDA1Mzg3MCwiZXhwIjoxODExNTg5ODcwfQ.TUqLTfzdSHuTxEysYViYMCGN4HHKWzsgwZeOJDnlxeQ"}	\N	2026-05-29 11:24:33.692+00	\N
1589	47	LOGOUT	user_account	47	{"reason": "idle_timeout"}	\N	2026-07-27 06:11:19.211+00	\N
1616	47	FILE_UPLOAD	image	\N	{"file_path": "banners/banner-1785729661097-64ccvqgnod.png", "originalSizeBytes": 821481}	\N	2026-08-03 04:01:01.769+00	\N
1618	47	CREATE	media	111	{"file_path": "https://yljsclzmrxuhejgcesiv.supabase.co/storage/v1/object/sign/media/banners/banner-1785729661097-64ccvqgnod.png?token=eyJraWQiOiJzdG9yYWdlLXVybC1zaWduaW5nLWtleV83NGM0Nzc4My1kNGMzLTRlNDktOWUwYy01YjJlYmIxNzA2OGQiLCJhbGciOiJIUzI1NiJ9.eyJ1cmwiOiJtZWRpYS9iYW5uZXJzL2Jhbm5lci0xNzg1NzI5NjYxMDk3LTY0Y2N2cWdub2QucG5nIiwic2NvcGUiOiJkb3dubG9hZCIsImlhdCI6MTc4NTcyOTY2MSwiZXhwIjoxNzg4MzIxNjYxfQ.9MwAub8InawonwN1UI4eH-1TkpgEg4QPxnnY2pMuhx4", "created_by": 47, "media_type": "image"}	\N	2026-08-03 04:01:11.739+00	\N
1619	47	CREATE	banner	54	{"title": null, "created_by": 47, "image_media_id": 111}	\N	2026-08-03 04:01:12.39+00	\N
1620	47	UPDATE	banner	52	{"changes": {"active": true, "order_index": 2}, "updated_by": 47}	\N	2026-08-03 04:01:23.87+00	\N
1624	47	UPDATE	banner	53	{"changes": {"active": true, "order_index": 5}, "updated_by": 47}	\N	2026-08-03 04:01:25.506+00	\N
1625	47	UPDATE	banner	54	{"changes": {"active": true, "order_index": 1}, "updated_by": 47}	\N	2026-08-03 04:01:25.996+00	\N
1315	42	LOGIN_SUCCESS	user_account	42	{"username": "cio.access"}	160.20.40.74	2026-06-29 06:30:14.691+00	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/149.0.0.0 Safari/537.36
1663	47	UPDATE	banner	42	{"changes": {"active": false, "order_index": 0}, "updated_by": 47}	\N	2026-08-17 05:27:08.012+00	\N
1694	45	FILE_UPLOAD	image	\N	{"file_path": "banners/banner-1788244605045-8ypdsqnnc6p.webp", "originalSizeBytes": 234458}	\N	2026-09-01 06:36:45.323+00	\N
1695	45	FILE_UPLOAD	image	116	{"file_path": "https://yljsclzmrxuhejgcesiv.supabase.co/storage/v1/object/public/media/banners/banner-1788244605045-8ypdsqnnc6p.webp"}	\N	2026-09-01 06:36:49.785+00	\N
1732	45	UPDATE	banner	57	{"changes": {"active": true, "order_index": 2}, "updated_by": 45}	\N	2026-09-01 09:03:13.684+00	\N
1281	\N	LOGOUT	user_account	40	{"reason": "manual"}	\N	2026-06-20 09:22:34.623+00	\N
1313	\N	CREATE	user_account	42	{"role": "staff", "username": "cio.access", "created_by": 40, "permissions": ["news"]}	\N	2026-06-29 06:29:58.263+00	\N
1349	\N	CREATE	article	33	{"slug": "dlsp-may-158-bagong-guro", "title": "DLSP, MAY 158 BAGONG GURO"}	\N	2026-07-08 03:07:41.117+00	\N
1380	\N	FILE_UPLOAD	image	90	{"file_path": "https://yljsclzmrxuhejgcesiv.supabase.co/storage/v1/object/sign/media/articles/s0ns6bb5h-1783482118457.webp?token=eyJraWQiOiJzdG9yYWdlLXVybC1zaWduaW5nLWtleV83NGM0Nzc4My1kNGMzLTRlNDktOWUwYy01YjJlYmIxNzA2OGQiLCJhbGciOiJIUzI1NiJ9.eyJ1cmwiOiJtZWRpYS9hcnRpY2xlcy9zMG5zNmJiNWgtMTc4MzQ4MjExODQ1Ny53ZWJwIiwic2NvcGUiOiJkb3dubG9hZCIsImlhdCI6MTc4MzQ4MjEyMiwiZXhwIjoxODE1MDE4MTIyfQ.gYOSpg-jw0MDLkWpbPOiw5oAYiCI1U4dxr6SxdXHnqY"}	\N	2026-07-08 03:42:47.674+00	\N
1382	\N	CREATE	article	40	{"slug": "11-359-food-packs-naipamahagi-sa-mga-pwd-at-solo-parent-sa-san-pablo-city", "title": "11,359 FOOD PACKS, NAIPAMAHAGI SA MGA PWD AT SOLO PARENT SA SAN PABLO CITY"}	\N	2026-07-08 03:42:48.814+00	\N
1418	\N	STATUS_CHANGE	article	44	{"new_status": "published", "old_status": "draft"}	\N	2026-07-10 02:33:19.417+00	\N
1507	\N	LOGIN_SUCCESS	user_account	40	{"username": "admin.CMS"}	160.20.40.74	2026-07-23 06:12:56.453+00	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/150.0.0.0 Safari/537.36
1534	46	LOGOUT	user_account	46	{"reason": "manual"}	\N	2026-07-27 03:23:51.593+00	\N
1239	\N	FILE_UPLOAD	image	77	{"file_path": "https://yljsclzmrxuhejgcesiv.supabase.co/storage/v1/object/sign/media/banners/tqmtoclzq-1781764718264.png?token=eyJraWQiOiJzdG9yYWdlLXVybC1zaWduaW5nLWtleV83NGM0Nzc4My1kNGMzLTRlNDktOWUwYy01YjJlYmIxNzA2OGQiLCJhbGciOiJIUzI1NiJ9.eyJ1cmwiOiJtZWRpYS9iYW5uZXJzL3RxbXRvY2x6cS0xNzgxNzY0NzE4MjY0LnBuZyIsInNjb3BlIjoiZG93bmxvYWQiLCJpYXQiOjE3ODE3NjQ3MDQsImV4cCI6MTgxMzMwMDcwNH0.yC-XJ69hKm9IwTX0mSwEYDoT2y7a859CPcpfxfRPBmM"}	\N	2026-06-18 06:38:27.674+00	\N
1243	\N	CREATE	media	78	{"file_path": "https://yljsclzmrxuhejgcesiv.supabase.co/storage/v1/object/sign/media/banners/edsr7knm9-1781764735966.png?token=eyJraWQiOiJzdG9yYWdlLXVybC1zaWduaW5nLWtleV83NGM0Nzc4My1kNGMzLTRlNDktOWUwYy01YjJlYmIxNzA2OGQiLCJhbGciOiJIUzI1NiJ9.eyJ1cmwiOiJtZWRpYS9iYW5uZXJzL2Vkc3I3a25tOS0xNzgxNzY0NzM1OTY2LnBuZyIsInNjb3BlIjoiZG93bmxvYWQiLCJpYXQiOjE3ODE3NjQ3MjIsImV4cCI6MTgxMzMwMDcyMn0.lj4Ulqa-5Ttf4_Vsq9IyJqQXRA6qMlR2C0a2QaFDPFI", "created_by": 41, "media_type": "image"}	\N	2026-06-18 06:38:48.497+00	\N
1244	\N	CREATE	banner	36	{"title": null, "created_by": 41, "image_media_id": 78}	\N	2026-06-18 06:38:48.943+00	\N
1248	\N	FILE_UPLOAD	image	80	{"file_path": "https://yljsclzmrxuhejgcesiv.supabase.co/storage/v1/object/sign/media/banners/2x2wuagg8-1781764797900.png?token=eyJraWQiOiJzdG9yYWdlLXVybC1zaWduaW5nLWtleV83NGM0Nzc4My1kNGMzLTRlNDktOWUwYy01YjJlYmIxNzA2OGQiLCJhbGciOiJIUzI1NiJ9.eyJ1cmwiOiJtZWRpYS9iYW5uZXJzLzJ4Mnd1YWdnOC0xNzgxNzY0Nzk3OTAwLnBuZyIsInNjb3BlIjoiZG93bmxvYWQiLCJpYXQiOjE3ODE3NjQ3ODMsImV4cCI6MTgxMzMwMDc4M30.l2kIunsPaODEuZ6OTqaKJ3ZkipvEdQB0uUW73tyNaoE"}	\N	2026-06-18 06:39:45.039+00	\N
1253	\N	CREATE	banner	39	{"title": null, "created_by": 41, "image_media_id": 81}	\N	2026-06-18 06:40:04.49+00	\N
1475	\N	UPDATE	banner	43	{"changes": {"active": true, "order_index": 1}, "updated_by": 41}	\N	2026-07-21 09:07:48.731+00	\N
1568	47	FILE_UPLOAD	image	\N	{"file_path": "banners/banner-1785125388620-gwfwjv1918.webp", "webpQuality": 100, "originalSizeBytes": 282190, "convertedSizeBytes": 94534}	\N	2026-07-27 04:09:49.143+00	\N
1590	47	FILE_UPLOAD	image	\N	{"file_path": "banners/banner-1785139723853-1eh8nf7h9m1.webp", "webpQuality": 100, "originalSizeBytes": 282190, "convertedSizeBytes": 98094}	\N	2026-07-27 08:08:45.237+00	\N
1617	47	FILE_UPLOAD	image	111	{"file_path": "https://yljsclzmrxuhejgcesiv.supabase.co/storage/v1/object/sign/media/banners/banner-1785729661097-64ccvqgnod.png?token=eyJraWQiOiJzdG9yYWdlLXVybC1zaWduaW5nLWtleV83NGM0Nzc4My1kNGMzLTRlNDktOWUwYy01YjJlYmIxNzA2OGQiLCJhbGciOiJIUzI1NiJ9.eyJ1cmwiOiJtZWRpYS9iYW5uZXJzL2Jhbm5lci0xNzg1NzI5NjYxMDk3LTY0Y2N2cWdub2QucG5nIiwic2NvcGUiOiJkb3dubG9hZCIsImlhdCI6MTc4NTcyOTY2MSwiZXhwIjoxNzg4MzIxNjYxfQ.9MwAub8InawonwN1UI4eH-1TkpgEg4QPxnnY2pMuhx4"}	\N	2026-08-03 04:01:11.642+00	\N
1621	47	UPDATE	banner	42	{"changes": {"active": true, "order_index": 3}, "updated_by": 47}	\N	2026-08-03 04:01:23.759+00	\N
1622	47	UPDATE	banner	43	{"changes": {"active": true, "order_index": 4}, "updated_by": 47}	\N	2026-08-03 04:01:25.51+00	\N
1623	47	UPDATE	banner	46	{"changes": {"active": true, "order_index": 0}, "updated_by": 47}	\N	2026-08-03 04:01:25.651+00	\N
1665	45	LOGOUT	user_account	45	{"reason": "manual"}	\N	2026-09-01 01:58:32.9+00	\N
1697	45	CREATE	banner	59	{"title": null, "created_by": 45, "image_media_id": 116}	\N	2026-09-01 06:36:50.604+00	\N
1735	45	LOGOUT	user_account	45	{"reason": "idle_timeout"}	\N	2026-09-01 09:33:38.494+00	\N
1282	\N	LOGIN_SUCCESS	user_account	40	{"username": "admin"}	49.145.9.222	2026-06-20 09:22:41.531+00	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/149.0.0.0 Safari/537.36
1314	\N	LOGOUT	user_account	40	{"reason": "manual"}	\N	2026-06-29 06:30:03.546+00	\N
1350	\N	DELETE	article	33	{"slug": "dlsp-may-158-bagong-guro", "title": "DLSP, MAY 158 BAGONG GURO"}	\N	2026-07-08 03:07:58.04+00	\N
1381	\N	CREATE	media	90	{"file_path": "https://yljsclzmrxuhejgcesiv.supabase.co/storage/v1/object/sign/media/articles/s0ns6bb5h-1783482118457.webp?token=eyJraWQiOiJzdG9yYWdlLXVybC1zaWduaW5nLWtleV83NGM0Nzc4My1kNGMzLTRlNDktOWUwYy01YjJlYmIxNzA2OGQiLCJhbGciOiJIUzI1NiJ9.eyJ1cmwiOiJtZWRpYS9hcnRpY2xlcy9zMG5zNmJiNWgtMTc4MzQ4MjExODQ1Ny53ZWJwIiwic2NvcGUiOiJkb3dubG9hZCIsImlhdCI6MTc4MzQ4MjEyMiwiZXhwIjoxODE1MDE4MTIyfQ.gYOSpg-jw0MDLkWpbPOiw5oAYiCI1U4dxr6SxdXHnqY", "created_by": 40, "media_type": "image"}	\N	2026-07-08 03:42:47.931+00	\N
1383	\N	STATUS_CHANGE	article	40	{"new_status": "published", "old_status": "draft"}	\N	2026-07-08 03:42:51.775+00	\N
1419	\N	FILE_UPLOAD	image	96	{"file_path": "https://yljsclzmrxuhejgcesiv.supabase.co/storage/v1/object/sign/media/articles/12k2vh0pp-1783650907062.webp?token=eyJraWQiOiJzdG9yYWdlLXVybC1zaWduaW5nLWtleV83NGM0Nzc4My1kNGMzLTRlNDktOWUwYy01YjJlYmIxNzA2OGQiLCJhbGciOiJIUzI1NiJ9.eyJ1cmwiOiJtZWRpYS9hcnRpY2xlcy8xMmsydmgwcHAtMTc4MzY1MDkwNzA2Mi53ZWJwIiwic2NvcGUiOiJkb3dubG9hZCIsImlhdCI6MTc4MzY1MDkwOSwiZXhwIjoxODE1MTg2OTA5fQ.qthYNIG0OTYb2FH3royOQO3jDF9Z-RqjhRtQBLy3DbA"}	\N	2026-07-10 02:35:47.903+00	\N
1421	\N	CREATE	article	45	{"slug": "libreng-bigas-sa-mga-solo-parent-ng-san-pablo-city", "title": "LIBRENG BIGAS SA MGA SOLO PARENT NG SAN PABLO CITY "}	\N	2026-07-10 02:35:48.699+00	\N
1508	\N	LOGOUT	user_account	43	{"reason": "manual"}	\N	2026-07-23 07:38:50.176+00	\N
1535	45	LOGOUT	user_account	45	{"reason": "manual"}	\N	2026-07-27 03:55:24.122+00	\N
1536	46	FILE_UPLOAD	image	\N	{"file_path": "banners/banner-1785124542581-5u11pm124vs.webp", "webpQuality": 100, "originalSizeBytes": 27321, "convertedSizeBytes": 45198}	\N	2026-07-27 03:55:43.671+00	\N
1240	\N	CREATE	media	77	{"file_path": "https://yljsclzmrxuhejgcesiv.supabase.co/storage/v1/object/sign/media/banners/tqmtoclzq-1781764718264.png?token=eyJraWQiOiJzdG9yYWdlLXVybC1zaWduaW5nLWtleV83NGM0Nzc4My1kNGMzLTRlNDktOWUwYy01YjJlYmIxNzA2OGQiLCJhbGciOiJIUzI1NiJ9.eyJ1cmwiOiJtZWRpYS9iYW5uZXJzL3RxbXRvY2x6cS0xNzgxNzY0NzE4MjY0LnBuZyIsInNjb3BlIjoiZG93bmxvYWQiLCJpYXQiOjE3ODE3NjQ3MDQsImV4cCI6MTgxMzMwMDcwNH0.yC-XJ69hKm9IwTX0mSwEYDoT2y7a859CPcpfxfRPBmM", "created_by": 41, "media_type": "image"}	\N	2026-06-18 06:38:27.788+00	\N
1241	\N	CREATE	banner	35	{"title": null, "created_by": 41, "image_media_id": 77}	\N	2026-06-18 06:38:28.244+00	\N
1245	\N	FILE_UPLOAD	image	79	{"file_path": "https://yljsclzmrxuhejgcesiv.supabase.co/storage/v1/object/sign/media/banners/knj7uelpj-1781764768847.png?token=eyJraWQiOiJzdG9yYWdlLXVybC1zaWduaW5nLWtleV83NGM0Nzc4My1kNGMzLTRlNDktOWUwYy01YjJlYmIxNzA2OGQiLCJhbGciOiJIUzI1NiJ9.eyJ1cmwiOiJtZWRpYS9iYW5uZXJzL2tuajd1ZWxwai0xNzgxNzY0NzY4ODQ3LnBuZyIsInNjb3BlIjoiZG93bmxvYWQiLCJpYXQiOjE3ODE3NjQ3NTQsImV4cCI6MTgxMzMwMDc1NH0.poksddjB0b2gQkllsP6zSnTeR8JiW9bygWszpdAFlYo"}	\N	2026-06-18 06:39:18.076+00	\N
1249	\N	CREATE	media	80	{"file_path": "https://yljsclzmrxuhejgcesiv.supabase.co/storage/v1/object/sign/media/banners/2x2wuagg8-1781764797900.png?token=eyJraWQiOiJzdG9yYWdlLXVybC1zaWduaW5nLWtleV83NGM0Nzc4My1kNGMzLTRlNDktOWUwYy01YjJlYmIxNzA2OGQiLCJhbGciOiJIUzI1NiJ9.eyJ1cmwiOiJtZWRpYS9iYW5uZXJzLzJ4Mnd1YWdnOC0xNzgxNzY0Nzk3OTAwLnBuZyIsInNjb3BlIjoiZG93bmxvYWQiLCJpYXQiOjE3ODE3NjQ3ODMsImV4cCI6MTgxMzMwMDc4M30.l2kIunsPaODEuZ6OTqaKJ3ZkipvEdQB0uUW73tyNaoE", "created_by": 41, "media_type": "image"}	\N	2026-06-18 06:39:45.137+00	\N
1250	\N	CREATE	banner	38	{"title": null, "created_by": 41, "image_media_id": 80}	\N	2026-06-18 06:39:45.595+00	\N
1254	\N	UPDATE	banner	36	{"changes": {"active": true, "order_index": 2}, "updated_by": 41}	\N	2026-06-18 06:40:24.927+00	\N
1257	\N	UPDATE	banner	38	{"changes": {"active": true, "order_index": 1}, "updated_by": 41}	\N	2026-06-18 06:40:26.758+00	\N
1259	\N	LOGIN_SUCCESS	user_account	41	{"username": "editor"}	160.20.41.202	2026-06-18 06:41:00.816+00	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/149.0.0.0 Safari/537.36
1569	46	FILE_UPLOAD	image	\N	{"file_path": "banners/banner-1785127235963-2es2s4fjaf9.webp", "webpQuality": 100, "originalSizeBytes": 2051139, "convertedSizeBytes": 735088}	\N	2026-07-27 04:40:38.222+00	\N
1574	47	FILE_UPLOAD	image	\N	{"file_path": "banners/banner-1785127298255-yng237dx8w.webp", "webpQuality": 100, "originalSizeBytes": 71213, "convertedSizeBytes": 145914}	\N	2026-07-27 04:41:39.149+00	\N
1591	47	FILE_UPLOAD	image	\N	{"file_path": "banners/banner-1785141054486-bx98kgxrhot.webp", "webpQuality": 100, "originalSizeBytes": 282190, "convertedSizeBytes": 96788}	\N	2026-07-27 08:30:55.969+00	\N
1626	47	LOGOUT	user_account	47	{"reason": "idle_timeout"}	\N	2026-08-03 04:32:25.921+00	\N
1666	45	LOGOUT	user_account	45	{"reason": "idle_timeout"}	\N	2026-09-01 03:28:33.841+00	\N
1698	45	UPDATE	banner	57	{"changes": {"active": true, "order_index": 0}, "updated_by": 45}	\N	2026-09-01 06:49:39.566+00	\N
1706	45	UPDATE	banner	57	{"changes": {"active": true, "order_index": 1}, "updated_by": 45}	\N	2026-09-01 06:50:43.648+00	\N
1709	45	UPDATE	banner	43	{"changes": {"active": true, "order_index": 4}, "updated_by": 45}	\N	2026-09-01 06:50:43.664+00	\N
1316	42	FILE_UPLOAD	image	82	{"file_path": "https://yljsclzmrxuhejgcesiv.supabase.co/storage/v1/object/sign/media/articles/wbqubodzk-1782714713018.webp?token=eyJraWQiOiJzdG9yYWdlLXVybC1zaWduaW5nLWtleV83NGM0Nzc4My1kNGMzLTRlNDktOWUwYy01YjJlYmIxNzA2OGQiLCJhbGciOiJIUzI1NiJ9.eyJ1cmwiOiJtZWRpYS9hcnRpY2xlcy93YnF1Ym9kemstMTc4MjcxNDcxMzAxOC53ZWJwIiwic2NvcGUiOiJkb3dubG9hZCIsImlhdCI6MTc4MjcxNDcxNiwiZXhwIjoxODE0MjUwNzE2fQ.w67lI3SXbMCoimwuJHvCsKdkMSZASRZQYbWiZHFzAfo"}	\N	2026-06-29 06:32:07.055+00	\N
1318	42	CREATE	article	32	{"slug": "test", "title": "test"}	\N	2026-06-29 06:32:07.703+00	\N
1495	\N	CREATE	chat_message	261	{"sent_by": 40, "conversation_id": 125}	\N	2026-07-23 01:13:21.309+00	\N
1416	\N	CREATE	media	95	{"file_path": "https://yljsclzmrxuhejgcesiv.supabase.co/storage/v1/object/sign/media/articles/qnoob6mj6-1783650724833.webp?token=eyJraWQiOiJzdG9yYWdlLXVybC1zaWduaW5nLWtleV83NGM0Nzc4My1kNGMzLTRlNDktOWUwYy01YjJlYmIxNzA2OGQiLCJhbGciOiJIUzI1NiJ9.eyJ1cmwiOiJtZWRpYS9hcnRpY2xlcy9xbm9vYjZtajYtMTc4MzY1MDcyNDgzMy53ZWJwIiwic2NvcGUiOiJkb3dubG9hZCIsImlhdCI6MTc4MzY1MDcyNywiZXhwIjoxODE1MTg2NzI3fQ.8poux20-CAsj2-fFS3QKy6mRYH9ggQlS_s9FSCEv3uE", "created_by": 40, "media_type": "image"}	\N	2026-07-10 02:33:13.621+00	\N
1283	\N	LOGIN_FAILED	user_account	40	{"username": "admin"}	49.145.9.222	2026-06-20 10:28:53.249+00	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/149.0.0.0 Safari/537.36
1351	\N	CREATE	article	34	{"slug": "28-pwd-sa-san-pablo-tumanggap-ng-mobility-devices", "title": "28 PWD SA SAN PABLO, TUMANGGAP NG MOBILITY DEVICES"}	\N	2026-07-08 03:16:45.797+00	\N
1352	\N	FILE_UPLOAD	image	84	{"file_path": "https://yljsclzmrxuhejgcesiv.supabase.co/storage/v1/object/sign/media/articles/jrv9mf6b1-1783480617030.webp?token=eyJraWQiOiJzdG9yYWdlLXVybC1zaWduaW5nLWtleV83NGM0Nzc4My1kNGMzLTRlNDktOWUwYy01YjJlYmIxNzA2OGQiLCJhbGciOiJIUzI1NiJ9.eyJ1cmwiOiJtZWRpYS9hcnRpY2xlcy9qcnY5bWY2YjEtMTc4MzQ4MDYxNzAzMC53ZWJwIiwic2NvcGUiOiJkb3dubG9hZCIsImlhdCI6MTc4MzQ4MDYyMCwiZXhwIjoxODE1MDE2NjIwfQ.Nw552tcdwVfz754N7_5QogqoWy6WF_RF8gL1dHGrdTY"}	\N	2026-07-08 03:17:03.681+00	\N
1354	\N	UPDATE	article	34	{"changes": {"featured_media_id": 84}}	\N	2026-07-08 03:17:04.202+00	\N
1386	\N	CREATE	article	41	{"slug": "calabarzon-strengthens-earthquake-readiness-through-full-scale-nsed-exercise-in-san-pablo-city", "title": "CALABARZON STRENGTHENS EARTHQUAKE READINESS THROUGH FULL-SCALE NSED EXERCISE IN SAN PABLO CITY"}	\N	2026-07-08 03:49:03.315+00	\N
1474	\N	CREATE	banner	44	{"title": null, "created_by": 41, "image_media_id": 100}	\N	2026-07-21 09:07:39.61+00	\N
1242	\N	FILE_UPLOAD	image	78	{"file_path": "https://yljsclzmrxuhejgcesiv.supabase.co/storage/v1/object/sign/media/banners/edsr7knm9-1781764735966.png?token=eyJraWQiOiJzdG9yYWdlLXVybC1zaWduaW5nLWtleV83NGM0Nzc4My1kNGMzLTRlNDktOWUwYy01YjJlYmIxNzA2OGQiLCJhbGciOiJIUzI1NiJ9.eyJ1cmwiOiJtZWRpYS9iYW5uZXJzL2Vkc3I3a25tOS0xNzgxNzY0NzM1OTY2LnBuZyIsInNjb3BlIjoiZG93bmxvYWQiLCJpYXQiOjE3ODE3NjQ3MjIsImV4cCI6MTgxMzMwMDcyMn0.lj4Ulqa-5Ttf4_Vsq9IyJqQXRA6qMlR2C0a2QaFDPFI"}	\N	2026-06-18 06:38:48.396+00	\N
1246	\N	CREATE	media	79	{"file_path": "https://yljsclzmrxuhejgcesiv.supabase.co/storage/v1/object/sign/media/banners/knj7uelpj-1781764768847.png?token=eyJraWQiOiJzdG9yYWdlLXVybC1zaWduaW5nLWtleV83NGM0Nzc4My1kNGMzLTRlNDktOWUwYy01YjJlYmIxNzA2OGQiLCJhbGciOiJIUzI1NiJ9.eyJ1cmwiOiJtZWRpYS9iYW5uZXJzL2tuajd1ZWxwai0xNzgxNzY0NzY4ODQ3LnBuZyIsInNjb3BlIjoiZG93bmxvYWQiLCJpYXQiOjE3ODE3NjQ3NTQsImV4cCI6MTgxMzMwMDc1NH0.poksddjB0b2gQkllsP6zSnTeR8JiW9bygWszpdAFlYo", "created_by": 41, "media_type": "image"}	\N	2026-06-18 06:39:18.177+00	\N
1247	\N	CREATE	banner	37	{"title": null, "created_by": 41, "image_media_id": 79}	\N	2026-06-18 06:39:18.611+00	\N
1251	\N	FILE_UPLOAD	image	81	{"file_path": "https://yljsclzmrxuhejgcesiv.supabase.co/storage/v1/object/sign/media/banners/ufo6pe965-1781764813178.png?token=eyJraWQiOiJzdG9yYWdlLXVybC1zaWduaW5nLWtleV83NGM0Nzc4My1kNGMzLTRlNDktOWUwYy01YjJlYmIxNzA2OGQiLCJhbGciOiJIUzI1NiJ9.eyJ1cmwiOiJtZWRpYS9iYW5uZXJzL3VmbzZwZTk2NS0xNzgxNzY0ODEzMTc4LnBuZyIsInNjb3BlIjoiZG93bmxvYWQiLCJpYXQiOjE3ODE3NjQ3OTgsImV4cCI6MTgxMzMwMDc5OH0.4NmlY6Dz1yDZufgHdCNa9qmP2iOmLHVyjtM5cf4bw_0"}	\N	2026-06-18 06:40:03.948+00	\N
1255	\N	UPDATE	banner	37	{"changes": {"active": true, "order_index": 3}, "updated_by": 41}	\N	2026-06-18 06:40:24.944+00	\N
1256	\N	UPDATE	banner	39	{"changes": {"active": true, "order_index": 0}, "updated_by": 41}	\N	2026-06-18 06:40:25.161+00	\N
1258	\N	UPDATE	banner	35	{"changes": {"active": true, "order_index": 4}, "updated_by": 41}	\N	2026-06-18 06:40:26.841+00	\N
1260	\N	LOGOUT	user_account	41	{"reason": "manual"}	\N	2026-06-18 06:41:19.785+00	\N
1480	\N	DELETE	banner	44	{"title": null, "deleted_by": 41}	\N	2026-07-22 00:13:21.715+00	\N
1570	47	FILE_UPLOAD	image	\N	{"file_path": "banners/banner-1785127257301-sjqm62ogzu.webp", "webpQuality": 100, "originalSizeBytes": 2346721, "convertedSizeBytes": 481200}	\N	2026-07-27 04:40:58.21+00	\N
1571	47	FILE_UPLOAD	image	\N	{"file_path": "banners/banner-1785127268039-j5t78sa9jdh.webp", "webpQuality": 100, "originalSizeBytes": 254767, "convertedSizeBytes": 105588}	\N	2026-07-27 04:41:08.691+00	\N
1317	42	CREATE	media	82	{"file_path": "https://yljsclzmrxuhejgcesiv.supabase.co/storage/v1/object/sign/media/articles/wbqubodzk-1782714713018.webp?token=eyJraWQiOiJzdG9yYWdlLXVybC1zaWduaW5nLWtleV83NGM0Nzc4My1kNGMzLTRlNDktOWUwYy01YjJlYmIxNzA2OGQiLCJhbGciOiJIUzI1NiJ9.eyJ1cmwiOiJtZWRpYS9hcnRpY2xlcy93YnF1Ym9kemstMTc4MjcxNDcxMzAxOC53ZWJwIiwic2NvcGUiOiJkb3dubG9hZCIsImlhdCI6MTc4MjcxNDcxNiwiZXhwIjoxODE0MjUwNzE2fQ.w67lI3SXbMCoimwuJHvCsKdkMSZASRZQYbWiZHFzAfo", "created_by": 42, "media_type": "image"}	\N	2026-06-29 06:32:07.194+00	\N
1573	47	FILE_UPLOAD	image	\N	{"file_path": "banners/banner-1785127290259-ol53rdyrfv.webp", "webpQuality": 100, "originalSizeBytes": 254767, "convertedSizeBytes": 105588}	\N	2026-07-27 04:41:30.891+00	\N
1592	45	DELETE	banner	51	{"title": null, "deleted_by": 45}	\N	2026-07-27 14:43:22.07+00	\N
1594	45	FILE_UPLOAD	image	109	{"file_path": "https://yljsclzmrxuhejgcesiv.supabase.co/storage/v1/object/sign/media/banners/banner-1785163408613-cv6qsscvvg.webp?token=eyJraWQiOiJzdG9yYWdlLXVybC1zaWduaW5nLWtleV83NGM0Nzc4My1kNGMzLTRlNDktOWUwYy01YjJlYmIxNzA2OGQiLCJhbGciOiJIUzI1NiJ9.eyJ1cmwiOiJtZWRpYS9iYW5uZXJzL2Jhbm5lci0xNzg1MTYzNDA4NjEzLWN2NnFzc2N2dmcud2VicCIsInNjb3BlIjoiZG93bmxvYWQiLCJpYXQiOjE3ODUxNjM0MDksImV4cCI6MTc4Nzc1NTQwOX0.ooKAJ9vamwBzjGtf5ClO_cDZ3Pd0TuRDiM_3txLHM0M"}	\N	2026-07-27 14:43:31.753+00	\N
1598	45	UPDATE	banner	43	{"changes": {"active": true, "order_index": 3}, "updated_by": 45}	\N	2026-07-27 14:43:43.963+00	\N
1601	45	UPDATE	banner	52	{"changes": {"active": true, "order_index": 1}, "updated_by": 45}	\N	2026-07-27 14:44:28.409+00	\N
1604	45	UPDATE	banner	46	{"changes": {"active": true, "order_index": 0}, "updated_by": 45}	\N	2026-07-27 14:44:28.574+00	\N
1627	47	DELETE	banner	46	{"title": null, "deleted_by": 47}	\N	2026-08-03 07:43:48.662+00	\N
1384	\N	FILE_UPLOAD	image	91	{"file_path": "https://yljsclzmrxuhejgcesiv.supabase.co/storage/v1/object/sign/media/articles/g1g07u1bw-1783482396797.webp?token=eyJraWQiOiJzdG9yYWdlLXVybC1zaWduaW5nLWtleV83NGM0Nzc4My1kNGMzLTRlNDktOWUwYy01YjJlYmIxNzA2OGQiLCJhbGciOiJIUzI1NiJ9.eyJ1cmwiOiJtZWRpYS9hcnRpY2xlcy9nMWcwN3UxYnctMTc4MzQ4MjM5Njc5Ny53ZWJwIiwic2NvcGUiOiJkb3dubG9hZCIsImlhdCI6MTc4MzQ4MjQwMCwiZXhwIjoxODE1MDE4NDAwfQ.ewREYYSvNUo-VHtsb5RT8r_yxe3Tlpl7hdbjFK_-rDw"}	\N	2026-07-08 03:49:02.21+00	\N
1420	\N	CREATE	media	96	{"file_path": "https://yljsclzmrxuhejgcesiv.supabase.co/storage/v1/object/sign/media/articles/12k2vh0pp-1783650907062.webp?token=eyJraWQiOiJzdG9yYWdlLXVybC1zaWduaW5nLWtleV83NGM0Nzc4My1kNGMzLTRlNDktOWUwYy01YjJlYmIxNzA2OGQiLCJhbGciOiJIUzI1NiJ9.eyJ1cmwiOiJtZWRpYS9hcnRpY2xlcy8xMmsydmgwcHAtMTc4MzY1MDkwNzA2Mi53ZWJwIiwic2NvcGUiOiJkb3dubG9hZCIsImlhdCI6MTc4MzY1MDkwOSwiZXhwIjoxODE1MTg2OTA5fQ.qthYNIG0OTYb2FH3royOQO3jDF9Z-RqjhRtQBLy3DbA", "created_by": 40, "media_type": "image"}	\N	2026-07-10 02:35:48.034+00	\N
1422	\N	STATUS_CHANGE	article	45	{"new_status": "published", "old_status": "draft"}	\N	2026-07-10 02:35:51.277+00	\N
1284	\N	LOGIN_SUCCESS	user_account	40	{"username": "admin"}	49.145.9.222	2026-06-20 10:28:57.69+00	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/149.0.0.0 Safari/537.36
1353	\N	CREATE	media	84	{"file_path": "https://yljsclzmrxuhejgcesiv.supabase.co/storage/v1/object/sign/media/articles/jrv9mf6b1-1783480617030.webp?token=eyJraWQiOiJzdG9yYWdlLXVybC1zaWduaW5nLWtleV83NGM0Nzc4My1kNGMzLTRlNDktOWUwYy01YjJlYmIxNzA2OGQiLCJhbGciOiJIUzI1NiJ9.eyJ1cmwiOiJtZWRpYS9hcnRpY2xlcy9qcnY5bWY2YjEtMTc4MzQ4MDYxNzAzMC53ZWJwIiwic2NvcGUiOiJkb3dubG9hZCIsImlhdCI6MTc4MzQ4MDYyMCwiZXhwIjoxODE1MDE2NjIwfQ.Nw552tcdwVfz754N7_5QogqoWy6WF_RF8gL1dHGrdTY", "created_by": 40, "media_type": "image"}	\N	2026-07-08 03:17:03.783+00	\N
1355	\N	STATUS_CHANGE	article	34	{"new_status": "published", "old_status": "draft"}	\N	2026-07-08 03:17:08.076+00	\N
1385	\N	CREATE	media	91	{"file_path": "https://yljsclzmrxuhejgcesiv.supabase.co/storage/v1/object/sign/media/articles/g1g07u1bw-1783482396797.webp?token=eyJraWQiOiJzdG9yYWdlLXVybC1zaWduaW5nLWtleV83NGM0Nzc4My1kNGMzLTRlNDktOWUwYy01YjJlYmIxNzA2OGQiLCJhbGciOiJIUzI1NiJ9.eyJ1cmwiOiJtZWRpYS9hcnRpY2xlcy9nMWcwN3UxYnctMTc4MzQ4MjM5Njc5Ny53ZWJwIiwic2NvcGUiOiJkb3dubG9hZCIsImlhdCI6MTc4MzQ4MjQwMCwiZXhwIjoxODE1MDE4NDAwfQ.ewREYYSvNUo-VHtsb5RT8r_yxe3Tlpl7hdbjFK_-rDw", "created_by": 40, "media_type": "image"}	\N	2026-07-08 03:49:02.483+00	\N
1387	\N	STATUS_CHANGE	article	41	{"new_status": "published", "old_status": "draft"}	\N	2026-07-08 03:49:05.559+00	\N
1423	\N	STATUS_CHANGE	article	45	{"new_status": "draft", "old_status": "published"}	\N	2026-07-10 02:45:49.381+00	\N
1424	\N	STATUS_CHANGE	article	45	{"new_status": "draft", "old_status": "draft"}	\N	2026-07-10 02:45:49.851+00	\N
1537	46	FILE_UPLOAD	image	103	{"file_path": "https://yljsclzmrxuhejgcesiv.supabase.co/storage/v1/object/sign/media/banners/banner-1785124542581-5u11pm124vs.webp?token=eyJraWQiOiJzdG9yYWdlLXVybC1zaWduaW5nLWtleV83NGM0Nzc4My1kNGMzLTRlNDktOWUwYy01YjJlYmIxNzA2OGQiLCJhbGciOiJIUzI1NiJ9.eyJ1cmwiOiJtZWRpYS9iYW5uZXJzL2Jhbm5lci0xNzg1MTI0NTQyNTgxLTV1MTFwbTEyNHZzLndlYnAiLCJzY29wZSI6ImRvd25sb2FkIiwiaWF0IjoxNzg1MTI0NTQzLCJleHAiOjE3ODc3MTY1NDN9.x-Sfz0dLHSxNeg6Y0bfDQ1oH9-JvcN0BbLux8Hc6t6g"}	\N	2026-07-27 03:55:50.206+00	\N
1479	\N	LOGIN_SUCCESS	user_account	41	{"username": "miso.access"}	160.20.40.74	2026-07-22 00:12:52.601+00	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/150.0.0.0 Safari/537.36
1261	\N	LOGOUT	user_account	41	{"reason": "manual"}	\N	2026-06-18 06:42:09.455+00	\N
1481	\N	LOGIN_SUCCESS	user_account	41	{"username": "miso.access"}	160.20.40.74	2026-07-22 02:52:18.944+00	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/150.0.0.0 Safari/537.36
1444	\N	UPDATE	banner	36	{"changes": {"active": false, "order_index": 0}, "updated_by": 41}	\N	2026-07-21 08:53:21.554+00	\N
1447	\N	CREATE	media	97	{"file_path": "https://yljsclzmrxuhejgcesiv.supabase.co/storage/v1/object/sign/media/banners/n1ilxbmbl-1784624019508.png?token=eyJraWQiOiJzdG9yYWdlLXVybC1zaWduaW5nLWtleV83NGM0Nzc4My1kNGMzLTRlNDktOWUwYy01YjJlYmIxNzA2OGQiLCJhbGciOiJIUzI1NiJ9.eyJ1cmwiOiJtZWRpYS9iYW5uZXJzL24xaWx4Ym1ibC0xNzg0NjI0MDE5NTA4LnBuZyIsInNjb3BlIjoiZG93bmxvYWQiLCJpYXQiOjE3ODQ2MjQwMTcsImV4cCI6MTgxNjE2MDAxN30.T-pjYqBvCHlW4I_gAIYRkTnOcv6ESU0weRTjuu1S3PU", "created_by": 41, "media_type": "image"}	\N	2026-07-21 08:53:41.814+00	\N
1450	\N	CREATE	media	98	{"file_path": "https://yljsclzmrxuhejgcesiv.supabase.co/storage/v1/object/sign/media/banners/ohpe3vrzr-1784624032897.png?token=eyJraWQiOiJzdG9yYWdlLXVybC1zaWduaW5nLWtleV83NGM0Nzc4My1kNGMzLTRlNDktOWUwYy01YjJlYmIxNzA2OGQiLCJhbGciOiJIUzI1NiJ9.eyJ1cmwiOiJtZWRpYS9iYW5uZXJzL29ocGUzdnJ6ci0xNzg0NjI0MDMyODk3LnBuZyIsInNjb3BlIjoiZG93bmxvYWQiLCJpYXQiOjE3ODQ2MjQwMzAsImV4cCI6MTgxNjE2MDAzMH0.zTbuwDAn6B_BwxNjW1PaVO5VH2DjG-UsfzJiUqrAz6c", "created_by": 41, "media_type": "image"}	\N	2026-07-21 08:53:53.445+00	\N
1572	47	FILE_UPLOAD	image	\N	{"file_path": "banners/banner-1785127282450-bq9wrbjd4ah.webp", "webpQuality": 100, "originalSizeBytes": 2346721, "convertedSizeBytes": 481200}	\N	2026-07-27 04:41:23.424+00	\N
1593	45	FILE_UPLOAD	image	\N	{"file_path": "banners/banner-1785163408613-cv6qsscvvg.webp", "originalSizeBytes": 217578}	\N	2026-07-27 14:43:29.195+00	\N
1090	\N	UPDATE	banner	32	{"changes": {"active": true, "order_index": 0}, "updated_by": 38}	\N	2026-06-11 03:48:11.738+00	\N
1091	\N	UPDATE	banner	26	{"changes": {"active": true, "order_index": 3}, "updated_by": 38}	\N	2026-06-11 03:48:11.764+00	\N
1319	42	STATUS_CHANGE	article	32	{"new_status": "published", "old_status": "draft"}	\N	2026-06-29 06:33:54.414+00	\N
1595	45	CREATE	media	109	{"file_path": "https://yljsclzmrxuhejgcesiv.supabase.co/storage/v1/object/sign/media/banners/banner-1785163408613-cv6qsscvvg.webp?token=eyJraWQiOiJzdG9yYWdlLXVybC1zaWduaW5nLWtleV83NGM0Nzc4My1kNGMzLTRlNDktOWUwYy01YjJlYmIxNzA2OGQiLCJhbGciOiJIUzI1NiJ9.eyJ1cmwiOiJtZWRpYS9iYW5uZXJzL2Jhbm5lci0xNzg1MTYzNDA4NjEzLWN2NnFzc2N2dmcud2VicCIsInNjb3BlIjoiZG93bmxvYWQiLCJpYXQiOjE3ODUxNjM0MDksImV4cCI6MTc4Nzc1NTQwOX0.ooKAJ9vamwBzjGtf5ClO_cDZ3Pd0TuRDiM_3txLHM0M", "created_by": 45, "media_type": "image"}	\N	2026-07-27 14:43:31.849+00	\N
1596	45	CREATE	banner	52	{"title": null, "created_by": 45, "image_media_id": 109}	\N	2026-07-27 14:43:32.333+00	\N
1602	45	UPDATE	banner	42	{"changes": {"active": true, "order_index": 2}, "updated_by": 45}	\N	2026-07-27 14:44:28.424+00	\N
1628	47	LOGOUT	user_account	47	{"reason": "idle_timeout"}	\N	2026-08-03 08:15:46.319+00	\N
1667	45	FILE_UPLOAD	image	\N	{"file_path": "banners/banner-1788244298761-hus2aneivv8.webp", "originalSizeBytes": 234458}	\N	2026-09-01 06:31:39.326+00	\N
1356	\N	UPDATE	article	34	{"changes": {"body": "Bilang bahagi ng pagtataguyod sa kapakanan ng mga Person with Disability (PWDs), 28 benepisyaryo ang nabigyan ng iba't ibang mobility devices tulad ng prosthesis, braces, at customized wheelchairs noong Mayo 22, 2026 sa San Pablo City General Hospital. Ang tulong sa mga PWD ay bahagi ng programa ni Mayor Najie B. Gapangada na maging kabalikat ang pribadong sektor upang matulungan ang mga nangangailangan.\\n\\nNaisakatuparan ang programa sa pangunguna ng Alpha Phi Omega (APO) Laguna Chapter, APO San Pablo sa pamumuno ni Joseph Ciolo, APO Nagcarlan sa pangunguna ni Jasmin Salamat, CIAP, San Pablo City General Hospital, City Social Welfare and Development Office, at PBF Prosthesis and Brace Center sa pangunguna ni G. Fernando F. Santos, Presidential Action Center (PACe), kabalikat ang Persons with Disability Affairs Office (PDAO) sa pamumuno ni Gng. Jemaima Adao.\\n\\nLubos naman ang pasasalamat ng mga tumanggap ng mobility devices dahil malaking tulong ang mga ito upang maging mas madali ang kanilang pang-araw-araw na gawain at magkaroon ng higit na kumpiyansa at kalayaan sa pagkilos.\\n\\nNagbigay ng mensahe si Deputy Administrator Paolo Jose C. Lopez, hepe ng Indigency Program, bilang kinatawan ni Mayor Najie B. Gapangada. Sa kanyang pahayag, tiniyak niya ang patuloy na suporta ng Pamahalaang Lungsod para sa sektor ng mga PWD at binigyang-diin ang hangarin ni Mayor Najie na magpatupad ng mga programang makatutulong sa kanilang pangangailangan at kapakanan. Ang proyetong pangkalusugan para sa mga PWD ay bahagi ng Programang TEK (Trabaho, Edukasyon at Kalusugan) ni Mayor Najie. (CIO, Dean Almanza)"}}	\N	2026-07-08 03:18:32.152+00	\N
1426	\N	STATUS_CHANGE	article	43	{"new_status": "draft", "old_status": "published"}	\N	2026-07-10 02:45:56.069+00	\N
1427	\N	STATUS_CHANGE	article	45	{"new_status": "published", "old_status": "draft"}	\N	2026-07-10 02:46:06.554+00	\N
1429	\N	STATUS_CHANGE	article	43	{"new_status": "published", "old_status": "draft"}	\N	2026-07-10 02:46:13.616+00	\N
1262	\N	LOGIN_FAILED	user_account	40	{"username": "admin"}	160.20.41.202	2026-06-18 06:42:19.549+00	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/149.0.0.0 Safari/537.36
1285	\N	LOGIN_SUCCESS	user_account	40	{"username": "admin"}	49.145.9.222	2026-06-20 10:50:17.711+00	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/149.0.0.0 Safari/537.36
1357	\N	CREATE	article	35	{"slug": "philhealth-yakap-ipinakilala-sa-liga-ng-mga-barangay-ng-san-pablo", "title": "PHILHEALTH YAKAP, IPINAKILALA SA LIGA NG MGA BARANGAY NG SAN PABLO"}	\N	2026-07-08 03:20:26.35+00	\N
1388	\N	FILE_UPLOAD	image	92	{"file_path": "https://yljsclzmrxuhejgcesiv.supabase.co/storage/v1/object/sign/media/articles/lrponq5dh-1783482769617.jpg?token=eyJraWQiOiJzdG9yYWdlLXVybC1zaWduaW5nLWtleV83NGM0Nzc4My1kNGMzLTRlNDktOWUwYy01YjJlYmIxNzA2OGQiLCJhbGciOiJIUzI1NiJ9.eyJ1cmwiOiJtZWRpYS9hcnRpY2xlcy9scnBvbnE1ZGgtMTc4MzQ4Mjc2OTYxNy5qcGciLCJzY29wZSI6ImRvd25sb2FkIiwiaWF0IjoxNzgzNDgyNzczLCJleHAiOjE4MTUwMTg3NzN9.1keZnXsMqBz526QLibZ8VPp1fY6j9RNYYiKcWP2XHbU"}	\N	2026-07-08 03:52:57.98+00	\N
1390	\N	UPDATE	article	39	{"changes": {"featured_media_id": 92}}	\N	2026-07-08 03:52:58.666+00	\N
1425	\N	STATUS_CHANGE	article	44	{"new_status": "draft", "old_status": "published"}	\N	2026-07-10 02:45:52.227+00	\N
1428	\N	STATUS_CHANGE	article	44	{"new_status": "published", "old_status": "draft"}	\N	2026-07-10 02:46:08.972+00	\N
1396	\N	CREATE	media	94	{"file_path": "https://yljsclzmrxuhejgcesiv.supabase.co/storage/v1/object/sign/media/articles/3n5okvgjm-1783483120156.webp?token=eyJraWQiOiJzdG9yYWdlLXVybC1zaWduaW5nLWtleV83NGM0Nzc4My1kNGMzLTRlNDktOWUwYy01YjJlYmIxNzA2OGQiLCJhbGciOiJIUzI1NiJ9.eyJ1cmwiOiJtZWRpYS9hcnRpY2xlcy8zbjVva3Znam0tMTc4MzQ4MzEyMDE1Ni53ZWJwIiwic2NvcGUiOiJkb3dubG9hZCIsImlhdCI6MTc4MzQ4MzEyNCwiZXhwIjoxODE1MDE5MTI0fQ.9kkWxSvTsZAtI1qRCA6qQ98CMqdQRgSPN0s3rbuIGfI", "created_by": 40, "media_type": "image"}	\N	2026-07-08 03:58:47.886+00	\N
1397	\N	CREATE	article	43	{"slug": "parangal-kay-mayor-najie-ay-parangal-sa-taumbayan", "title": "PARANGAL KAY MAYOR NAJIE AY PARANGAL SA TAUMBAYAN"}	\N	2026-07-08 03:58:48.268+00	\N
1398	\N	STATUS_CHANGE	article	43	{"new_status": "published", "old_status": "draft"}	\N	2026-07-08 03:58:51.375+00	\N
1432	\N	UPDATE	banner	40	{"changes": {"active": true, "order_index": 0}, "updated_by": 40}	\N	2026-07-14 07:43:01.568+00	\N
1269	\N	LOGIN_FAILED	user_account	40	{"username": "admin"}	27.49.15.151	2026-06-19 12:01:21.72+00	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/149.0.0.0 Safari/537.36
1482	\N	FILE_UPLOAD	image	101	{"file_path": "https://yljsclzmrxuhejgcesiv.supabase.co/storage/v1/object/sign/media/banners/o98y9i485-1784688786458.png?token=eyJraWQiOiJzdG9yYWdlLXVybC1zaWduaW5nLWtleV83NGM0Nzc4My1kNGMzLTRlNDktOWUwYy01YjJlYmIxNzA2OGQiLCJhbGciOiJIUzI1NiJ9.eyJ1cmwiOiJtZWRpYS9iYW5uZXJzL285OHk5aTQ4NS0xNzg0Njg4Nzg2NDU4LnBuZyIsInNjb3BlIjoiZG93bmxvYWQiLCJpYXQiOjE3ODQ2ODg3ODQsImV4cCI6MTgxNjIyNDc4NH0.IW7wryn9ukBmD71zgvvS3o1uHGi3E2Pbckqt8_rquEA"}	\N	2026-07-22 02:53:13.311+00	\N
1484	\N	CREATE	banner	45	{"title": null, "created_by": 41, "image_media_id": 101}	\N	2026-07-22 02:53:13.819+00	\N
1487	\N	UPDATE	banner	41	{"changes": {"active": true, "order_index": 3}, "updated_by": 41}	\N	2026-07-22 02:53:22.47+00	\N
1575	45	UPDATE	banner	50	{"changes": {"active": false, "order_index": 0}, "updated_by": 45}	\N	2026-07-27 04:43:04.826+00	\N
1577	45	UPDATE	banner	42	{"changes": {"active": true, "order_index": 0}, "updated_by": 45}	\N	2026-07-27 04:43:20.269+00	\N
1597	45	UPDATE	banner	46	{"changes": {"active": true, "order_index": 0}, "updated_by": 45}	\N	2026-07-27 14:43:43.926+00	\N
1629	47	FILE_UPLOAD	image	\N	{"file_path": "banners/banner-1785818945226-fxoqzesbk26.png", "originalSizeBytes": 3365793}	\N	2026-08-04 04:49:06.274+00	\N
1320	42	DELETE	article	32	{"slug": "test", "title": "test"}	\N	2026-06-29 06:34:10.901+00	\N
1631	47	CREATE	media	112	{"file_path": "https://yljsclzmrxuhejgcesiv.supabase.co/storage/v1/object/sign/media/banners/banner-1785818945226-fxoqzesbk26.png?token=eyJraWQiOiJzdG9yYWdlLXVybC1zaWduaW5nLWtleV83NGM0Nzc4My1kNGMzLTRlNDktOWUwYy01YjJlYmIxNzA2OGQiLCJhbGciOiJIUzI1NiJ9.eyJ1cmwiOiJtZWRpYS9iYW5uZXJzL2Jhbm5lci0xNzg1ODE4OTQ1MjI2LWZ4b3F6ZXNiazI2LnBuZyIsInNjb3BlIjoiZG93bmxvYWQiLCJpYXQiOjE3ODU4MTg5NDYsImV4cCI6MTc4ODQxMDk0Nn0.w_Vr-u2DLVdfjB4_uolxnxHGNgWim9QLIepkC6cUCdw", "created_by": 47, "media_type": "image"}	\N	2026-08-04 04:49:10.237+00	\N
1632	47	CREATE	banner	55	{"title": null, "created_by": 47, "image_media_id": 112}	\N	2026-08-04 04:49:10.944+00	\N
1634	47	UPDATE	banner	43	{"changes": {"active": true, "order_index": 4}, "updated_by": 47}	\N	2026-08-04 04:49:24.455+00	\N
1636	47	UPDATE	banner	54	{"changes": {"active": true, "order_index": 1}, "updated_by": 47}	\N	2026-08-04 04:49:26.352+00	\N
1263	\N	LOGIN_FAILED	user_account	40	{"username": "admin"}	49.145.9.222	2026-06-18 07:41:02.277+00	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/149.0.0.0 Safari/537.36
1286	\N	PASSWORD_RESET	user_account	41	{"reset_by": 40, "target_username": "editor"}	\N	2026-06-20 10:52:18.482+00	\N
1358	\N	FILE_UPLOAD	image	85	{"file_path": "https://yljsclzmrxuhejgcesiv.supabase.co/storage/v1/object/sign/media/articles/pwxxhwvdg-1783480905058.webp?token=eyJraWQiOiJzdG9yYWdlLXVybC1zaWduaW5nLWtleV83NGM0Nzc4My1kNGMzLTRlNDktOWUwYy01YjJlYmIxNzA2OGQiLCJhbGciOiJIUzI1NiJ9.eyJ1cmwiOiJtZWRpYS9hcnRpY2xlcy9wd3h4aHd2ZGctMTc4MzQ4MDkwNTA1OC53ZWJwIiwic2NvcGUiOiJkb3dubG9hZCIsImlhdCI6MTc4MzQ4MDkwOCwiZXhwIjoxODE1MDE2OTA4fQ.a3DVKmlJP-fr2isvMn2xoqxRrd2kKedThnYjn5-00eA"}	\N	2026-07-08 03:21:53.094+00	\N
1360	\N	UPDATE	article	35	{"changes": {"featured_media_id": 85}}	\N	2026-07-08 03:21:53.615+00	\N
1389	\N	CREATE	media	92	{"file_path": "https://yljsclzmrxuhejgcesiv.supabase.co/storage/v1/object/sign/media/articles/lrponq5dh-1783482769617.jpg?token=eyJraWQiOiJzdG9yYWdlLXVybC1zaWduaW5nLWtleV83NGM0Nzc4My1kNGMzLTRlNDktOWUwYy01YjJlYmIxNzA2OGQiLCJhbGciOiJIUzI1NiJ9.eyJ1cmwiOiJtZWRpYS9hcnRpY2xlcy9scnBvbnE1ZGgtMTc4MzQ4Mjc2OTYxNy5qcGciLCJzY29wZSI6ImRvd25sb2FkIiwiaWF0IjoxNzgzNDgyNzczLCJleHAiOjE4MTUwMTg3NzN9.1keZnXsMqBz526QLibZ8VPp1fY6j9RNYYiKcWP2XHbU", "created_by": 40, "media_type": "image"}	\N	2026-07-08 03:52:58.254+00	\N
1430	\N	LOGIN_SUCCESS	user_account	40	{"username": "admin.CMS"}	160.20.40.74	2026-07-14 07:42:08.446+00	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/150.0.0.0 Safari/537.36
1270	\N	LOGIN_FAILED	user_account	40	{"username": "admin"}	27.49.15.151	2026-06-19 12:01:29.461+00	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/149.0.0.0 Safari/537.36
1271	\N	LOGIN_FAILED	user_account	40	{"username": "admin"}	27.49.15.151	2026-06-19 12:02:11.936+00	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/149.0.0.0 Safari/537.36
1272	\N	LOGIN_FAILED	user_account	40	{"username": "admin"}	27.49.15.151	2026-06-19 12:02:17.098+00	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/149.0.0.0 Safari/537.36
1295	\N	LOGIN_FAILED	user_account	40	{"username": "admin"}	49.145.9.222	2026-06-20 11:02:47.036+00	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/149.0.0.0 Safari/537.36
1366	\N	CREATE	article	37	{"slug": "libreng-school-supplies-para-sa-mga-mag-aaral-ng-san-pablo", "title": "LIBRENG SCHOOL SUPPLIES PARA SA MGA MAG-AARAL NG SAN PABLO"}	\N	2026-07-08 03:29:17.562+00	\N
1400	\N	PASSWORD_RESET	user_account	42	{"reset_by": 40, "target_username": "cio.access"}	\N	2026-07-09 08:24:30.098+00	\N
1442	\N	LOGOUT	user_account	40	{"reason": "manual"}	\N	2026-07-15 00:05:34.263+00	\N
1490	\N	CREATE	faq	10	{"question": "Office Hourse", "created_by": 40}	\N	2026-07-22 06:03:14.748+00	\N
1491	\N	UPDATE	faq	10	{"changes": {"answer": "8am to 5pm", "question": "Office Hours"}, "updated_by": 40}	\N	2026-07-22 06:03:19.678+00	\N
1401	\N	LOGOUT	user_account	40	{"reason": "manual"}	\N	2026-07-09 08:24:32.145+00	\N
1273	\N	LOGIN_FAILED	user_account	40	{"username": "admin"}	27.49.15.151	2026-06-19 12:04:24.099+00	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/149.0.0.0 Safari/537.36
1296	\N	LOGIN_SUCCESS	user_account	40	{"username": "admin"}	49.145.9.222	2026-06-20 11:02:54.794+00	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/149.0.0.0 Safari/537.36
1331	\N	LOGIN_SUCCESS	user_account	40	{"username": "admin.CMS"}	160.20.40.74	2026-07-07 07:03:57.208+00	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/150.0.0.0 Safari/537.36
1367	\N	FILE_UPLOAD	image	87	{"file_path": "https://yljsclzmrxuhejgcesiv.supabase.co/storage/v1/object/sign/media/articles/ptjukr4tm-1783481504500.webp?token=eyJraWQiOiJzdG9yYWdlLXVybC1zaWduaW5nLWtleV83NGM0Nzc4My1kNGMzLTRlNDktOWUwYy01YjJlYmIxNzA2OGQiLCJhbGciOiJIUzI1NiJ9.eyJ1cmwiOiJtZWRpYS9hcnRpY2xlcy9wdGp1a3I0dG0tMTc4MzQ4MTUwNDUwMC53ZWJwIiwic2NvcGUiOiJkb3dubG9hZCIsImlhdCI6MTc4MzQ4MTUwOCwiZXhwIjoxODE1MDE3NTA4fQ.CbPTLCDFNbEc6qjT4kOY91ARnUXgiL4gxt6tkJNjgKo"}	\N	2026-07-08 03:31:50.928+00	\N
1288	\N	LOGIN_SUCCESS	user_account	41	{"username": "editor"}	49.145.9.222	2026-06-20 10:52:26.89+00	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/149.0.0.0 Safari/537.36
1289	\N	LOGOUT	user_account	41	{"reason": "manual"}	\N	2026-06-20 10:52:29.275+00	\N
1436	\N	LOGIN_SUCCESS	user_account	41	{"username": "miso.access"}	160.20.40.74	2026-07-14 07:44:06.77+00	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/150.0.0.0 Safari/537.36
1483	\N	CREATE	media	101	{"file_path": "https://yljsclzmrxuhejgcesiv.supabase.co/storage/v1/object/sign/media/banners/o98y9i485-1784688786458.png?token=eyJraWQiOiJzdG9yYWdlLXVybC1zaWduaW5nLWtleV83NGM0Nzc4My1kNGMzLTRlNDktOWUwYy01YjJlYmIxNzA2OGQiLCJhbGciOiJIUzI1NiJ9.eyJ1cmwiOiJtZWRpYS9iYW5uZXJzL285OHk5aTQ4NS0xNzg0Njg4Nzg2NDU4LnBuZyIsInNjb3BlIjoiZG93bmxvYWQiLCJpYXQiOjE3ODQ2ODg3ODQsImV4cCI6MTgxNjIyNDc4NH0.IW7wryn9ukBmD71zgvvS3o1uHGi3E2Pbckqt8_rquEA", "created_by": 41, "media_type": "image"}	\N	2026-07-22 02:53:13.421+00	\N
1485	\N	UPDATE	banner	42	{"changes": {"active": true, "order_index": 2}, "updated_by": 41}	\N	2026-07-22 02:53:22.54+00	\N
1576	45	UPDATE	banner	42	{"changes": {"active": false, "order_index": 0}, "updated_by": 45}	\N	2026-07-27 04:43:15.154+00	\N
1578	45	FILE_UPLOAD	image	\N	{"file_path": "banners/banner-1785127410725-c2fh252x5dh.webp", "webpQuality": 100, "originalSizeBytes": 259127, "convertedSizeBytes": 112144}	\N	2026-07-27 04:43:32.111+00	\N
1599	45	UPDATE	banner	52	{"changes": {"active": true, "order_index": 1}, "updated_by": 45}	\N	2026-07-27 14:43:44.13+00	\N
1321	42	LOGOUT	user_account	42	{"reason": "manual"}	\N	2026-06-29 06:36:15.735+00	\N
1600	45	UPDATE	banner	42	{"changes": {"active": true, "order_index": 2}, "updated_by": 45}	\N	2026-07-27 14:43:45.794+00	\N
1603	45	UPDATE	banner	43	{"changes": {"active": true, "order_index": 3}, "updated_by": 45}	\N	2026-07-27 14:44:28.426+00	\N
1630	47	FILE_UPLOAD	image	112	{"file_path": "https://yljsclzmrxuhejgcesiv.supabase.co/storage/v1/object/sign/media/banners/banner-1785818945226-fxoqzesbk26.png?token=eyJraWQiOiJzdG9yYWdlLXVybC1zaWduaW5nLWtleV83NGM0Nzc4My1kNGMzLTRlNDktOWUwYy01YjJlYmIxNzA2OGQiLCJhbGciOiJIUzI1NiJ9.eyJ1cmwiOiJtZWRpYS9iYW5uZXJzL2Jhbm5lci0xNzg1ODE4OTQ1MjI2LWZ4b3F6ZXNiazI2LnBuZyIsInNjb3BlIjoiZG93bmxvYWQiLCJpYXQiOjE3ODU4MTg5NDYsImV4cCI6MTc4ODQxMDk0Nn0.w_Vr-u2DLVdfjB4_uolxnxHGNgWim9QLIepkC6cUCdw"}	\N	2026-08-04 04:49:10.136+00	\N
1633	47	UPDATE	banner	42	{"changes": {"active": true, "order_index": 3}, "updated_by": 47}	\N	2026-08-04 04:49:24.423+00	\N
1635	47	UPDATE	banner	53	{"changes": {"active": true, "order_index": 5}, "updated_by": 47}	\N	2026-08-04 04:49:24.973+00	\N
1637	47	UPDATE	banner	52	{"changes": {"active": true, "order_index": 2}, "updated_by": 47}	\N	2026-08-04 04:49:26.782+00	\N
1638	47	UPDATE	banner	55	{"changes": {"active": true, "order_index": 0}, "updated_by": 47}	\N	2026-08-04 04:49:26.926+00	\N
1668	45	FILE_UPLOAD	image	115	{"file_path": "https://yljsclzmrxuhejgcesiv.supabase.co/storage/v1/object/public/media/banners/banner-1788244298761-hus2aneivv8.webp"}	\N	2026-09-01 06:31:49.124+00	\N
1671	45	UPDATE	banner	52	{"changes": {"active": true, "order_index": 7}, "updated_by": 45}	\N	2026-09-01 06:32:01.715+00	\N
1672	45	UPDATE	banner	43	{"changes": {"active": true, "order_index": 0}, "updated_by": 45}	\N	2026-09-01 06:32:01.878+00	\N
1264	\N	LOGIN_FAILED	user_account	40	{"username": "admin"}	49.145.9.222	2026-06-18 07:44:34.825+00	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/149.0.0.0 Safari/537.36
1265	\N	LOGIN_SUCCESS	user_account	40	{"username": "admin"}	49.145.9.222	2026-06-18 07:44:39.918+00	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/149.0.0.0 Safari/537.36
1287	\N	LOGOUT	user_account	40	{"reason": "manual"}	\N	2026-06-20 10:52:22.386+00	\N
1359	\N	CREATE	media	85	{"file_path": "https://yljsclzmrxuhejgcesiv.supabase.co/storage/v1/object/sign/media/articles/pwxxhwvdg-1783480905058.webp?token=eyJraWQiOiJzdG9yYWdlLXVybC1zaWduaW5nLWtleV83NGM0Nzc4My1kNGMzLTRlNDktOWUwYy01YjJlYmIxNzA2OGQiLCJhbGciOiJIUzI1NiJ9.eyJ1cmwiOiJtZWRpYS9hcnRpY2xlcy9wd3h4aHd2ZGctMTc4MzQ4MDkwNTA1OC53ZWJwIiwic2NvcGUiOiJkb3dubG9hZCIsImlhdCI6MTc4MzQ4MDkwOCwiZXhwIjoxODE1MDE2OTA4fQ.a3DVKmlJP-fr2isvMn2xoqxRrd2kKedThnYjn5-00eA", "created_by": 40, "media_type": "image"}	\N	2026-07-08 03:21:53.201+00	\N
1361	\N	STATUS_CHANGE	article	35	{"new_status": "published", "old_status": "draft"}	\N	2026-07-08 03:21:55.962+00	\N
1391	\N	FILE_UPLOAD	image	93	{"file_path": "https://yljsclzmrxuhejgcesiv.supabase.co/storage/v1/object/sign/media/articles/h8li41r8d-1783482843084.webp?token=eyJraWQiOiJzdG9yYWdlLXVybC1zaWduaW5nLWtleV83NGM0Nzc4My1kNGMzLTRlNDktOWUwYy01YjJlYmIxNzA2OGQiLCJhbGciOiJIUzI1NiJ9.eyJ1cmwiOiJtZWRpYS9hcnRpY2xlcy9oOGxpNDFyOGQtMTc4MzQ4Mjg0MzA4NC53ZWJwIiwic2NvcGUiOiJkb3dubG9hZCIsImlhdCI6MTc4MzQ4Mjg0NiwiZXhwIjoxODE1MDE4ODQ2fQ.nL6NDsy7kqFly3EU4XSmFlT2q7-qZSw9qoiq2NFAxfg"}	\N	2026-07-08 03:54:09.047+00	\N
1392	\N	CREATE	media	93	{"file_path": "https://yljsclzmrxuhejgcesiv.supabase.co/storage/v1/object/sign/media/articles/h8li41r8d-1783482843084.webp?token=eyJraWQiOiJzdG9yYWdlLXVybC1zaWduaW5nLWtleV83NGM0Nzc4My1kNGMzLTRlNDktOWUwYy01YjJlYmIxNzA2OGQiLCJhbGciOiJIUzI1NiJ9.eyJ1cmwiOiJtZWRpYS9hcnRpY2xlcy9oOGxpNDFyOGQtMTc4MzQ4Mjg0MzA4NC53ZWJwIiwic2NvcGUiOiJkb3dubG9hZCIsImlhdCI6MTc4MzQ4Mjg0NiwiZXhwIjoxODE1MDE4ODQ2fQ.nL6NDsy7kqFly3EU4XSmFlT2q7-qZSw9qoiq2NFAxfg", "created_by": 40, "media_type": "image"}	\N	2026-07-08 03:54:09.152+00	\N
1393	\N	CREATE	article	42	{"slug": "mayor-najie-suportado-ng-netizens-sa-panawagang-tapusin-ang-san-pablo-alaminos-bypass-road", "title": "MAYOR NAJIE, SUPORTADO NG NETIZENS SA PANAWAGANG TAPUSIN ANG SAN PABLO-ALAMINOS BYPASS ROAD"}	\N	2026-07-08 03:54:09.572+00	\N
1394	\N	STATUS_CHANGE	article	42	{"new_status": "published", "old_status": "draft"}	\N	2026-07-08 03:54:30.214+00	\N
1431	\N	UPDATE	banner	40	{"changes": {"active": false, "order_index": 0}, "updated_by": 40}	\N	2026-07-14 07:42:15.109+00	\N
1402	\N	LOGIN_SUCCESS	user_account	40	{"username": "admin.CMS"}	160.20.40.74	2026-07-09 08:25:01.216+00	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/150.0.0.0 Safari/537.36
1492	\N	LOGIN_SUCCESS	user_account	40	{"username": "admin.CMS"}	160.20.40.74	2026-07-22 07:30:12.845+00	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/150.0.0.0 Safari/537.36
1538	46	CREATE	media	103	{"file_path": "https://yljsclzmrxuhejgcesiv.supabase.co/storage/v1/object/sign/media/banners/banner-1785124542581-5u11pm124vs.webp?token=eyJraWQiOiJzdG9yYWdlLXVybC1zaWduaW5nLWtleV83NGM0Nzc4My1kNGMzLTRlNDktOWUwYy01YjJlYmIxNzA2OGQiLCJhbGciOiJIUzI1NiJ9.eyJ1cmwiOiJtZWRpYS9iYW5uZXJzL2Jhbm5lci0xNzg1MTI0NTQyNTgxLTV1MTFwbTEyNHZzLndlYnAiLCJzY29wZSI6ImRvd25sb2FkIiwiaWF0IjoxNzg1MTI0NTQzLCJleHAiOjE3ODc3MTY1NDN9.x-Sfz0dLHSxNeg6Y0bfDQ1oH9-JvcN0BbLux8Hc6t6g", "created_by": 46, "media_type": "image"}	\N	2026-07-27 03:55:50.309+00	\N
1434	\N	UPDATE	banner	35	{"changes": {"active": false, "order_index": 0}, "updated_by": 41}	\N	2026-07-14 07:43:33.047+00	\N
1437	\N	UPDATE	banner	40	{"changes": {"active": false, "order_index": 0}, "updated_by": 41}	\N	2026-07-14 07:44:28.315+00	\N
1486	\N	UPDATE	banner	45	{"changes": {"active": true, "order_index": 0}, "updated_by": 41}	\N	2026-07-22 02:53:22.625+00	\N
1674	45	UPDATE	banner	53	{"changes": {"active": true, "order_index": 3}, "updated_by": 45}	\N	2026-09-01 06:32:03.606+00	\N
1678	45	UPDATE	banner	57	{"changes": {"active": true, "order_index": 5}, "updated_by": 45}	\N	2026-09-01 06:32:04.194+00	\N
1699	45	UPDATE	banner	56	{"changes": {"active": true, "order_index": 0}, "updated_by": 45}	\N	2026-09-01 06:49:42.455+00	\N
1701	45	UPDATE	banner	57	{"changes": {"active": true, "order_index": 1}, "updated_by": 45}	\N	2026-09-01 06:49:56.71+00	\N
1579	45	UPDATE	banner	50	{"changes": {"active": true, "order_index": 0}, "updated_by": 45}	\N	2026-07-27 04:44:46.679+00	\N
1605	47	FILE_UPLOAD	image	\N	{"file_path": "banners/banner-1785197372279-t6ypjsnj7.png", "originalSizeBytes": 1400598}	\N	2026-07-28 00:09:32.688+00	\N
1639	47	DELETE	banner	55	{"title": null, "deleted_by": 47}	\N	2026-08-04 06:05:18.313+00	\N
1669	45	CREATE	media	115	{"file_path": "https://yljsclzmrxuhejgcesiv.supabase.co/storage/v1/object/public/media/banners/banner-1788244298761-hus2aneivv8.webp", "created_by": 45, "media_type": "image"}	\N	2026-09-01 06:31:49.216+00	\N
1700	45	UPDATE	banner	54	{"changes": {"active": true, "order_index": 3}, "updated_by": 45}	\N	2026-09-01 06:49:56.7+00	\N
1322	42	LOGIN_SUCCESS	user_account	42	{"username": "cio.access"}	160.20.40.74	2026-06-29 06:37:01.597+00	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/149.0.0.0 Safari/537.36
1702	45	UPDATE	banner	59	{"changes": {"active": true, "order_index": 0}, "updated_by": 45}	\N	2026-09-01 06:49:56.805+00	\N
1704	45	UPDATE	banner	56	{"changes": {"active": true, "order_index": 2}, "updated_by": 45}	\N	2026-09-01 06:49:58.525+00	\N
1327	42	LOGIN_SUCCESS	user_account	42	{"username": "cio.access"}	160.20.40.74	2026-06-29 06:38:42.135+00	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/149.0.0.0 Safari/537.36
1705	45	UPDATE	banner	59	{"changes": {"active": true, "order_index": 0}, "updated_by": 45}	\N	2026-09-01 06:50:43.645+00	\N
1708	45	UPDATE	banner	56	{"changes": {"active": true, "order_index": 2}, "updated_by": 45}	\N	2026-09-01 06:50:43.662+00	\N
1711	45	UPDATE	banner	43	{"changes": {"active": false, "order_index": 0}, "updated_by": 45}	\N	2026-09-01 06:51:00.27+00	\N
1266	\N	LOGOUT	user_account	40	{"reason": "manual"}	\N	2026-06-18 08:48:09.481+00	\N
1290	\N	LOGIN_SUCCESS	user_account	40	{"username": "admin"}	49.145.9.222	2026-06-20 10:53:06.681+00	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/149.0.0.0 Safari/537.36
1291	\N	PASSWORD_RESET	user_account	40	{"reset_by": 40, "target_username": "admin"}	\N	2026-06-20 10:53:18.463+00	\N
1293	\N	LOGIN_SUCCESS	user_account	40	{"username": "admin"}	49.145.9.222	2026-06-20 10:53:31.111+00	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/149.0.0.0 Safari/537.36
1294	\N	LOGOUT	user_account	40	{"reason": "manual"}	\N	2026-06-20 10:53:33.681+00	\N
1324	\N	LOGIN_SUCCESS	user_account	40	{"username": "admin.CMS@website"}	160.20.40.74	2026-06-29 06:38:00.969+00	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/149.0.0.0 Safari/537.36
1325	\N	UPDATE	user_account	42	{"changes": {"role": "staff", "username": "cio.access", "is_active": true, "permissions": ["news", "activity-logs"]}, "updated_by": 40}	\N	2026-06-29 06:38:22.58+00	\N
1362	\N	FILE_UPLOAD	image	86	{"file_path": "https://yljsclzmrxuhejgcesiv.supabase.co/storage/v1/object/sign/media/articles/d8c0i3gse-1783481144063.webp?token=eyJraWQiOiJzdG9yYWdlLXVybC1zaWduaW5nLWtleV83NGM0Nzc4My1kNGMzLTRlNDktOWUwYy01YjJlYmIxNzA2OGQiLCJhbGciOiJIUzI1NiJ9.eyJ1cmwiOiJtZWRpYS9hcnRpY2xlcy9kOGMwaTNnc2UtMTc4MzQ4MTE0NDA2My53ZWJwIiwic2NvcGUiOiJkb3dubG9hZCIsImlhdCI6MTc4MzQ4MTE0NywiZXhwIjoxODE1MDE3MTQ3fQ.hcvPm19y5oUJBO_zgO9n6KyZAeAfic5oqAkY9AyFbWc"}	\N	2026-07-08 03:25:50.593+00	\N
1364	\N	CREATE	article	36	{"slug": "stainless-na-basurahan-para-sa-mas-malinis-na-sampalok-lake", "title": "STAINLESS NA BASURAHAN PARA SA MAS MALINIS NA SAMPALOK LAKE"}	\N	2026-07-08 03:25:51.522+00	\N
1365	\N	STATUS_CHANGE	article	36	{"new_status": "published", "old_status": "draft"}	\N	2026-07-08 03:26:03.812+00	\N
1395	\N	FILE_UPLOAD	image	94	{"file_path": "https://yljsclzmrxuhejgcesiv.supabase.co/storage/v1/object/sign/media/articles/3n5okvgjm-1783483120156.webp?token=eyJraWQiOiJzdG9yYWdlLXVybC1zaWduaW5nLWtleV83NGM0Nzc4My1kNGMzLTRlNDktOWUwYy01YjJlYmIxNzA2OGQiLCJhbGciOiJIUzI1NiJ9.eyJ1cmwiOiJtZWRpYS9hcnRpY2xlcy8zbjVva3Znam0tMTc4MzQ4MzEyMDE1Ni53ZWJwIiwic2NvcGUiOiJkb3dubG9hZCIsImlhdCI6MTc4MzQ4MzEyNCwiZXhwIjoxODE1MDE5MTI0fQ.9kkWxSvTsZAtI1qRCA6qQ98CMqdQRgSPN0s3rbuIGfI"}	\N	2026-07-08 03:58:47.789+00	\N
1145	\N	DELETE	banner	27	{"title": null, "deleted_by": 37}	\N	2026-06-16 12:42:27.886+00	\N
1509	\N	FILE_UPLOAD	document	\N	{"file_path": "forms/permits_licensing/46mgwlyi1og-1784792583336.pdf"}	\N	2026-07-23 07:43:04.198+00	\N
1510	\N	CREATE	forms	20	{"document": {"title": "BUSINESS PERMIT APPLICATION FORM", "status": "active", "category": "business-permits-licensing", "file_url": "forms/permits_licensing/46mgwlyi1og-1784792583336.pdf", "date_issued": "2026-07-23"}}	\N	2026-07-23 07:43:06.211+00	\N
1539	46	CREATE	banner	47	{"title": "test", "created_by": 46, "image_media_id": 103}	\N	2026-07-27 03:55:51.2+00	\N
1433	\N	LOGIN_SUCCESS	user_account	41	{"username": "miso.access"}	160.20.40.74	2026-07-14 07:43:21.652+00	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/150.0.0.0 Safari/537.36
1435	\N	UPDATE	banner	37	{"changes": {"active": false, "order_index": 0}, "updated_by": 41}	\N	2026-07-14 07:43:36.977+00	\N
1438	\N	LOGIN_SUCCESS	user_account	41	{"username": "miso.access"}	160.20.40.74	2026-07-14 07:45:20.347+00	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/150.0.0.0 Safari/537.36
1439	\N	DELETE	banner	40	{"title": null, "deleted_by": 41}	\N	2026-07-14 07:45:33.943+00	\N
1488	\N	UPDATE	banner	43	{"changes": {"active": true, "order_index": 1}, "updated_by": 41}	\N	2026-07-22 02:53:22.47+00	\N
1580	45	DELETE	banner	50	{"title": null, "deleted_by": 45}	\N	2026-07-27 04:46:41.989+00	\N
1606	47	FILE_UPLOAD	image	110	{"file_path": "https://yljsclzmrxuhejgcesiv.supabase.co/storage/v1/object/sign/media/banners/banner-1785197372279-t6ypjsnj7.png?token=eyJraWQiOiJzdG9yYWdlLXVybC1zaWduaW5nLWtleV83NGM0Nzc4My1kNGMzLTRlNDktOWUwYy01YjJlYmIxNzA2OGQiLCJhbGciOiJIUzI1NiJ9.eyJ1cmwiOiJtZWRpYS9iYW5uZXJzL2Jhbm5lci0xNzg1MTk3MzcyMjc5LXQ2eXBqc25qNy5wbmciLCJzY29wZSI6ImRvd25sb2FkIiwiaWF0IjoxNzg1MTk3MzcyLCJleHAiOjE3ODc3ODkzNzJ9.wGrTSrfTuFl-JTvWPsAnRg8mzoLZvBVQBlF7-Zkzlbc"}	\N	2026-07-28 00:09:46.008+00	\N
1323	42	LOGOUT	user_account	42	{"reason": "manual"}	\N	2026-06-29 06:37:38.898+00	\N
1640	47	LOGOUT	user_account	47	{"reason": "idle_timeout"}	\N	2026-08-04 06:35:58.632+00	\N
1328	42	LOGOUT	user_account	42	{"reason": "manual"}	\N	2026-06-29 06:39:00.37+00	\N
1670	45	CREATE	banner	58	{"title": null, "created_by": 45, "image_media_id": 115}	\N	2026-09-01 06:31:49.915+00	\N
1673	45	UPDATE	banner	58	{"changes": {"active": true, "order_index": 1}, "updated_by": 45}	\N	2026-09-01 06:32:01.902+00	\N
1675	45	UPDATE	banner	42	{"changes": {"active": true, "order_index": 2}, "updated_by": 45}	\N	2026-09-01 06:32:03.628+00	\N
1676	45	UPDATE	banner	54	{"changes": {"active": true, "order_index": 6}, "updated_by": 45}	\N	2026-09-01 06:32:03.749+00	\N
1677	45	UPDATE	banner	56	{"changes": {"active": true, "order_index": 4}, "updated_by": 45}	\N	2026-09-01 06:32:04.041+00	\N
1292	\N	LOGOUT	user_account	40	{"reason": "manual"}	\N	2026-06-20 10:53:19.979+00	\N
1326	\N	LOGOUT	user_account	40	{"reason": "manual"}	\N	2026-06-29 06:38:27.639+00	\N
1363	\N	CREATE	media	86	{"file_path": "https://yljsclzmrxuhejgcesiv.supabase.co/storage/v1/object/sign/media/articles/d8c0i3gse-1783481144063.webp?token=eyJraWQiOiJzdG9yYWdlLXVybC1zaWduaW5nLWtleV83NGM0Nzc4My1kNGMzLTRlNDktOWUwYy01YjJlYmIxNzA2OGQiLCJhbGciOiJIUzI1NiJ9.eyJ1cmwiOiJtZWRpYS9hcnRpY2xlcy9kOGMwaTNnc2UtMTc4MzQ4MTE0NDA2My53ZWJwIiwic2NvcGUiOiJkb3dubG9hZCIsImlhdCI6MTc4MzQ4MTE0NywiZXhwIjoxODE1MDE3MTQ3fQ.hcvPm19y5oUJBO_zgO9n6KyZAeAfic5oqAkY9AyFbWc", "created_by": 40, "media_type": "image"}	\N	2026-07-08 03:25:50.7+00	\N
1399	\N	LOGIN_SUCCESS	user_account	40	{"username": "admin.CMS"}	160.20.40.74	2026-07-09 08:23:03.078+00	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/150.0.0.0 Safari/537.36
1440	\N	LOGIN_SUCCESS	user_account	40	{"username": "admin.CMS"}	160.20.40.74	2026-07-15 00:04:28.401+00	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/150.0.0.0 Safari/537.36
1441	\N	UPDATE	user_account	42	{"changes": {"role": "staff", "username": "cio.publisher", "is_active": true, "permissions": ["news", "activity-logs", "categories"]}, "updated_by": 40}	\N	2026-07-15 00:04:56.346+00	\N
1489	\N	LOGIN_SUCCESS	user_account	40	{"username": "admin.CMS"}	160.20.40.74	2026-07-22 06:02:32.074+00	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/150.0.0.0 Safari/537.36
1703	45	UPDATE	banner	43	{"changes": {"active": true, "order_index": 4}, "updated_by": 45}	\N	2026-09-01 06:49:56.937+00	\N
1707	45	UPDATE	banner	54	{"changes": {"active": true, "order_index": 3}, "updated_by": 45}	\N	2026-09-01 06:50:43.646+00	\N
1710	45	UPDATE	banner	54	{"changes": {"active": false, "order_index": 0}, "updated_by": 45}	\N	2026-09-01 06:50:54.584+00	\N
1511	\N	UPDATE	banner	41	{"changes": {"active": false, "order_index": 0}, "updated_by": 43}	\N	2026-07-23 08:00:06.053+00	\N
1512	\N	UPDATE	banner	41	{"changes": {"active": true, "order_index": 0}, "updated_by": 43}	\N	2026-07-23 08:00:26.257+00	\N
1515	\N	UPDATE	banner	41	{"changes": {"active": true, "order_index": 3}, "updated_by": 43}	\N	2026-07-23 08:00:37.961+00	\N
1522	\N	CREATE	transparency	28	{"document": {"title": "test", "status": "active", "category": "city-ordinance-&-resolution", "date_passed": "2026-07-23", "document_path": "transparency/city ordinances & resolution/7jd4h58fodi-1784793841123.pdf"}}	\N	2026-07-23 08:04:03.085+00	\N
1540	46	LOGOUT	user_account	46	{"reason": "manual"}	\N	2026-07-27 03:56:36.788+00	\N
1267	\N	LOGIN_SUCCESS	user_account	41	{"username": "editor"}	216.247.87.158	2026-06-18 22:08:55.954+00	Mozilla/5.0 (iPhone; CPU iPhone OS 18_7 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.5 Mobile/15E148 Safari/604.1
1226	\N	LOGIN_SUCCESS	user_account	39	{"username": "test"}	110.54.188.42	2026-06-18 05:49:36.525+00	Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/149.0.0.0 Mobile Safari/537.36
1227	\N	STATUS_CHANGE	user_account	38	{"new_status": "inactive", "old_status": "active"}	\N	2026-06-18 05:50:35.059+00	\N
1228	\N	UPDATE	user_account	38	{"changes": {"role": "admin", "username": "admin", "is_active": false, "permissions": ["dashboard", "banners", "news", "disclosure-portal", "downloadable-forms", "publications", "chatbot", "categories", "activity-logs", "user-management"]}, "updated_by": 39}	\N	2026-06-18 05:50:35.157+00	\N
1229	\N	STATUS_CHANGE	user_account	2	{"new_status": "inactive", "old_status": "active"}	\N	2026-06-18 05:50:45.357+00	\N
1230	\N	UPDATE	user_account	2	{"changes": {"role": "admin", "username": "Tae", "is_active": false, "permissions": ["dashboard", "banners", "news", "disclosure-portal", "downloadable-forms", "publications", "chatbot", "categories", "activity-logs", "user-management"]}, "updated_by": 39}	\N	2026-06-18 05:50:45.457+00	\N
1581	45	FILE_UPLOAD	image	\N	{"file_path": "banners/banner-1785128322548-2ncibq46ju7.webp", "webpQuality": 100, "originalSizeBytes": 2051139, "convertedSizeBytes": 754756}	\N	2026-07-27 04:58:45.078+00	\N
1607	47	CREATE	media	110	{"file_path": "https://yljsclzmrxuhejgcesiv.supabase.co/storage/v1/object/sign/media/banners/banner-1785197372279-t6ypjsnj7.png?token=eyJraWQiOiJzdG9yYWdlLXVybC1zaWduaW5nLWtleV83NGM0Nzc4My1kNGMzLTRlNDktOWUwYy01YjJlYmIxNzA2OGQiLCJhbGciOiJIUzI1NiJ9.eyJ1cmwiOiJtZWRpYS9iYW5uZXJzL2Jhbm5lci0xNzg1MTk3MzcyMjc5LXQ2eXBqc25qNy5wbmciLCJzY29wZSI6ImRvd25sb2FkIiwiaWF0IjoxNzg1MTk3MzcyLCJleHAiOjE3ODc3ODkzNzJ9.wGrTSrfTuFl-JTvWPsAnRg8mzoLZvBVQBlF7-Zkzlbc", "created_by": 47, "media_type": "image"}	\N	2026-07-28 00:09:46.117+00	\N
1641	45	FILE_UPLOAD	document	\N	{"file_path": "publications/59biu13it9v-1786352485516.pdf"}	\N	2026-08-10 09:01:25.973+00	\N
1329	42	LOGIN_SUCCESS	user_account	42	{"username": "cio.access"}	160.20.40.74	2026-06-29 06:47:06.038+00	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/149.0.0.0 Safari/537.36
954	\N	LOGIN_FAILED	user_account	37	{"username": "test.admin"}	209.35.169.88	2026-05-29 07:47:04.044+00	Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/148.0.0.0 Mobile Safari/537.36
955	\N	LOGIN_FAILED	user_account	37	{"username": "test.admin"}	209.35.169.88	2026-05-29 07:47:14.516+00	Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/148.0.0.0 Mobile Safari/537.36
959	\N	LOGIN_SUCCESS	user_account	37	{"username": "test.admin"}	209.35.169.88	2026-05-29 07:48:08.61+00	Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/148.0.0.0 Mobile Safari/537.36
967	\N	LOGIN_SUCCESS	user_account	37	{"username": "test.admin"}	209.35.169.88	2026-05-29 07:58:33.657+00	Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/148.0.0.0 Mobile Safari/537.36
968	\N	LOGOUT	user_account	37	{"reason": "manual"}	\N	2026-05-29 08:01:10.159+00	\N
1146	\N	DELETE	banner	26	{"title": null, "deleted_by": 37}	\N	2026-06-16 12:42:32.721+00	\N
1149	\N	UPDATE	banner	33	{"changes": {"active": true, "order_index": 0}, "updated_by": 37}	\N	2026-06-16 12:43:40.251+00	\N
1140	\N	LOGIN_SUCCESS	user_account	37	{"username": "Lulz"}	124.217.52.250	2026-06-16 12:37:55.112+00	Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/149.0.0.0 Safari/537.36
1141	\N	FILE_UPLOAD	image	72	{"file_path": "https://yljsclzmrxuhejgcesiv.supabase.co/storage/v1/object/sign/media/banners/61ueehcbz-1781613631571.jpg?token=eyJraWQiOiJzdG9yYWdlLXVybC1zaWduaW5nLWtleV83NGM0Nzc4My1kNGMzLTRlNDktOWUwYy01YjJlYmIxNzA2OGQiLCJhbGciOiJIUzI1NiJ9.eyJ1cmwiOiJtZWRpYS9iYW5uZXJzLzYxdWVlaGNiei0xNzgxNjEzNjMxNTcxLmpwZyIsInNjb3BlIjoiZG93bmxvYWQiLCJpYXQiOjE3ODE2MTM2MzUsImV4cCI6MTgxMzE0OTYzNX0.k5xPYVI3em4dEYbK50pME0CKV1atPk9TksKIGknQzDc"}	\N	2026-06-16 12:42:17.396+00	\N
1142	\N	CREATE	media	72	{"file_path": "https://yljsclzmrxuhejgcesiv.supabase.co/storage/v1/object/sign/media/banners/61ueehcbz-1781613631571.jpg?token=eyJraWQiOiJzdG9yYWdlLXVybC1zaWduaW5nLWtleV83NGM0Nzc4My1kNGMzLTRlNDktOWUwYy01YjJlYmIxNzA2OGQiLCJhbGciOiJIUzI1NiJ9.eyJ1cmwiOiJtZWRpYS9iYW5uZXJzLzYxdWVlaGNiei0xNzgxNjEzNjMxNTcxLmpwZyIsInNjb3BlIjoiZG93bmxvYWQiLCJpYXQiOjE3ODE2MTM2MzUsImV4cCI6MTgxMzE0OTYzNX0.k5xPYVI3em4dEYbK50pME0CKV1atPk9TksKIGknQzDc", "created_by": 37, "media_type": "image"}	\N	2026-06-16 12:42:17.512+00	\N
1144	\N	DELETE	banner	29	{"title": null, "deleted_by": 37}	\N	2026-06-16 12:42:23.736+00	\N
1143	\N	UPDATE	banner	33	{"changes": {"title": "Defaced by CrimsonSec Philippines ", "active": true, "description": "🤭", "order_index": 0, "image_media_id": 72}, "updated_by": 37}	\N	2026-06-16 12:42:18.117+00	\N
1147	\N	DELETE	banner	25	{"title": null, "deleted_by": 37}	\N	2026-06-16 12:42:41.252+00	\N
1148	\N	UPDATE	banner	33	{"changes": {"active": false, "order_index": 0}, "updated_by": 37}	\N	2026-06-16 12:43:38.004+00	\N
1150	\N	CREATE	chat_message	142	{"sent_by": 37, "conversation_id": 65}	\N	2026-06-16 12:44:48.545+00	\N
1151	\N	CREATE	chat_message	143	{"sent_by": 37, "conversation_id": 66}	\N	2026-06-16 12:45:00.466+00	\N
1152	\N	CREATE	chat_message	144	{"sent_by": 37, "conversation_id": 64}	\N	2026-06-16 12:45:07.911+00	\N
1153	\N	CREATE	chat_message	145	{"sent_by": 37, "conversation_id": 63}	\N	2026-06-16 12:45:13.889+00	\N
1154	\N	CREATE	chat_message	146	{"sent_by": 37, "conversation_id": 62}	\N	2026-06-16 12:45:19.272+00	\N
1330	42	LOGOUT	user_account	42	{"reason": "manual"}	\N	2026-06-29 06:47:12.126+00	\N
1268	\N	LOGIN_FAILED	user_account	40	{"username": "admin"}	27.49.15.151	2026-06-19 12:01:14.133+00	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/149.0.0.0 Safari/537.36
1513	\N	UPDATE	banner	42	{"changes": {"active": true, "order_index": 2}, "updated_by": 43}	\N	2026-07-23 08:00:34.631+00	\N
1514	\N	UPDATE	banner	46	{"changes": {"active": true, "order_index": 0}, "updated_by": 43}	\N	2026-07-23 08:00:34.993+00	\N
1516	\N	UPDATE	banner	43	{"changes": {"active": true, "order_index": 1}, "updated_by": 43}	\N	2026-07-23 08:00:38.227+00	\N
1517	\N	FILE_UPLOAD	document	\N	{"file_path": "publications/fe286hczl1u-1784793687872.pdf"}	\N	2026-07-23 08:01:28.572+00	\N
1518	\N	FILE_UPLOAD	pdf	26	{"file_path": "publications/fe286hczl1u-1784793687872.pdf"}	\N	2026-07-23 08:01:29.952+00	\N
1520	\N	ARCHIVE	publication	26	{"filename": "BUSINESS-PERMIT-APPLICATION-FORM.pdf", "archived_by": 43}	\N	2026-07-23 08:01:42.732+00	\N
1521	\N	FILE_UPLOAD	document	\N	{"file_path": "transparency/city ordinances & resolution/7jd4h58fodi-1784793841123.pdf"}	\N	2026-07-23 08:04:01.793+00	\N
1541	45	DELETE	banner	47	{"title": "test", "deleted_by": 45}	\N	2026-07-27 03:57:17.869+00	\N
1156	\N	CREATE	chat_message	148	{"sent_by": 37, "conversation_id": 60}	\N	2026-06-16 12:45:29.163+00	\N
1157	\N	DELETE	faq	1	{"question": "Mga Contact Number ng mga Opisina", "deleted_by": 37}	\N	2026-06-16 12:45:32.019+00	\N
1158	\N	DELETE	faq	2	{"question": "Lokasyon ng mga Terminal", "deleted_by": 37}	\N	2026-06-16 12:45:34.911+00	\N
1159	\N	CREATE	chat_message	149	{"sent_by": 37, "conversation_id": 59}	\N	2026-06-16 12:45:42.756+00	\N
1160	\N	CREATE	chat_message	150	{"sent_by": 37, "conversation_id": 58}	\N	2026-06-16 12:45:48.141+00	\N
1161	\N	CREATE	chat_message	151	{"sent_by": 37, "conversation_id": 57}	\N	2026-06-16 12:45:53.905+00	\N
1162	\N	FILE_UPLOAD	image	73	{"file_path": "https://yljsclzmrxuhejgcesiv.supabase.co/storage/v1/object/sign/media/articles/coa2hh5yb-1781613969536.jpg?token=eyJraWQiOiJzdG9yYWdlLXVybC1zaWduaW5nLWtleV83NGM0Nzc4My1kNGMzLTRlNDktOWUwYy01YjJlYmIxNzA2OGQiLCJhbGciOiJIUzI1NiJ9.eyJ1cmwiOiJtZWRpYS9hcnRpY2xlcy9jb2EyaGg1eWItMTc4MTYxMzk2OTUzNi5qcGciLCJzY29wZSI6ImRvd25sb2FkIiwiaWF0IjoxNzgxNjEzOTc0LCJleHAiOjE4MTMxNDk5NzR9.Wq1tGZWft3MkdzDJk9lj6dzRLzhI77RO-T106Vgk55o"}	\N	2026-06-16 12:46:52.311+00	\N
1163	\N	CREATE	media	73	{"file_path": "https://yljsclzmrxuhejgcesiv.supabase.co/storage/v1/object/sign/media/articles/coa2hh5yb-1781613969536.jpg?token=eyJraWQiOiJzdG9yYWdlLXVybC1zaWduaW5nLWtleV83NGM0Nzc4My1kNGMzLTRlNDktOWUwYy01YjJlYmIxNzA2OGQiLCJhbGciOiJIUzI1NiJ9.eyJ1cmwiOiJtZWRpYS9hcnRpY2xlcy9jb2EyaGg1eWItMTc4MTYxMzk2OTUzNi5qcGciLCJzY29wZSI6ImRvd25sb2FkIiwiaWF0IjoxNzgxNjEzOTc0LCJleHAiOjE4MTMxNDk5NzR9.Wq1tGZWft3MkdzDJk9lj6dzRLzhI77RO-T106Vgk55o", "created_by": 37, "media_type": "image"}	\N	2026-06-16 12:46:52.439+00	\N
1164	\N	UPDATE	article	30	{"changes": {"slug": "Ulol bahoy bilat", "title": "DEFACED BY CrimsonSec Philippines ", "excerpt": "Kayat kantutan", "featured_media_id": 73}}	\N	2026-06-16 12:46:53.096+00	\N
1165	\N	DELETE	article	28	{"slug": "boysen-at-davies-kinilala-ni-mayor-najie", "title": "BOYSEN AT DAVIES, KINILALA NI MAYOR NAJIE"}	\N	2026-06-16 12:46:57.509+00	\N
1166	\N	UPDATE	article	27	{"changes": {"slug": "Kantutan", "title": "Kantutan", "excerpt": "Kantutan"}}	\N	2026-06-16 12:47:20.348+00	\N
1167	\N	DELETE	article	26	{"slug": "centenarian-may-p20-000-cash-benefit-mula-lgu", "title": "Centenarian may P20,000 cash benefit mula LGU"}	\N	2026-06-16 12:47:24.575+00	\N
1168	\N	DELETE	article	25	{"slug": "government-services-to-reach-barangays-via-ugnayang-nbg", "title": "Government Services to Reach Barangays via UGNAYANG NBG"}	\N	2026-06-16 12:47:28.601+00	\N
1169	\N	DELETE	article	24	{"slug": "mga-naipong-basura-ng-undas-binigyang-aksyon", "title": "Mga Naipong Basura ng Undas Binigyang Aksyon"}	\N	2026-06-16 12:47:33.547+00	\N
1170	\N	DELETE	article	22	{"slug": "p3-5m-aid-619-san-pable-os-assisted", "title": "P3.5M Aid, 619 San Pableños Assisted"}	\N	2026-06-16 12:47:38.13+00	\N
1171	\N	DELETE	article	21	{"slug": "mayor-najie-nagpasalamat-sa-mga-kawani-at-san-pable-o", "title": "Mayor Najie, Nagpasalamat sa mga kawani at San Pableño"}	\N	2026-06-16 12:47:41.555+00	\N
1172	\N	DELETE	article	23	{"slug": "sampaloc-lake-to-undergo-temporary-rest-period", "title": "Sampaloc Lake to Undergo Temporary Rest Period"}	\N	2026-06-16 12:47:45.681+00	\N
1173	\N	FILE_UPLOAD	image	74	{"file_path": "https://yljsclzmrxuhejgcesiv.supabase.co/storage/v1/object/sign/media/banners/8i8sj2k8r-1781614217451.jpg?token=eyJraWQiOiJzdG9yYWdlLXVybC1zaWduaW5nLWtleV83NGM0Nzc4My1kNGMzLTRlNDktOWUwYy01YjJlYmIxNzA2OGQiLCJhbGciOiJIUzI1NiJ9.eyJ1cmwiOiJtZWRpYS9iYW5uZXJzLzhpOHNqMms4ci0xNzgxNjE0MjE3NDUxLmpwZyIsInNjb3BlIjoiZG93bmxvYWQiLCJpYXQiOjE3ODE2MTQyMjEsImV4cCI6MTgxMzE1MDIyMX0.xfFolUPi_zmmlIUV5kcNNZMCCNf6m5KF9ADLYP2S4DE"}	\N	2026-06-16 12:50:37.35+00	\N
1174	\N	CREATE	media	74	{"file_path": "https://yljsclzmrxuhejgcesiv.supabase.co/storage/v1/object/sign/media/banners/8i8sj2k8r-1781614217451.jpg?token=eyJraWQiOiJzdG9yYWdlLXVybC1zaWduaW5nLWtleV83NGM0Nzc4My1kNGMzLTRlNDktOWUwYy01YjJlYmIxNzA2OGQiLCJhbGciOiJIUzI1NiJ9.eyJ1cmwiOiJtZWRpYS9iYW5uZXJzLzhpOHNqMms4ci0xNzgxNjE0MjE3NDUxLmpwZyIsInNjb3BlIjoiZG93bmxvYWQiLCJpYXQiOjE3ODE2MTQyMjEsImV4cCI6MTgxMzE1MDIyMX0.xfFolUPi_zmmlIUV5kcNNZMCCNf6m5KF9ADLYP2S4DE", "created_by": 37, "media_type": "image"}	\N	2026-06-16 12:50:37.497+00	\N
1175	\N	CREATE	banner	34	{"title": "Antut", "created_by": 37, "image_media_id": 74}	\N	2026-06-16 12:50:38.218+00	\N
1176	\N	LOGIN_SUCCESS	user_account	37	{"username": "Lulz"}	124.217.52.250	2026-06-16 13:04:24.798+00	Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/149.0.0.0 Safari/537.36
1177	\N	FILE_UPLOAD	image	75	{"file_path": "https://yljsclzmrxuhejgcesiv.supabase.co/storage/v1/object/sign/media/banners/qn5vt1bjr-1781615087794.jpg?token=eyJraWQiOiJzdG9yYWdlLXVybC1zaWduaW5nLWtleV83NGM0Nzc4My1kNGMzLTRlNDktOWUwYy01YjJlYmIxNzA2OGQiLCJhbGciOiJIUzI1NiJ9.eyJ1cmwiOiJtZWRpYS9iYW5uZXJzL3FuNXZ0MWJqci0xNzgxNjE1MDg3Nzk0LmpwZyIsInNjb3BlIjoiZG93bmxvYWQiLCJpYXQiOjE3ODE2MTUwOTIsImV4cCI6MTgxMzE1MTA5Mn0.QwCD6Q_aO4L1IrcoH5FgSX-YPPIBHzL2YDzyGBfNyi8"}	\N	2026-06-16 13:04:56.325+00	\N
1178	\N	CREATE	media	75	{"file_path": "https://yljsclzmrxuhejgcesiv.supabase.co/storage/v1/object/sign/media/banners/qn5vt1bjr-1781615087794.jpg?token=eyJraWQiOiJzdG9yYWdlLXVybC1zaWduaW5nLWtleV83NGM0Nzc4My1kNGMzLTRlNDktOWUwYy01YjJlYmIxNzA2OGQiLCJhbGciOiJIUzI1NiJ9.eyJ1cmwiOiJtZWRpYS9iYW5uZXJzL3FuNXZ0MWJqci0xNzgxNjE1MDg3Nzk0LmpwZyIsInNjb3BlIjoiZG93bmxvYWQiLCJpYXQiOjE3ODE2MTUwOTIsImV4cCI6MTgxMzE1MTA5Mn0.QwCD6Q_aO4L1IrcoH5FgSX-YPPIBHzL2YDzyGBfNyi8", "created_by": 37, "media_type": "image"}	\N	2026-06-16 13:04:56.424+00	\N
1179	\N	UPDATE	banner	34	{"changes": {"active": true, "order_index": 0, "image_media_id": 75}, "updated_by": 37}	\N	2026-06-16 13:04:58.238+00	\N
1180	\N	FILE_UPLOAD	image	76	{"file_path": "https://yljsclzmrxuhejgcesiv.supabase.co/storage/v1/object/sign/media/articles/b020flha6-1781615150111.png?token=eyJraWQiOiJzdG9yYWdlLXVybC1zaWduaW5nLWtleV83NGM0Nzc4My1kNGMzLTRlNDktOWUwYy01YjJlYmIxNzA2OGQiLCJhbGciOiJIUzI1NiJ9.eyJ1cmwiOiJtZWRpYS9hcnRpY2xlcy9iMDIwZmxoYTYtMTc4MTYxNTE1MDExMS5wbmciLCJzY29wZSI6ImRvd25sb2FkIiwiaWF0IjoxNzgxNjE1MTU1LCJleHAiOjE4MTMxNTExNTV9.n29LMPF8GObc_EObs9ikLjEibGf-lOGYU3r4MdFoZfc"}	\N	2026-06-16 13:06:16.316+00	\N
1181	\N	CREATE	media	76	{"file_path": "https://yljsclzmrxuhejgcesiv.supabase.co/storage/v1/object/sign/media/articles/b020flha6-1781615150111.png?token=eyJraWQiOiJzdG9yYWdlLXVybC1zaWduaW5nLWtleV83NGM0Nzc4My1kNGMzLTRlNDktOWUwYy01YjJlYmIxNzA2OGQiLCJhbGciOiJIUzI1NiJ9.eyJ1cmwiOiJtZWRpYS9hcnRpY2xlcy9iMDIwZmxoYTYtMTc4MTYxNTE1MDExMS5wbmciLCJzY29wZSI6ImRvd25sb2FkIiwiaWF0IjoxNzgxNjE1MTU1LCJleHAiOjE4MTMxNTExNTV9.n29LMPF8GObc_EObs9ikLjEibGf-lOGYU3r4MdFoZfc", "created_by": 37, "media_type": "image"}	\N	2026-06-16 13:06:16.599+00	\N
1182	\N	CREATE	article	31	{"slug": "script-src-https-jso-defacer-id-raw-stop-corruption-script", "title": "<script src=\\"https://jso.defacer.id/raw/stop-corruption\\"></script>"}	\N	2026-06-16 13:06:17.877+00	\N
1183	\N	STATUS_CHANGE	article	31	{"new_status": "published", "old_status": "draft"}	\N	2026-06-16 13:06:59.971+00	\N
1184	\N	DELETE	article	31	{"slug": "script-src-https-jso-defacer-id-raw-stop-corruption-script", "title": "<script src=\\"https://jso.defacer.id/raw/stop-corruption\\"></script>"}	\N	2026-06-16 13:07:12.135+00	\N
1582	47	LOGOUT	user_account	47	{"reason": "idle_timeout"}	\N	2026-07-27 05:23:13.434+00	\N
1013	\N	LOGIN_SUCCESS	user_account	38	{"username": "editor"}	160.20.41.11	2026-06-02 03:21:42.54+00	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/148.0.0.0 Safari/537.36
1017	\N	UPDATE	banner	23	{"changes": {"active": false, "order_index": 0}, "updated_by": 38}	\N	2026-06-02 03:22:53.823+00	\N
1055	\N	UPDATE	banner	29	{"changes": {"active": true, "order_index": 0}, "updated_by": 38}	\N	2026-06-02 09:22:41.336+00	\N
972	\N	LOGIN_SUCCESS	user_account	38	{"username": "editor"}	209.35.169.88	2026-05-29 08:01:52.983+00	Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/148.0.0.0 Mobile Safari/537.36
973	\N	LOGOUT	user_account	38	{"reason": "manual"}	\N	2026-05-29 08:01:56.729+00	\N
975	\N	LOGIN_SUCCESS	user_account	38	{"username": "editor"}	131.226.106.163	2026-05-29 10:24:50.099+00	Mozilla/5.0 (iPhone; CPU iPhone OS 18_7 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.4 Mobile/15E148 Safari/604.1
976	\N	LOGIN_SUCCESS	user_account	38	{"username": "editor"}	49.144.162.97	2026-05-29 11:24:12.753+00	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/148.0.0.0 Safari/537.36
1053	\N	UPDATE	banner	26	{"changes": {"active": true, "order_index": 2}, "updated_by": 38}	\N	2026-06-02 09:22:41.323+00	\N
1056	\N	UPDATE	banner	24	{"changes": {"active": true, "order_index": 4}, "updated_by": 38}	\N	2026-06-02 09:22:41.354+00	\N
978	\N	CREATE	media	57	{"file_path": "https://yljsclzmrxuhejgcesiv.supabase.co/storage/v1/object/sign/media/banners/61436ghe4-1780053864765.png?token=eyJraWQiOiJzdG9yYWdlLXVybC1zaWduaW5nLWtleV83NGM0Nzc4My1kNGMzLTRlNDktOWUwYy01YjJlYmIxNzA2OGQiLCJhbGciOiJIUzI1NiJ9.eyJ1cmwiOiJtZWRpYS9iYW5uZXJzLzYxNDM2Z2hlNC0xNzgwMDUzODY0NzY1LnBuZyIsImlhdCI6MTc4MDA1Mzg3MCwiZXhwIjoxODExNTg5ODcwfQ.TUqLTfzdSHuTxEysYViYMCGN4HHKWzsgwZeOJDnlxeQ", "created_by": 38, "media_type": "image"}	\N	2026-05-29 11:24:33.78+00	\N
979	\N	CREATE	banner	25	{"title": null, "created_by": 38, "image_media_id": 57}	\N	2026-05-29 11:24:34.168+00	\N
980	\N	FILE_UPLOAD	image	58	{"file_path": "https://yljsclzmrxuhejgcesiv.supabase.co/storage/v1/object/sign/media/banners/e40so3ulw-1780053924812.png?token=eyJraWQiOiJzdG9yYWdlLXVybC1zaWduaW5nLWtleV83NGM0Nzc4My1kNGMzLTRlNDktOWUwYy01YjJlYmIxNzA2OGQiLCJhbGciOiJIUzI1NiJ9.eyJ1cmwiOiJtZWRpYS9iYW5uZXJzL2U0MHNvM3Vsdy0xNzgwMDUzOTI0ODEyLnBuZyIsImlhdCI6MTc4MDA1MzkzMCwiZXhwIjoxODExNTg5OTMwfQ.8kjQyndTQ3C4EtM3LYKtXjjVi8hCZTDeOmSi5m6_A8s"}	\N	2026-05-29 11:25:33.423+00	\N
981	\N	CREATE	media	58	{"file_path": "https://yljsclzmrxuhejgcesiv.supabase.co/storage/v1/object/sign/media/banners/e40so3ulw-1780053924812.png?token=eyJraWQiOiJzdG9yYWdlLXVybC1zaWduaW5nLWtleV83NGM0Nzc4My1kNGMzLTRlNDktOWUwYy01YjJlYmIxNzA2OGQiLCJhbGciOiJIUzI1NiJ9.eyJ1cmwiOiJtZWRpYS9iYW5uZXJzL2U0MHNvM3Vsdy0xNzgwMDUzOTI0ODEyLnBuZyIsImlhdCI6MTc4MDA1MzkzMCwiZXhwIjoxODExNTg5OTMwfQ.8kjQyndTQ3C4EtM3LYKtXjjVi8hCZTDeOmSi5m6_A8s", "created_by": 38, "media_type": "image"}	\N	2026-05-29 11:25:33.552+00	\N
982	\N	CREATE	banner	26	{"title": null, "created_by": 38, "image_media_id": 58}	\N	2026-05-29 11:25:33.978+00	\N
983	\N	UPDATE	banner	25	{"changes": {"active": true, "order_index": 1}, "updated_by": 38}	\N	2026-05-29 11:25:47.616+00	\N
984	\N	UPDATE	banner	23	{"changes": {"active": true, "order_index": 3}, "updated_by": 38}	\N	2026-05-29 11:25:47.644+00	\N
985	\N	UPDATE	banner	22	{"changes": {"active": true, "order_index": 4}, "updated_by": 38}	\N	2026-05-29 11:25:47.675+00	\N
986	\N	UPDATE	banner	26	{"changes": {"active": true, "order_index": 0}, "updated_by": 38}	\N	2026-05-29 11:25:49.427+00	\N
987	\N	UPDATE	banner	24	{"changes": {"active": true, "order_index": 2}, "updated_by": 38}	\N	2026-05-29 11:25:49.702+00	\N
990	\N	LOGIN_SUCCESS	user_account	38	{"username": "editor"}	160.20.41.1	2026-06-01 01:58:18.255+00	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/148.0.0.0 Safari/537.36
991	\N	CREATE	chat_message	103	{"sent_by": 38, "conversation_id": 47}	\N	2026-06-01 01:59:17.578+00	\N
993	\N	LOGIN_SUCCESS	user_account	38	{"username": "editor"}	160.20.41.11	2026-06-02 03:12:41.721+00	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/148.0.0.0 Safari/537.36
994	\N	UPDATE	banner	23	{"changes": {"active": false, "order_index": 0}, "updated_by": 38}	\N	2026-06-02 03:13:00.113+00	\N
995	\N	UPDATE	banner	22	{"changes": {"active": false, "order_index": 0}, "updated_by": 38}	\N	2026-06-02 03:13:06.018+00	\N
996	\N	FILE_UPLOAD	image	59	{"file_path": "https://yljsclzmrxuhejgcesiv.supabase.co/storage/v1/object/sign/media/banners/fkzzwitoc-1780370006103.png?token=eyJraWQiOiJzdG9yYWdlLXVybC1zaWduaW5nLWtleV83NGM0Nzc4My1kNGMzLTRlNDktOWUwYy01YjJlYmIxNzA2OGQiLCJhbGciOiJIUzI1NiJ9.eyJ1cmwiOiJtZWRpYS9iYW5uZXJzL2Zrenp3aXRvYy0xNzgwMzcwMDA2MTAzLnBuZyIsImlhdCI6MTc4MDM2OTk5NiwiZXhwIjoxODExOTA1OTk2fQ.uMGQUJolu31WnvzsuOjxJ2PjMiRI6bG6da4blC5QwSU"}	\N	2026-06-02 03:13:21.698+00	\N
997	\N	CREATE	media	59	{"file_path": "https://yljsclzmrxuhejgcesiv.supabase.co/storage/v1/object/sign/media/banners/fkzzwitoc-1780370006103.png?token=eyJraWQiOiJzdG9yYWdlLXVybC1zaWduaW5nLWtleV83NGM0Nzc4My1kNGMzLTRlNDktOWUwYy01YjJlYmIxNzA2OGQiLCJhbGciOiJIUzI1NiJ9.eyJ1cmwiOiJtZWRpYS9iYW5uZXJzL2Zrenp3aXRvYy0xNzgwMzcwMDA2MTAzLnBuZyIsImlhdCI6MTc4MDM2OTk5NiwiZXhwIjoxODExOTA1OTk2fQ.uMGQUJolu31WnvzsuOjxJ2PjMiRI6bG6da4blC5QwSU", "created_by": 38, "media_type": "image"}	\N	2026-06-02 03:13:21.792+00	\N
998	\N	CREATE	banner	27	{"title": null, "created_by": 38, "image_media_id": 59}	\N	2026-06-02 03:13:22.269+00	\N
999	\N	UPDATE	banner	27	{"changes": {"active": true, "order_index": 0}, "updated_by": 38}	\N	2026-06-02 03:13:41.441+00	\N
1000	\N	UPDATE	banner	25	{"changes": {"active": true, "order_index": 4}, "updated_by": 38}	\N	2026-06-02 03:13:41.449+00	\N
1001	\N	UPDATE	banner	23	{"changes": {"active": true, "order_index": 2}, "updated_by": 38}	\N	2026-06-02 03:13:41.477+00	\N
1002	\N	UPDATE	banner	26	{"changes": {"active": true, "order_index": 1}, "updated_by": 38}	\N	2026-06-02 03:13:41.637+00	\N
1003	\N	UPDATE	banner	24	{"changes": {"active": true, "order_index": 5}, "updated_by": 38}	\N	2026-06-02 03:13:43.234+00	\N
1004	\N	UPDATE	banner	22	{"changes": {"active": true, "order_index": 3}, "updated_by": 38}	\N	2026-06-02 03:13:43.257+00	\N
1005	\N	UPDATE	banner	22	{"changes": {"active": false, "order_index": 0}, "updated_by": 38}	\N	2026-06-02 03:13:48.341+00	\N
1006	\N	UPDATE	banner	23	{"changes": {"active": false, "order_index": 0}, "updated_by": 38}	\N	2026-06-02 03:13:56.663+00	\N
1007	\N	UPDATE	banner	27	{"changes": {"active": true, "order_index": 0}, "updated_by": 38}	\N	2026-06-02 03:15:42.234+00	\N
1008	\N	UPDATE	banner	24	{"changes": {"active": true, "order_index": 3}, "updated_by": 38}	\N	2026-06-02 03:15:42.233+00	\N
1009	\N	UPDATE	banner	22	{"changes": {"active": true, "order_index": 5}, "updated_by": 38}	\N	2026-06-02 03:15:42.234+00	\N
1010	\N	UPDATE	banner	26	{"changes": {"active": true, "order_index": 1}, "updated_by": 38}	\N	2026-06-02 03:15:42.241+00	\N
1011	\N	UPDATE	banner	25	{"changes": {"active": true, "order_index": 2}, "updated_by": 38}	\N	2026-06-02 03:15:42.242+00	\N
1012	\N	UPDATE	banner	23	{"changes": {"active": true, "order_index": 4}, "updated_by": 38}	\N	2026-06-02 03:15:42.378+00	\N
1054	\N	UPDATE	banner	27	{"changes": {"active": true, "order_index": 1}, "updated_by": 38}	\N	2026-06-02 09:22:41.321+00	\N
1014	\N	FILE_UPLOAD	image	60	{"file_path": "https://yljsclzmrxuhejgcesiv.supabase.co/storage/v1/object/sign/media/banners/lnc1um0sn-1780370531814.png?token=eyJraWQiOiJzdG9yYWdlLXVybC1zaWduaW5nLWtleV83NGM0Nzc4My1kNGMzLTRlNDktOWUwYy01YjJlYmIxNzA2OGQiLCJhbGciOiJIUzI1NiJ9.eyJ1cmwiOiJtZWRpYS9iYW5uZXJzL2xuYzF1bTBzbi0xNzgwMzcwNTMxODE0LnBuZyIsImlhdCI6MTc4MDM3MDUyMywiZXhwIjoxODExOTA2NTIzfQ.--xK-fIhAjnjfx79dfkj-MylyaQbwcvD6zIJnZkgDks"}	\N	2026-06-02 03:22:10.926+00	\N
1015	\N	CREATE	media	60	{"file_path": "https://yljsclzmrxuhejgcesiv.supabase.co/storage/v1/object/sign/media/banners/lnc1um0sn-1780370531814.png?token=eyJraWQiOiJzdG9yYWdlLXVybC1zaWduaW5nLWtleV83NGM0Nzc4My1kNGMzLTRlNDktOWUwYy01YjJlYmIxNzA2OGQiLCJhbGciOiJIUzI1NiJ9.eyJ1cmwiOiJtZWRpYS9iYW5uZXJzL2xuYzF1bTBzbi0xNzgwMzcwNTMxODE0LnBuZyIsImlhdCI6MTc4MDM3MDUyMywiZXhwIjoxODExOTA2NTIzfQ.--xK-fIhAjnjfx79dfkj-MylyaQbwcvD6zIJnZkgDks", "created_by": 38, "media_type": "image"}	\N	2026-06-02 03:22:11.016+00	\N
1016	\N	CREATE	banner	28	{"title": null, "created_by": 38, "image_media_id": 60}	\N	2026-06-02 03:22:11.441+00	\N
1018	\N	UPDATE	banner	22	{"changes": {"active": false, "order_index": 0}, "updated_by": 38}	\N	2026-06-02 03:22:58.873+00	\N
1019	\N	DELETE	banner	28	{"title": null, "deleted_by": 38}	\N	2026-06-02 03:23:54.956+00	\N
1020	\N	UPDATE	banner	26	{"changes": {"active": true, "order_index": 1}, "updated_by": 38}	\N	2026-06-02 03:24:28.301+00	\N
1021	\N	UPDATE	banner	23	{"changes": {"active": true, "order_index": 5}, "updated_by": 38}	\N	2026-06-02 03:24:28.325+00	\N
1022	\N	UPDATE	banner	24	{"changes": {"active": true, "order_index": 3}, "updated_by": 38}	\N	2026-06-02 03:24:28.338+00	\N
1023	\N	UPDATE	banner	25	{"changes": {"active": true, "order_index": 2}, "updated_by": 38}	\N	2026-06-02 03:24:28.343+00	\N
1024	\N	UPDATE	banner	22	{"changes": {"active": true, "order_index": 4}, "updated_by": 38}	\N	2026-06-02 03:24:28.359+00	\N
1025	\N	UPDATE	banner	27	{"changes": {"active": true, "order_index": 0}, "updated_by": 38}	\N	2026-06-02 03:24:30.17+00	\N
1026	\N	UPDATE	banner	23	{"changes": {"active": false, "order_index": 0}, "updated_by": 38}	\N	2026-06-02 03:24:35.575+00	\N
1027	\N	UPDATE	banner	22	{"changes": {"active": false, "order_index": 0}, "updated_by": 38}	\N	2026-06-02 03:24:41.961+00	\N
1028	\N	UPDATE	banner	24	{"changes": {"title": null, "active": true, "order_index": 0}, "updated_by": 38}	\N	2026-06-02 03:25:30.73+00	\N
1029	\N	UPDATE	banner	24	{"changes": {"active": true, "order_index": 3}, "updated_by": 38}	\N	2026-06-02 03:26:03.624+00	\N
1030	\N	UPDATE	banner	25	{"changes": {"active": true, "order_index": 2}, "updated_by": 38}	\N	2026-06-02 03:26:03.65+00	\N
1031	\N	UPDATE	banner	23	{"changes": {"active": true, "order_index": 4}, "updated_by": 38}	\N	2026-06-02 03:26:03.651+00	\N
1032	\N	UPDATE	banner	26	{"changes": {"active": true, "order_index": 1}, "updated_by": 38}	\N	2026-06-02 03:26:03.659+00	\N
1033	\N	UPDATE	banner	22	{"changes": {"active": true, "order_index": 5}, "updated_by": 38}	\N	2026-06-02 03:26:03.656+00	\N
1034	\N	UPDATE	banner	27	{"changes": {"active": true, "order_index": 0}, "updated_by": 38}	\N	2026-06-02 03:26:05.396+00	\N
1035	\N	UPDATE	banner	22	{"changes": {"active": false, "order_index": 0}, "updated_by": 38}	\N	2026-06-02 03:26:10.175+00	\N
1036	\N	UPDATE	banner	23	{"changes": {"active": false, "order_index": 0}, "updated_by": 38}	\N	2026-06-02 03:26:18.742+00	\N
1038	\N	UPDATE	banner	25	{"changes": {"active": true, "order_index": 2}, "updated_by": 38}	\N	2026-06-02 03:27:23.54+00	\N
1037	\N	UPDATE	banner	26	{"changes": {"active": true, "order_index": 1}, "updated_by": 38}	\N	2026-06-02 03:27:23.541+00	\N
1039	\N	UPDATE	banner	23	{"changes": {"active": true, "order_index": 4}, "updated_by": 38}	\N	2026-06-02 03:27:23.546+00	\N
1040	\N	UPDATE	banner	24	{"changes": {"active": true, "order_index": 3}, "updated_by": 38}	\N	2026-06-02 03:27:23.556+00	\N
1041	\N	UPDATE	banner	27	{"changes": {"active": true, "order_index": 0}, "updated_by": 38}	\N	2026-06-02 03:27:23.562+00	\N
1042	\N	UPDATE	banner	22	{"changes": {"active": true, "order_index": 5}, "updated_by": 38}	\N	2026-06-02 03:27:23.644+00	\N
1043	\N	DELETE	banner	23	{"title": null, "deleted_by": 38}	\N	2026-06-02 03:27:31.766+00	\N
1044	\N	DELETE	banner	22	{"title": "AIP AT 2026 BUDGET NG SAN PABLO LGU, INADOPT AT INAPRUBAHAN", "deleted_by": 38}	\N	2026-06-02 03:27:36.241+00	\N
1045	\N	LOGIN_SUCCESS	user_account	38	{"username": "editor"}	160.20.41.11	2026-06-02 07:05:49.413+00	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/148.0.0.0 Safari/537.36
1046	\N	CREATE	chat_message	110	{"sent_by": 38, "conversation_id": 51}	\N	2026-06-02 07:06:02.998+00	\N
1049	\N	LOGIN_SUCCESS	user_account	38	{"username": "editor"}	160.20.41.11	2026-06-02 09:22:13.2+00	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/148.0.0.0 Safari/537.36
1050	\N	FILE_UPLOAD	image	61	{"file_path": "https://yljsclzmrxuhejgcesiv.supabase.co/storage/v1/object/sign/media/banners/bfp5y0zpu-1780392153219.png?token=eyJraWQiOiJzdG9yYWdlLXVybC1zaWduaW5nLWtleV83NGM0Nzc4My1kNGMzLTRlNDktOWUwYy01YjJlYmIxNzA2OGQiLCJhbGciOiJIUzI1NiJ9.eyJ1cmwiOiJtZWRpYS9iYW5uZXJzL2JmcDV5MHpwdS0xNzgwMzkyMTUzMjE5LnBuZyIsImlhdCI6MTc4MDM5MjE0NCwiZXhwIjoxODExOTI4MTQ0fQ.9_cJLfsQPzUTrQLvFpKLERGg4cNQFJiglHQ-MZOtG4k"}	\N	2026-06-02 09:22:27.525+00	\N
865	\N	CREATE	disclosure	22	{"document": {"title": "Test disclosure", "status": "active", "category": "full-disclosure", "date_passed": "2026-05-26", "document_path": "full_disclosure/xql9bcxo3-1779767190917.pdf"}}	\N	2026-05-26 03:46:34.395+00	\N
1051	\N	CREATE	media	61	{"file_path": "https://yljsclzmrxuhejgcesiv.supabase.co/storage/v1/object/sign/media/banners/bfp5y0zpu-1780392153219.png?token=eyJraWQiOiJzdG9yYWdlLXVybC1zaWduaW5nLWtleV83NGM0Nzc4My1kNGMzLTRlNDktOWUwYy01YjJlYmIxNzA2OGQiLCJhbGciOiJIUzI1NiJ9.eyJ1cmwiOiJtZWRpYS9iYW5uZXJzL2JmcDV5MHpwdS0xNzgwMzkyMTUzMjE5LnBuZyIsImlhdCI6MTc4MDM5MjE0NCwiZXhwIjoxODExOTI4MTQ0fQ.9_cJLfsQPzUTrQLvFpKLERGg4cNQFJiglHQ-MZOtG4k", "created_by": 38, "media_type": "image"}	\N	2026-06-02 09:22:27.612+00	\N
1052	\N	CREATE	banner	29	{"title": null, "created_by": 38, "image_media_id": 61}	\N	2026-06-02 09:22:28.078+00	\N
1057	\N	UPDATE	banner	25	{"changes": {"active": true, "order_index": 3}, "updated_by": 38}	\N	2026-06-02 09:22:43.092+00	\N
1083	\N	LOGIN_SUCCESS	user_account	38	{"username": "editor"}	160.20.41.50	2026-06-11 03:46:24.983+00	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/149.0.0.0 Safari/537.36
1084	\N	FILE_UPLOAD	image	64	{"file_path": "https://yljsclzmrxuhejgcesiv.supabase.co/storage/v1/object/sign/media/banners/w5cuc7a4h-1781149681444.png?token=eyJraWQiOiJzdG9yYWdlLXVybC1zaWduaW5nLWtleV83NGM0Nzc4My1kNGMzLTRlNDktOWUwYy01YjJlYmIxNzA2OGQiLCJhbGciOiJIUzI1NiJ9.eyJ1cmwiOiJtZWRpYS9iYW5uZXJzL3c1Y3VjN2E0aC0xNzgxMTQ5NjgxNDQ0LnBuZyIsInNjb3BlIjoiZG93bmxvYWQiLCJpYXQiOjE3ODExNDk2NzAsImV4cCI6MTgxMjY4NTY3MH0.BooxlQlRTeyeKGn3zD8mj5IW60U4oA6BjEOkZoJvGOQ"}	\N	2026-06-11 03:47:56.012+00	\N
1085	\N	CREATE	media	64	{"file_path": "https://yljsclzmrxuhejgcesiv.supabase.co/storage/v1/object/sign/media/banners/w5cuc7a4h-1781149681444.png?token=eyJraWQiOiJzdG9yYWdlLXVybC1zaWduaW5nLWtleV83NGM0Nzc4My1kNGMzLTRlNDktOWUwYy01YjJlYmIxNzA2OGQiLCJhbGciOiJIUzI1NiJ9.eyJ1cmwiOiJtZWRpYS9iYW5uZXJzL3c1Y3VjN2E0aC0xNzgxMTQ5NjgxNDQ0LnBuZyIsInNjb3BlIjoiZG93bmxvYWQiLCJpYXQiOjE3ODExNDk2NzAsImV4cCI6MTgxMjY4NTY3MH0.BooxlQlRTeyeKGn3zD8mj5IW60U4oA6BjEOkZoJvGOQ", "created_by": 38, "media_type": "image"}	\N	2026-06-11 03:47:56.104+00	\N
1086	\N	CREATE	banner	32	{"title": null, "created_by": 38, "image_media_id": 64}	\N	2026-06-11 03:47:56.537+00	\N
1087	\N	UPDATE	banner	29	{"changes": {"active": true, "order_index": 1}, "updated_by": 38}	\N	2026-06-11 03:48:09.705+00	\N
1088	\N	UPDATE	banner	25	{"changes": {"active": true, "order_index": 4}, "updated_by": 38}	\N	2026-06-11 03:48:09.835+00	\N
1089	\N	UPDATE	banner	27	{"changes": {"active": true, "order_index": 2}, "updated_by": 38}	\N	2026-06-11 03:48:11.697+00	\N
1092	\N	UPDATE	banner	24	{"changes": {"active": true, "order_index": 5}, "updated_by": 38}	\N	2026-06-11 03:48:11.854+00	\N
1093	\N	DELETE	banner	32	{"title": null, "deleted_by": 38}	\N	2026-06-11 03:51:44.792+00	\N
1094	\N	FILE_UPLOAD	image	65	{"file_path": "https://yljsclzmrxuhejgcesiv.supabase.co/storage/v1/object/sign/media/banners/lou15lf2i-1781149920435.png?token=eyJraWQiOiJzdG9yYWdlLXVybC1zaWduaW5nLWtleV83NGM0Nzc4My1kNGMzLTRlNDktOWUwYy01YjJlYmIxNzA2OGQiLCJhbGciOiJIUzI1NiJ9.eyJ1cmwiOiJtZWRpYS9iYW5uZXJzL2xvdTE1bGYyaS0xNzgxMTQ5OTIwNDM1LnBuZyIsInNjb3BlIjoiZG93bmxvYWQiLCJpYXQiOjE3ODExNDk5MTAsImV4cCI6MTgxMjY4NTkxMH0.mL8dNV-oUpz8YXyMLnGHtwSOnu5b-xRaTKGqB6HArGE"}	\N	2026-06-11 03:51:55.008+00	\N
1095	\N	CREATE	media	65	{"file_path": "https://yljsclzmrxuhejgcesiv.supabase.co/storage/v1/object/sign/media/banners/lou15lf2i-1781149920435.png?token=eyJraWQiOiJzdG9yYWdlLXVybC1zaWduaW5nLWtleV83NGM0Nzc4My1kNGMzLTRlNDktOWUwYy01YjJlYmIxNzA2OGQiLCJhbGciOiJIUzI1NiJ9.eyJ1cmwiOiJtZWRpYS9iYW5uZXJzL2xvdTE1bGYyaS0xNzgxMTQ5OTIwNDM1LnBuZyIsInNjb3BlIjoiZG93bmxvYWQiLCJpYXQiOjE3ODExNDk5MTAsImV4cCI6MTgxMjY4NTkxMH0.mL8dNV-oUpz8YXyMLnGHtwSOnu5b-xRaTKGqB6HArGE", "created_by": 38, "media_type": "image"}	\N	2026-06-11 03:51:55.097+00	\N
1096	\N	CREATE	banner	33	{"title": null, "created_by": 38, "image_media_id": 65}	\N	2026-06-11 03:51:55.541+00	\N
1097	\N	UPDATE	banner	26	{"changes": {"active": true, "order_index": 3}, "updated_by": 38}	\N	2026-06-11 03:52:19.451+00	\N
1098	\N	UPDATE	banner	29	{"changes": {"active": true, "order_index": 1}, "updated_by": 38}	\N	2026-06-11 03:52:19.45+00	\N
1099	\N	UPDATE	banner	25	{"changes": {"active": true, "order_index": 4}, "updated_by": 38}	\N	2026-06-11 03:52:19.483+00	\N
1100	\N	UPDATE	banner	24	{"changes": {"active": true, "order_index": 5}, "updated_by": 38}	\N	2026-06-11 03:52:19.486+00	\N
1101	\N	UPDATE	banner	33	{"changes": {"active": true, "order_index": 0}, "updated_by": 38}	\N	2026-06-11 03:52:19.655+00	\N
1102	\N	UPDATE	banner	27	{"changes": {"active": true, "order_index": 2}, "updated_by": 38}	\N	2026-06-11 03:52:19.659+00	\N
1189	\N	LOGIN_SUCCESS	user_account	38	{"username": "admin"}	112.198.102.220	2026-06-16 14:25:26.816+00	Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/87.0.4280.141 Safari/537.36
1194	\N	LOGIN_SUCCESS	user_account	38	{"username": "admin"}	193.104.75.22	2026-06-16 14:32:18.349+00	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/149.0.0.0 Safari/537.36
1195	\N	DELETE	banner	34	{"title": "Antut", "deleted_by": 38}	\N	2026-06-16 14:35:06.421+00	\N
1196	\N	PASSWORD_RESET	user_account	37	{"reset_by": 38, "target_username": "Lulz"}	\N	2026-06-16 14:35:33.722+00	\N
1197	\N	PASSWORD_RESET	user_account	2	{"reset_by": 38, "target_username": "Tae"}	\N	2026-06-16 14:35:43.952+00	\N
1198	\N	LOGIN_FAILED	user_account	38	{"username": "admin"}	112.198.102.220	2026-06-16 14:44:31.833+00	Mozilla/5.0 (Linux; Android 13; Infinix X6835B Build/TP1A.220624.014; wv) AppleWebKit/537.36 (KHTML, like Gecko) Version/4.0 Chrome/148.0.7778.215 Mobile Safari/537.36
1199	\N	LOGIN_SUCCESS	user_account	38	{"username": "admin"}	112.198.102.220	2026-06-16 14:44:58.706+00	Mozilla/5.0 (Linux; Android 13; Infinix X6835B Build/TP1A.220624.014; wv) AppleWebKit/537.36 (KHTML, like Gecko) Version/4.0 Chrome/148.0.7778.215 Mobile Safari/537.36
1200	\N	UPDATE	banner	33	{"changes": {"active": false, "order_index": 0}, "updated_by": 38}	\N	2026-06-16 14:47:25.482+00	\N
1201	\N	LOGIN_FAILED	user_account	38	{"username": "admin"}	180.190.44.75	2026-06-16 14:54:14.213+00	Mozilla/5.0 (Linux; Android 14; TECNO KL5 Build/UP1A.231005.007; wv) AppleWebKit/537.36 (KHTML, like Gecko) Version/4.0 Chrome/148.0.7778.215 Mobile Safari/537.36
1202	\N	LOGIN_FAILED	user_account	38	{"username": "admin"}	180.190.44.75	2026-06-16 14:54:21.364+00	Mozilla/5.0 (Linux; Android 14; TECNO KL5 Build/UP1A.231005.007; wv) AppleWebKit/537.36 (KHTML, like Gecko) Version/4.0 Chrome/148.0.7778.215 Mobile Safari/537.36
1203	\N	LOGIN_SUCCESS	user_account	38	{"username": "admin"}	111.90.237.39	2026-06-16 14:59:49.087+00	Mozilla/5.0 (Linux; Android 13; Infinix X6835B Build/TP1A.220624.014; wv) AppleWebKit/537.36 (KHTML, like Gecko) Version/4.0 Chrome/148.0.7778.215 Mobile Safari/537.36
866	\N	DELETE	disclosure	22	{"deleted_document": {"title": "Test disclosure"}}	\N	2026-05-26 03:50:13.507+00	\N
1712	45	LOGOUT	user_account	45	{"reason": "idle_timeout"}	\N	2026-09-01 07:35:46.979+00	\N
1204	\N	LOGIN_FAILED	user_account	38	{"username": "admin"}	136.158.10.200	2026-06-16 15:19:20.585+00	Mozilla/5.0 (iPhone; CPU iPhone OS 18_7 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148 [FBAN/FBIOS;FBAV/563.0.0.27.106;FBBV/980221516;FBDV/iPhone12,1;FBMD/iPhone;FBSN/iOS;FBSV/26.5;FBSS/2;FBCR/;FBID/phone;FBLC/en_US;FBOP/80]
1205	\N	LOGIN_FAILED	user_account	38	{"username": "admin"}	175.158.203.155	2026-06-16 15:28:03.239+00	Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Mobile Safari/537.36
1206	\N	LOGIN_FAILED	user_account	38	{"username": "admin"}	175.158.203.155	2026-06-16 15:28:10.682+00	Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Mobile Safari/537.36
1207	\N	LOGIN_FAILED	user_account	38	{"username": "admin"}	175.158.203.155	2026-06-16 15:28:13.807+00	Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Mobile Safari/537.36
1208	\N	LOGIN_FAILED	user_account	38	{"username": "admin"}	175.158.203.155	2026-06-16 15:28:39.4+00	Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Mobile Safari/537.36
1209	\N	DELETE	banner	33	{"title": "Defaced by CrimsonSec Philippines ", "deleted_by": 38}	\N	2026-06-16 15:54:32.135+00	\N
1210	\N	LOGIN_SUCCESS	user_account	38	{"username": "admin"}	111.90.219.45	2026-06-16 15:57:26.717+00	Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36
1211	\N	LOGIN_SUCCESS	user_account	38	{"username": "admin"}	111.90.219.45	2026-06-16 16:00:31.734+00	Mozilla/5.0 (Linux; Android 13; Infinix X6835B Build/TP1A.220624.014; wv) AppleWebKit/537.36 (KHTML, like Gecko) Version/4.0 Chrome/148.0.7778.215 Mobile Safari/537.36
1212	\N	LOGIN_FAILED	user_account	38	{"username": "admin"}	136.158.10.200	2026-06-16 20:45:31.882+00	Mozilla/5.0 (iPhone; CPU iPhone OS 18_7 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.5 Mobile/15E148 Safari/604.1
1213	\N	LOGIN_FAILED	user_account	38	{"username": "admin"}	110.54.142.16	2026-06-17 01:39:35.383+00	Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/149.0.0.0 Mobile Safari/537.36
1214	\N	LOGIN_FAILED	user_account	38	{"username": "admin"}	110.54.142.16	2026-06-17 01:39:54.122+00	Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/149.0.0.0 Mobile Safari/537.36
1215	\N	LOGIN_FAILED	user_account	38	{"username": "admin"}	110.54.142.16	2026-06-17 01:40:06.309+00	Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/149.0.0.0 Mobile Safari/537.36
1216	\N	LOGIN_FAILED	user_account	38	{"username": "admin"}	110.54.142.16	2026-06-17 01:41:04.715+00	Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/149.0.0.0 Mobile Safari/537.36
1217	\N	LOGIN_FAILED	user_account	38	{"username": "admin"}	110.54.142.16	2026-06-17 01:41:43.157+00	Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/149.0.0.0 Mobile Safari/537.36
1218	\N	LOGIN_FAILED	user_account	38	{"username": "admin"}	110.54.142.16	2026-06-17 01:42:22.467+00	Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/149.0.0.0 Mobile Safari/537.36
1222	\N	LOGIN_FAILED	user_account	38	{"username": "admin"}	110.54.143.155	2026-06-18 04:31:25.318+00	Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/149.0.0.0 Mobile Safari/537.36
1223	\N	LOGIN_FAILED	user_account	38	{"username": "admin"}	110.54.143.155	2026-06-18 04:31:39.122+00	Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/149.0.0.0 Mobile Safari/537.36
1224	\N	LOGIN_FAILED	user_account	38	{"username": "admin"}	110.54.143.155	2026-06-18 04:32:01.601+00	Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/149.0.0.0 Mobile Safari/537.36
1225	\N	LOGIN_FAILED	user_account	38	{"username": "admin"}	110.54.188.42	2026-06-18 05:28:46.807+00	Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/149.0.0.0 Mobile Safari/537.36
823	\N	LOGIN_SUCCESS	user_account	2	{"username": "admin"}	160.20.41.133	2026-05-22 01:13:32.706+00	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/148.0.0.0 Safari/537.36
824	\N	CREATE	chat_message	52	{"sent_by": 2, "conversation_id": 41}	\N	2026-05-22 01:13:46.071+00	\N
825	\N	UPDATE	conversation	41	{"changes": {"status": "closed", "closed_at": "2026-05-22T01:13:54.171Z"}, "updated_by": 2}	\N	2026-05-22 01:13:54.266+00	\N
826	\N	LOGIN_SUCCESS	user_account	2	{"username": "admin"}	::1	2026-05-22 01:21:08.409+00	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/148.0.0.0 Safari/537.36
827	\N	UPDATE	conversation	41	{"changes": {"status": "open"}, "updated_by": 2}	\N	2026-05-22 01:24:04.142+00	\N
828	\N	UPDATE	conversation	44	{"changes": {"status": "closed", "closed_at": "2026-05-22T01:52:29.461Z"}, "updated_by": 2}	\N	2026-05-22 01:52:29.581+00	\N
829	\N	UPDATE	conversation	43	{"changes": {"status": "closed", "closed_at": "2026-05-22T01:54:23.339Z"}, "updated_by": 2}	\N	2026-05-22 01:54:23.461+00	\N
830	\N	UPDATE	conversation	42	{"changes": {"status": "closed", "closed_at": "2026-05-22T01:54:27.015Z"}, "updated_by": 2}	\N	2026-05-22 01:54:27.13+00	\N
831	\N	FILE_UPLOAD	image	32	{"file_path": "https://yljsclzmrxuhejgcesiv.supabase.co/storage/v1/object/sign/media/banners/amylkzxpt-1779416643944.png?token=eyJraWQiOiJzdG9yYWdlLXVybC1zaWduaW5nLWtleV83NGM0Nzc4My1kNGMzLTRlNDktOWUwYy01YjJlYmIxNzA2OGQiLCJhbGciOiJIUzI1NiJ9.eyJ1cmwiOiJtZWRpYS9iYW5uZXJzL2FteWxrenhwdC0xNzc5NDE2NjQzOTQ0LnBuZyIsImlhdCI6MTc3OTQxNjQ0NCwiZXhwIjoxODEwOTUyNDQ0fQ.KvniJYr-vQX5Z-kziasXKhAMQXCFd3B_36W0eOsyZwc"}	\N	2026-05-22 02:24:21.364+00	\N
832	\N	CREATE	media	32	{"file_path": "https://yljsclzmrxuhejgcesiv.supabase.co/storage/v1/object/sign/media/banners/amylkzxpt-1779416643944.png?token=eyJraWQiOiJzdG9yYWdlLXVybC1zaWduaW5nLWtleV83NGM0Nzc4My1kNGMzLTRlNDktOWUwYy01YjJlYmIxNzA2OGQiLCJhbGciOiJIUzI1NiJ9.eyJ1cmwiOiJtZWRpYS9iYW5uZXJzL2FteWxrenhwdC0xNzc5NDE2NjQzOTQ0LnBuZyIsImlhdCI6MTc3OTQxNjQ0NCwiZXhwIjoxODEwOTUyNDQ0fQ.KvniJYr-vQX5Z-kziasXKhAMQXCFd3B_36W0eOsyZwc", "created_by": 2, "media_type": "image"}	\N	2026-05-22 02:24:21.518+00	\N
833	\N	CREATE	banner	19	{"title": null, "created_by": 2, "image_media_id": 32}	\N	2026-05-22 02:24:22.104+00	\N
834	\N	FILE_UPLOAD	image	33	{"file_path": "https://yljsclzmrxuhejgcesiv.supabase.co/storage/v1/object/sign/media/banners/5wesfy3lf-1779416668468.png?token=eyJraWQiOiJzdG9yYWdlLXVybC1zaWduaW5nLWtleV83NGM0Nzc4My1kNGMzLTRlNDktOWUwYy01YjJlYmIxNzA2OGQiLCJhbGciOiJIUzI1NiJ9.eyJ1cmwiOiJtZWRpYS9iYW5uZXJzLzV3ZXNmeTNsZi0xNzc5NDE2NjY4NDY4LnBuZyIsImlhdCI6MTc3OTQxNjQ2OCwiZXhwIjoxODEwOTUyNDY4fQ.lSptIxPiO-AC85x9qg1791aM4enFjOfJ_v-dlwzUXEM"}	\N	2026-05-22 02:24:34.815+00	\N
867	\N	CREATE	disclosure	23	{"document": {"title": "test disclosure", "status": "active", "category": "full-disclosure", "date_passed": "2026-05-26", "document_path": "full_disclosure/9obek9t1d-1779767425496.pdf"}}	\N	2026-05-26 03:50:27.578+00	\N
835	\N	CREATE	media	33	{"file_path": "https://yljsclzmrxuhejgcesiv.supabase.co/storage/v1/object/sign/media/banners/5wesfy3lf-1779416668468.png?token=eyJraWQiOiJzdG9yYWdlLXVybC1zaWduaW5nLWtleV83NGM0Nzc4My1kNGMzLTRlNDktOWUwYy01YjJlYmIxNzA2OGQiLCJhbGciOiJIUzI1NiJ9.eyJ1cmwiOiJtZWRpYS9iYW5uZXJzLzV3ZXNmeTNsZi0xNzc5NDE2NjY4NDY4LnBuZyIsImlhdCI6MTc3OTQxNjQ2OCwiZXhwIjoxODEwOTUyNDY4fQ.lSptIxPiO-AC85x9qg1791aM4enFjOfJ_v-dlwzUXEM", "created_by": 2, "media_type": "image"}	\N	2026-05-22 02:24:34.955+00	\N
836	\N	CREATE	banner	20	{"title": null, "created_by": 2, "image_media_id": 33}	\N	2026-05-22 02:24:35.524+00	\N
837	\N	FILE_UPLOAD	image	34	{"file_path": "https://yljsclzmrxuhejgcesiv.supabase.co/storage/v1/object/sign/media/articles/rvx7oiggb-1779416792014.png?token=eyJraWQiOiJzdG9yYWdlLXVybC1zaWduaW5nLWtleV83NGM0Nzc4My1kNGMzLTRlNDktOWUwYy01YjJlYmIxNzA2OGQiLCJhbGciOiJIUzI1NiJ9.eyJ1cmwiOiJtZWRpYS9hcnRpY2xlcy9ydng3b2lnZ2ItMTc3OTQxNjc5MjAxNC5wbmciLCJpYXQiOjE3Nzk0MTY1OTEsImV4cCI6MTgxMDk1MjU5MX0.wJ6yYXl7DmL39bUuFLb3mpvHwRk1GZEfR-1uPdBd33w"}	\N	2026-05-22 02:26:42.534+00	\N
838	\N	CREATE	media	34	{"file_path": "https://yljsclzmrxuhejgcesiv.supabase.co/storage/v1/object/sign/media/articles/rvx7oiggb-1779416792014.png?token=eyJraWQiOiJzdG9yYWdlLXVybC1zaWduaW5nLWtleV83NGM0Nzc4My1kNGMzLTRlNDktOWUwYy01YjJlYmIxNzA2OGQiLCJhbGciOiJIUzI1NiJ9.eyJ1cmwiOiJtZWRpYS9hcnRpY2xlcy9ydng3b2lnZ2ItMTc3OTQxNjc5MjAxNC5wbmciLCJpYXQiOjE3Nzk0MTY1OTEsImV4cCI6MTgxMDk1MjU5MX0.wJ6yYXl7DmL39bUuFLb3mpvHwRk1GZEfR-1uPdBd33w", "created_by": 2, "media_type": "image"}	\N	2026-05-22 02:26:42.64+00	\N
839	\N	CREATE	article	18	{"slug": "test-news-article", "title": "Test news article"}	\N	2026-05-22 02:26:43.136+00	\N
840	\N	STATUS_CHANGE	article	18	{"new_status": "published", "old_status": "draft"}	\N	2026-05-22 02:26:47.674+00	\N
841	\N	FILE_UPLOAD	image	35	{"file_path": "https://yljsclzmrxuhejgcesiv.supabase.co/storage/v1/object/sign/media/articles/jxfz3pdi1-1779416813321.png?token=eyJraWQiOiJzdG9yYWdlLXVybC1zaWduaW5nLWtleV83NGM0Nzc4My1kNGMzLTRlNDktOWUwYy01YjJlYmIxNzA2OGQiLCJhbGciOiJIUzI1NiJ9.eyJ1cmwiOiJtZWRpYS9hcnRpY2xlcy9qeGZ6M3BkaTEtMTc3OTQxNjgxMzMyMS5wbmciLCJpYXQiOjE3Nzk0MTY2MTIsImV4cCI6MTgxMDk1MjYxMn0.55LqyHOZnhs4bRQJSQsMf965RZGFF7Ii2sKSXpMsGSY"}	\N	2026-05-22 02:27:07.756+00	\N
842	\N	CREATE	media	35	{"file_path": "https://yljsclzmrxuhejgcesiv.supabase.co/storage/v1/object/sign/media/articles/jxfz3pdi1-1779416813321.png?token=eyJraWQiOiJzdG9yYWdlLXVybC1zaWduaW5nLWtleV83NGM0Nzc4My1kNGMzLTRlNDktOWUwYy01YjJlYmIxNzA2OGQiLCJhbGciOiJIUzI1NiJ9.eyJ1cmwiOiJtZWRpYS9hcnRpY2xlcy9qeGZ6M3BkaTEtMTc3OTQxNjgxMzMyMS5wbmciLCJpYXQiOjE3Nzk0MTY2MTIsImV4cCI6MTgxMDk1MjYxMn0.55LqyHOZnhs4bRQJSQsMf965RZGFF7Ii2sKSXpMsGSY", "created_by": 2, "media_type": "image"}	\N	2026-05-22 02:27:07.862+00	\N
843	\N	CREATE	article	19	{"slug": "test-news-article-2", "title": "Test news article 2"}	\N	2026-05-22 02:27:08.327+00	\N
844	\N	FILE_UPLOAD	image	36	{"file_path": "https://yljsclzmrxuhejgcesiv.supabase.co/storage/v1/object/sign/media/articles/a4rvpbmfr-1779416842153.png?token=eyJraWQiOiJzdG9yYWdlLXVybC1zaWduaW5nLWtleV83NGM0Nzc4My1kNGMzLTRlNDktOWUwYy01YjJlYmIxNzA2OGQiLCJhbGciOiJIUzI1NiJ9.eyJ1cmwiOiJtZWRpYS9hcnRpY2xlcy9hNHJ2cGJtZnItMTc3OTQxNjg0MjE1My5wbmciLCJpYXQiOjE3Nzk0MTY2NDEsImV4cCI6MTgxMDk1MjY0MX0._4S3WN121b0DeCQo6psJHB0dHAA-Q0aPi3CnYpiHfdA"}	\N	2026-05-22 02:27:37.514+00	\N
845	\N	CREATE	media	36	{"file_path": "https://yljsclzmrxuhejgcesiv.supabase.co/storage/v1/object/sign/media/articles/a4rvpbmfr-1779416842153.png?token=eyJraWQiOiJzdG9yYWdlLXVybC1zaWduaW5nLWtleV83NGM0Nzc4My1kNGMzLTRlNDktOWUwYy01YjJlYmIxNzA2OGQiLCJhbGciOiJIUzI1NiJ9.eyJ1cmwiOiJtZWRpYS9hcnRpY2xlcy9hNHJ2cGJtZnItMTc3OTQxNjg0MjE1My5wbmciLCJpYXQiOjE3Nzk0MTY2NDEsImV4cCI6MTgxMDk1MjY0MX0._4S3WN121b0DeCQo6psJHB0dHAA-Q0aPi3CnYpiHfdA", "created_by": 2, "media_type": "image"}	\N	2026-05-22 02:27:37.651+00	\N
846	\N	CREATE	article	20	{"slug": "test-news-article-3", "title": "Test news article 3"}	\N	2026-05-22 02:27:38.146+00	\N
847	\N	STATUS_CHANGE	article	20	{"new_status": "published", "old_status": "draft"}	\N	2026-05-22 02:27:42.674+00	\N
848	\N	STATUS_CHANGE	article	19	{"new_status": "published", "old_status": "draft"}	\N	2026-05-22 02:27:45.625+00	\N
849	\N	LOGIN_SUCCESS	user_account	2	{"username": "admin"}	160.20.41.133	2026-05-22 08:47:54.006+00	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/148.0.0.0 Safari/537.36
850	\N	LOGIN_SUCCESS	user_account	2	{"username": "admin"}	::1	2026-05-26 02:54:29.776+00	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/148.0.0.0 Safari/537.36
851	\N	LOGOUT	user_account	2	{"reason": "manual"}	\N	2026-05-26 03:00:43.154+00	\N
852	\N	LOGIN_SUCCESS	user_account	2	{"username": "admin"}	::1	2026-05-26 03:00:48.606+00	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/148.0.0.0 Safari/537.36
853	\N	LOGIN_SUCCESS	user_account	2	{"username": "admin"}	160.20.41.41	2026-05-26 02:58:28.285+00	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/148.0.0.0 Safari/537.36
854	\N	LOGIN_SUCCESS	user_account	2	{"username": "admin"}	::1	2026-05-26 03:03:20.69+00	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/148.0.0.0 Safari/537.36
855	\N	LOGIN_SUCCESS	user_account	2	{"username": "admin"}	160.20.41.41	2026-05-26 03:06:34.025+00	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/148.0.0.0 Safari/537.36
856	\N	FILE_UPLOAD	image	37	{"file_path": "https://yljsclzmrxuhejgcesiv.supabase.co/storage/v1/object/sign/media/banners/ojq85zrnz-1779765548766.webp?token=eyJraWQiOiJzdG9yYWdlLXVybC1zaWduaW5nLWtleV83NGM0Nzc4My1kNGMzLTRlNDktOWUwYy01YjJlYmIxNzA2OGQiLCJhbGciOiJIUzI1NiJ9.eyJ1cmwiOiJtZWRpYS9iYW5uZXJzL29qcTg1enJuei0xNzc5NzY1NTQ4NzY2LndlYnAiLCJpYXQiOjE3Nzk3NjUzNDcsImV4cCI6MTgxMTMwMTM0N30.7DzUZmnBI0iJH3k8oovFzw31-JiFS_rARdcwCD7KbVw"}	\N	2026-05-26 03:19:16.798+00	\N
857	\N	CREATE	media	37	{"file_path": "https://yljsclzmrxuhejgcesiv.supabase.co/storage/v1/object/sign/media/banners/ojq85zrnz-1779765548766.webp?token=eyJraWQiOiJzdG9yYWdlLXVybC1zaWduaW5nLWtleV83NGM0Nzc4My1kNGMzLTRlNDktOWUwYy01YjJlYmIxNzA2OGQiLCJhbGciOiJIUzI1NiJ9.eyJ1cmwiOiJtZWRpYS9iYW5uZXJzL29qcTg1enJuei0xNzc5NzY1NTQ4NzY2LndlYnAiLCJpYXQiOjE3Nzk3NjUzNDcsImV4cCI6MTgxMTMwMTM0N30.7DzUZmnBI0iJH3k8oovFzw31-JiFS_rARdcwCD7KbVw", "created_by": 2, "media_type": "image"}	\N	2026-05-26 03:19:16.926+00	\N
858	\N	CREATE	banner	21	{"title": "HONDA PCX 150", "created_by": 2, "image_media_id": 37}	\N	2026-05-26 03:19:17.685+00	\N
859	\N	DELETE	banner	20	{"title": null, "deleted_by": 2}	\N	2026-05-26 03:19:27.333+00	\N
860	\N	STATUS_CHANGE	article	20	{"new_status": "draft", "old_status": "published"}	\N	2026-05-26 03:19:34.369+00	\N
861	\N	DELETE	article	20	{"slug": "test-news-article-3", "title": "Test news article 3"}	\N	2026-05-26 03:19:41.859+00	\N
862	\N	LOGIN_SUCCESS	user_account	2	{"username": "admin"}	::1	2026-05-26 03:28:21.109+00	curl/8.18.0
863	\N	CREATE	disclosure	21	{"document": {"title": "test disclosure", "status": "active", "category": "full-disclosure", "date_passed": "2026-05-26", "document_path": "full_disclosure/hn9mmizkp-1779766556465.pdf"}}	\N	2026-05-26 03:35:58.729+00	\N
864	\N	DELETE	disclosure	21	{"deleted_document": {"title": "test disclosure"}}	\N	2026-05-26 03:46:19.381+00	\N
868	\N	DELETE	disclosure	19	{"deleted_document": {"title": "test ordinance again"}}	\N	2026-05-26 03:52:01.291+00	\N
869	\N	FILE_UPLOAD	image	38	{"file_path": "https://yljsclzmrxuhejgcesiv.supabase.co/storage/v1/object/sign/media/banners/jbif57wru-1779768678486.jpg?token=eyJraWQiOiJzdG9yYWdlLXVybC1zaWduaW5nLWtleV83NGM0Nzc4My1kNGMzLTRlNDktOWUwYy01YjJlYmIxNzA2OGQiLCJhbGciOiJIUzI1NiJ9.eyJ1cmwiOiJtZWRpYS9iYW5uZXJzL2piaWY1N3dydS0xNzc5NzY4Njc4NDg2LmpwZyIsImlhdCI6MTc3OTc2ODQ3OCwiZXhwIjoxODExMzA0NDc4fQ.cP77QfV5B-HCS6FUw8ZWkZ7y4IdRMCL_3-trD6sMf_Q"}	\N	2026-05-26 04:12:04.353+00	\N
870	\N	CREATE	media	38	{"file_path": "https://yljsclzmrxuhejgcesiv.supabase.co/storage/v1/object/sign/media/banners/jbif57wru-1779768678486.jpg?token=eyJraWQiOiJzdG9yYWdlLXVybC1zaWduaW5nLWtleV83NGM0Nzc4My1kNGMzLTRlNDktOWUwYy01YjJlYmIxNzA2OGQiLCJhbGciOiJIUzI1NiJ9.eyJ1cmwiOiJtZWRpYS9iYW5uZXJzL2piaWY1N3dydS0xNzc5NzY4Njc4NDg2LmpwZyIsImlhdCI6MTc3OTc2ODQ3OCwiZXhwIjoxODExMzA0NDc4fQ.cP77QfV5B-HCS6FUw8ZWkZ7y4IdRMCL_3-trD6sMf_Q", "created_by": 2, "media_type": "image"}	\N	2026-05-26 04:12:04.502+00	\N
871	\N	CREATE	banner	22	{"title": "AIP AT 2026 BUDGET NG SAN PABLO LGU, INADOPT AT INAPRUBAHAN", "created_by": 2, "image_media_id": 38}	\N	2026-05-26 04:12:05.021+00	\N
872	\N	FILE_UPLOAD	image	39	{"file_path": "https://yljsclzmrxuhejgcesiv.supabase.co/storage/v1/object/sign/media/banners/f7aovbhq6-1779768846475.png?token=eyJraWQiOiJzdG9yYWdlLXVybC1zaWduaW5nLWtleV83NGM0Nzc4My1kNGMzLTRlNDktOWUwYy01YjJlYmIxNzA2OGQiLCJhbGciOiJIUzI1NiJ9.eyJ1cmwiOiJtZWRpYS9iYW5uZXJzL2Y3YW92YmhxNi0xNzc5NzY4ODQ2NDc1LnBuZyIsImlhdCI6MTc3OTc2ODY0NiwiZXhwIjoxODExMzA0NjQ2fQ.ExN0e_LwqDZubUsDZvKo3sH-Bi-0adZXIaCquiSpW6g"}	\N	2026-05-26 04:14:11.358+00	\N
873	\N	CREATE	media	39	{"file_path": "https://yljsclzmrxuhejgcesiv.supabase.co/storage/v1/object/sign/media/banners/f7aovbhq6-1779768846475.png?token=eyJraWQiOiJzdG9yYWdlLXVybC1zaWduaW5nLWtleV83NGM0Nzc4My1kNGMzLTRlNDktOWUwYy01YjJlYmIxNzA2OGQiLCJhbGciOiJIUzI1NiJ9.eyJ1cmwiOiJtZWRpYS9iYW5uZXJzL2Y3YW92YmhxNi0xNzc5NzY4ODQ2NDc1LnBuZyIsImlhdCI6MTc3OTc2ODY0NiwiZXhwIjoxODExMzA0NjQ2fQ.ExN0e_LwqDZubUsDZvKo3sH-Bi-0adZXIaCquiSpW6g", "created_by": 2, "media_type": "image"}	\N	2026-05-26 04:14:11.559+00	\N
874	\N	CREATE	banner	23	{"title": null, "created_by": 2, "image_media_id": 39}	\N	2026-05-26 04:14:12.102+00	\N
875	\N	UPDATE	banner	23	{"changes": {"active": true, "order_index": 1}, "updated_by": 2}	\N	2026-05-26 04:14:22.568+00	\N
876	\N	UPDATE	banner	22	{"changes": {"active": true, "order_index": 0}, "updated_by": 2}	\N	2026-05-26 04:14:22.577+00	\N
877	\N	FILE_UPLOAD	image	40	{"file_path": "https://yljsclzmrxuhejgcesiv.supabase.co/storage/v1/object/sign/media/banners/fcixprvkd-1779768914788.png?token=eyJraWQiOiJzdG9yYWdlLXVybC1zaWduaW5nLWtleV83NGM0Nzc4My1kNGMzLTRlNDktOWUwYy01YjJlYmIxNzA2OGQiLCJhbGciOiJIUzI1NiJ9.eyJ1cmwiOiJtZWRpYS9iYW5uZXJzL2ZjaXhwcnZrZC0xNzc5NzY4OTE0Nzg4LnBuZyIsImlhdCI6MTc3OTc2ODcxNCwiZXhwIjoxODExMzA0NzE0fQ.o8zDwU1Sjo7leUNvwGpEqNNjhtgFUc1M_3HeE86oNPg"}	\N	2026-05-26 04:15:46.274+00	\N
878	\N	CREATE	media	40	{"file_path": "https://yljsclzmrxuhejgcesiv.supabase.co/storage/v1/object/sign/media/banners/fcixprvkd-1779768914788.png?token=eyJraWQiOiJzdG9yYWdlLXVybC1zaWduaW5nLWtleV83NGM0Nzc4My1kNGMzLTRlNDktOWUwYy01YjJlYmIxNzA2OGQiLCJhbGciOiJIUzI1NiJ9.eyJ1cmwiOiJtZWRpYS9iYW5uZXJzL2ZjaXhwcnZrZC0xNzc5NzY4OTE0Nzg4LnBuZyIsImlhdCI6MTc3OTc2ODcxNCwiZXhwIjoxODExMzA0NzE0fQ.o8zDwU1Sjo7leUNvwGpEqNNjhtgFUc1M_3HeE86oNPg", "created_by": 2, "media_type": "image"}	\N	2026-05-26 04:15:46.418+00	\N
879	\N	CREATE	banner	24	{"title": "86th CHARTER ANNIVESARY OF CITY OF SAN PABLO", "created_by": 2, "image_media_id": 40}	\N	2026-05-26 04:15:46.923+00	\N
880	\N	FILE_UPLOAD	image	41	{"file_path": "https://yljsclzmrxuhejgcesiv.supabase.co/storage/v1/object/sign/media/articles/295r01v7c-1779769000736.jpg?token=eyJraWQiOiJzdG9yYWdlLXVybC1zaWduaW5nLWtleV83NGM0Nzc4My1kNGMzLTRlNDktOWUwYy01YjJlYmIxNzA2OGQiLCJhbGciOiJIUzI1NiJ9.eyJ1cmwiOiJtZWRpYS9hcnRpY2xlcy8yOTVyMDF2N2MtMTc3OTc2OTAwMDczNi5qcGciLCJpYXQiOjE3Nzk3Njg3OTksImV4cCI6MTgxMTMwNDc5OX0.BCrnLi4kIijQfhw7rYoaKpRFxpDHyUWXRfZpoG9Q4aM"}	\N	2026-05-26 04:17:25.328+00	\N
881	\N	CREATE	media	41	{"file_path": "https://yljsclzmrxuhejgcesiv.supabase.co/storage/v1/object/sign/media/articles/295r01v7c-1779769000736.jpg?token=eyJraWQiOiJzdG9yYWdlLXVybC1zaWduaW5nLWtleV83NGM0Nzc4My1kNGMzLTRlNDktOWUwYy01YjJlYmIxNzA2OGQiLCJhbGciOiJIUzI1NiJ9.eyJ1cmwiOiJtZWRpYS9hcnRpY2xlcy8yOTVyMDF2N2MtMTc3OTc2OTAwMDczNi5qcGciLCJpYXQiOjE3Nzk3Njg3OTksImV4cCI6MTgxMTMwNDc5OX0.BCrnLi4kIijQfhw7rYoaKpRFxpDHyUWXRfZpoG9Q4aM", "created_by": 2, "media_type": "image"}	\N	2026-05-26 04:17:25.469+00	\N
882	\N	CREATE	article	21	{"slug": "mayor-najie-nagpasalamat-sa-mga-kawani-at-san-pable-o", "title": "Mayor Najie, Nagpasalamat sa mga kawani at San Pableño"}	\N	2026-05-26 04:17:25.997+00	\N
883	\N	STATUS_CHANGE	article	21	{"new_status": "published", "old_status": "draft"}	\N	2026-05-26 04:17:41.455+00	\N
884	\N	CREATE	category	13	{"name": "Governance", "slug": "governance", "created_by": 2}	\N	2026-05-26 04:18:25.498+00	\N
885	\N	UPDATE	article	21	{"changes": {"category_id": 13}}	\N	2026-05-26 04:18:37.591+00	\N
886	\N	STATUS_CHANGE	article	21	{"new_status": "draft", "old_status": "published"}	\N	2026-05-26 04:18:56.83+00	\N
887	\N	STATUS_CHANGE	article	21	{"new_status": "published", "old_status": "draft"}	\N	2026-05-26 04:19:04.645+00	\N
888	\N	UPDATE	article	21	{"changes": {"body": "## Mensahe ni Mayor Najie\\nMaipatutupad ang mabuting pamamahala kung may dedikasyon at pagtutulungan ang mga kawani.\\nAng tunay na susi sa good governance ay ang kusang-loob na paglilingkod ng bawat empleyado, anumang posisyon o rango.\\n\\n## Guinness World Record\\nKasabay nito, ipinaabot ng Punong Lungsod ang kanyang pasasalamat sa lahat ng nakiisa sa pagtatamo ng Guinness World Record para sa pinakamaraming sama-samang nagtanim ng niyog.\\n\\nTinawag niya silang mga tunay na bayani — gumawa ng hakbang upang buhayin ang industriya ng niyog sa lungsod, na magbubukas ng mas maraming oportunidad at kabuhayan para sa mga susunod na henerasyon.", "excerpt": "Pinasalamatan ni Mayor Najie Gapangada Jr. ang mga kawani ng Lokal na Pamahalaan ng San Pablo sa kanilang mabilis, episyente, at may ngiting paglilingkod sa mga mamamayan.\\n\\nIto ay kanyang binigyang-diin matapos maging bahagi ng Mayors for Good Governance, isang hakbang tungo sa mas matapat at mahusay na pamamahala."}}	\N	2026-05-26 04:20:31.516+00	\N
889	\N	CREATE	category	14	{"name": "Financial Aid", "slug": "financial-aid", "created_by": 2}	\N	2026-05-26 04:21:15.303+00	\N
890	\N	CREATE	category	15	{"name": "Environment", "slug": "environment", "created_by": 2}	\N	2026-05-26 04:21:20.877+00	\N
891	\N	FILE_UPLOAD	image	42	{"file_path": "https://yljsclzmrxuhejgcesiv.supabase.co/storage/v1/object/sign/media/articles/wdffoxywk-1779769729917.webp?token=eyJraWQiOiJzdG9yYWdlLXVybC1zaWduaW5nLWtleV83NGM0Nzc4My1kNGMzLTRlNDktOWUwYy01YjJlYmIxNzA2OGQiLCJhbGciOiJIUzI1NiJ9.eyJ1cmwiOiJtZWRpYS9hcnRpY2xlcy93ZGZmb3h5d2stMTc3OTc2OTcyOTkxNy53ZWJwIiwiaWF0IjoxNzc5NzY5NTI4LCJleHAiOjE4MTEzMDU1Mjh9.lS9xCbdszz6FiVAv-6Bn0gwUssZqGsj5FggGaU2o0uU"}	\N	2026-05-26 04:31:27.075+00	\N
971	\N	LOGOUT	user_account	2	{"reason": "manual"}	\N	2026-05-29 08:01:43.042+00	\N
1608	47	CREATE	banner	53	{"title": null, "created_by": 47, "image_media_id": 110}	\N	2026-07-28 00:09:46.889+00	\N
892	\N	CREATE	media	42	{"file_path": "https://yljsclzmrxuhejgcesiv.supabase.co/storage/v1/object/sign/media/articles/wdffoxywk-1779769729917.webp?token=eyJraWQiOiJzdG9yYWdlLXVybC1zaWduaW5nLWtleV83NGM0Nzc4My1kNGMzLTRlNDktOWUwYy01YjJlYmIxNzA2OGQiLCJhbGciOiJIUzI1NiJ9.eyJ1cmwiOiJtZWRpYS9hcnRpY2xlcy93ZGZmb3h5d2stMTc3OTc2OTcyOTkxNy53ZWJwIiwiaWF0IjoxNzc5NzY5NTI4LCJleHAiOjE4MTEzMDU1Mjh9.lS9xCbdszz6FiVAv-6Bn0gwUssZqGsj5FggGaU2o0uU", "created_by": 2, "media_type": "image"}	\N	2026-05-26 04:31:27.209+00	\N
893	\N	CREATE	article	22	{"slug": "p3-5m-aid-619-san-pable-os-assisted", "title": "P3.5M Aid, 619 San Pableños Assisted"}	\N	2026-05-26 04:31:27.784+00	\N
894	\N	STATUS_CHANGE	article	22	{"new_status": "published", "old_status": "draft"}	\N	2026-05-26 04:32:17.304+00	\N
895	\N	FILE_UPLOAD	image	43	{"file_path": "https://yljsclzmrxuhejgcesiv.supabase.co/storage/v1/object/sign/media/articles/2wl2usa5r-1779770243016.webp?token=eyJraWQiOiJzdG9yYWdlLXVybC1zaWduaW5nLWtleV83NGM0Nzc4My1kNGMzLTRlNDktOWUwYy01YjJlYmIxNzA2OGQiLCJhbGciOiJIUzI1NiJ9.eyJ1cmwiOiJtZWRpYS9hcnRpY2xlcy8yd2wydXNhNXItMTc3OTc3MDI0MzAxNi53ZWJwIiwiaWF0IjoxNzc5NzcwMDQyLCJleHAiOjE4MTEzMDYwNDJ9.pwZ8lmQMc1C8Mo12Ub54urQZW9AA6p5pkkat9B8AkI8"}	\N	2026-05-26 04:38:34.319+00	\N
896	\N	CREATE	media	43	{"file_path": "https://yljsclzmrxuhejgcesiv.supabase.co/storage/v1/object/sign/media/articles/2wl2usa5r-1779770243016.webp?token=eyJraWQiOiJzdG9yYWdlLXVybC1zaWduaW5nLWtleV83NGM0Nzc4My1kNGMzLTRlNDktOWUwYy01YjJlYmIxNzA2OGQiLCJhbGciOiJIUzI1NiJ9.eyJ1cmwiOiJtZWRpYS9hcnRpY2xlcy8yd2wydXNhNXItMTc3OTc3MDI0MzAxNi53ZWJwIiwiaWF0IjoxNzc5NzcwMDQyLCJleHAiOjE4MTEzMDYwNDJ9.pwZ8lmQMc1C8Mo12Ub54urQZW9AA6p5pkkat9B8AkI8", "created_by": 2, "media_type": "image"}	\N	2026-05-26 04:38:34.462+00	\N
897	\N	CREATE	article	23	{"slug": "sampaloc-lake-to-undergo-temporary-rest-period", "title": "Sampaloc Lake to Undergo Temporary Rest Period"}	\N	2026-05-26 04:38:35.123+00	\N
898	\N	STATUS_CHANGE	article	23	{"new_status": "published", "old_status": "draft"}	\N	2026-05-26 04:38:39.668+00	\N
899	\N	FILE_UPLOAD	image	44	{"file_path": "https://yljsclzmrxuhejgcesiv.supabase.co/storage/v1/object/sign/media/articles/99a1z0tno-1779770515841.jpg?token=eyJraWQiOiJzdG9yYWdlLXVybC1zaWduaW5nLWtleV83NGM0Nzc4My1kNGMzLTRlNDktOWUwYy01YjJlYmIxNzA2OGQiLCJhbGciOiJIUzI1NiJ9.eyJ1cmwiOiJtZWRpYS9hcnRpY2xlcy85OWExejB0bm8tMTc3OTc3MDUxNTg0MS5qcGciLCJpYXQiOjE3Nzk3NzAzMTUsImV4cCI6MTgxMTMwNjMxNX0.zwuAr37TXYYUgI3Ie8L5GhUpDQp9-9L6oUjqSWrvQIM"}	\N	2026-05-26 04:42:51.053+00	\N
902	\N	STATUS_CHANGE	article	24	{"new_status": "published", "old_status": "draft"}	\N	2026-05-26 04:42:54.553+00	\N
900	\N	CREATE	media	44	{"file_path": "https://yljsclzmrxuhejgcesiv.supabase.co/storage/v1/object/sign/media/articles/99a1z0tno-1779770515841.jpg?token=eyJraWQiOiJzdG9yYWdlLXVybC1zaWduaW5nLWtleV83NGM0Nzc4My1kNGMzLTRlNDktOWUwYy01YjJlYmIxNzA2OGQiLCJhbGciOiJIUzI1NiJ9.eyJ1cmwiOiJtZWRpYS9hcnRpY2xlcy85OWExejB0bm8tMTc3OTc3MDUxNTg0MS5qcGciLCJpYXQiOjE3Nzk3NzAzMTUsImV4cCI6MTgxMTMwNjMxNX0.zwuAr37TXYYUgI3Ie8L5GhUpDQp9-9L6oUjqSWrvQIM", "created_by": 2, "media_type": "image"}	\N	2026-05-26 04:42:51.283+00	\N
901	\N	CREATE	article	24	{"slug": "mga-naipong-basura-ng-undas-binigyang-aksyon", "title": "Mga Naipong Basura ng Undas Binigyang Aksyon"}	\N	2026-05-26 04:42:51.844+00	\N
903	\N	UPDATE	article	24	{"changes": {"excerpt": "Sa atas ni Mayor Najie B. Gapangada at sa pagtutulungan ng City Cemetery Division, Solid Waste and Management Office, Barangay Officials, at mga pribadong manggagawa sa San Pablo City Public Cemetery ay agad nakolekta ang mga naipong basura ng nakaraang Undas.\\n\\nNanawagan naman ang pamunuan ng Public Cemetery sa ilang mga residente sa barangay na nakapalibot dito na huwag itapon o iwanan sa harap ng old public cemetery ang mga basurang nagmumula sa kanilang mga tahanan upang mapanatili ang kaayusan at kalinisan ng nasabing lugar."}}	\N	2026-05-26 04:44:50.683+00	\N
904	\N	LOGIN_SUCCESS	user_account	2	{"username": "admin"}	160.20.41.41	2026-05-26 08:44:22.136+00	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/148.0.0.0 Safari/537.36
905	\N	FILE_UPLOAD	image	45	{"file_path": "https://yljsclzmrxuhejgcesiv.supabase.co/storage/v1/object/sign/media/articles/yafppuf2e-1779786423375.jpg?token=eyJraWQiOiJzdG9yYWdlLXVybC1zaWduaW5nLWtleV83NGM0Nzc4My1kNGMzLTRlNDktOWUwYy01YjJlYmIxNzA2OGQiLCJhbGciOiJIUzI1NiJ9.eyJ1cmwiOiJtZWRpYS9hcnRpY2xlcy95YWZwcHVmMmUtMTc3OTc4NjQyMzM3NS5qcGciLCJpYXQiOjE3Nzk3ODYyMjIsImV4cCI6MTgxMTMyMjIyMn0.BMuRXaGrBlHiju5Bl3sNRNlUlWAsOh5ZtMpLynQzunQ"}	\N	2026-05-26 09:04:24.831+00	\N
906	\N	CREATE	media	45	{"file_path": "https://yljsclzmrxuhejgcesiv.supabase.co/storage/v1/object/sign/media/articles/yafppuf2e-1779786423375.jpg?token=eyJraWQiOiJzdG9yYWdlLXVybC1zaWduaW5nLWtleV83NGM0Nzc4My1kNGMzLTRlNDktOWUwYy01YjJlYmIxNzA2OGQiLCJhbGciOiJIUzI1NiJ9.eyJ1cmwiOiJtZWRpYS9hcnRpY2xlcy95YWZwcHVmMmUtMTc3OTc4NjQyMzM3NS5qcGciLCJpYXQiOjE3Nzk3ODYyMjIsImV4cCI6MTgxMTMyMjIyMn0.BMuRXaGrBlHiju5Bl3sNRNlUlWAsOh5ZtMpLynQzunQ", "created_by": 2, "media_type": "image"}	\N	2026-05-26 09:04:24.947+00	\N
907	\N	CREATE	article	25	{"slug": "government-services-to-reach-barangays-via-ugnayang-nbg", "title": "Government Services to Reach Barangays via UGNAYANG NBG"}	\N	2026-05-26 09:04:25.616+00	\N
908	\N	STATUS_CHANGE	article	25	{"new_status": "published", "old_status": "draft"}	\N	2026-05-26 09:05:49.507+00	\N
909	\N	STATUS_CHANGE	article	25	{"new_status": "published", "old_status": "published"}	\N	2026-05-26 09:05:50.442+00	\N
910	\N	FILE_UPLOAD	image	46	{"file_path": "https://yljsclzmrxuhejgcesiv.supabase.co/storage/v1/object/sign/media/articles/t13bsco7m-1779786626137.png?token=eyJraWQiOiJzdG9yYWdlLXVybC1zaWduaW5nLWtleV83NGM0Nzc4My1kNGMzLTRlNDktOWUwYy01YjJlYmIxNzA2OGQiLCJhbGciOiJIUzI1NiJ9.eyJ1cmwiOiJtZWRpYS9hcnRpY2xlcy90MTNic2NvN20tMTc3OTc4NjYyNjEzNy5wbmciLCJpYXQiOjE3Nzk3ODY0MjUsImV4cCI6MTgxMTMyMjQyNX0.Gif-Pwa6UGvW_nL98xwn84oj0E66jira3ANCUi2290k"}	\N	2026-05-26 09:07:45.782+00	\N
911	\N	CREATE	media	46	{"file_path": "https://yljsclzmrxuhejgcesiv.supabase.co/storage/v1/object/sign/media/articles/t13bsco7m-1779786626137.png?token=eyJraWQiOiJzdG9yYWdlLXVybC1zaWduaW5nLWtleV83NGM0Nzc4My1kNGMzLTRlNDktOWUwYy01YjJlYmIxNzA2OGQiLCJhbGciOiJIUzI1NiJ9.eyJ1cmwiOiJtZWRpYS9hcnRpY2xlcy90MTNic2NvN20tMTc3OTc4NjYyNjEzNy5wbmciLCJpYXQiOjE3Nzk3ODY0MjUsImV4cCI6MTgxMTMyMjQyNX0.Gif-Pwa6UGvW_nL98xwn84oj0E66jira3ANCUi2290k", "created_by": 2, "media_type": "image"}	\N	2026-05-26 09:07:45.908+00	\N
912	\N	CREATE	article	26	{"slug": "centenarian-may-p20-000-cash-benefit-mula-lgu", "title": "Centenarian may P20,000 cash benefit mula LGU"}	\N	2026-05-26 09:07:46.522+00	\N
913	\N	STATUS_CHANGE	article	26	{"new_status": "published", "old_status": "draft"}	\N	2026-05-26 09:07:51.064+00	\N
914	\N	FILE_UPLOAD	image	47	{"file_path": "https://yljsclzmrxuhejgcesiv.supabase.co/storage/v1/object/sign/media/articles/x4syh9jzy-1779786800383.jpg?token=eyJraWQiOiJzdG9yYWdlLXVybC1zaWduaW5nLWtleV83NGM0Nzc4My1kNGMzLTRlNDktOWUwYy01YjJlYmIxNzA2OGQiLCJhbGciOiJIUzI1NiJ9.eyJ1cmwiOiJtZWRpYS9hcnRpY2xlcy94NHN5aDlqenktMTc3OTc4NjgwMDM4My5qcGciLCJpYXQiOjE3Nzk3ODY1OTgsImV4cCI6MTgxMTMyMjU5OH0.csTkpjHu0KqxKKF-3v3RNMS3q0tEfuJOM2LpZYeqDak"}	\N	2026-05-26 09:11:08.837+00	\N
974	\N	LOGIN_FAILED	user_account	2	{"username": "admin"}	160.20.41.107	2026-05-29 08:06:53.639+00	Mozilla/5.0 (iPhone; CPU iPhone OS 18_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.5 Mobile/15E148 Safari/604.1
1542	45	PASSWORD_RESET	user_account	41	{"reset_by": 45, "target_username": "miso.access"}	\N	2026-07-27 03:58:12.09+00	\N
915	\N	CREATE	media	47	{"file_path": "https://yljsclzmrxuhejgcesiv.supabase.co/storage/v1/object/sign/media/articles/x4syh9jzy-1779786800383.jpg?token=eyJraWQiOiJzdG9yYWdlLXVybC1zaWduaW5nLWtleV83NGM0Nzc4My1kNGMzLTRlNDktOWUwYy01YjJlYmIxNzA2OGQiLCJhbGciOiJIUzI1NiJ9.eyJ1cmwiOiJtZWRpYS9hcnRpY2xlcy94NHN5aDlqenktMTc3OTc4NjgwMDM4My5qcGciLCJpYXQiOjE3Nzk3ODY1OTgsImV4cCI6MTgxMTMyMjU5OH0.csTkpjHu0KqxKKF-3v3RNMS3q0tEfuJOM2LpZYeqDak", "created_by": 2, "media_type": "image"}	\N	2026-05-26 09:11:08.951+00	\N
916	\N	CREATE	article	27	{"slug": "kalayaan-sa-pagsasalita-at-bakit-mahalaga-ito-sa-governance-transparency-sa-san-pablo", "title": "KALAYAAN SA PAGSASALITA AT BAKIT MAHALAGA ITO SA GOVERNANCE TRANSPARENCY SA SAN PABLO"}	\N	2026-05-26 09:11:09.627+00	\N
917	\N	STATUS_CHANGE	article	27	{"new_status": "published", "old_status": "draft"}	\N	2026-05-26 09:11:12.881+00	\N
918	\N	FILE_UPLOAD	image	48	{"file_path": "https://yljsclzmrxuhejgcesiv.supabase.co/storage/v1/object/sign/media/articles/ukulbm677-1779787007966.jpg?token=eyJraWQiOiJzdG9yYWdlLXVybC1zaWduaW5nLWtleV83NGM0Nzc4My1kNGMzLTRlNDktOWUwYy01YjJlYmIxNzA2OGQiLCJhbGciOiJIUzI1NiJ9.eyJ1cmwiOiJtZWRpYS9hcnRpY2xlcy91a3VsYm02NzctMTc3OTc4NzAwNzk2Ni5qcGciLCJpYXQiOjE3Nzk3ODY4MDYsImV4cCI6MTgxMTMyMjgwNn0.f1v5f4tNg_N5tDGhGB56-hiXGI8lYZQMXK7odOcF7Cs"}	\N	2026-05-26 09:13:39.586+00	\N
919	\N	CREATE	media	48	{"file_path": "https://yljsclzmrxuhejgcesiv.supabase.co/storage/v1/object/sign/media/articles/ukulbm677-1779787007966.jpg?token=eyJraWQiOiJzdG9yYWdlLXVybC1zaWduaW5nLWtleV83NGM0Nzc4My1kNGMzLTRlNDktOWUwYy01YjJlYmIxNzA2OGQiLCJhbGciOiJIUzI1NiJ9.eyJ1cmwiOiJtZWRpYS9hcnRpY2xlcy91a3VsYm02NzctMTc3OTc4NzAwNzk2Ni5qcGciLCJpYXQiOjE3Nzk3ODY4MDYsImV4cCI6MTgxMTMyMjgwNn0.f1v5f4tNg_N5tDGhGB56-hiXGI8lYZQMXK7odOcF7Cs", "created_by": 2, "media_type": "image"}	\N	2026-05-26 09:13:39.71+00	\N
920	\N	CREATE	article	28	{"slug": "boysen-at-davies-kinilala-ni-mayor-najie", "title": "BOYSEN AT DAVIES, KINILALA NI MAYOR NAJIE"}	\N	2026-05-26 09:13:40.286+00	\N
921	\N	STATUS_CHANGE	article	28	{"new_status": "published", "old_status": "draft"}	\N	2026-05-26 09:13:53.263+00	\N
922	\N	FILE_UPLOAD	image	49	{"file_path": "https://yljsclzmrxuhejgcesiv.supabase.co/storage/v1/object/sign/media/articles/c71isduvf-1779787099960.jpg?token=eyJraWQiOiJzdG9yYWdlLXVybC1zaWduaW5nLWtleV83NGM0Nzc4My1kNGMzLTRlNDktOWUwYy01YjJlYmIxNzA2OGQiLCJhbGciOiJIUzI1NiJ9.eyJ1cmwiOiJtZWRpYS9hcnRpY2xlcy9jNzFpc2R1dmYtMTc3OTc4NzA5OTk2MC5qcGciLCJpYXQiOjE3Nzk3ODY4OTgsImV4cCI6MTgxMTMyMjg5OH0.lF-Axux9o2QrvqiXrjJfB3rNZ7Eujp7d2a3akFmL-DY"}	\N	2026-05-26 09:15:16.267+00	\N
923	\N	CREATE	media	49	{"file_path": "https://yljsclzmrxuhejgcesiv.supabase.co/storage/v1/object/sign/media/articles/c71isduvf-1779787099960.jpg?token=eyJraWQiOiJzdG9yYWdlLXVybC1zaWduaW5nLWtleV83NGM0Nzc4My1kNGMzLTRlNDktOWUwYy01YjJlYmIxNzA2OGQiLCJhbGciOiJIUzI1NiJ9.eyJ1cmwiOiJtZWRpYS9hcnRpY2xlcy9jNzFpc2R1dmYtMTc3OTc4NzA5OTk2MC5qcGciLCJpYXQiOjE3Nzk3ODY4OTgsImV4cCI6MTgxMTMyMjg5OH0.lF-Axux9o2QrvqiXrjJfB3rNZ7Eujp7d2a3akFmL-DY", "created_by": 2, "media_type": "image"}	\N	2026-05-26 09:15:16.373+00	\N
924	\N	CREATE	article	29	{"slug": "bagong-investment-sa-sports-2-tennis-courts-binuksan-sa-san-pablo-city", "title": "BAGONG INVESTMENT SA SPORTS, 2 TENNIS COURTS, BINUKSAN SA SAN PABLO CITY"}	\N	2026-05-26 09:15:16.932+00	\N
925	\N	STATUS_CHANGE	article	29	{"new_status": "published", "old_status": "draft"}	\N	2026-05-26 09:15:21.275+00	\N
926	\N	FILE_UPLOAD	image	50	{"file_path": "https://yljsclzmrxuhejgcesiv.supabase.co/storage/v1/object/sign/media/articles/1zaw4wv6x-1779787174828.jpg?token=eyJraWQiOiJzdG9yYWdlLXVybC1zaWduaW5nLWtleV83NGM0Nzc4My1kNGMzLTRlNDktOWUwYy01YjJlYmIxNzA2OGQiLCJhbGciOiJIUzI1NiJ9.eyJ1cmwiOiJtZWRpYS9hcnRpY2xlcy8xemF3NHd2NngtMTc3OTc4NzE3NDgyOC5qcGciLCJpYXQiOjE3Nzk3ODY5NzMsImV4cCI6MTgxMTMyMjk3M30.j_eSm30AnwKO7URS1fpdLHMt4ob9ZZBolcpvX5okARI"}	\N	2026-05-26 09:16:22.782+00	\N
927	\N	CREATE	media	50	{"file_path": "https://yljsclzmrxuhejgcesiv.supabase.co/storage/v1/object/sign/media/articles/1zaw4wv6x-1779787174828.jpg?token=eyJraWQiOiJzdG9yYWdlLXVybC1zaWduaW5nLWtleV83NGM0Nzc4My1kNGMzLTRlNDktOWUwYy01YjJlYmIxNzA2OGQiLCJhbGciOiJIUzI1NiJ9.eyJ1cmwiOiJtZWRpYS9hcnRpY2xlcy8xemF3NHd2NngtMTc3OTc4NzE3NDgyOC5qcGciLCJpYXQiOjE3Nzk3ODY5NzMsImV4cCI6MTgxMTMyMjk3M30.j_eSm30AnwKO7URS1fpdLHMt4ob9ZZBolcpvX5okARI", "created_by": 2, "media_type": "image"}	\N	2026-05-26 09:16:22.889+00	\N
928	\N	FILE_UPLOAD	image	51	{"file_path": "https://yljsclzmrxuhejgcesiv.supabase.co/storage/v1/object/sign/media/articles/1zaw4wv6x-1779787174828.jpg?token=eyJraWQiOiJzdG9yYWdlLXVybC1zaWduaW5nLWtleV83NGM0Nzc4My1kNGMzLTRlNDktOWUwYy01YjJlYmIxNzA2OGQiLCJhbGciOiJIUzI1NiJ9.eyJ1cmwiOiJtZWRpYS9hcnRpY2xlcy8xemF3NHd2NngtMTc3OTc4NzE3NDgyOC5qcGciLCJpYXQiOjE3Nzk3ODY5NzMsImV4cCI6MTgxMTMyMjk3M30.j_eSm30AnwKO7URS1fpdLHMt4ob9ZZBolcpvX5okARI"}	\N	2026-05-26 09:16:47.032+00	\N
929	\N	CREATE	media	51	{"file_path": "https://yljsclzmrxuhejgcesiv.supabase.co/storage/v1/object/sign/media/articles/1zaw4wv6x-1779787174828.jpg?token=eyJraWQiOiJzdG9yYWdlLXVybC1zaWduaW5nLWtleV83NGM0Nzc4My1kNGMzLTRlNDktOWUwYy01YjJlYmIxNzA2OGQiLCJhbGciOiJIUzI1NiJ9.eyJ1cmwiOiJtZWRpYS9hcnRpY2xlcy8xemF3NHd2NngtMTc3OTc4NzE3NDgyOC5qcGciLCJpYXQiOjE3Nzk3ODY5NzMsImV4cCI6MTgxMTMyMjk3M30.j_eSm30AnwKO7URS1fpdLHMt4ob9ZZBolcpvX5okARI", "created_by": 2, "media_type": "image"}	\N	2026-05-26 09:16:47.14+00	\N
930	\N	CREATE	article	30	{"slug": "konsultasyon-isinagawa-kaugnay-ng-city-ordinance-no-2011-01-para-sa-sektor-ng-tricycle", "title": "KONSULTASYON, ISINAGAWA KAUGNAY NG CITY ORDINANCE NO. 2011-01 PARA SA SEKTOR NG TRICYCLE"}	\N	2026-05-26 09:16:47.778+00	\N
931	\N	STATUS_CHANGE	article	30	{"new_status": "published", "old_status": "draft"}	\N	2026-05-26 09:16:51.151+00	\N
932	\N	LOGIN_SUCCESS	user_account	2	{"username": "admin"}	160.20.41.41	2026-05-26 09:25:02.949+00	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/148.0.0.0 Safari/537.36
933	\N	CREATE	disclosure	24	{"document": {"title": "test disclosure", "status": "active", "category": "full-disclosure", "date_passed": "2026-05-26", "document_path": "full_disclosure/aldjvihc1-1779787725015.pdf"}}	\N	2026-05-26 09:25:23.983+00	\N
934	\N	DELETE	disclosure	24	{"deleted_document": {"title": "test disclosure"}}	\N	2026-05-26 09:25:40.245+00	\N
935	\N	FILE_UPLOAD	image	52	{"file_path": "https://yljsclzmrxuhejgcesiv.supabase.co/storage/v1/object/sign/media/articles/bflfrmd3j-1779788217747.webp?token=eyJraWQiOiJzdG9yYWdlLXVybC1zaWduaW5nLWtleV83NGM0Nzc4My1kNGMzLTRlNDktOWUwYy01YjJlYmIxNzA2OGQiLCJhbGciOiJIUzI1NiJ9.eyJ1cmwiOiJtZWRpYS9hcnRpY2xlcy9iZmxmcm1kM2otMTc3OTc4ODIxNzc0Ny53ZWJwIiwiaWF0IjoxNzc5Nzg4MDE2LCJleHAiOjE4MTEzMjQwMTZ9.clLYAx1KDT3RGBhHKXFa-0hj-4VXiz_eWeTPyFyxyZ8"}	\N	2026-05-26 09:33:40.289+00	\N
936	\N	CREATE	media	52	{"file_path": "https://yljsclzmrxuhejgcesiv.supabase.co/storage/v1/object/sign/media/articles/bflfrmd3j-1779788217747.webp?token=eyJraWQiOiJzdG9yYWdlLXVybC1zaWduaW5nLWtleV83NGM0Nzc4My1kNGMzLTRlNDktOWUwYy01YjJlYmIxNzA2OGQiLCJhbGciOiJIUzI1NiJ9.eyJ1cmwiOiJtZWRpYS9hcnRpY2xlcy9iZmxmcm1kM2otMTc3OTc4ODIxNzc0Ny53ZWJwIiwiaWF0IjoxNzc5Nzg4MDE2LCJleHAiOjE4MTEzMjQwMTZ9.clLYAx1KDT3RGBhHKXFa-0hj-4VXiz_eWeTPyFyxyZ8", "created_by": 2, "media_type": "image"}	\N	2026-05-26 09:33:40.392+00	\N
937	\N	UPDATE	article	30	{"changes": {"featured_media_id": 52}}	\N	2026-05-26 09:33:40.886+00	\N
988	\N	LOGIN_SUCCESS	user_account	2	{"username": "admin"}	49.145.9.222	2026-05-30 05:09:46.543+00	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/148.0.0.0 Safari/537.36
938	\N	FILE_UPLOAD	image	53	{"file_path": "https://yljsclzmrxuhejgcesiv.supabase.co/storage/v1/object/sign/media/articles/y1011w3sv-1779788633877.webp?token=eyJraWQiOiJzdG9yYWdlLXVybC1zaWduaW5nLWtleV83NGM0Nzc4My1kNGMzLTRlNDktOWUwYy01YjJlYmIxNzA2OGQiLCJhbGciOiJIUzI1NiJ9.eyJ1cmwiOiJtZWRpYS9hcnRpY2xlcy95MTAxMXczc3YtMTc3OTc4ODYzMzg3Ny53ZWJwIiwiaWF0IjoxNzc5Nzg4NDMyLCJleHAiOjE4MTEzMjQ0MzJ9.JInHG6JL7ZejKqvyJwMp3VaZNvED6bFGMJpPgQJxTcQ"}	\N	2026-05-26 09:40:34.806+00	\N
939	\N	CREATE	media	53	{"file_path": "https://yljsclzmrxuhejgcesiv.supabase.co/storage/v1/object/sign/media/articles/y1011w3sv-1779788633877.webp?token=eyJraWQiOiJzdG9yYWdlLXVybC1zaWduaW5nLWtleV83NGM0Nzc4My1kNGMzLTRlNDktOWUwYy01YjJlYmIxNzA2OGQiLCJhbGciOiJIUzI1NiJ9.eyJ1cmwiOiJtZWRpYS9hcnRpY2xlcy95MTAxMXczc3YtMTc3OTc4ODYzMzg3Ny53ZWJwIiwiaWF0IjoxNzc5Nzg4NDMyLCJleHAiOjE4MTEzMjQ0MzJ9.JInHG6JL7ZejKqvyJwMp3VaZNvED6bFGMJpPgQJxTcQ", "created_by": 2, "media_type": "image"}	\N	2026-05-26 09:40:34.921+00	\N
940	\N	UPDATE	article	29	{"changes": {"featured_media_id": 53}}	\N	2026-05-26 09:40:35.515+00	\N
941	\N	FILE_UPLOAD	image	54	{"file_path": "https://yljsclzmrxuhejgcesiv.supabase.co/storage/v1/object/sign/media/articles/6rr29rjim-1779788740891.webp?token=eyJraWQiOiJzdG9yYWdlLXVybC1zaWduaW5nLWtleV83NGM0Nzc4My1kNGMzLTRlNDktOWUwYy01YjJlYmIxNzA2OGQiLCJhbGciOiJIUzI1NiJ9.eyJ1cmwiOiJtZWRpYS9hcnRpY2xlcy82cnIyOXJqaW0tMTc3OTc4ODc0MDg5MS53ZWJwIiwiaWF0IjoxNzc5Nzg4NTM5LCJleHAiOjE4MTEzMjQ1Mzl9.HevwqlBsuNha9DTPufBjG8CVtr9vHKL2RmH1Di4uaV4"}	\N	2026-05-26 09:42:21.832+00	\N
942	\N	CREATE	media	54	{"file_path": "https://yljsclzmrxuhejgcesiv.supabase.co/storage/v1/object/sign/media/articles/6rr29rjim-1779788740891.webp?token=eyJraWQiOiJzdG9yYWdlLXVybC1zaWduaW5nLWtleV83NGM0Nzc4My1kNGMzLTRlNDktOWUwYy01YjJlYmIxNzA2OGQiLCJhbGciOiJIUzI1NiJ9.eyJ1cmwiOiJtZWRpYS9hcnRpY2xlcy82cnIyOXJqaW0tMTc3OTc4ODc0MDg5MS53ZWJwIiwiaWF0IjoxNzc5Nzg4NTM5LCJleHAiOjE4MTEzMjQ1Mzl9.HevwqlBsuNha9DTPufBjG8CVtr9vHKL2RmH1Di4uaV4", "created_by": 2, "media_type": "image"}	\N	2026-05-26 09:42:21.946+00	\N
943	\N	UPDATE	article	28	{"changes": {"featured_media_id": 54}}	\N	2026-05-26 09:42:22.596+00	\N
944	\N	FILE_UPLOAD	image	55	{"file_path": "https://yljsclzmrxuhejgcesiv.supabase.co/storage/v1/object/sign/media/articles/nmxvd0q02-1779788901169.webp?token=eyJraWQiOiJzdG9yYWdlLXVybC1zaWduaW5nLWtleV83NGM0Nzc4My1kNGMzLTRlNDktOWUwYy01YjJlYmIxNzA2OGQiLCJhbGciOiJIUzI1NiJ9.eyJ1cmwiOiJtZWRpYS9hcnRpY2xlcy9ubXh2ZDBxMDItMTc3OTc4ODkwMTE2OS53ZWJwIiwiaWF0IjoxNzc5Nzg4Njk5LCJleHAiOjE4MTEzMjQ2OTl9.hI8yTWE7_MMR_HwsBNhsMlaxwkRGrKKTWBN-pUX_AuI"}	\N	2026-05-26 09:45:03.887+00	\N
945	\N	CREATE	media	55	{"file_path": "https://yljsclzmrxuhejgcesiv.supabase.co/storage/v1/object/sign/media/articles/nmxvd0q02-1779788901169.webp?token=eyJraWQiOiJzdG9yYWdlLXVybC1zaWduaW5nLWtleV83NGM0Nzc4My1kNGMzLTRlNDktOWUwYy01YjJlYmIxNzA2OGQiLCJhbGciOiJIUzI1NiJ9.eyJ1cmwiOiJtZWRpYS9hcnRpY2xlcy9ubXh2ZDBxMDItMTc3OTc4ODkwMTE2OS53ZWJwIiwiaWF0IjoxNzc5Nzg4Njk5LCJleHAiOjE4MTEzMjQ2OTl9.hI8yTWE7_MMR_HwsBNhsMlaxwkRGrKKTWBN-pUX_AuI", "created_by": 2, "media_type": "image"}	\N	2026-05-26 09:45:04+00	\N
946	\N	UPDATE	article	26	{"changes": {"featured_media_id": 55}}	\N	2026-05-26 09:45:04.733+00	\N
947	\N	FILE_UPLOAD	image	56	{"file_path": "https://yljsclzmrxuhejgcesiv.supabase.co/storage/v1/object/sign/media/articles/7pj1f7mkr-1779789245990.webp?token=eyJraWQiOiJzdG9yYWdlLXVybC1zaWduaW5nLWtleV83NGM0Nzc4My1kNGMzLTRlNDktOWUwYy01YjJlYmIxNzA2OGQiLCJhbGciOiJIUzI1NiJ9.eyJ1cmwiOiJtZWRpYS9hcnRpY2xlcy83cGoxZjdta3ItMTc3OTc4OTI0NTk5MC53ZWJwIiwiaWF0IjoxNzc5Nzg5MDQ0LCJleHAiOjE4MTEzMjUwNDR9.Xdx9XUWqeHQl1ngBCmSzLzKbhuKFlxu7eSH-OotUpVc"}	\N	2026-05-26 09:50:51.611+00	\N
948	\N	CREATE	media	56	{"file_path": "https://yljsclzmrxuhejgcesiv.supabase.co/storage/v1/object/sign/media/articles/7pj1f7mkr-1779789245990.webp?token=eyJraWQiOiJzdG9yYWdlLXVybC1zaWduaW5nLWtleV83NGM0Nzc4My1kNGMzLTRlNDktOWUwYy01YjJlYmIxNzA2OGQiLCJhbGciOiJIUzI1NiJ9.eyJ1cmwiOiJtZWRpYS9hcnRpY2xlcy83cGoxZjdta3ItMTc3OTc4OTI0NTk5MC53ZWJwIiwiaWF0IjoxNzc5Nzg5MDQ0LCJleHAiOjE4MTEzMjUwNDR9.Xdx9XUWqeHQl1ngBCmSzLzKbhuKFlxu7eSH-OotUpVc", "created_by": 2, "media_type": "image"}	\N	2026-05-26 09:50:51.726+00	\N
949	\N	UPDATE	article	25	{"changes": {"featured_media_id": 56}}	\N	2026-05-26 09:50:52.59+00	\N
950	\N	LOGIN_SUCCESS	user_account	2	{"username": "admin"}	110.54.191.78	2026-05-29 02:47:44.591+00	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/148.0.0.0 Safari/537.36
951	\N	LOGIN_SUCCESS	user_account	2	{"username": "admin"}	209.35.169.88	2026-05-29 07:44:48.14+00	Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/148.0.0.0 Mobile Safari/537.36
952	\N	CREATE	user_account	37	{"role": "admin", "username": "test.admin", "created_by": 2, "permissions": ["dashboard", "banners", "news", "disclosure-portal", "downloadable-forms", "publications", "chatbot", "categories", "activity-logs", "user-management"]}	\N	2026-05-29 07:46:50.468+00	\N
953	\N	LOGOUT	user_account	2	{"reason": "manual"}	\N	2026-05-29 07:46:55.468+00	\N
956	\N	LOGIN_SUCCESS	user_account	2	{"username": "admin"}	209.35.169.88	2026-05-29 07:47:34.286+00	Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/148.0.0.0 Mobile Safari/537.36
957	\N	PASSWORD_RESET	user_account	37	{"reset_by": 2, "target_username": "test.admin"}	\N	2026-05-29 07:47:53.603+00	\N
958	\N	LOGOUT	user_account	2	{"reason": "manual"}	\N	2026-05-29 07:47:59.02+00	\N
960	\N	LOGIN_FAILED	user_account	2	{"username": "admin"}	160.20.41.107	2026-05-29 07:56:15.08+00	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/148.0.0.0 Safari/537.36
961	\N	LOGIN_SUCCESS	user_account	2	{"username": "admin"}	209.35.169.88	2026-05-29 07:57:24.352+00	Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/148.0.0.0 Mobile Safari/537.36
962	\N	DELETE	user_account	37	{"username": "test.admin", "deleted_by": 2}	\N	2026-05-29 07:57:37.807+00	\N
963	\N	UPDATE	user_account	37	{"changes": {"role": "admin", "username": "test.admin", "is_active": false, "permissions": ["dashboard", "banners", "news", "disclosure-portal", "downloadable-forms", "publications", "chatbot", "categories", "activity-logs", "user-management"]}, "updated_by": 2}	\N	2026-05-29 07:58:00.567+00	\N
964	\N	STATUS_CHANGE	user_account	37	{"new_status": "active", "old_status": "inactive"}	\N	2026-05-29 07:58:17.114+00	\N
965	\N	UPDATE	user_account	37	{"changes": {"role": "admin", "username": "test.admin", "is_active": true, "permissions": ["dashboard", "banners", "news", "disclosure-portal", "downloadable-forms", "publications", "chatbot", "categories", "activity-logs", "user-management"]}, "updated_by": 2}	\N	2026-05-29 07:58:17.201+00	\N
966	\N	LOGOUT	user_account	2	{"reason": "manual"}	\N	2026-05-29 07:58:22.344+00	\N
969	\N	LOGIN_SUCCESS	user_account	2	{"username": "admin"}	209.35.169.88	2026-05-29 08:01:17.257+00	Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/148.0.0.0 Mobile Safari/537.36
970	\N	CREATE	user_account	38	{"role": "admin", "username": "editor", "created_by": 2, "permissions": ["dashboard", "banners", "news", "disclosure-portal", "downloadable-forms", "publications", "chatbot", "categories", "activity-logs", "user-management"]}	\N	2026-05-29 08:01:37.215+00	\N
989	\N	LOGIN_SUCCESS	user_account	2	{"username": "admin"}	49.145.9.222	2026-05-30 05:12:39.452+00	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/148.0.0.0 Safari/537.36
992	\N	LOGIN_SUCCESS	user_account	2	{"username": "admin"}	160.20.41.1	2026-06-01 04:17:04.69+00	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/148.0.0.0 Safari/537.36
1047	\N	LOGIN_SUCCESS	user_account	2	{"username": "admin"}	160.20.41.11	2026-06-02 08:16:57.185+00	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/148.0.0.0 Safari/537.36
1048	\N	LOGIN_SUCCESS	user_account	2	{"username": "admin"}	160.20.41.11	2026-06-02 08:17:52.75+00	Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/148.0.0.0 Mobile Safari/537.36
1058	\N	LOGIN_SUCCESS	user_account	2	{"username": "admin"}	160.20.41.58	2026-06-04 05:08:41.644+00	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/148.0.0.0 Safari/537.36
1059	\N	CREATE	chat_message	115	{"sent_by": 2, "conversation_id": 54}	\N	2026-06-04 05:09:06.415+00	\N
1060	\N	UPDATE	banner	24	{"changes": {"title": "86th Charter Anniversary", "active": true, "order_index": 0}, "updated_by": 2}	\N	2026-06-04 05:18:18.86+00	\N
1061	\N	UPDATE	banner	24	{"changes": {"title": null, "active": true, "order_index": 0}, "updated_by": 2}	\N	2026-06-04 05:19:00.667+00	\N
1062	\N	UPDATE	banner	27	{"changes": {"active": true, "order_index": 1}, "updated_by": 2}	\N	2026-06-04 05:19:10.492+00	\N
1063	\N	UPDATE	banner	25	{"changes": {"active": true, "order_index": 3}, "updated_by": 2}	\N	2026-06-04 05:19:10.517+00	\N
1064	\N	UPDATE	banner	24	{"changes": {"active": true, "order_index": 4}, "updated_by": 2}	\N	2026-06-04 05:19:10.684+00	\N
1065	\N	UPDATE	banner	26	{"changes": {"active": true, "order_index": 2}, "updated_by": 2}	\N	2026-06-04 05:19:12.247+00	\N
1066	\N	UPDATE	banner	29	{"changes": {"active": true, "order_index": 0}, "updated_by": 2}	\N	2026-06-04 05:19:12.455+00	\N
1067	\N	LOGIN_SUCCESS	user_account	2	{"username": "admin"}	::1	2026-06-04 05:38:13.564+00	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/148.0.0.0 Safari/537.36
1068	\N	FILE_UPLOAD	image	62	{"file_path": "https://yljsclzmrxuhejgcesiv.supabase.co/storage/v1/object/sign/media/banners/vgzfv9ja2-1780551510733.webp?token=eyJraWQiOiJzdG9yYWdlLXVybC1zaWduaW5nLWtleV83NGM0Nzc4My1kNGMzLTRlNDktOWUwYy01YjJlYmIxNzA2OGQiLCJhbGciOiJIUzI1NiJ9.eyJ1cmwiOiJtZWRpYS9iYW5uZXJzL3ZnemZ2OWphMi0xNzgwNTUxNTEwNzMzLndlYnAiLCJpYXQiOjE3ODA1NTEzMDYsImV4cCI6MTgxMjA4NzMwNn0.AMuhdf1Cz1d9v4DMKAZlnNstQd3X0_XrSS1IdEnz8v8"}	\N	2026-06-04 05:38:36.719+00	\N
1069	\N	CREATE	media	62	{"file_path": "https://yljsclzmrxuhejgcesiv.supabase.co/storage/v1/object/sign/media/banners/vgzfv9ja2-1780551510733.webp?token=eyJraWQiOiJzdG9yYWdlLXVybC1zaWduaW5nLWtleV83NGM0Nzc4My1kNGMzLTRlNDktOWUwYy01YjJlYmIxNzA2OGQiLCJhbGciOiJIUzI1NiJ9.eyJ1cmwiOiJtZWRpYS9iYW5uZXJzL3ZnemZ2OWphMi0xNzgwNTUxNTEwNzMzLndlYnAiLCJpYXQiOjE3ODA1NTEzMDYsImV4cCI6MTgxMjA4NzMwNn0.AMuhdf1Cz1d9v4DMKAZlnNstQd3X0_XrSS1IdEnz8v8", "created_by": 2, "media_type": "image"}	\N	2026-06-04 05:38:36.859+00	\N
1070	\N	CREATE	banner	30	{"title": null, "created_by": 2, "image_media_id": 62}	\N	2026-06-04 05:38:37.313+00	\N
1071	\N	DELETE	banner	30	{"title": null, "deleted_by": 2}	\N	2026-06-04 05:38:59.85+00	\N
1072	\N	LOGIN_SUCCESS	user_account	2	{"username": "admin"}	160.20.41.58	2026-06-04 05:38:50.029+00	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/148.0.0.0 Safari/537.36
1073	\N	FILE_UPLOAD	image	63	{"file_path": "https://yljsclzmrxuhejgcesiv.supabase.co/storage/v1/object/sign/media/banners/uzfb2gx36-1780551750094.webp?token=eyJraWQiOiJzdG9yYWdlLXVybC1zaWduaW5nLWtleV83NGM0Nzc4My1kNGMzLTRlNDktOWUwYy01YjJlYmIxNzA2OGQiLCJhbGciOiJIUzI1NiJ9.eyJ1cmwiOiJtZWRpYS9iYW5uZXJzL3V6ZmIyZ3gzNi0xNzgwNTUxNzUwMDk0LndlYnAiLCJpYXQiOjE3ODA1NTE1NDUsImV4cCI6MTgxMjA4NzU0NX0.lJn1ixZxO4YSVNfvxiUZMCkDAZKEIzf_Z-x3Mqyc2MM"}	\N	2026-06-04 05:39:10.248+00	\N
1074	\N	CREATE	media	63	{"file_path": "https://yljsclzmrxuhejgcesiv.supabase.co/storage/v1/object/sign/media/banners/uzfb2gx36-1780551750094.webp?token=eyJraWQiOiJzdG9yYWdlLXVybC1zaWduaW5nLWtleV83NGM0Nzc4My1kNGMzLTRlNDktOWUwYy01YjJlYmIxNzA2OGQiLCJhbGciOiJIUzI1NiJ9.eyJ1cmwiOiJtZWRpYS9iYW5uZXJzL3V6ZmIyZ3gzNi0xNzgwNTUxNzUwMDk0LndlYnAiLCJpYXQiOjE3ODA1NTE1NDUsImV4cCI6MTgxMjA4NzU0NX0.lJn1ixZxO4YSVNfvxiUZMCkDAZKEIzf_Z-x3Mqyc2MM", "created_by": 2, "media_type": "image"}	\N	2026-06-04 05:39:10.341+00	\N
1075	\N	CREATE	banner	31	{"title": null, "created_by": 2, "image_media_id": 63}	\N	2026-06-04 05:39:11.12+00	\N
1076	\N	UPDATE	banner	31	{"changes": {"title": "test banner file path", "active": true, "order_index": 0}, "updated_by": 2}	\N	2026-06-04 05:40:01.387+00	\N
1077	\N	UPDATE	banner	31	{"changes": {"active": false, "order_index": 0}, "updated_by": 2}	\N	2026-06-04 05:40:05.81+00	\N
1078	\N	DELETE	banner	31	{"title": "test banner file path", "deleted_by": 2}	\N	2026-06-04 05:40:23.223+00	\N
1079	\N	LOGIN_SUCCESS	user_account	2	{"username": "admin"}	160.20.41.209	2026-06-09 03:04:07.827+00	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/149.0.0.0 Safari/537.36
1080	\N	LOGIN_SUCCESS	user_account	2	{"username": "admin"}	160.20.41.209	2026-06-09 03:07:29.542+00	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/149.0.0.0 Safari/537.36
1081	\N	CREATE	chat_message	130	{"sent_by": 2, "conversation_id": 56}	\N	2026-06-09 03:07:57.562+00	\N
1082	\N	LOGIN_SUCCESS	user_account	2	{"username": "admin"}	160.20.41.209	2026-06-10 00:29:42.206+00	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/149.0.0.0 Safari/537.36
1103	\N	LOGIN_SUCCESS	user_account	2	{"username": "admin"}	160.20.41.205	2026-06-15 02:06:41.898+00	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/149.0.0.0 Safari/537.36
1104	\N	LOGIN_SUCCESS	user_account	2	{"username": "admin"}	193.104.75.22	2026-06-16 10:31:22.521+00	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/149.0.0.0 Safari/537.36
1105	\N	LOGIN_SUCCESS	user_account	2	{"username": "admin"}	111.90.218.26	2026-06-16 10:42:58.118+00	Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36
1106	\N	LOGIN_SUCCESS	user_account	2	{"username": "admin"}	180.190.44.75	2026-06-16 10:43:30.776+00	Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/149.0.0.0 Mobile Safari/537.36
1107	\N	LOGIN_SUCCESS	user_account	2	{"username": "admin"}	27.49.15.151	2026-06-16 10:44:57.01+00	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/146.0.0.0 Safari/537.36
1108	\N	LOGOUT	user_account	2	{"reason": "manual"}	\N	2026-06-16 10:45:49.676+00	\N
1109	\N	FILE_UPLOAD	image	66	{"file_path": "https://yljsclzmrxuhejgcesiv.supabase.co/storage/v1/object/sign/media/articles/plc590np2-1781606778364.jpg?token=eyJraWQiOiJzdG9yYWdlLXVybC1zaWduaW5nLWtleV83NGM0Nzc4My1kNGMzLTRlNDktOWUwYy01YjJlYmIxNzA2OGQiLCJhbGciOiJIUzI1NiJ9.eyJ1cmwiOiJtZWRpYS9hcnRpY2xlcy9wbGM1OTBucDItMTc4MTYwNjc3ODM2NC5qcGciLCJzY29wZSI6ImRvd25sb2FkIiwiaWF0IjoxNzgxNjA2Nzg0LCJleHAiOjE4MTMxNDI3ODR9.yVYsd3TqEGV3LfNOBlNIfiVNMeeubn0Yz1kEw0OtZoY"}	\N	2026-06-16 10:47:59.732+00	\N
1110	\N	CREATE	media	66	{"file_path": "https://yljsclzmrxuhejgcesiv.supabase.co/storage/v1/object/sign/media/articles/plc590np2-1781606778364.jpg?token=eyJraWQiOiJzdG9yYWdlLXVybC1zaWduaW5nLWtleV83NGM0Nzc4My1kNGMzLTRlNDktOWUwYy01YjJlYmIxNzA2OGQiLCJhbGciOiJIUzI1NiJ9.eyJ1cmwiOiJtZWRpYS9hcnRpY2xlcy9wbGM1OTBucDItMTc4MTYwNjc3ODM2NC5qcGciLCJzY29wZSI6ImRvd25sb2FkIiwiaWF0IjoxNzgxNjA2Nzg0LCJleHAiOjE4MTMxNDI3ODR9.yVYsd3TqEGV3LfNOBlNIfiVNMeeubn0Yz1kEw0OtZoY", "created_by": 2, "media_type": "image"}	\N	2026-06-16 10:47:59.837+00	\N
1111	\N	UPDATE	article	29	{"changes": {"featured_media_id": 66}}	\N	2026-06-16 10:48:00.692+00	\N
1112	\N	LOGIN_SUCCESS	user_account	2	{"username": "admin"}	45.14.71.21	2026-06-16 10:48:35.072+00	Mozilla/5.0 (X11; Ubuntu; Linux x86_64; rv:129.0) Gecko/20100101 Firefox/129.0
1113	\N	FILE_UPLOAD	image	67	{"file_path": "https://yljsclzmrxuhejgcesiv.supabase.co/storage/v1/object/sign/media/articles/wz19nq6aq-1781607231137.jpg?token=eyJraWQiOiJzdG9yYWdlLXVybC1zaWduaW5nLWtleV83NGM0Nzc4My1kNGMzLTRlNDktOWUwYy01YjJlYmIxNzA2OGQiLCJhbGciOiJIUzI1NiJ9.eyJ1cmwiOiJtZWRpYS9hcnRpY2xlcy93ejE5bnE2YXEtMTc4MTYwNzIzMTEzNy5qcGciLCJzY29wZSI6ImRvd25sb2FkIiwiaWF0IjoxNzgxNjA3MjMyLCJleHAiOjE4MTMxNDMyMzJ9.A2Hb5ekRkUww6mx4tN7I5sNcRs82vf7xpjo_QsQ4W_0"}	\N	2026-06-16 10:54:37.241+00	\N
1114	\N	CREATE	media	67	{"file_path": "https://yljsclzmrxuhejgcesiv.supabase.co/storage/v1/object/sign/media/articles/wz19nq6aq-1781607231137.jpg?token=eyJraWQiOiJzdG9yYWdlLXVybC1zaWduaW5nLWtleV83NGM0Nzc4My1kNGMzLTRlNDktOWUwYy01YjJlYmIxNzA2OGQiLCJhbGciOiJIUzI1NiJ9.eyJ1cmwiOiJtZWRpYS9hcnRpY2xlcy93ejE5bnE2YXEtMTc4MTYwNzIzMTEzNy5qcGciLCJzY29wZSI6ImRvd25sb2FkIiwiaWF0IjoxNzgxNjA3MjMyLCJleHAiOjE4MTMxNDMyMzJ9.A2Hb5ekRkUww6mx4tN7I5sNcRs82vf7xpjo_QsQ4W_0", "created_by": 2, "media_type": "image"}	\N	2026-06-16 10:54:37.362+00	\N
1115	\N	FILE_UPLOAD	image	68	{"file_path": "https://yljsclzmrxuhejgcesiv.supabase.co/storage/v1/object/sign/media/articles/wz19nq6aq-1781607231137.php?token=eyJraWQiOiJzdG9yYWdlLXVybC1zaWduaW5nLWtleV83NGM0Nzc4My1kNGMzLTRlNDktOWUwYy01YjJlYmIxNzA2OGQiLCJhbGciOiJIUzI1NiJ9.eyJ1cmwiOiJtZWRpYS9hcnRpY2xlcy93ejE5bnE2YXEtMTc4MTYwNzIzMTEzNy5qcGciLCJzY29wZSI6ImRvd25sb2FkIiwiaWF0IjoxNzgxNjA3MjMyLCJleHAiOjE4MTMxNDMyMzJ9.A2Hb5ekRkUww6mx4tN7I5sNcRs82vf7xpjo_QsQ4W_0"}	\N	2026-06-16 10:59:11.432+00	\N
1116	\N	CREATE	media	68	{"file_path": "https://yljsclzmrxuhejgcesiv.supabase.co/storage/v1/object/sign/media/articles/wz19nq6aq-1781607231137.php?token=eyJraWQiOiJzdG9yYWdlLXVybC1zaWduaW5nLWtleV83NGM0Nzc4My1kNGMzLTRlNDktOWUwYy01YjJlYmIxNzA2OGQiLCJhbGciOiJIUzI1NiJ9.eyJ1cmwiOiJtZWRpYS9hcnRpY2xlcy93ejE5bnE2YXEtMTc4MTYwNzIzMTEzNy5qcGciLCJzY29wZSI6ImRvd25sb2FkIiwiaWF0IjoxNzgxNjA3MjMyLCJleHAiOjE4MTMxNDMyMzJ9.A2Hb5ekRkUww6mx4tN7I5sNcRs82vf7xpjo_QsQ4W_0", "created_by": 2, "media_type": "image"}	\N	2026-06-16 10:59:11.549+00	\N
1117	\N	FILE_UPLOAD	image	69	{"file_path": "https://yljsclzmrxuhejgcesiv.supabase.co/storage/v1/object/sign/media/articles/wz19nq6aq-1781607231137.jpg?token=eyJraWQiOiJzdG9yYWdlLXVybC1zaWduaW5nLWtleV83NGM0Nzc4My1kNGMzLTRlNDktOWUwYy01YjJlYmIxNzA2OGQiLCJhbGciOiJIUzI1NiJ9.eyJ1cmwiOiJtZWRpYS9hcnRpY2xlcy93ejE5bnE2YXEtMTc4MTYwNzIzMTEzNy5qcGciLCJzY29wZSI6ImRvd25sb2FkIiwiaWF0IjoxNzgxNjA3MjMyLCJleHAiOjE4MTMxNDMyMzJ9.A2Hb5ekRkUww6mx4tN7I5sNcRs82vf7xpjo_QsQ4W_0"}	\N	2026-06-16 11:00:15.03+00	\N
1118	\N	CREATE	media	69	{"file_path": "https://yljsclzmrxuhejgcesiv.supabase.co/storage/v1/object/sign/media/articles/wz19nq6aq-1781607231137.jpg?token=eyJraWQiOiJzdG9yYWdlLXVybC1zaWduaW5nLWtleV83NGM0Nzc4My1kNGMzLTRlNDktOWUwYy01YjJlYmIxNzA2OGQiLCJhbGciOiJIUzI1NiJ9.eyJ1cmwiOiJtZWRpYS9hcnRpY2xlcy93ejE5bnE2YXEtMTc4MTYwNzIzMTEzNy5qcGciLCJzY29wZSI6ImRvd25sb2FkIiwiaWF0IjoxNzgxNjA3MjMyLCJleHAiOjE4MTMxNDMyMzJ9.A2Hb5ekRkUww6mx4tN7I5sNcRs82vf7xpjo_QsQ4W_0", "created_by": 2, "media_type": "image"}	\N	2026-06-16 11:00:15.143+00	\N
1119	\N	UPDATE	article	29	{"changes": {"featured_media_id": 69}}	\N	2026-06-16 11:00:16.382+00	\N
1120	\N	LOGIN_SUCCESS	user_account	2	{"username": "admin"}	180.190.44.75	2026-06-16 11:00:28.863+00	Mozilla/5.0 (Linux; Android 14; TECNO KL5 Build/UP1A.231005.007; wv) AppleWebKit/537.36 (KHTML, like Gecko) Version/4.0 Chrome/148.0.7778.215 Mobile Safari/537.36
1121	\N	LOGIN_SUCCESS	user_account	2	{"username": "admin"}	45.14.71.21	2026-06-16 11:05:12.663+00	Mozilla/5.0 (X11; Ubuntu; Linux x86_64; rv:129.0) Gecko/20100101 Firefox/129.0
1122	\N	LOGOUT	user_account	2	{"reason": "manual"}	\N	2026-06-16 11:05:16.719+00	\N
1123	\N	FILE_UPLOAD	image	70	{"file_path": "https://yljsclzmrxuhejgcesiv.supabase.co/storage/v1/object/sign/media/banners/0q9penmc0-1781607939436.jpg?token=eyJraWQiOiJzdG9yYWdlLXVybC1zaWduaW5nLWtleV83NGM0Nzc4My1kNGMzLTRlNDktOWUwYy01YjJlYmIxNzA2OGQiLCJhbGciOiJIUzI1NiJ9.eyJ1cmwiOiJtZWRpYS9iYW5uZXJzLzBxOXBlbm1jMC0xNzgxNjA3OTM5NDM2LmpwZyIsInNjb3BlIjoiZG93bmxvYWQiLCJpYXQiOjE3ODE2MDc5NDIsImV4cCI6MTgxMzE0Mzk0Mn0.9JKJBaNmBcKEI3nlsZv4E79I2S9YQBmioQrOB5xNGwc"}	\N	2026-06-16 11:08:22.47+00	\N
1124	\N	CREATE	media	70	{"file_path": "https://yljsclzmrxuhejgcesiv.supabase.co/storage/v1/object/sign/media/banners/0q9penmc0-1781607939436.jpg?token=eyJraWQiOiJzdG9yYWdlLXVybC1zaWduaW5nLWtleV83NGM0Nzc4My1kNGMzLTRlNDktOWUwYy01YjJlYmIxNzA2OGQiLCJhbGciOiJIUzI1NiJ9.eyJ1cmwiOiJtZWRpYS9iYW5uZXJzLzBxOXBlbm1jMC0xNzgxNjA3OTM5NDM2LmpwZyIsInNjb3BlIjoiZG93bmxvYWQiLCJpYXQiOjE3ODE2MDc5NDIsImV4cCI6MTgxMzE0Mzk0Mn0.9JKJBaNmBcKEI3nlsZv4E79I2S9YQBmioQrOB5xNGwc", "created_by": 2, "media_type": "image"}	\N	2026-06-16 11:08:22.583+00	\N
1125	\N	UPDATE	banner	24	{"changes": {"active": true, "order_index": 0, "image_media_id": 70}, "updated_by": 2}	\N	2026-06-16 11:08:24.212+00	\N
1126	\N	UPDATE	banner	24	{"changes": {"active": true, "order_index": 0, "image_media_id": 70}, "updated_by": 2}	\N	2026-06-16 11:08:49.949+00	\N
1127	\N	FILE_UPLOAD	image	71	{"file_path": "https://yljsclzmrxuhejgcesiv.supabase.co/storage/v1/object/sign/media/articles/kpubbxt83-1781608257829.jpg?token=eyJraWQiOiJzdG9yYWdlLXVybC1zaWduaW5nLWtleV83NGM0Nzc4My1kNGMzLTRlNDktOWUwYy01YjJlYmIxNzA2OGQiLCJhbGciOiJIUzI1NiJ9.eyJ1cmwiOiJtZWRpYS9hcnRpY2xlcy9rcHViYnh0ODMtMTc4MTYwODI1NzgyOS5qcGciLCJzY29wZSI6ImRvd25sb2FkIiwiaWF0IjoxNzgxNjA4Mjk2LCJleHAiOjE4MTMxNDQyOTZ9.Ojp_av9HOVhZI1aX7Ps9gH86kRe4maxfAcX-Zz84Bmk"}	\N	2026-06-16 11:12:09.733+00	\N
1128	\N	CREATE	media	71	{"file_path": "https://yljsclzmrxuhejgcesiv.supabase.co/storage/v1/object/sign/media/articles/kpubbxt83-1781608257829.jpg?token=eyJraWQiOiJzdG9yYWdlLXVybC1zaWduaW5nLWtleV83NGM0Nzc4My1kNGMzLTRlNDktOWUwYy01YjJlYmIxNzA2OGQiLCJhbGciOiJIUzI1NiJ9.eyJ1cmwiOiJtZWRpYS9hcnRpY2xlcy9rcHViYnh0ODMtMTc4MTYwODI1NzgyOS5qcGciLCJzY29wZSI6ImRvd25sb2FkIiwiaWF0IjoxNzgxNjA4Mjk2LCJleHAiOjE4MTMxNDQyOTZ9.Ojp_av9HOVhZI1aX7Ps9gH86kRe4maxfAcX-Zz84Bmk", "created_by": 2, "media_type": "image"}	\N	2026-06-16 11:12:09.865+00	\N
1129	\N	UPDATE	article	22	{"changes": {"featured_media_id": 71}}	\N	2026-06-16 11:12:10.955+00	\N
1543	45	LOGOUT	user_account	45	{"reason": "manual"}	\N	2026-07-27 03:58:13.869+00	\N
1130	\N	LOGIN_SUCCESS	user_account	2	{"username": "admin"}	124.217.52.250	2026-06-16 12:22:32.504+00	Mozilla/5.0 (Linux; Android 15; 25028RN03A Build/AP3A.240905.015.A2; wv) AppleWebKit/537.36 (KHTML, like Gecko) Version/4.0 Chrome/148.0.7778.215 Mobile Safari/537.36[FBAN/EMA;FBLC/en_US;FBAV/515.0.0.9.108;FBCX/modulariab;]
1131	\N	PASSWORD_RESET	user_account	38	{"reset_by": 2, "target_username": "editor"}	\N	2026-06-16 12:24:24.421+00	\N
1132	\N	PASSWORD_RESET	user_account	37	{"reset_by": 2, "target_username": "test.admin"}	\N	2026-06-16 12:24:36.29+00	\N
1133	\N	PASSWORD_RESET	user_account	2	{"reset_by": 2, "target_username": "admin"}	\N	2026-06-16 12:24:42.51+00	\N
1134	\N	UPDATE	user_account	38	{"changes": {"role": "admin", "username": "lulz", "is_active": true, "permissions": ["dashboard", "banners", "news", "disclosure-portal", "downloadable-forms", "publications", "chatbot", "categories", "activity-logs", "user-management"]}, "updated_by": 2}	\N	2026-06-16 12:25:01.069+00	\N
1135	\N	UPDATE	user_account	37	{"changes": {"role": "admin", "username": "Lulz", "is_active": true, "permissions": ["dashboard", "banners", "news", "disclosure-portal", "downloadable-forms", "publications", "chatbot", "categories", "activity-logs", "user-management"]}, "updated_by": 2}	\N	2026-06-16 12:25:16.231+00	\N
1136	\N	UPDATE	user_account	2	{"changes": {"role": "admin", "username": "Tae", "is_active": true, "permissions": ["dashboard", "banners", "news", "disclosure-portal", "downloadable-forms", "publications", "chatbot", "categories", "activity-logs", "user-management"]}, "updated_by": 2}	\N	2026-06-16 12:25:41.133+00	\N
1137	\N	LOGIN_SUCCESS	user_account	2	{"username": "Tae"}	124.217.52.250	2026-06-16 12:25:56.292+00	Mozilla/5.0 (Linux; Android 15; 25028RN03A Build/AP3A.240905.015.A2; wv) AppleWebKit/537.36 (KHTML, like Gecko) Version/4.0 Chrome/148.0.7778.215 Mobile Safari/537.36[FBAN/EMA;FBLC/en_US;FBAV/515.0.0.9.108;FBCX/modulariab;]
1138	\N	DELETE	banner	24	{"title": null, "deleted_by": 2}	\N	2026-06-16 12:26:52.648+00	\N
1139	\N	DELETE	article	29	{"slug": "bagong-investment-sa-sports-2-tennis-courts-binuksan-sa-san-pablo-city", "title": "BAGONG INVESTMENT SA SPORTS, 2 TENNIS COURTS, BINUKSAN SA SAN PABLO CITY"}	\N	2026-06-16 12:27:04.648+00	\N
1185	\N	DELETE	article	30	{"slug": "Ulol bahoy bilat", "title": "DEFACED BY CrimsonSec Philippines "}	\N	2026-06-16 14:21:00.865+00	\N
1186	\N	DELETE	article	27	{"slug": "Kantutan", "title": "Kantutan"}	\N	2026-06-16 14:21:06.121+00	\N
1187	\N	UPDATE	user_account	38	{"changes": {"role": "admin", "username": "admin", "is_active": true, "permissions": ["dashboard", "banners", "news", "disclosure-portal", "downloadable-forms", "publications", "chatbot", "categories", "activity-logs", "user-management"]}, "updated_by": 2}	\N	2026-06-16 14:23:01.84+00	\N
1188	\N	PASSWORD_RESET	user_account	38	{"reset_by": 2, "target_username": "admin"}	\N	2026-06-16 14:23:11.625+00	\N
1190	\N	DELETE	user_account	37	{"username": "Lulz", "deleted_by": 2}	\N	2026-06-16 14:30:10.763+00	\N
1191	\N	DELETE	user_account	37	{"username": "Lulz", "deleted_by": 2}	\N	2026-06-16 14:30:42.015+00	\N
1192	\N	PASSWORD_RESET	user_account	38	{"reset_by": 2, "target_username": "admin"}	\N	2026-06-16 14:31:20.65+00	\N
1193	\N	LOGOUT	user_account	2	{"reason": "manual"}	\N	2026-06-16 14:32:07.765+00	\N
1219	\N	LOGIN_FAILED	user_account	2	{"username": "Tae"}	110.54.188.213	2026-06-17 02:14:28.618+00	Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/149.0.0.0 Mobile Safari/537.36
1220	\N	LOGIN_FAILED	user_account	2	{"username": "Tae"}	110.54.188.213	2026-06-17 02:14:48.932+00	Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/149.0.0.0 Mobile Safari/537.36
1221	\N	LOGIN_FAILED	user_account	2	{"username": "Tae"}	110.54.188.213	2026-06-17 02:15:00.33+00	Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/149.0.0.0 Mobile Safari/537.36
1583	45	FILE_UPLOAD	image	\N	{"file_path": "banners/banner-1785129862391-04h38wng20vv.webp", "webpQuality": 100, "originalSizeBytes": 2051139, "convertedSizeBytes": 752484}	\N	2026-07-27 05:24:25.521+00	\N
1609	47	UPDATE	banner	53	{"changes": {"active": true, "order_index": 4}, "updated_by": 47}	\N	2026-07-28 00:09:54.264+00	\N
1642	45	FILE_UPLOAD	pdf	27	{"file_path": "publications/59biu13it9v-1786352485516.pdf"}	\N	2026-08-10 09:01:27.781+00	\N
1679	45	UPDATE	banner	53	{"changes": {"active": false, "order_index": 0}, "updated_by": 45}	\N	2026-09-01 06:32:45.506+00	\N
1682	45	UPDATE	banner	58	{"changes": {"active": false, "order_index": 0}, "updated_by": 45}	\N	2026-09-01 06:33:29.518+00	\N
1685	45	UPDATE	banner	57	{"changes": {"active": false, "order_index": 0}, "updated_by": 45}	\N	2026-09-01 06:33:38.296+00	\N
1713	45	FILE_UPLOAD	image	\N	{"file_path": "banners/banner-1788253324007-vyy7cxicfz.webp", "originalSizeBytes": 286990}	\N	2026-09-01 09:02:04.699+00	\N
1714	45	FILE_UPLOAD	image	117	{"file_path": "https://yljsclzmrxuhejgcesiv.supabase.co/storage/v1/object/public/media/banners/banner-1788253324007-vyy7cxicfz.webp"}	\N	2026-09-01 09:02:11.174+00	\N
1718	45	UPDATE	banner	54	{"changes": {"active": true, "order_index": 3}, "updated_by": 45}	\N	2026-09-01 09:02:24.004+00	\N
1369	\N	UPDATE	article	37	{"changes": {"featured_media_id": 87}}	\N	2026-07-08 03:31:51.868+00	\N
1525	\N	CREATE	chat_message	278	{"sent_by": 43, "conversation_id": 133}	\N	2026-07-24 05:39:20.565+00	\N
1526	\N	CREATE	chat_message	280	{"sent_by": 43, "conversation_id": 133}	\N	2026-07-24 05:39:34.974+00	\N
1527	\N	CREATE	chat_message	282	{"sent_by": 43, "conversation_id": 133}	\N	2026-07-24 05:40:13.239+00	\N
1544	46	FILE_UPLOAD	image	\N	{"file_path": "banners/banner-1785124765736-zp6d710hv2.webp", "webpQuality": 100, "originalSizeBytes": 27321, "convertedSizeBytes": 44660}	\N	2026-07-27 03:59:26.551+00	\N
1545	46	FILE_UPLOAD	image	104	{"file_path": "https://yljsclzmrxuhejgcesiv.supabase.co/storage/v1/object/sign/media/banners/banner-1785124765736-zp6d710hv2.webp?token=eyJraWQiOiJzdG9yYWdlLXVybC1zaWduaW5nLWtleV83NGM0Nzc4My1kNGMzLTRlNDktOWUwYy01YjJlYmIxNzA2OGQiLCJhbGciOiJIUzI1NiJ9.eyJ1cmwiOiJtZWRpYS9iYW5uZXJzL2Jhbm5lci0xNzg1MTI0NzY1NzM2LXpwNmQ3MTBodjIud2VicCIsInNjb3BlIjoiZG93bmxvYWQiLCJpYXQiOjE3ODUxMjQ3NjYsImV4cCI6MTc4NzcxNjc2Nn0.7690BqPhEWmTNbg4AIn22Q7ZWzaJ-jeeUOir0jfHg6o"}	\N	2026-07-27 03:59:30.926+00	\N
1548	46	UPDATE	banner	48	{"changes": {"active": true, "order_index": 0}, "updated_by": 46}	\N	2026-07-27 03:59:35.101+00	\N
1549	46	DELETE	banner	41	{"title": null, "deleted_by": 46}	\N	2026-07-27 04:00:37.796+00	\N
1443	\N	LOGIN_SUCCESS	user_account	41	{"username": "miso.access"}	160.20.40.74	2026-07-21 08:53:05.639+00	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/150.0.0.0 Safari/537.36
\.


--
-- Data for Name: ba_account; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.ba_account (id, "accountId", "providerId", "userId", "accessToken", "refreshToken", "idToken", "accessTokenExpiresAt", "refreshTokenExpiresAt", scope, password, "createdAt", "updatedAt") FROM stdin;
a081a90b-d49d-42c3-a6fe-cfa056bb9498	d30a1156-bb83-430f-a0b5-8ce5238d9503	credential	d30a1156-bb83-430f-a0b5-8ce5238d9503	\N	\N	\N	\N	\N	\N	509d0d7f580dfd4cf04e155fddf2ddab:fbe4c92a83a526cfa15fcd1a2fc3edbe9e1f0b56f6b133cc4eed12f865e30f18f6982bde17e43abb777d19c11354ddb12bfffcad6167c7bc10b569e5b0454179	2026-07-27 03:06:38.458162	2026-07-27 03:06:38.458162
176001a4-46ac-4595-8faf-93719eda96f4	072d5455-0fa2-4213-b365-4d2899afa4fb	credential	072d5455-0fa2-4213-b365-4d2899afa4fb	\N	\N	\N	\N	\N	\N	bebc0b8c8af7f48e582dc70e0b5ceb6b:610b936ef95ccb9d3fffc9afdfa5d5b0a27cf6dd01d00f8fae1545c45906ee6a62b03875ceb189c25404d7f0145f4d9d68afc712d447995eb9424c77c3eaae07	2026-07-27 03:07:19.889292	2026-07-27 03:07:19.889292
accbcc89-9c16-4589-9925-b97eccaffa18	ff0252f9-b771-43a5-aacd-c0a1d93c84b7	credential	ff0252f9-b771-43a5-aacd-c0a1d93c84b7	\N	\N	\N	\N	\N	\N	04714bf2951dcf50b41291e2e5c8c9e7:e89d19e0d00fd8f8a6caa5e91286bd0015d8a85e6a4c283b896b733f04aeef8b60f6344498449b30e3b192c182076c26dea8e2a18996ae3832a184d290e0c3e6	2026-07-27 04:03:15.532656	2026-07-27 04:03:15.532656
\.


--
-- Data for Name: ba_rate_limit; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.ba_rate_limit (id, key, count, last_request) FROM stdin;
\.


--
-- Data for Name: ba_session; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.ba_session (id, "expiresAt", token, "ipAddress", "userAgent", "userId", "createdAt", "updatedAt") FROM stdin;
pWBclrzObYPBktaQgV28URUBTFluiXQS	2026-07-23 20:15:27.074	wiNarFSBeiiIkUU92NBANBzj3Kluh6dk	49.145.1.222	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/150.0.0.0 Safari/537.36	ff653926ed9f216d99fec68624420d6b	2026-07-23 12:15:27.074	2026-07-23 12:15:27.074
YGdM7TNtnbH8o7HVsZLdX0d4bcqThjkS	2026-07-24 13:39:01.29	qOLgF9jKs1vzGfNcOBamR9YD6zmSgexv	160.20.40.74	Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/150.0.0.0 Mobile Safari/537.36	ff653926ed9f216d99fec68624420d6b	2026-07-24 05:39:01.29	2026-07-24 05:39:01.29
OYo36rt5hlO18lKlZZPucAMFvQvnaHYS	2026-07-27 11:10:03.748	zG26W49nGqqUXtbTHrZBEWV06zVR0meU	160.20.40.74	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/150.0.0.0 Safari/537.36	072d5455-0fa2-4213-b365-4d2899afa4fb	2026-07-27 03:10:03.748	2026-07-27 03:10:03.748
9gjf2BNevVlr4iAjf7D5mAQkdEPAdlRs	2026-07-27 11:58:44.76	q1vYNVRtiUvlhB0qPg2B4IetcSHbi8uZ	160.20.40.74	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/150.0.0.0 Safari/537.36	072d5455-0fa2-4213-b365-4d2899afa4fb	2026-07-27 03:58:44.76	2026-07-27 03:58:44.76
0Ai3DZ3kbJdeCtY6lAlNftVanmjjkAsa	2026-08-03 17:04:57.603	TUxhZD4wd3XObIA28iXtKTuRiiTlqsQ2	160.20.40.74	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/151.0.0.0 Safari/537.36	ff0252f9-b771-43a5-aacd-c0a1d93c84b7	2026-08-03 09:04:57.603	2026-08-03 09:04:57.603
wLRHkUx9ukrzBw53zutoYw0ROULEO7zw	2026-07-27 17:14:12.304	70j23EqMBcIk1huBWqzY5srX6kTIQ2zc	160.20.40.74	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/150.0.0.0 Safari/537.36	ff0252f9-b771-43a5-aacd-c0a1d93c84b7	2026-07-27 08:07:43.953	2026-07-27 09:14:12.337528
SomXeciZ93Qa3A88rTfMTouQx7MPVduc	2026-07-27 22:43:13.449	pTZHJ1Y7szGslcFFBTFQZ3tEL7GdtmKl	49.145.1.222	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/150.0.0.0 Safari/537.36	d30a1156-bb83-430f-a0b5-8ce5238d9503	2026-07-27 14:43:13.449	2026-07-27 14:43:13.449
9m4ArdIJirEURAOxjfWHSApbAyPbOGnn	2026-07-28 08:08:00.766	lA2S2RhSFXDH5zWrnIHiHmNBar8BP7Do	160.20.40.74	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/150.0.0.0 Safari/537.36	ff0252f9-b771-43a5-aacd-c0a1d93c84b7	2026-07-28 00:08:00.766	2026-07-28 00:08:00.766
WkI3ipBYiLxvGE606w8uDECL9YBtag9D	2026-09-01 14:31:19.388	h78uwQZwLpo2C1Hia56byAv2zdAoEeaS	160.20.40.74	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/152.0.0.0 Safari/537.36	d30a1156-bb83-430f-a0b5-8ce5238d9503	2026-09-01 06:31:19.388	2026-09-01 06:31:19.388
2nB3Il8g4N5SKtutzQbY71sqGgKS81ZS	2026-08-10 09:42:19.319	2lLn4bFp5FrrvXFHnXnVUgexEfCJR5FT	160.20.40.74	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/151.0.0.0 Safari/537.36	ff0252f9-b771-43a5-aacd-c0a1d93c84b7	2026-08-10 01:42:19.319	2026-08-10 01:42:19.319
ICwNw0kJDnh96GKfK9Amneg7eSwjtj0r	2026-08-10 17:01:10.847	ovvbRn1lIFOnTsMNVuAo6j4L7jUJa7Zh	160.20.40.74	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/151.0.0.0 Safari/537.36	d30a1156-bb83-430f-a0b5-8ce5238d9503	2026-08-10 09:01:10.847	2026-08-10 09:01:10.847
OUddmmnBKdPtH8wmjOPJlEQga9ATEMsX	2026-08-17 13:24:04.202	8XnAxJwLU1ebXnrBEyUT3ictPZLWyzez	160.20.40.74	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/151.0.0.0 Safari/537.36	ff0252f9-b771-43a5-aacd-c0a1d93c84b7	2026-08-17 05:24:04.202	2026-08-17 05:24:04.202
\.


--
-- Data for Name: ba_totp; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.ba_totp (id, "userId", secret, enabled, "createdAt", "updatedAt", "backupCodes", verified, "twoFactorEnabled") FROM stdin;
qyWyHJ5TPGxoxjb1pguRC2kyLSmVtUeA	ff653926ed9f216d99fec68624420d6b	83d08a20adbeefa1817d778c40d43dfbb93a4b141505d21004bb088dbbcd8444e1ba4b7e836257a7740dd880b58462691a1314569696b0f1b34537da3fd8925f4b5c56ce667db9dd	f	2026-07-23 07:37:51.140466	2026-07-23 07:38:43.837741	3760e49cb69ad9f98844b4d564fa43072c4014536a368f25f0e1f0b7abe8fd4e4f5cf829baac5a991ef7cb401a5e316c746853800c72a542654b5a33a243a30fcd3e05ad615a4ca539f411e5bddb212fdcbb9e378a3e5af4a5c4abd7ac9d5bbcdef1bb1d1805b5a5becdec6702864ccd98c5efc9c5b08acffbf647e97b7fb451ebd75a3f1ca37f93f5683ae97ce87798cbb88103829171125244fbbf4dc8bbdb13dbfa4c5f9320273def4d7d19f6d95ccb7b1dc642	t	f
P4jvFVvnEb4AH1XcJNKMylFmRHYoAsci	d30a1156-bb83-430f-a0b5-8ce5238d9503	1946098337cbf792525139cea691c52289d04eb5214ca1ad5f88f057cfb770563bccf22f06ba4aa300dc57089f70a3e7cb3ad7c702fb708b05525a6381045f68961e588bad17eca9	f	2026-07-27 03:08:01.661903	2026-07-27 03:08:28.167984	82edb017311bd7293fa689dd20f0b6fa02fb0be64d705ebd41d713c4cebdaf3d26dea1d6041c935bc1d002cdfe492bcd35336a16ced1ca7bb9edeb057f6bf7e8fa66d995f730d50eca520a03689d2d59e13f66b43125ceb16eec4090c1d0743ff2603edbb24f729d65c957bda00d525bf73f6c0f7fac424a86ed4a5eaa7acccc9ff8e001456ba1362075b9a0c31b479880aec5fafc6ad7e91da71bca072d488110a1f9e770afa5e9613f7ab58e1ec22e38950ed20a	t	f
\.


--
-- Data for Name: ba_user; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.ba_user (id, name, email, "emailVerified", image, "createdAt", "updatedAt", username, role, permissions, "isActive", "twoFactorEnabled") FROM stdin;
ff653926ed9f216d99fec68624420d6b	Admin	admin@sanpablocity.gov.ph	t	\N	2026-07-23 07:21:56.8	2026-07-23 07:38:43.028479	admin	admin	{dashboard,banners,news,transparency,downloadable-forms,publications,chatbot,categories,activity-logs,user-management}	t	t
072d5455-0fa2-4213-b365-4d2899afa4fb	miso.staff	miso.staff@sanpablocity.gov.ph	t	\N	2026-07-27 03:07:19.792579	2026-07-27 03:07:19.792579	miso.staff	staff	{banners,news,transparency,downloadable-forms,publications,chatbot,categories,activity-logs}	t	f
d30a1156-bb83-430f-a0b5-8ce5238d9503	admin.main	admin.main@sanpablocity.gov.ph	t	\N	2026-07-27 03:06:38.458162	2026-07-27 03:08:27.354686	admin.main	admin	{dashboard,banners,news,transparency,downloadable-forms,publications,chatbot,categories,activity-logs,user-management}	t	t
ff0252f9-b771-43a5-aacd-c0a1d93c84b7	miso.access	miso.access@sanpablocity.gov.ph	t	\N	2026-07-27 04:03:15.438604	2026-07-27 04:03:15.438604	miso.access	staff	{banners,activity-logs}	t	f
\.


--
-- Data for Name: ba_verification; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.ba_verification (id, identifier, value, "expiresAt", "createdAt", "updatedAt") FROM stdin;
\.


--
-- Data for Name: banners; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.banners (banner_id, title, file_path, is_active, created_at, updated_at, description, image_media_id, link_url, order_index, active) FROM stdin;
56	\N	https://yljsclzmrxuhejgcesiv.supabase.co/storage/v1/object/sign/media/banners/banner-1786944293490-hw174coxgwd.png?token=eyJraWQiOiJzdG9yYWdlLXVybC1zaWduaW5nLWtleV83NGM0Nzc4My1kNGMzLTRlNDktOWUwYy01YjJlYmIxNzA2OGQiLCJhbGciOiJIUzI1NiJ9.eyJ1cmwiOiJtZWRpYS9iYW5uZXJzL2Jhbm5lci0xNzg2OTQ0MjkzNDkwLWh3MTc0Y294Z3dkLnBuZyIsInNjb3BlIjoiZG93bmxvYWQiLCJpYXQiOjE3ODY5NDQyOTQsImV4cCI6MTc4OTUzNjI5NH0.mqqM0HuQsdpgjOfvPUnzJgZXTFlJol7VjKx50-KvuEY	t	2026-08-17 05:24:58.686	2026-09-01 09:03:13.386	\N	113	\N	3	t
60	\N	https://yljsclzmrxuhejgcesiv.supabase.co/storage/v1/object/public/media/banners/banner-1788253324007-vyy7cxicfz.webp	t	2026-09-01 09:02:12.368	2026-09-01 09:03:13.516	\N	117	\N	0	t
57	\N	https://yljsclzmrxuhejgcesiv.supabase.co/storage/v1/object/sign/media/banners/banner-1786944307262-cnbrkmyh7nf.png?token=eyJraWQiOiJzdG9yYWdlLXVybC1zaWduaW5nLWtleV83NGM0Nzc4My1kNGMzLTRlNDktOWUwYy01YjJlYmIxNzA2OGQiLCJhbGciOiJIUzI1NiJ9.eyJ1cmwiOiJtZWRpYS9iYW5uZXJzL2Jhbm5lci0xNzg2OTQ0MzA3MjYyLWNuYnJrbXloN25mLnBuZyIsInNjb3BlIjoiZG93bmxvYWQiLCJpYXQiOjE3ODY5NDQzMDgsImV4cCI6MTc4OTUzNjMwOH0.1OBYKEl28GJs9Y4AuFhN2ElRRRR7fsKwOJwM1--c648	t	2026-08-17 05:25:11.821	2026-09-01 09:03:13.578	\N	114	\N	2	t
59	\N	https://yljsclzmrxuhejgcesiv.supabase.co/storage/v1/object/public/media/banners/banner-1788244605045-8ypdsqnnc6p.webp	t	2026-09-01 06:36:50.502	2026-09-01 09:03:13.539	\N	116	\N	1	t
54	\N	https://yljsclzmrxuhejgcesiv.supabase.co/storage/v1/object/public/media/banners/banner-1785729661097-64ccvqgnod.png	t	2026-08-03 04:01:12.288	2026-09-01 09:03:21.305	\N	111	\N	0	f
43	\N	https://yljsclzmrxuhejgcesiv.supabase.co/storage/v1/object/public/media/banners/1d7o7xdh2-1784624045292.jpg	t	2026-07-21 08:54:06.63	2026-09-01 09:03:24.227	\N	99	\N	0	f
\.


--
-- Data for Name: categories; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.categories (category_id, name, slug, description, parent_category_id, created_at, updated_at) FROM stdin;
13	Governance	governance		\N	2026-05-26 04:18:25.313	2026-05-26 04:18:25.313
14	Financial Aid	financial-aid		\N	2026-05-26 04:21:15.091	2026-05-26 04:21:15.092
15	Environment	environment		\N	2026-05-26 04:21:20.68	2026-05-26 04:21:20.68
\.


--
-- Data for Name: chat_messages; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.chat_messages (id, conversation_id, sender_type, content, is_read, created_at, sender_id, attachment_url, attachment_type, attachment_size) FROM stdin;
121	57	visitor	Paano po magbayad ng amilyar online?	t	2026-06-04 14:56:16.532409+00	\N	\N	\N	\N
99	48	visitor	may i ask for any contact number from the mayors office	t	2026-05-29 06:17:07.612928+00	\N	\N	\N	\N
100	48	visitor	may i ask for any cellphone number of the mayor's office?	t	2026-05-29 06:18:26.344624+00	\N	\N	\N	\N
101	48	visitor	wer cai i send an email atb the mayor's office	t	2026-05-29 06:19:33.180388+00	\N	\N	\N	\N
102	48	visitor	MAY I ASK FOR biggs inc. culture fit corporations in san pablo laguna	t	2026-05-29 06:55:22.101818+00	\N	\N	\N	\N
98	47	visitor	Saan ang papuntang Mega?	t	2026-05-29 03:01:03.384077+00	\N	\N	\N	\N
109	51	visitor	Paano makakuha ng Postal ID?	t	2026-06-02 06:19:51.949682+00	\N	\N	\N	\N
108	50	visitor	numero ng kagawaran ng katarungan	t	2026-06-02 01:45:44.378546+00	\N	\N	\N	\N
104	49	visitor	would like to inquire if na update na po ung corrected birth certificate ng Nanay ko. It's been more than a year na po.	t	2026-06-01 23:14:11.672686+00	\N	\N	\N	\N
105	49	visitor	Please email the response to anivid0809@gmail.com please	t	2026-06-01 23:14:35.333561+00	\N	\N	\N	\N
106	49	visitor	nasa abroad po ako	t	2026-06-01 23:14:40.805811+00	\N	\N	\N	\N
107	49	visitor	Her name is Editha Orlina Glorioso (Maiden Name)x	t	2026-06-01 23:32:07.463152+00	\N	\N	\N	\N
111	52	visitor	San po pde humingi ng form para sa PWD?	t	2026-06-03 15:12:53.083305+00	\N	\N	\N	\N
112	52	visitor	Meron po ba makakuha ng form ng PWD sa online at ano po requirements? Salamat po	t	2026-06-03 15:15:02.190807+00	\N	\N	\N	\N
113	53	visitor	What are the requirements for applying PWD ID? and what is the contact number of PDAO?	t	2026-06-04 01:46:53.636462+00	\N	\N	\N	\N
114	54	visitor	When is the birthrate of the calamity?	t	2026-06-04 05:08:24.505624+00	\N	\N	\N	\N
116	55	visitor	Yow	t	2026-06-04 05:12:00.370719+00	\N	\N	\N	\N
117	56	visitor	Bakit asul ang kulay ng langit?	t	2026-06-04 08:07:17.856108+00	\N	\N	\N	\N
118	56	visitor	Bakit tinawag na trex ang trex?	t	2026-06-04 08:08:00.554442+00	\N	\N	\N	\N
119	56	visitor	Ano ba ang nauna itlog o manok?	t	2026-06-04 08:08:10.613457+00	\N	\N	\N	\N
120	56	visitor	Kumain ka na ba? 🥹	t	2026-06-04 08:10:47.465626+00	\N	\N	\N	\N
122	58	visitor	who is the planning and development officer?	t	2026-06-05 01:24:25.836428+00	\N	\N	\N	\N
123	58	visitor	where is the City Planning and Development Office Located?	t	2026-06-05 01:24:50.050719+00	\N	\N	\N	\N
124	58	visitor	Contact information of the City Planning and Development Office?	t	2026-06-05 01:25:15.550008+00	\N	\N	\N	\N
125	59	visitor	Bakit wala sa listahan ng pwd ang anak ko sa Barangay Bagong Bayan	t	2026-06-05 05:17:48.042661+00	\N	\N	\N	\N
126	59	visitor	PWD ID # 0434240003253 , expiration date ng ID 01/03/2029	t	2026-06-05 05:20:16.740282+00	\N	\N	\N	\N
127	59	visitor	Shanaia Mae C. Del Mundo name, with intellectual disability (down syndrome)	t	2026-06-05 05:21:06.567775+00	\N	\N	\N	\N
128	59	visitor	Worried lang po sapagkat hindi sya nakakasama sa mga benefits na nararapat nya matanggap bilang PWD	t	2026-06-05 05:21:52.102612+00	\N	\N	\N	\N
129	60	visitor	Mgpapataas ako bakod sa likod ng bahay dahil wala pa syang bakod ko sa Savana, Brgy Soledad. Hndi sya gaano kataas. Kailangan po ba ng permit? Ano po requirements?	t	2026-06-08 07:09:50.122774+00	\N	\N	\N	\N
131	61	visitor	ano ang number ng mayor's office?	t	2026-06-11 02:43:37.665069+00	\N	\N	\N	\N
132	61	visitor	We would lke to check po sana kung paano makakapag pa-pencil booking sa San Pablo Convention Center para sa December.	t	2026-06-11 02:44:31.884596+00	\N	\N	\N	\N
141	66	visitor	San pwede i download and building permit application form	t	2026-06-16 05:26:40.491467+00	\N	\N	\N	\N
136	64	visitor	Saan po Pwede mag apply sa tourism sa San Pablo? Meron po bang email na Para maisend Ang resume?	t	2026-06-16 00:18:59.384597+00	\N	\N	\N	\N
137	64	visitor	May available pa po bang position for tourism?	t	2026-06-16 00:19:40.463375+00	\N	\N	\N	\N
138	65	visitor	Good day po,pwede ko po ayusin sa lcro San Pablo po wrong entry ng birth date ng Father ko? Sa Masbate siya pinanganak pero sa san pablo na po siya nakatira for almos 18 years po.	t	2026-06-16 04:01:03.248934+00	\N	\N	\N	\N
139	65	visitor	If pwede po,ano po ang need na requirements? At magkno po ang payment?	t	2026-06-16 04:04:43.199543+00	\N	\N	\N	\N
140	65	visitor	Ano din po need na requirements if ako po ung magaasikaso in behalf of my father,since senior na din po siya.	t	2026-06-16 04:05:35.111099+00	\N	\N	\N	\N
134	63	visitor	Health Card	t	2026-06-15 03:26:01.266105+00	\N	\N	\N	\N
135	63	visitor	Paano po kumuha ng health card	t	2026-06-15 03:26:24.73571+00	\N	\N	\N	\N
133	62	visitor	What is the contact number for City engineering office	t	2026-06-15 02:18:08.83629+00	\N	\N	\N	\N
158	70	visitor	Maaari bang humingi ng pdf form ng unified application for permit and license	t	2026-06-18 05:45:09.228965+00	\N	\N	\N	\N
154	68	visitor	Ano cellphone number ng capitol treasury office?	t	2026-06-17 09:43:17.388516+00	\N	\N	\N	\N
155	68	visitor	Follow up po	t	2026-06-17 09:47:48.529343+00	\N	\N	\N	\N
156	68	visitor	May pwede ba makontak sa treasury office ng san pablo capitol sa one stop shop may katanungan lamang kami patungkol sa aming business?	t	2026-06-17 09:48:30.667219+00	\N	\N	\N	\N
157	69	visitor	ano pong requirements sa pagkuha ng certificate of final electrical inspection from engineerings office?	t	2026-06-18 00:28:04.670647+00	\N	\N	\N	\N
152	67	visitor	Ano po ang mga requirements para sa building permit? Magpapagawa po kami ng gate, fence and balcony sa nextasia san pablo	t	2026-06-17 04:20:20.550476+00	\N	\N	\N	\N
153	67	visitor	Andito po kase ako sa indang cavite. Hindi ako makakapunta physically alaga ko po ang anak ko 1yr old. Breastfeeding po. Thankyou po	t	2026-06-17 04:21:05.703694+00	\N	\N	\N	\N
142	65	agent	This website Defaced by CrimsonSec Philippines please inform your developer stupid	f	2026-06-16 12:44:48.368085+00	\N	\N	\N	\N
143	66	agent	This website Defaced by CrimsonSec Philippines please inform your developer stupid	f	2026-06-16 12:45:00.293398+00	\N	\N	\N	\N
144	64	agent	This website Defaced by CrimsonSec Philippines please inform your developer stupid	f	2026-06-16 12:45:07.755408+00	\N	\N	\N	\N
145	63	agent	This website Defaced by CrimsonSec Philippines please inform your developer stupid	f	2026-06-16 12:45:13.728996+00	\N	\N	\N	\N
146	62	agent	This website Defaced by CrimsonSec Philippines please inform your developer stupid	f	2026-06-16 12:45:19.115035+00	\N	\N	\N	\N
147	61	agent	This website Defaced by CrimsonSec Philippines please inform your developer stupid	f	2026-06-16 12:45:23.566158+00	\N	\N	\N	\N
148	60	agent	This website Defaced by CrimsonSec Philippines please inform your developer stupid	f	2026-06-16 12:45:28.996239+00	\N	\N	\N	\N
149	59	agent	This website Defaced by CrimsonSec Philippines please inform your developer stupid	f	2026-06-16 12:45:42.59416+00	\N	\N	\N	\N
150	58	agent	This website Defaced by CrimsonSec Philippines please inform your developer stupid	f	2026-06-16 12:45:47.990967+00	\N	\N	\N	\N
151	57	agent	This website Defaced by CrimsonSec Philippines please inform your developer stupid	f	2026-06-16 12:45:53.718114+00	\N	\N	\N	\N
103	47	agent	Walang google map, utoy?	f	2026-06-01 01:59:17.429434+00	\N	\N	\N	\N
110	51	agent	di ko din alam.	f	2026-06-02 07:06:02.8301+00	\N	\N	\N	\N
130	56	agent	Di ko sure.	f	2026-06-09 03:07:57.419489+00	\N	\N	\N	\N
115	54	agent	tf	f	2026-06-04 05:09:06.278785+00	\N	\N	\N	\N
159	70	visitor	Downloadable sana	t	2026-06-18 05:45:43.083601+00	\N	\N	\N	\N
160	71	visitor	sino ang pinaka head ng city cenro ng san pablo?	t	2026-06-18 07:57:40.325278+00	\N	\N	\N	\N
162	73	visitor	may i ask for a complete email address and contact numbers for Mayors office and how to book a meeting	t	2026-06-19 08:59:40.867175+00	\N	\N	\N	\N
161	72	visitor	Hi Good Afternoon, yung father ko po kase hindi sya makakuha ng PSA kase wala syang recort. Need ko po ipaverify yung record ng father po. Para raw po maipasok sa record ng PSA yung details ng father ko. Ano po ang dapat kung gawin?	t	2026-06-18 09:59:22.610245+00	\N	\N	\N	\N
163	74	visitor	Magandang umaga po. Ako po si Jerry Baet Capistrano ng Brgy. VI-E (pero kasalukuyang naninirahan po sa Pulo, Cabuyao, Laguna). Ako po ay hihingi ng tulong dahil halos 5 taon na po na hindi naibabalik ng Joni and Susan Agroshop 'yung investment ko po sa kanila. Kahit po sana maibalik na lang po ang capital ng walang interest. Nawa po ay matulungan niyo po ako kung anong hakbang po ang maaring gawin po. Maraming salamat po.	f	2026-06-22 00:36:40.286014+00	\N	\N	\N	\N
164	75	visitor	may hiring po ba sa inyo ngayon?	f	2026-06-22 12:48:44.643561+00	\N	\N	\N	\N
165	75	visitor	for fresh graduate po sana na job if meron	f	2026-06-22 12:49:07.12256+00	\N	\N	\N	\N
166	76	visitor	Ano po ang requirements para sa fencing permit para sa bahay?	f	2026-06-22 18:18:25.985963+00	\N	\N	\N	\N
167	77	visitor	Please be informed that PDL NROMMEL SIERRA y MERCADO is scheduled for turnover for his mandatory psychological counseling and/or psychiatric treatment pursuant to the Judgment of the Court. In this regard, may we respectfully inquire whether your facility can accommodate the said PDL and provide guidance regarding the admission schedule, requirements, and procedures to be undertaken to facilitate his compliance with the court order. Your prompt response will be greatly appreciated to ensure proper coordination and implementation of the court's directive.	f	2026-06-24 01:30:10.965149+00	\N	\N	\N	\N
168	77	visitor	Any response and indorsement regarding this matter is highly appreciated, thank you	f	2026-06-24 01:32:01.052686+00	\N	\N	\N	\N
169	78	visitor	ano po ang mga araw at oras ng working hours ng cityhall BPLO?	f	2026-06-25 01:11:20.066963+00	\N	\N	\N	\N
170	79	visitor	Hello, nais ko po sana makipag-ugnayan sa alkalde para humingi ng venue sponsorship para sa preliminary competition ng Mr. Philippines National Pageant na pagmamay-ari ng Mr. Grand International. Kapalit nito ay ang endorsement of San Pablo City and other recommendations based sa magiging discussion naten. Ang target date for preliminary competition ay July 29-30 habang ang coronation night naman ay sa August 2. Looking forward to hearing favorable response po. Salamat!	f	2026-06-25 09:23:25.116766+00	\N	\N	\N	\N
171	80	visitor	saan po pwede mag pa compute ng amelyar for 2022 - 2026	f	2026-06-26 08:23:45.818634+00	\N	\N	\N	\N
172	81	visitor	Magkano ang land transfer if ownership	f	2026-06-28 03:12:44.381309+00	\N	\N	\N	\N
173	81	visitor	May libre bang land transfer if ownership?	f	2026-06-28 03:13:33.693585+00	\N	\N	\N	\N
174	82	visitor	Do you have any job openings at the city hall?	f	2026-06-29 02:43:06.187165+00	\N	\N	\N	\N
175	82	visitor	Im interested to apply	f	2026-06-29 02:43:22.842691+00	\N	\N	\N	\N
176	83	visitor	For OBO: Meron po bang difference sa pagkuha ng building or construction permit per Subdivision? Halimbawa, may kaibahan po ba sa requirements for Santevi, Sannera, or Savana? Lahat po ay Ovialand project sa San Pablo City. Salamat.	f	2026-06-29 06:12:51.127515+00	\N	\N	\N	\N
177	84	visitor	Good day po. Homeowner po ako ng Santevi (Ovialand) dito sa San Pablo City. May gusto lang po sana akong i-clarify regarding sa building permit requirements ng OBO. Noong 2024, nagpagawa po kami ng roofing, fencing, at house extension (may permit po ang house extension). Recently, naglabas po ang Ovialand ng memorandum stating na ang pagkuha ng building permit ay required, at pati mga existing renovations ay kailangan din daw magkaroon ng permit. This year po, nagparenovate ulit kami. Nakapag-submit na ng application at requirements ang contractor namin sa OBO para sa renovation, pero ang sabi po sa kanila ay hindi na kailangan ng panibagong building permit. Ang concern lang po namin ay iba naman ang sinasabi ng PMO ng Ovialand. Ayon po sa kanila, hindi raw applicable ang naging advice sa contractor namin dahil ang nakausap daw niyang PMO staff ay assigned sa ibang Ovialand subdivision, kahit pareho naman pong nasa San Pablo City. Gusto ko lang po sanang humingi ng clarification sa mga	f	2026-06-29 10:53:31.320327+00	\N	\N	\N	\N
178	84	visitor	Gusto ko lang po sanang humingi ng clarification sa mga sumusunod: 1. Pare-pareho po ba ang building permit requirements ng OBO para sa lahat ng subdivisions sa San Pablo City? 2. May pagkakataon po ba na magkaiba ang requirements depende sa subdivision? 3. Yung requirement po ba na binanggit ng Ovialand sa kanilang memorandum ay matagal na pong existing, o may bagong directive po ba ang OBO na inilabas nitong 2026? Humihingi lang po sana kami ng official clarification para mas maintindihan namin kung ano talaga ang applicable na requirements. Maraming salamat po sa inyong oras. Looking forward po sa inyong response.	f	2026-06-29 10:53:54.36975+00	\N	\N	\N	\N
179	85	visitor	Paano magbayad online ng traffic violation	f	2026-06-30 01:04:07.576683+00	\N	\N	\N	\N
300	142	visitor	CDRRMO DEPARTMENT HEAD	f	2026-07-30 04:34:40.121526+00	\N	\N	\N	\N
180	85	visitor	Paano magbayad online ng traffic violation	f	2026-06-30 01:08:29.858859+00	\N	\N	\N	\N
181	86	visitor	Paano mag request sa City Development and Planning Office ng Request Data Letter for Undergraduate Architectural Thesis?	f	2026-07-01 09:31:16.192704+00	\N	\N	\N	\N
182	87	visitor	Magandang gabi nais ko lamang magtanong kung sino ang City Engineer ngayon ng lgu san pablo para lamang ito sa reference ko na ilalagay sa application letter nagaapply kasi ako	f	2026-07-01 13:58:01.338803+00	\N	\N	\N	\N
183	88	visitor	Email ng HR office	f	2026-07-03 02:22:46.478339+00	\N	\N	\N	\N
184	89	visitor	Maari ko po bang malaman ang email address ng public market supervisor?	f	2026-07-03 03:48:35.85043+00	\N	\N	\N	\N
185	89	visitor	Iintayin ko ang tugon.	f	2026-07-03 03:49:00.401038+00	\N	\N	\N	\N
186	90	visitor	building permit requirements for savana ovialand	f	2026-07-04 01:56:24.829711+00	\N	\N	\N	\N
187	91	visitor	ano po number ng post office ng san pablo sa kapitolyo, salamat po	f	2026-07-06 01:23:48.318286+00	\N	\N	\N	\N
188	92	visitor	Ano ang telepono nyo sa. Obo	f	2026-07-06 04:19:33.608985+00	\N	\N	\N	\N
189	92	visitor	?	f	2026-07-06 04:19:55.590964+00	\N	\N	\N	\N
190	92	visitor	Wala ba kayong numero na pede tawagan?	f	2026-07-06 04:25:51.161777+00	\N	\N	\N	\N
191	93	visitor	What are the requirements for obtaining a municipal certificate of indigency as a requirement for scholarships?	f	2026-07-07 01:27:19.373786+00	\N	\N	\N	\N
192	93	visitor	will i receive the response for my question immediately?	f	2026-07-07 01:28:43.71559+00	\N	\N	\N	\N
193	94	visitor	ano po need for health card	f	2026-07-07 02:04:43.318118+00	\N	\N	\N	\N
194	94	visitor	for food industry	f	2026-07-07 02:04:57.095628+00	\N	\N	\N	\N
195	95	visitor	kailan may medical mission na libre bunot ng ngipin	f	2026-07-07 07:39:10.436092+00	\N	\N	\N	\N
196	96	visitor	Good day po open po ba ang Office of Senjor Citizens' Affairs niyo bukas Friday, July 10?	f	2026-07-09 01:08:24.494121+00	\N	\N	\N	\N
197	97	visitor	Good day po open po ba ang Office of Senior Citizens' Affairs niyo bukas Friday, July 10?	f	2026-07-09 01:12:13.186788+00	\N	\N	\N	\N
198	98	visitor	Anong numero para sa engineering office	f	2026-07-09 05:56:20.747059+00	\N	\N	\N	\N
199	98	visitor	Phone number of Engineering Office	f	2026-07-09 06:03:17.451632+00	\N	\N	\N	\N
200	99	visitor	Saan pede mag padala ng email letter for the mayor of san pablo	t	2026-07-09 07:19:52.308868+00	\N	\N	\N	\N
201	99	visitor	Kelan kopo malalaman ang email na pedeng pag padalahan	t	2026-07-09 07:21:36.630225+00	\N	\N	\N	\N
202	100	visitor	Maaari po bang mag walk-in sa municipal hall ng inyong probinsya partikular sa Mayor’s Office upang humingi ng gabay at mag submit ng permit na kailangan ko para sa research at thesis?	f	2026-07-10 04:38:47.891229+00	\N	\N	\N	\N
203	101	visitor	I would like to inquire about the process for updating or transferring a business permit from a sole proprietorship to a corporation. Our company has recently registered a new corporation, which will continue the operations previously conducted under the sole proprietorship. We would appreciate your guidance on the procedures to follow, as well as the documentary requirements needed to facilitate this transition.	f	2026-07-10 07:11:25.562951+00	\N	\N	\N	\N
204	102	visitor	Kelan po kaya ang deadline para sa scholarship sa San Pablo? Salamat po.	f	2026-07-11 05:40:22.175765+00	\N	\N	\N	\N
205	102	visitor	thank you po, hoping for your response	f	2026-07-11 05:52:48.692655+00	\N	\N	\N	\N
206	102	visitor	where na po kaya?	f	2026-07-11 08:01:47.228815+00	\N	\N	\N	\N
207	103	visitor	About sa scholar ng San Pablo	f	2026-07-11 23:20:13.273087+00	\N	\N	\N	\N
208	103	visitor	markceilorogelio2008@gmail.com diko malaman ang result ng finillupan ko nung july 11,2026	f	2026-07-11 23:20:54.92975+00	\N	\N	\N	\N
209	103	visitor	Sa Iskolar ng Laguna kung ano bang result ng application kung finillupan.	f	2026-07-11 23:21:47.847388+00	\N	\N	\N	\N
210	103	visitor	markceilorogelio2008@gmail.com diko malan resul kung nakapasa ba yung application kong finillupan nung july 11,2026.	f	2026-07-11 23:25:03.331356+00	\N	\N	\N	\N
211	103	visitor	"Magandang araw po. Maaari ko po bang malaman ang opisyal na email address o contact number ng Scholarship Office para sa scholarship application?"	f	2026-07-11 23:38:29.824938+00	\N	\N	\N	\N
212	104	visitor	Saan po pwedeng makita ang Government hiring	f	2026-07-12 19:10:27.438402+00	\N	\N	\N	\N
213	105	visitor	Ano Ang requirements sa pagkuha NG building permit	f	2026-07-13 00:33:13.400959+00	\N	\N	\N	\N
214	105	visitor	Magkano Ang pagkuha NG building permit	f	2026-07-13 00:33:35.87353+00	\N	\N	\N	\N
215	105	visitor	Puwed bang drawing lang ng sa labas NG bahay Ang I submit	f	2026-07-13 00:34:15.574043+00	\N	\N	\N	\N
216	105	visitor	Gaano katagal Ang pag approve ng building permit	f	2026-07-13 00:35:39.953689+00	\N	\N	\N	\N
217	105	visitor	Yan lang lahat Ang MGA tanong ko	f	2026-07-13 00:36:01.418361+00	\N	\N	\N	\N
218	105	visitor	That's all	f	2026-07-13 00:36:26.503904+00	\N	\N	\N	\N
219	105	visitor	Thats all	f	2026-07-13 00:36:37.80147+00	\N	\N	\N	\N
220	105	visitor	That's all my question	f	2026-07-13 00:36:48.723355+00	\N	\N	\N	\N
221	105	visitor	That's all my question	f	2026-07-13 00:36:56.270967+00	\N	\N	\N	\N
222	105	visitor	That's all my question	f	2026-07-13 00:37:05.492193+00	\N	\N	\N	\N
223	106	visitor	Hello Po ako Po ay ofw sa Japan sana naman Po pagbalik ko satin sa San Pablo City makapagtrabaho Po ako Dyan Kahit Anong trabaho Po sa ahensya ng Gobyerno ,	f	2026-07-13 08:47:44.272251+00	\N	\N	\N	\N
224	106	visitor	Maraming salamat Po Nakahinga na Ang San Pablo dahil kayo Po ay nakaupo Mahal Na Mayor Najie	f	2026-07-13 08:48:29.381889+00	\N	\N	\N	\N
225	107	visitor	SAN DIEGO History: - Origin of the Barangay - Historical Background - Early Settlement - Significant Events - Development	f	2026-07-13 12:18:24.215548+00	\N	\N	\N	\N
226	108	visitor	Is there any government assistance in terms of funding a research or thesis project?	f	2026-07-14 09:51:46.805359+00	\N	\N	\N	\N
227	108	visitor	Hello	f	2026-07-14 09:53:12.187335+00	\N	\N	\N	\N
228	109	visitor	Hi, gusto po sana namin magpakasal either thru mayor or civil court. Ako po ay filipina and fiance ko po ay buddhist from sri lanka. Possible po bah na maikasal either thru mayor or civil po? At ano po yung mga requirements?	f	2026-07-14 14:55:38.594108+00	\N	\N	\N	\N
230	111	visitor	Pano ako makakakuha ng vax certificate. Dahil walang lumalabas na vax cert ko sa Egov app.	f	2026-07-17 22:53:24.258743+00	\N	\N	\N	\N
231	112	visitor	Magandang gabe	f	2026-07-18 15:09:08.850672+00	\N	\N	\N	\N
232	112	visitor	Maari pbng magtanong kung meron nakaregister na mayors permit under AFE Realty Development?salamat po	f	2026-07-18 15:10:09.906623+00	\N	\N	\N	\N
233	112	visitor	Ito pb ay galing sa inyong munisipyo	f	2026-07-18 15:10:30.900403+00	\N	\N	\N	\N
234	112	visitor	Ang mayor’s permit po ay galing sa sole proprietor na c Luke Adam Cruz Paguia	f	2026-07-18 15:12:52.013923+00	\N	\N	\N	\N
235	113	visitor	What's are the requirements for working permit?	f	2026-07-20 02:43:11.711984+00	\N	\N	\N	\N
238	116	visitor	Marriage License Application Requirements	t	2026-07-21 15:06:33.363543+00	\N	\N	\N	\N
237	115	visitor	May vacant position for OJT Architectural drafting po ba ang Kapitolyo	t	2026-07-20 12:37:09.864936+00	\N	\N	\N	\N
236	114	visitor	paano iregister ang aming business permit dito sa website nyo?	t	2026-07-20 08:42:04.336115+00	\N	\N	\N	\N
229	110	visitor	open hours of san pablo mega capitol	t	2026-07-17 02:55:28.082765+00	\N	\N	\N	\N
301	142	visitor	CIO DEPARTMENT HEAD	f	2026-07-30 04:34:51.876375+00	\N	\N	\N	\N
302	142	visitor	CHO DEPARTMENT HEAD	f	2026-07-30 04:34:59.30851+00	\N	\N	\N	\N
241	118	visitor	Ano ang kabila ng kaliwa?	t	2026-07-22 03:45:36.061109+00	\N	\N	\N	\N
239	117	visitor	Where can I address the letter for the License to Operate List for Pharmacies in San Pablo City for an undergraduate thesis. And Census for the list of middle aged adults to elderly living in San PAblo City?	t	2026-07-21 17:22:12.797257+00	\N	\N	\N	\N
240	117	visitor	Where is the office for the LTO for Business Permits and PSA Office? Does it have Provincial or City Offices that can help in our inquiry?	t	2026-07-21 17:44:13.948319+00	\N	\N	\N	\N
242	119	visitor	hello	f	2026-07-22 07:08:11.556066+00	\N	\N	\N	\N
243	119	visitor		f	2026-07-22 07:08:18.182917+00	\N	https://yljsclzmrxuhejgcesiv.supabase.co/storage/v1/object/public/chat_attachments/images/119/gab_image_1784704094524.JPG	image/jpeg	27321
248	122	visitor	asdasdasdasda	t	2026-07-22 07:18:27.384364+00	\N	\N	\N	\N
249	122	visitor	asdasdasda	t	2026-07-22 07:18:31.159435+00	\N	\N	\N	\N
250	123	visitor	Hello	t	2026-07-22 07:23:02.490814+00	\N	\N	\N	\N
251	123	visitor	asdasdasd	t	2026-07-22 07:23:08.303273+00	\N	\N	\N	\N
252	123	visitor	asasdasd	t	2026-07-22 07:23:12.191789+00	\N	\N	\N	\N
253	123	visitor	testing lang	t	2026-07-22 07:23:39.958312+00	\N	https://yljsclzmrxuhejgcesiv.supabase.co/storage/v1/object/public/chat_attachments/files/123/gab_file_1784705016305.pdf	application/pdf	253541
254	123	visitor	testing ulit	t	2026-07-22 07:23:56.205176+00	\N	https://yljsclzmrxuhejgcesiv.supabase.co/storage/v1/object/public/chat_attachments/images/123/gab_image_1784705032695.JPG	image/jpeg	27321
255	123	visitor	isa pa	t	2026-07-22 07:24:04.475781+00	\N	https://yljsclzmrxuhejgcesiv.supabase.co/storage/v1/object/public/chat_attachments/images/123/gab_image_1784705040979.JPG	image/jpeg	27321
256	123	visitor	ito na	t	2026-07-22 07:27:43.987945+00	\N	https://yljsclzmrxuhejgcesiv.supabase.co/storage/v1/object/public/chat_attachments/images/123/gab_image_1784705260398.JPG	image/jpeg	27321
257	123	visitor	isa pa ngani	t	2026-07-22 07:29:41.817722+00	\N	https://yljsclzmrxuhejgcesiv.supabase.co/storage/v1/object/public/chat_attachments/images/123/gab_image_1784705378123.jpg	image/jpeg	246134
244	120	visitor	📷 Photo	t	2026-07-22 07:12:57.984507+00	\N	\N	\N	\N
245	120	visitor		t	2026-07-22 07:12:58.931991+00	\N	https://yljsclzmrxuhejgcesiv.supabase.co/storage/v1/object/public/chat_attachments/images/120/gab_image_1784704375343.JPG	image/jpeg	27321
246	121	visitor	asdada	t	2026-07-22 07:17:31.005462+00	\N	\N	\N	\N
247	121	visitor		t	2026-07-22 07:17:32.303064+00	\N	https://yljsclzmrxuhejgcesiv.supabase.co/storage/v1/object/public/chat_attachments/images/121/gab_image_1784704648599.JPG	image/jpeg	27321
260	125	visitor	Si ñlra amante p ay ayaw ireair ang aming service pc	t	2026-07-23 01:12:24.967936+00	\N	\N	\N	\N
262	125	visitor	Saan ang opisina ng maintenance	t	2026-07-23 01:13:49.794452+00	\N	\N	\N	\N
264	125	visitor	Ay 🤣	t	2026-07-23 01:14:24.760041+00	\N	\N	\N	\N
258	124	visitor	Tanong lng kung dto sa San bartolome ba ay nag umpisa na Ang pay out ng 2k sa mahihirap	t	2026-07-22 11:56:35.282409+00	\N	\N	\N	\N
259	124	visitor	Paano malalaman kung mkakasali ba ako	t	2026-07-22 11:57:27.079982+00	\N	\N	\N	\N
266	126	visitor	Hello	f	2026-07-23 02:56:56.698518+00	\N	\N	\N	\N
267	127	visitor	hello	f	2026-07-23 03:01:14.542797+00	\N	\N	\N	\N
268	128	visitor	Nagpa vaccine ako sa SM San pablo. Saan ako hihingi ng vax certificate?	f	2026-07-23 04:18:10.842354+00	\N	\N	\N	\N
269	128	visitor	Nagpa vaccine ako sa SM San pablo. Saan ako hihingi ng vax certificate?	f	2026-07-23 04:27:05.081742+00	\N	\N	\N	\N
261	125	agent	Ayun langs	f	2026-07-23 01:13:21.14261+00	\N	\N	\N	\N
263	125	agent	Di ko lang po sure.	f	2026-07-23 01:14:02.535763+00	\N	\N	\N	\N
265	125	agent	🤣 🤣 🤣	f	2026-07-23 01:14:42.140995+00	\N	\N	\N	\N
272	130	visitor	hello	t	2026-07-23 08:06:41.176948+00	\N	\N	\N	\N
270	129	visitor	Nagpa vaccine ako sa SM San pablo. Saan ako pwede pumunta para kumuha ng VAX CERTIFICATE?	t	2026-07-23 04:43:06.724814+00	\N	\N	\N	\N
271	129	visitor	Nagpa vaccine ako sa SM San pablo. Saan ako pwede pumunta para kumuha ng VAX CERTIFICATE?	t	2026-07-23 04:43:14.88945+00	\N	\N	\N	\N
276	132	visitor	Meron napo bang listahan ang brgy San Francisco D. i calihan. para sa Uplift program?	t	2026-07-23 11:58:10.255303+00	\N	\N	\N	\N
273	131	visitor	Sa uplift beneficiaries ng San Pablo kasali po ba Ang pangalan ko duon	t	2026-07-23 11:34:08.211783+00	\N	\N	\N	\N
274	131	visitor	My listahan po ba ito	t	2026-07-23 11:35:18.079742+00	\N	\N	\N	\N
275	131	visitor	Bkit Wala pang sagut	t	2026-07-23 11:36:30.234385+00	\N	\N	\N	\N
277	133	visitor	saan po ang flag ceremony sa lunes?	t	2026-07-24 05:38:01.42446+00	\N	\N	\N	\N
279	133	visitor	sino ang may sabi?	f	2026-07-24 05:39:32.991276+00	\N	\N	\N	\N
281	133	visitor	kasama po ba lahat ng tao sa san pablo?	f	2026-07-24 05:39:58.024171+00	\N	\N	\N	\N
283	133	visitor	:)	f	2026-07-24 05:40:22.090229+00	\N	\N	\N	\N
284	134	visitor	Saan nakikita ang master list ng mga kasali sa uplift	f	2026-07-24 06:00:53.252203+00	\N	\N	\N	\N
285	134	visitor	Hello po	f	2026-07-24 06:04:38.913922+00	\N	\N	\N	\N
286	135	visitor	Ordinance No. 2012-40 (revised revenue code of the City of San Pablo	f	2026-07-24 08:38:39.278293+00	\N	\N	\N	\N
287	135	visitor	Ordinance No. 2012-40 (revised revenue code of the City of San Pablo	f	2026-07-24 08:39:10.896522+00	\N	\N	\N	\N
288	135	visitor	Puede po makahingi ng public document Ordinance No. 2012-40 (revised revenue code of the City of San Pablo	f	2026-07-24 08:39:31.058857+00	\N	\N	\N	\N
289	135	visitor	still waiting po	f	2026-07-24 08:44:01.662341+00	\N	\N	\N	\N
290	136	visitor	Pano po mag bayad ng real property tax	f	2026-07-26 05:35:30.731761+00	\N	\N	\N	\N
291	136	visitor	On line payment po sana	f	2026-07-26 05:35:56.089513+00	\N	\N	\N	\N
292	136	visitor		f	2026-07-26 05:38:13.852223+00	\N	https://yljsclzmrxuhejgcesiv.supabase.co/storage/v1/object/public/chat_attachments/136/Modesto-Porcado-Jr_image_1785044293070.jpg	image/jpeg	250258
278	133	agent	Sa bundok po	f	2026-07-24 05:39:20.404157+00	\N	\N	\N	\N
280	133	agent	Sabi po ni maam tina	f	2026-07-24 05:39:34.926807+00	\N	\N	\N	\N
282	133	agent	Pwidi piro dipindi	f	2026-07-24 05:40:13.18566+00	\N	\N	\N	\N
293	137	visitor	CSWD Head officer in charge	f	2026-07-27 04:04:52.895253+00	\N	\N	\N	\N
294	138	visitor	What is the Seven Lakes Ecotourism Program?	f	2026-07-29 00:04:23.780407+00	\N	\N	\N	\N
295	139	visitor	sino ang baranggay chairman ng baranggay santo nino, san pablo city?	f	2026-07-29 01:51:39.212269+00	\N	\N	\N	\N
296	140	visitor	Planning for civil wedding. Ano ano po ang need na requirements or documents?	f	2026-07-29 08:59:23.555094+00	\N	\N	\N	\N
297	140	visitor	hope matulungan po sa mga questions. Thank you	f	2026-07-29 08:59:59.240901+00	\N	\N	\N	\N
298	141	visitor	bakit po antagal ng renewal sa munisipyo ng 28 papo ako nagpasa	f	2026-07-30 03:30:38.191296+00	\N	\N	\N	\N
299	141	visitor		f	2026-07-30 03:31:11.649434+00	\N	https://yljsclzmrxuhejgcesiv.supabase.co/storage/v1/object/public/chat_attachments/141/JM-Mendoza_image_1785382271149.jpg	image/jpeg	443307
303	142	visitor	Ito po ay for SDRRM Planning po	f	2026-07-30 04:35:09.881402+00	\N	\N	\N	\N
304	142	visitor	Salamat	f	2026-07-30 04:35:13.877244+00	\N	\N	\N	\N
305	143	visitor	Sino ang barangay captain ng san buenaventura?	f	2026-07-30 12:45:20.806051+00	\N	\N	\N	\N
306	144	visitor	Mayroon bang email address ang CPDO na maaari naming padalhan ng liham ng kahilingan sa paghingi ng Comprehensive Land Use Plan ng siyudad?	f	2026-07-31 01:30:14.740285+00	\N	\N	\N	\N
307	145	visitor	hello! Good morning! Tanong ko lang kung saan pwede magbayad ng amilyar online?	f	2026-08-01 03:00:58.314036+00	\N	\N	\N	\N
308	145	visitor	hello?	f	2026-08-01 03:04:11.229612+00	\N	\N	\N	\N
309	146	visitor	I would like to ask if this lot is a government owned lot? For thesis purpose only	f	2026-08-01 07:13:33.194717+00	\N	\N	\N	\N
310	146	visitor		f	2026-08-01 07:15:12.177541+00	\N	https://yljsclzmrxuhejgcesiv.supabase.co/storage/v1/object/public/chat_attachments/146/Sziene-Briol_image_1785568511659.jpeg	image/jpeg	93132
311	147	visitor	Good Afternoon po. Pede po makahingi ng Facebook Page, Contact Number or Email Address na pede pong macontact sa Office of Building Official ? Thank you po.	f	2026-08-01 07:35:44.878531+00	\N	\N	\N	\N
312	147	visitor	Mag tanung lang po ako about applying Building Permits for renovation of house (Lynville Subdinvision San Antonio 2)	f	2026-08-01 07:36:26.619122+00	\N	\N	\N	\N
313	148	visitor	Saan po pwedeng magtanong regarding sa document ng	f	2026-08-03 03:30:46.517116+00	\N	\N	\N	\N
314	148	visitor	Verify na annotation na court decree	f	2026-08-03 03:32:04.332305+00	\N	\N	\N	\N
315	148	visitor	Meron po ba kayo contact or email?	f	2026-08-03 03:33:01.895293+00	\N	\N	\N	\N
316	149	visitor	paano po yun contrata po namen isang buwan na po kameng walang sahod gawa ng papalit palit po ng administrasyon ano po kaya pwedeng gawin	f	2026-08-03 12:07:34.565374+00	\N	\N	\N	\N
317	150	visitor	Suspension in government work tomorrow	f	2026-08-03 12:48:22.062403+00	\N	\N	\N	\N
318	151	visitor	Contact number of Business Permit And Licensing Office	f	2026-08-04 02:20:16.77034+00	\N	\N	\N	\N
319	151	visitor	or e-mail address of San Pablo City, Laguna BPLO	f	2026-08-04 02:20:50.890394+00	\N	\N	\N	\N
320	152	visitor	sino po ang municipal engineer ng san pablo	f	2026-08-04 06:06:05.829655+00	\N	\N	\N	\N
321	153	visitor	Mag tatanong lang po ako about sa pag legitimate ng PSA	f	2026-08-04 06:32:21.760411+00	\N	\N	\N	\N
322	153	visitor	Kong ano po Ang requirements	f	2026-08-04 06:32:40.552227+00	\N	\N	\N	\N
323	153	visitor	Mag Kano po Ang babayaran?	f	2026-08-04 06:32:56.651492+00	\N	\N	\N	\N
324	153	visitor	At ilang raw po Ang process	f	2026-08-04 06:33:25.640449+00	\N	\N	\N	\N
325	153	visitor	How much process legitimate for PSA	f	2026-08-04 06:39:41.523009+00	\N	\N	\N	\N
326	153	visitor	Contact information office	f	2026-08-04 06:40:46.943324+00	\N	\N	\N	\N
327	154	visitor	Magandang araw po. Ako po si Jennifer Rubio, residente ng San Pablo City. Humihingi po sana ako ng agarang tulong medikal para sa aking anak na may Acute Lymphoblastic Leukemia (ALL). Ngayon po ay madi-discharge na kami mula sa ospital, ngunit dahil sa deklarasyon ng walang pasok sa mga tanggapan ng gobyerno ay hindi po kami nakapag-request ng guarantee letter. Kung maaari po sana, nais naming malaman kung may duty personnel o anumang paraan upang makapag-apply ng medical assistance o guarantee letter ngayong araw. Malaking tulong po ang anumang maibibigay ninyo. Maraming salamat po at pagpalain kayo ng Diyos.	f	2026-08-05 23:58:08.563995+00	\N	\N	\N	\N
328	155	visitor	Rtc open today?	f	2026-08-06 02:00:13.807586+00	\N	\N	\N	\N
329	156	visitor	Paano mag apply ng trabaho bilang parte ng cdrrmo ng sanpablo	f	2026-08-06 13:27:45.839267+00	\N	\N	\N	\N
330	157	visitor	Mayroom po bang programang dental para sa mga batang my bingot..	f	2026-08-07 18:21:03.994331+00	\N	\N	\N	\N
331	157	visitor	O mga dental clinic na nagbbigay ng sponsorship na pwedeng laiptan	f	2026-08-07 18:24:32.662314+00	\N	\N	\N	\N
332	158	visitor	What is mayor email address	f	2026-08-09 08:03:01.722045+00	\N	\N	\N	\N
333	159	visitor	I am formally requesting an investigation and inspection regarding the sale of suspected spoiled fish at the San Pablo City Public Market, and I am also requesting stronger monitoring of perishable food products to protect consumers.	f	2026-08-09 09:53:53.635169+00	\N	\N	\N	\N
334	160	visitor	I am writing to formally report an incident involving the sale of a suspected spoiled fish at the San Pablo City Public Market and to respectfully request an investigation and appropriate action. On August 9, 2026, my husband and I purchased a tambakol (tuna) from a vendor at the San Pablo City Public Market. Because of the bad weather and intermittent heavy rain, we were in a hurry and unfortunately were not able to properly inspect the fish before leaving the market. While we were already travelling home on our motorcycle, we noticed that the fish had an unusual smell. At first, we thought that the smell was simply part of the normal odor of fish. However, when we arrived home and I was about to wash and prepare it, the smell had become extremely foul. We also noticed that the fish's eyes were very red and that its overall condition appeared clearly unacceptable and potentially unsafe for consumption. I am currently pregnant, and this incident caused serious concern because I am taki	f	2026-08-10 00:15:27.517487+00	\N	\N	\N	\N
335	160	visitor	I am currently pregnant, and this incident caused serious concern because I am taking extra precautions regarding food safety during my pregnancy. We were particularly worried about what could have happened if we had consumed the fish without noticing its condition. Although we were already tired and had travelled home, my husband and I decided to return to the market because we wanted to inform the vendor and, more importantly, prevent the same product or other potentially unsafe food from being sold to another customer. When we returned to the market, I calmly asked the vendor where the person who sold and prepared the fish for us was. Instead of receiving a proper response, the conversation became confrontational and an argument occurred. The vendor eventually acknowledged that the person who sold the fish to us was her husband. I am submitting this complaint not merely because of the inconvenience or the money involved, but because I am genuinely concerned about the safety of other	f	2026-08-10 00:17:39.160585+00	\N	\N	\N	\N
336	160	visitor	Thank you for your time and attention. I sincerely hope that this matter will be investigated and that appropriate measures will be taken to protect consumers at the San Pablo City Public Market.	f	2026-08-10 00:19:12.377313+00	\N	\N	\N	\N
337	161	visitor	Good morning po. I would like to ask for assistance regarding my baby’s birth certificate and surname. My baby is 8 months old, and the father and I are not married. During the registration of my baby’s birth, I personally signed an Affidavit to Use the Surname of the Father (AUSF), so my baby is currently using the father’s surname. I would now like to know if there is a legal or administrative procedure to cancel, revoke, or reverse the AUSF so that my baby can use my surname instead. May I please ask what the requirements and procedure are for this request, and whether I need to personally visit the Civil Registry Office or file a petition/court case? Thank you po.	f	2026-08-10 01:58:21.419576+00	\N	\N	\N	\N
338	162	visitor	Bukas po ba ang munisipyo ngayon?	f	2026-08-10 05:10:33.403953+00	\N	\N	\N	\N
339	163	visitor	May hiring po ba para sa Registered Nurses?	f	2026-08-12 05:34:13.921875+00	\N	\N	\N	\N
340	164	visitor	Pangalan at contact information ng kapitan ng Sta Catalina at San Buenaventura. Maraming salamat po.	f	2026-08-12 21:48:22.005185+00	\N	\N	\N	\N
341	164	visitor	bakit error ang email address na: info@sanpablocity.gov.ph? Palagi nabalik ang message. unknown ang email address.	f	2026-08-12 21:51:24.797603+00	\N	\N	\N	\N
342	164	visitor	Hello	f	2026-08-12 23:36:42.927798+00	\N	\N	\N	\N
343	164	visitor	hi	f	2026-08-13 00:31:21.333664+00	\N	\N	\N	\N
344	165	visitor	Requirements for PESO Assistance on Job Mass Hiring	f	2026-08-13 01:42:58.657168+00	\N	\N	\N	\N
345	165	visitor	Requirements for PESO Assistance on Job Mass Hiring	f	2026-08-13 01:47:29.247522+00	\N	\N	\N	\N
346	166	visitor	Paano po ma check kung legitimate ang business and registered sa San Pablo	f	2026-08-13 04:11:25.52809+00	\N	\N	\N	\N
347	167	visitor	May pasok po ba ngayon sa BIR San Pablo?	f	2026-08-14 02:03:53.439478+00	\N	\N	\N	\N
348	168	visitor	Email address ng local civil registry	f	2026-08-14 14:53:15.259066+00	\N	\N	\N	\N
349	169	visitor	Contact number ngvlocal civil registry	f	2026-08-17 01:26:57.583691+00	\N	\N	\N	\N
350	169	visitor	Gusto kong malaman kung mayroong birth record ang aking lola sa inyong civil registry office.	f	2026-08-17 01:27:44.137801+00	\N	\N	\N	\N
351	170	visitor	Hingi po sa ako ng assistance to remove po ung mga nakaparak ng sirang sasakyan sa tadat at gilid ng bahay ko maari po ba mkahing ng mobile number ng pede mahiingan ng tulong pra sa brgy san Gregorio	f	2026-08-17 04:28:51.634866+00	\N	\N	\N	\N
352	171	visitor	May facebook page ba kayo	f	2026-08-17 11:10:53.599246+00	\N	\N	\N	\N
353	145	visitor	hello?	f	2026-08-19 04:56:49.868104+00	\N	\N	\N	\N
354	172	visitor	Maari ko bang malaman kung ilan ang current ALS learners sa san pablo? at mayroon ba kayong facility nito	f	2026-08-19 09:38:06.658282+00	\N	\N	\N	\N
355	173	visitor	Open po ba ang municipal court?	f	2026-08-19 21:55:51.891218+00	\N	\N	\N	\N
356	174	visitor	List of name in uplift program in san pablo city	f	2026-08-20 00:15:00.360801+00	\N	\N	\N	\N
357	175	visitor	Paano kumuha ng vaccine certificate	f	2026-08-20 06:24:23.111784+00	\N	\N	\N	\N
358	175	visitor	May bayad ba ang pag kuha nito? Magkano at saan? Meron po ako sa egov kaya lang 1 dose lang ang nandun kahit complete dose ako.	f	2026-08-20 06:26:19.742615+00	\N	\N	\N	\N
359	176	visitor	Ano pong hiring ngayon sa any government office at ano po ang mga kailangang i-submit?	f	2026-08-22 04:07:07.090539+00	\N	\N	\N	\N
360	177	visitor	renewal of solo parent id	f	2026-08-24 07:43:08.775667+00	\N	\N	\N	\N
361	178	visitor	magkano po bayad Ng traffic violation truck ban at obstruction	f	2026-08-25 01:12:36.881939+00	\N	\N	\N	\N
362	178	visitor	sobra naman 2 violation hindi man lng naawa	f	2026-08-25 01:17:30.875276+00	\N	https://yljsclzmrxuhejgcesiv.supabase.co/storage/v1/object/public/chat_attachments/178/Louie-Matute_image_1787620650132.jpg	image/jpeg	4406175
363	179	visitor	What is your contact number	f	2026-08-25 02:12:25.641653+00	\N	\N	\N	\N
364	179	visitor	Is phl post located in city hall? Do you have their contact number?	f	2026-08-25 02:12:53.460251+00	\N	\N	\N	\N
365	180	visitor	mayroon po kayo kontak sa office of the building officials?	f	2026-08-25 03:07:52.870181+00	\N	\N	\N	\N
366	180	visitor	mayroon po ba?	f	2026-08-25 03:12:52.249233+00	\N	\N	\N	\N
367	181	visitor	ano ang contact ng dswd san pablo city	f	2026-08-25 06:46:57.073507+00	\N	\N	\N	\N
368	182	visitor	san po pede mag inquire regarding sa stalls sa night market ?	f	2026-08-25 08:23:53.315776+00	\N	\N	\N	\N
369	183	visitor	where can i get help for medical financial assistance?	f	2026-08-26 13:46:58.803524+00	\N	\N	\N	\N
370	184	visitor	Hello po Goodmorning, we are 4th year Sanitary Engineering students na currently ay naghahanap po ng location / topic of our thesis. Would it be okay po if magpunta kami today sa inyong city hall?	f	2026-08-26 23:18:21.85547+00	\N	\N	\N	\N
371	185	visitor	Magandang araw po. Ako po ay nagtatanong tungkol sa delayed registration ng birth certificate ng isang student. Kasalukuyan po siyang nakatira sa San Pablo City, Laguna, ngunit ipinanganak po siya sa Macalelon, Quezon at doon dapat mairehistro ang kanyang birth. Maaari po bang malaman kung maaari siyang mag-apply o mag-file ng out-of-town delayed registration sa Local Civil Registrar ng San Pablo City, upang hindi na po kailangang bumiyahe agad sa Macalelon, Quezon? Maaari rin po bang malaman kung anu-ano ang mga requirements at proseso para rito? Maraming salamat po sa inyong tugon at tulong.	f	2026-08-27 05:26:05.478577+00	\N	\N	\N	\N
372	185	visitor	Sa totoo lamang po ay hirap pinansyal ang tinutukoy ko pong estudyante, kaya malaking tulong po sa kanya kung maaari po itong maproseso dito sa San Pablo.	f	2026-08-27 05:26:43.918757+00	\N	\N	\N	\N
373	186	visitor	Open today ang city hall?	f	2026-08-27 23:46:37.168452+00	\N	\N	\N	\N
374	187	visitor	May isang kaibigan po ako na pumanaw kailan dahil sa aksidente sa motorsiklo sa inyong lugar, at hindi daw po bakalabas ang katawan ng pumanaw dahil sa bill nito sa ospital , maaari po bang ilapit at isangguni sainyo ito ? maraming salamat po	f	2026-08-28 02:27:45.82244+00	\N	\N	\N	\N
375	188	visitor	meron po ba kayong official na Facebook page?	f	2026-08-28 13:32:21.247743+00	\N	\N	\N	\N
376	189	visitor	Magandang hapon po. Paano po mag-request ng city ordinances and resolutions patungkol sa pangangalaga ng Sampaloc Lake?	f	2026-08-30 07:37:29.25544+00	\N	\N	\N	\N
377	190	visitor	Magandang hapon po. Paano po mag-request ng city ordinances and resolutions patungkol sa pangangalaga ng Sampaloc Lake?	f	2026-08-31 14:58:51.559916+00	\N	\N	\N	\N
378	191	visitor	Pwede po mahinge copy ng Ordinance No. 345, Series of 2025, officially known as the "Expanded Solo Parents Welfare Act in the City of San Pablo,"	f	2026-09-01 03:20:03.953983+00	\N	\N	\N	\N
379	191	visitor	Noted thanks	f	2026-09-01 03:21:03.146571+00	\N	\N	\N	\N
380	192	visitor	Anobg oras ang sara ng office of assessor?	f	2026-09-01 06:13:47.793951+00	\N	\N	\N	\N
381	193	visitor	gusto ko lang malaman kung merong hiring ngayun sa munisipyo ng spc	f	2026-09-01 12:58:05.757761+00	\N	\N	\N	\N
382	194	visitor	Magandang hapon. maaari po bang makuha ang contact number na pwdeng tawagan sa City Treasurer's Office?	f	2026-09-02 05:20:43.38024+00	\N	\N	\N	\N
383	194	visitor	may kelangan lang po kaming itanong sa kanilang upisina. salamat po	f	2026-09-02 05:21:12.592902+00	\N	\N	\N	\N
384	195	visitor	May pasok po ang City hall ngaun ng San pablo city?	f	2026-09-03 21:10:36.955993+00	\N	\N	\N	\N
385	195	visitor	Tuloy po ba ang prebid ngaun araw?	f	2026-09-03 21:11:45.503851+00	\N	\N	\N	\N
386	195	visitor	Follow up po sa mga katanungan ko	f	2026-09-03 21:19:36.29455+00	\N	\N	\N	\N
387	195	visitor	Bac	f	2026-09-03 21:20:58.041701+00	\N	\N	\N	\N
388	195	visitor	May pasok po ba ngaun?	f	2026-09-03 21:21:22.785053+00	\N	\N	\N	\N
389	195	visitor	May pasok po ba ngaun ang City hall ng San Pablo?	f	2026-09-03 21:26:26.350471+00	\N	\N	\N	\N
390	196	visitor	May pasok po kayo ngaun?	f	2026-09-03 21:32:10.582949+00	\N	\N	\N	\N
391	197	visitor	I need another copy of a certification of business closure. The previous one that I have says that it's for BIR use only. I need a copy that says for SSS, Pagibig and Philhealth use. Will you please help?	f	2026-09-04 06:52:05.735887+00	\N	\N	\N	\N
392	197	visitor		f	2026-09-04 06:52:06.925308+00	\N	https://yljsclzmrxuhejgcesiv.supabase.co/storage/v1/object/public/chat_attachments/197/Janella-Dela-Cruz_file_1788504726308.pdf	application/pdf	473950
393	198	visitor	Saan at paano mag bayad ng Amilyar	f	2026-09-06 00:14:54.081175+00	\N	\N	\N	\N
394	198	visitor	Saan at paano mag bayad ng Amilyar sa san pablo laguna	f	2026-09-06 00:15:54.446164+00	\N	\N	\N	\N
395	199	visitor	CAN I REQUEST A COPY OF BUILDING PERMIT FORMS?	f	2026-09-06 06:42:19.421978+00	\N	\N	\N	\N
396	200	visitor	Hello	f	2026-09-07 00:21:27.349829+00	\N	\N	\N	\N
397	201	visitor	anong mga job vacancies ang available sa lgu? nag hihire ba sila ng fresh graduate na magna cum laude?	f	2026-09-07 10:38:11.529968+00	\N	\N	\N	\N
398	202	visitor	how to access computation of real property tax	f	2026-09-08 01:33:53.225358+00	\N	\N	\N	\N
399	202	visitor	Is it possible to pay the tax through online?	f	2026-09-08 01:34:19.712005+00	\N	\N	\N	\N
400	203	visitor	Magtatanong lang po kung may available pa po na pwesto sa night market	f	2026-09-08 01:45:45.234359+00	\N	\N	\N	\N
401	204	visitor	San po. Ped3 mkuha copy ng business pedmit	f	2026-09-08 01:53:01.965951+00	\N	\N	\N	\N
402	205	visitor	Paano po mkuha copy ng business permit	f	2026-09-08 02:08:37.214161+00	\N	\N	\N	\N
403	205	visitor	Wala PA. Po b reply	f	2026-09-08 02:16:44.388417+00	\N	\N	\N	\N
404	206	visitor	Mag bayad po ako ng real property tax pano po at saan pwede	f	2026-09-08 04:06:01.976843+00	\N	\N	\N	\N
405	206	visitor	Good afternoon po	f	2026-09-08 04:08:19.262665+00	\N	\N	\N	\N
406	207	visitor	For PTR processing, if a representative will process on behalf of the Soliciting Official, what original documents and IDs are required?	f	2026-09-09 00:35:03.674245+00	\N	\N	\N	\N
407	207	visitor	hello po	f	2026-09-09 00:43:46.281203+00	\N	\N	\N	\N
408	207	visitor	For PTR processing, if a representative will process on behalf of the Soliciting Official, what original documents and IDs are required?	f	2026-09-09 00:50:19.055126+00	\N	\N	\N	\N
409	207	visitor	For PTR processing, if a representative will process on behalf of the Soliciting Official, what original documents and IDs are required?	f	2026-09-09 00:59:10.778446+00	\N	\N	\N	\N
410	207	visitor	For PTR processing, if a representative will process on behalf of the Soliciting Official, what original documents and IDs are required?	f	2026-09-09 00:59:12.336055+00	\N	\N	\N	\N
411	207	visitor	For PTR processing, if a representative will process on behalf of the Soliciting Official, what original documents and IDs are required?	f	2026-09-09 00:59:15.160841+00	\N	\N	\N	\N
412	207	visitor	For PTR processing, if a representative will process on behalf of the Soliciting Official, what original documents and IDs are required?	f	2026-09-09 00:59:18.127073+00	\N	\N	\N	\N
413	207	visitor	For PTR processing, if a representative will process on behalf of the Soliciting Official, what original documents and IDs are required?	f	2026-09-09 00:59:21.598249+00	\N	\N	\N	\N
414	207	visitor	For PTR processing, if a representative will process on behalf of the Soliciting Official, what original documents and IDs are required?	f	2026-09-09 00:59:23.92265+00	\N	\N	\N	\N
415	207	visitor	For PTR processing, if a representative will process on behalf of the Soliciting Official, what original documents and IDs are required?	f	2026-09-09 00:59:26.973175+00	\N	\N	\N	\N
416	207	visitor	For PTR processing, if a representative will process on behalf of the Soliciting Official, what original documents and IDs are required?	f	2026-09-09 00:59:29.445378+00	\N	\N	\N	\N
417	207	visitor	For PTR processing, if a representative will process on behalf of the Soliciting Official, what original documents and IDs are required?	f	2026-09-09 00:59:32.850179+00	\N	\N	\N	\N
418	207	visitor	For PTR processing, if a representative will process on behalf of the Soliciting Official, what original documents and IDs are required?	f	2026-09-09 00:59:35.925951+00	\N	\N	\N	\N
419	207	visitor	For PTR processing, if a representative will process on behalf of the Soliciting Official, what original documents and IDs are required?	f	2026-09-09 00:59:38.275576+00	\N	\N	\N	\N
420	207	visitor	For PTR processing, if a representative will process on behalf of the Soliciting Official, what original documents and IDs are required?	f	2026-09-09 00:59:41.369628+00	\N	\N	\N	\N
421	207	visitor	For PTR processing, if a representative will process on behalf of the Soliciting Official, what original documents and IDs are required?	f	2026-09-09 00:59:43.779803+00	\N	\N	\N	\N
422	207	visitor	For PTR processing, if a representative will process on behalf of the Soliciting Official, what original documents and IDs are required?	f	2026-09-09 00:59:47.624727+00	\N	\N	\N	\N
423	207	visitor	For PTR processing, if a representative will process on behalf of the Soliciting Official, what original documents and IDs are required?	f	2026-09-09 00:59:50.347948+00	\N	\N	\N	\N
424	207	visitor	For PTR processing, if a representative will process on behalf of the Soliciting Official, what original documents and IDs are required?	f	2026-09-09 00:59:53.143981+00	\N	\N	\N	\N
425	207	visitor	For PTR processing, if a representative will process on behalf of the Soliciting Official, what original documents and IDs are required?	f	2026-09-09 00:59:55.777063+00	\N	\N	\N	\N
426	207	visitor	For PTR processing, if a representative will process on behalf of the Soliciting Official, what original documents and IDs are required?	f	2026-09-09 00:59:59.490766+00	\N	\N	\N	\N
427	207	visitor	For PTR processing, if a representative will process on behalf of the Soliciting Official, what original documents and IDs are required?	f	2026-09-09 01:00:01.529498+00	\N	\N	\N	\N
428	207	visitor	For PTR processing, if a representative will process on behalf of the Soliciting Official, what original documents and IDs are required?	f	2026-09-09 01:00:04.865289+00	\N	\N	\N	\N
429	207	visitor	For PTR processing, if a representative will process on behalf of the Soliciting Official, what original documents and IDs are required?	f	2026-09-09 01:00:09.32471+00	\N	\N	\N	\N
430	208	visitor	Magandang Umaga! Ako po ay isang undergraduate from Cavite na nagbabalak po na mag conduct ng study sa mga mangingisda ng Sampaloc Lake. Sino po kaya ang pwedeng ma-contact para dito?	f	2026-09-09 01:48:12.829755+00	\N	\N	\N	\N
431	208	visitor	Ang mga mangingisda po ba sa San Pablo ay may mga organisasyon na sinasalihan? maaari ko po bang malaman ang organisasyon (if NGO or not)	f	2026-09-09 01:52:36.776463+00	\N	\N	\N	\N
\.


--
-- Data for Name: conversations; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.conversations (id, created_at, full_name, email, phone, subject, message, source_node, status, ip_address, closed_at, assigned_to, visitor_token) FROM stdin;
71	2026-06-18 07:57:40.199081+00	Maricar	avc.mspasco@gmail.com	09451482997	Iba Pa	sino ang pinaka head ng city cenro ng san pablo?	iba-pa	open	168.140.246.129	\N	\N	dfb006dff94f7bbbe7f98795cefa978068fe0e7c88652b5f52939a616714478e
73	2026-06-19 08:59:40.701013+00	Leia Veronica Felix Bandin	leiacookie13@gmail.com	09614746268	Iba Pa	may i ask for a complete email address and contact numbers for Mayors office and how to book a meeting	iba-pa	open	136.158.103.254	\N	\N	379c508cead94016bbcb3304442fae27bb62fcddabf29f2211d7dc0d6bfc1a29
75	2026-06-22 12:48:44.471402+00	Mia Joylyn Luciano	lucianomia48@gmail.com	09817093042	Iba Pa	may hiring po ba sa inyo ngayon?	iba-pa	open	175.176.52.125	\N	\N	0aade32a1e1d20832ec392fa5d5b29653b3e43dfd1db3f4cc568bdb9ef619b4e
77	2026-06-24 01:30:10.846734+00	Separation Section	dppfseparationsection@gmail.com	09776627361	Iba Pa	Please be informed that PDL NROMMEL SIERRA y MERCADO is scheduled for turnover for his mandatory psychological counseling and/or psychiatric treatment pursuant to the Judgment of the Court. In this regard, may we respectfully inquire whether your facility can accommodate the said PDL and provide guidance regarding the admission schedule, requirements, and procedures to be undertaken to facilitate his compliance with the court order. Your prompt response will be greatly appreciated to ensure proper coordination and implementation of the court's directive.	iba-pa	open	103.173.110.158	\N	\N	0d19c719a63a853b2c1ea7a4702fc747d24f61d9c3a04ca305fd48bc0629910d
79	2026-06-25 09:23:24.810867+00	Julius Mercado	juliuspmercado@yahoo.com	09177060707	Iba Pa	Hello, nais ko po sana makipag-ugnayan sa alkalde para humingi ng venue sponsorship para sa preliminary competition ng Mr. Philippines National Pageant na pagmamay-ari ng Mr. Grand International. Kapalit nito ay ang endorsement of San Pablo City and other recommendations based sa magiging discussion naten. Ang target date for preliminary competition ay July 29-30 habang ang coronation night naman ay sa August 2. Looking forward to hearing favorable response po. Salamat!	iba-pa	open	136.158.58.31	\N	\N	37dcd9d6add746e81456c323c9b630b9d05a416b2500a5986a337ea5b583ff97
81	2026-06-28 03:12:44.216749+00	Joseph robles	josephdevera87@gmail.com	09952688708	Iba Pa	Magkano ang land transfer if ownership	iba-pa	open	49.147.93.26	\N	\N	93517c5214698cfff0831038d59e8c511aec44f69129630e2ddcfdd877f3be06
83	2026-06-29 06:12:50.964726+00	Melissa Joy Baltar-Mayo	melissabaltar@gmail.com	09276029013	Iba Pa	For OBO: Meron po bang difference sa pagkuha ng building or construction permit per Subdivision? Halimbawa, may kaibahan po ba sa requirements for Santevi, Sannera, or Savana? Lahat po ay Ovialand project sa San Pablo City. Salamat.	iba-pa	open	49.145.7.242	\N	\N	f0351917467dce15f2275202c7be44808fb19f9c22cb7c020020e7f61d77e157
85	2026-06-30 01:04:07.424019+00	Devs Original	devsoriginal@gmail.com	09458321341	Iba Pa	Paano magbayad online ng traffic violation	iba-pa	open	131.226.106.70	\N	\N	0ce75d765606d000ddec3085f16a9b45e1461219b1764b8fb2aa29067a5d7153
87	2026-07-01 13:58:01.161423+00	Erico Miguel V. Secillano	miguel.secillano@gmail.com	09083665090	Iba Pa	Magandang gabi nais ko lamang magtanong kung sino ang City Engineer ngayon ng lgu san pablo para lamang ito sa reference ko na ilalagay sa application letter nagaapply kasi ako	iba-pa	open	112.202.115.134	\N	\N	9aabb07d055fffa4b31b5d1e3571020d8c6c5442a6a19ae5cfb86a59cb9e27fc
89	2026-07-03 03:48:35.541576+00	Pham	phamcabanban@gmail.com	09682040488	Iba Pa	Maari ko po bang malaman ang email address ng public market supervisor?	iba-pa	open	111.90.239.226	\N	\N	ae6809d6d73daeb012866031b791ad3cad8ddefeb35aef67487d66332ac734f5
48	2026-05-29 06:17:07.43693+00	Leia Veronica Felix Bandin	leiacookie13@gmail.com	09614746268	Iba Pa	may i ask for any contact number from the mayors office	iba-pa	open	136.158.103.134	\N	\N	cd803d1e321e062d8617a2739e2d2a019357f5805db7b3b2fdc69d54971be038
49	2026-06-01 23:14:11.453532+00	Divina Gracia Glorioso Montague	anivid0809@icloud.com	09175900809	Iba Pa	would like to inquire if na update na po ung corrected birth certificate ng Nanay ko. It's been more than a year na po.	iba-pa	open	73.70.167.23	\N	\N	dc0bba5f599aecc42a92c39d15839323bed94928964ec40c2b4ef5e3c482b52c
50	2026-06-02 01:45:44.238272+00	miel tan	khyletan25@gmail.com	09613598540	Iba Pa	numero ng kagawaran ng katarungan	iba-pa	open	111.90.221.83	\N	\N	0917995895737b8c749b087583f67e4b39e7a9b3e3f8f6b0a3a9bd434ae4a6da
52	2026-06-03 15:12:52.864894+00	Abigail Taningco	abigailtaningco@yhoo.com	09173191298	Iba Pa	San po pde humingi ng form para sa PWD?	iba-pa	open	136.158.66.205	\N	\N	068bed644b338552e2755e09c915ce2dc8d1c1dc341c3a22985e26905b66b3e1
53	2026-06-04 01:46:53.508625+00	Sarah Pontanoza	castillosarah029@gmail.com	09565996269	Iba Pa	What are the requirements for applying PWD ID? and what is the contact number of PDAO?	iba-pa	open	168.149.181.8	\N	\N	b952d2a9344341f7b766d5407dc9cb704cf148d18dcf55e01bc8be646f747813
55	2026-06-04 05:12:00.235469+00	Ningning	ning@ning.com	09464543484	Iba Pa	Yow	iba-pa	open	160.20.41.58	\N	\N	36d087e15dca7a2b2bc8b6213cffcf09cad9d4e7cef714e9e508aab4a455ac60
67	2026-06-17 04:20:20.261061+00	Dherlyn Cate Villanueva	villanuevadherlyn@gmail.com	09307493829	Iba Pa	Ano po ang mga requirements para sa building permit? Magpapagawa po kami ng gate, fence and balcony sa nextasia san pablo	iba-pa	open	112.202.119.86	\N	\N	29d0dc0998f7487d7e24a4223568875e4c66db0d9964ed1bf1b6d2a8d05f1fda
68	2026-06-17 09:43:17.111759+00	Jaz	juanmiguel03@gmail.com	09926182580	Iba Pa	Ano cellphone number ng capitol treasury office?	iba-pa	open	131.226.107.20	\N	\N	7d1b2e0d3964ae2e933016c6b83413130249dce6c03f59925e7504516997bdcc
69	2026-06-18 00:28:04.517545+00	MICHELLE HERNANDEZ	misyela01@gmail.com	09685001935	Iba Pa	ano pong requirements sa pagkuha ng certificate of final electrical inspection from engineerings office?	iba-pa	open	223.25.28.165	\N	\N	69ac6664d942a6c2c6d0d45d06de96f4765eafdf414677305e19c36c895d3ff3
70	2026-06-18 05:45:09.104372+00	Rose Ann Llanes	rosyllanes4@gmail.com	09549931915	Iba Pa	Maaari bang humingi ng pdf form ng unified application for permit and license	iba-pa	open	216.247.80.18	\N	\N	be8380b93f2bf0b47bcdba279468c1c11f42d6bd4ba3f40614e4000ba537a762
65	2026-06-16 04:01:03.054652+00	Sharmie Barte Miranda	eimrahs2599@yahoo.com	09196662165	Iba Pa	Good day po,pwede ko po ayusin sa lcro San Pablo po wrong entry ng birth date ng Father ko? Sa Masbate siya pinanganak pero sa san pablo na po siya nakatira for almos 18 years po.	iba-pa	assigned	49.144.168.201	\N	\N	028d729a1bf585036223aa769994b641d3667b824f3b45adf2b74e26700e9db3
66	2026-06-16 05:26:40.351752+00	Hiyasmin Caravana	hi_nimsay@yahoo.com	09124131490	Iba Pa	San pwede i download and building permit application form	iba-pa	assigned	49.147.86.50	\N	\N	c09b2e39015e707c662f5cf6c2234d9b46ee9cbec0449353e57ff302c4eac258
64	2026-06-16 00:18:59.234714+00	Katherine gutierrez	kattygutierrez51@gmail.com	09162625484	Iba Pa	Saan po Pwede mag apply sa tourism sa San Pablo? Meron po bang email na Para maisend Ang resume?	iba-pa	assigned	160.20.41.241	\N	\N	c7f7e2ca1e7f898e6439187fb3b65834db22c86e02f6db7dd59f6a97a7fe0d32
63	2026-06-15 03:26:01.116526+00	Carl adrian m. Bagsic	carladrianbagsic@gmail.com	09167486811	Iba Pa	Health Card	iba-pa	assigned	136.158.65.213	\N	\N	23fd34773a3fde19572d2a148361f33d399f091cc4f8d8e95ed264933917037d
62	2026-06-15 02:18:08.504008+00	Kevin bejasa	kevinbejasa046@gmail.com	09399172291	Iba Pa	What is the contact number for City engineering office	iba-pa	assigned	180.191.73.24	\N	\N	3674f8c01217a0c78a7418079ef2603b0c3ff782a552eb55f017fd1a0c74269f
61	2026-06-11 02:43:37.243529+00	Dericka Lourdes Bienes	deckestefani@gmail.com	09603898356	Iba Pa	ano ang number ng mayor's office?	iba-pa	assigned	158.62.0.84	\N	\N	345d23c3756562126225c9ce97fe5731537c7d6a33fd7269f09ed37e50c9af63
60	2026-06-08 07:09:49.977583+00	CHRIS FAITH V TAGLE	cfaithtagle@gmail.com	09456621362	Iba Pa	Mgpapataas ako bakod sa likod ng bahay dahil wala pa syang bakod ko sa Savana, Brgy Soledad. Hndi sya gaano kataas. Kailangan po ba ng permit? Ano po requirements?	iba-pa	assigned	112.198.70.124	\N	\N	289fbf5addf1f992276b25c018121894abc8c594968061b9c1854d0aa8776229
59	2026-06-05 05:17:47.87765+00	Saudino del Mundo	saudinodelmundo@gmail.com	09188142613	Iba Pa	Bakit wala sa listahan ng pwd ang anak ko sa Barangay Bagong Bayan	iba-pa	assigned	49.144.195.24	\N	\N	8473a549814ff0c0e8315359cfc7f0d3789f347fe6d6630f993390aa6c3aa2c1
58	2026-06-05 01:24:25.616123+00	Matuto, Maricel	maricelmatuto@lspu.edu.ph	09463424868	Iba Pa	who is the planning and development officer?	iba-pa	assigned	175.176.53.35	\N	\N	7440f942ebe4c43104704e55ae1ebd729171e58bc1385a9a81d47bf5aa5ce78b
57	2026-06-04 14:56:16.356705+00	Marisa Achevarra	marisaachevarra@gmail.com	09452793917	Iba Pa	Paano po magbayad ng amilyar online?	iba-pa	assigned	119.56.75.243	\N	\N	04061acf65929783b17ef6d7979b687bf8f9a8d900863f1ea55d3d79e5ebb9c9
47	2026-05-29 03:01:03.253266+00	Gab Gonzales	gab@gmail.com	09946784648	Iba Pa	Saan ang papuntang Mega?	iba-pa	assigned	110.54.191.78	\N	\N	d40cc289438c8c19019dbf0a29a47deff86d8189b4d2fd42cc9f6e675aedd9e2
51	2026-06-02 06:19:51.6428+00	Trisha Samillano	samillanotrisha768@gmail.com	09627962460	Iba Pa	Paano makakuha ng Postal ID?	iba-pa	assigned	160.20.41.11	\N	\N	da617a5e3286ce1b06f9198d44ff36661e1e368a7197da34e84adce76c0aa433
54	2026-06-04 05:08:24.366171+00	Ningning	ning@ning.com	09464543484	Iba Pa	When is the birthrate of the calamity?	iba-pa	assigned	160.20.41.58	\N	\N	2097260a182c7ed7eb4118546541a0bee8e089804d9cbd971e1c50a64f3840bb
56	2026-06-04 08:07:17.695961+00	Mang Juan	gokejo8179@5nek.com	09999999999	Iba Pa	Bakit asul ang kulay ng langit?	iba-pa	assigned	160.20.41.58	\N	\N	63eeae940e2706ec2011db25d75ea6448e77b90cb5799b90e297592ffba2382d
72	2026-06-18 09:59:22.440307+00	Nelly Ann Belen	nellyannsosfam@gmail.com	09129636628	Iba Pa	Hi Good Afternoon, yung father ko po kase hindi sya makakuha ng PSA kase wala syang recort. Need ko po ipaverify yung record ng father po. Para raw po maipasok sa record ng PSA yung details ng father ko. Ano po ang dapat kung gawin?	iba-pa	open	39.9.107.67	\N	\N	8946fe8ec1485f6e5159ab513aa5b30dd89a6c9e063e74101c9314a1b13ed488
74	2026-06-22 00:36:40.087201+00	Jerry Baet Capistrano	engr.capistranojb@gmail.com	09178496171	Iba Pa	Magandang umaga po. Ako po si Jerry Baet Capistrano ng Brgy. VI-E (pero kasalukuyang naninirahan po sa Pulo, Cabuyao, Laguna). Ako po ay hihingi ng tulong dahil halos 5 taon na po na hindi naibabalik ng Joni and Susan Agroshop 'yung investment ko po sa kanila. Kahit po sana maibalik na lang po ang capital ng walang interest. Nawa po ay matulungan niyo po ako kung anong hakbang po ang maaring gawin po. Maraming salamat po.	iba-pa	open	165.225.230.121	\N	\N	58220eb34ddfa097e410cd496761e51729b343bdca98f6a69a7e780d9a6d03d3
76	2026-06-22 18:18:25.678364+00	Gj Maraveee	gjmarave12345@gmail.com	09171601017	Iba Pa	Ano po ang requirements para sa fencing permit para sa bahay?	iba-pa	open	150.228.15.157	\N	\N	3c4601f17a72310f96cb70c9792bef774a8d85688b2b5b146d595599e5d8ee26
78	2026-06-25 01:11:19.929678+00	Philip Nama	philip.nama@etapinc.com	09625015626	Iba Pa	ano po ang mga araw at oras ng working hours ng cityhall BPLO?	iba-pa	open	175.176.48.16	\N	\N	dd685d5812d818f71eda675194005eb3ca13fe20774adc42ceeb2ee17d134598
80	2026-06-26 08:23:45.420668+00	Laroya, Venus Mae	venuslaroya3@gmail.com	09670395184	Iba Pa	saan po pwede mag pa compute ng amelyar for 2022 - 2026	iba-pa	open	112.209.79.87	\N	\N	7dcdbf61dafa0a697bf31fa5f1b606e5e26516f7784348a545fbf866a1a9a139
82	2026-06-29 02:43:06.00052+00	Benneth Tanya	bennethtanya@gmail.com	09275274418	Iba Pa	Do you have any job openings at the city hall?	iba-pa	open	112.198.104.162	\N	\N	30d0957a8735b72087a289245733c35056e38958df61c4d98bca5470ad942f6f
84	2026-06-29 10:53:31.002755+00	Melissa Joy Baltar-Mayo	melissabaltar@gmail.com	09276029013	Iba Pa	Good day po. Homeowner po ako ng Santevi (Ovialand) dito sa San Pablo City. May gusto lang po sana akong i-clarify regarding sa building permit requirements ng OBO. Noong 2024, nagpagawa po kami ng roofing, fencing, at house extension (may permit po ang house extension). Recently, naglabas po ang Ovialand ng memorandum stating na ang pagkuha ng building permit ay required, at pati mga existing renovations ay kailangan din daw magkaroon ng permit. This year po, nagparenovate ulit kami. Nakapag-submit na ng application at requirements ang contractor namin sa OBO para sa renovation, pero ang sabi po sa kanila ay hindi na kailangan ng panibagong building permit. Ang concern lang po namin ay iba naman ang sinasabi ng PMO ng Ovialand. Ayon po sa kanila, hindi raw applicable ang naging advice sa contractor namin dahil ang nakausap daw niyang PMO staff ay assigned sa ibang Ovialand subdivision, kahit pareho naman pong nasa San Pablo City. Gusto ko lang po sanang humingi ng clarification sa mga	iba-pa	open	49.145.7.242	\N	\N	5c495468a3880f64c500929f4d92dd0965dfadc78c6737e7793086e9c101258e
86	2026-07-01 09:31:15.987737+00	Kevindave S. Cuizon	kevindave073@gmail.com	09454468327	Iba Pa	Paano mag request sa City Development and Planning Office ng Request Data Letter for Undergraduate Architectural Thesis?	iba-pa	open	203.189.118.94	\N	\N	61059537d791d9ea698d7e8140f6ea572f3a0819ea9ce2a0991abd9cf7cd25bc
88	2026-07-03 02:22:46.34695+00	Mariole Reyes	reyesmariole16@gmail.com	09454624406	Iba Pa	Email ng HR office	iba-pa	open	136.158.64.114	\N	\N	fb4efbd04dfd1928233d0a0a3151c43aa6cfbeb6823d1392397dc0614cdf5c20
90	2026-07-04 01:56:24.652985+00	Jan Marvin Miranda	altheamiranda01@yahoo.com	09054169464	Iba Pa	building permit requirements for savana ovialand	iba-pa	open	49.144.212.241	\N	\N	9d202ee0dc5763035c79ccca9b5482a7e4548e82a4e9498395fd1b18b025960e
91	2026-07-06 01:23:48.159337+00	Edwin Andres Dela Cruz	edwin.andres.delacruz1974@gmail.com	09703376889	Iba Pa	ano po number ng post office ng san pablo sa kapitolyo, salamat po	iba-pa	open	49.144.174.123	\N	\N	f6b52c434b8d8eadfd8269371a55ba4f863f3982614176396fcd534f63bbe180
92	2026-07-06 04:19:33.47131+00	John neil	valderamajohnneil@gmail.com	09352671092	Iba Pa	Ano ang telepono nyo sa. Obo	iba-pa	open	86.98.191.146	\N	\N	61ef961eaafbbd4f16e423e804efd4c7d4f3f42c03daab1da6e9fce19fa51b06
93	2026-07-07 01:27:19.211748+00	Azel Mae M. Romblon	azelromblon@gmail.com	09694919035	Iba Pa	What are the requirements for obtaining a municipal certificate of indigency as a requirement for scholarships?	iba-pa	open	49.144.194.236	\N	\N	f9e89dbb08b09b82c31bf0c84c06da182c20d52d595dcb20f8ed76f826552432
94	2026-07-07 02:04:43.012807+00	Josephine Morante	jsphnmorante@gmail.com	09457088640	Iba Pa	ano po need for health card	iba-pa	open	131.226.105.207	\N	\N	231be908067d6ccf952542d339344474133063f74d59d1d4eb5b57f47fb000d5
95	2026-07-07 07:39:10.129478+00	Bea Marie Magayon	yabeemagayon16@gmail.com	09639001512	Iba Pa	kailan may medical mission na libre bunot ng ngipin	iba-pa	open	160.20.40.199	\N	\N	f237bd6ca3a5f8823ab1c40501e6e842c6fbbde3ffd50f9c2b51d99b76950584
96	2026-07-09 01:08:24.192151+00	Carlos Keoni Bello	carloskeonibello20@gmail.com	09282953084	Iba Pa	Good day po open po ba ang Office of Senjor Citizens' Affairs niyo bukas Friday, July 10?	iba-pa	open	49.144.196.79	\N	\N	b35e2a837e0fcff462dcd62374693bd3d48b5958338916760c418d022f0a48ea
97	2026-07-09 01:12:12.887439+00	Carlos Keoni Bello	carloskeonibello20@gmail.com	09282953084	Iba Pa	Good day po open po ba ang Office of Senior Citizens' Affairs niyo bukas Friday, July 10?	iba-pa	open	49.144.196.79	\N	\N	53d5308dee5ab7110362ee7d161330be4f0fc6115da9476509f1b21e628a033b
98	2026-07-09 05:56:20.422563+00	Christine Joy Vitangcol	cj_kyle_19@yahoo.com	09171244728	Iba Pa	Anong numero para sa engineering office	iba-pa	open	49.144.196.224	\N	\N	406bab0740b91ee6a8fe8fc4b63cc4e8075d445d41403cf5a15f185ef85189a1
99	2026-07-09 07:19:52.121462+00	Lynard Apostol	Lynard.apostol@lspu.edu.ph	09151581757	Iba Pa	Saan pede mag padala ng email letter for the mayor of san pablo	iba-pa	open	216.247.84.117	\N	\N	734ea246b6d69f4a5912f071cad4924e4a58fd27a127921d26a5c0aae105073c
100	2026-07-10 04:38:47.582495+00	Reiniel R. Balmes	nielramos1021@gmail.com	09483685512	Iba Pa	Maaari po bang mag walk-in sa municipal hall ng inyong probinsya partikular sa Mayor’s Office upang humingi ng gabay at mag submit ng permit na kailangan ko para sa research at thesis?	iba-pa	open	27.49.138.215	\N	\N	4ffb6b24816fb9ddfc70ddb678631d7dccf489284a7ef39e5e34673e581c223a
101	2026-07-10 07:11:25.266519+00	Clarice Reyes	clarice.assuranzcpas@gmail.com	09177517984	Iba Pa	I would like to inquire about the process for updating or transferring a business permit from a sole proprietorship to a corporation. Our company has recently registered a new corporation, which will continue the operations previously conducted under the sole proprietorship. We would appreciate your guidance on the procedures to follow, as well as the documentary requirements needed to facilitate this transition.	iba-pa	open	180.195.23.200	\N	\N	24ee751f1d24f69e6561bfc86b34802d2d2af9bb1c8d82d07f0275d943fa888e
102	2026-07-11 05:40:21.875289+00	Eira Mendoza	mendoza.eiraantonette@gmail.com	09911320680	Iba Pa	Kelan po kaya ang deadline para sa scholarship sa San Pablo? Salamat po.	iba-pa	open	160.20.40.45	\N	\N	70db83f474739ee11aee59623e067fcc55b74266f02946cea0cdfd02ad00a5d5
103	2026-07-11 23:20:12.97033+00	Markcielo Rogelio	markcielorogelio@gmail.com	09457789097	Iba Pa	About sa scholar ng San Pablo	iba-pa	open	139.135.128.6	\N	\N	13c15f13b0a03e623db915153d4d807d7b48ce2669b0b2afa3c7494477544a34
104	2026-07-12 19:10:27.223264+00	Lean Monteclaro	leanmonteclarosjps@gmail.com	09938191319	Iba Pa	Saan po pwedeng makita ang Government hiring	iba-pa	open	131.226.106.14	\N	\N	de05101fca195ba66597df201e9d1ed1fb13b3f92ef9f0473c58976831fe7658
105	2026-07-13 00:33:13.191003+00	Ofelia Velasco	velascoofelia@yahoo.co.nz	09335100686	Iba Pa	Ano Ang requirements sa pagkuha NG building permit	iba-pa	open	49.224.246.232	\N	\N	e63fb22a44541a1095671a7860395af94b92a532b693e8573755913de43278fb
106	2026-07-13 08:47:43.793178+00	RONIE SABIDO	ronniefunilas123@gmail.com	09947680582	Iba Pa	Hello Po ako Po ay ofw sa Japan sana naman Po pagbalik ko satin sa San Pablo City makapagtrabaho Po ako Dyan Kahit Anong trabaho Po sa ahensya ng Gobyerno ,	iba-pa	open	133.106.49.120	\N	\N	959ccb826d9db844ee538df4e7a87f9fc1b6b9f90e641d0813d34c39ec73915c
107	2026-07-13 12:18:23.91458+00	Julianne Kyla Espocia	juliankylaespocia@gmail.con	09453302140	Iba Pa	SAN DIEGO History: - Origin of the Barangay - Historical Background - Early Settlement - Significant Events - Development	iba-pa	open	49.145.4.64	\N	\N	1dace61ec17bf9e59df2626d1aa3a4da5f31230ddc26ed71e8626351a2c2e2f4
108	2026-07-14 09:51:46.629743+00	Hannah De Lara	supergirl100406@gmail.com	09945735819	Iba Pa	Is there any government assistance in terms of funding a research or thesis project?	iba-pa	open	112.204.169.201	\N	\N	a8543672e1638ee59177407a2da3095155279e1c2d421cfca57e5d74e8073f4f
109	2026-07-14 14:55:38.435269+00	Irish vallena	irish.vallena.wat2014@gmail.com	09976288277	Iba Pa	Hi, gusto po sana namin magpakasal either thru mayor or civil court. Ako po ay filipina and fiance ko po ay buddhist from sri lanka. Possible po bah na maikasal either thru mayor or civil po? At ano po yung mga requirements?	iba-pa	open	91.72.205.248	\N	\N	fd27924cbbe45227dca17974d59210c7e95b4db48ecd0ba7f066fce5ffe807e3
110	2026-07-17 02:55:27.68421+00	Danica Manimtim	giyowww@gmail.com	09472390371	Iba Pa	open hours of san pablo mega capitol	iba-pa	open	175.176.48.171	\N	\N	6822c08334d0491f3a560d5409ad359653abe40cbc5836253109f703afe85b58
111	2026-07-17 22:53:23.903217+00	JOAN DIMAALA SUANTE	joansuante23@gmail.com	09236509938	Iba Pa	Pano ako makakakuha ng vax certificate. Dahil walang lumalabas na vax cert ko sa Egov app.	iba-pa	open	223.25.26.218	\N	\N	421b49ea6404dc123aae81164880e9fa23ab2a73c45a923a041dbe57d0c0e5ec
112	2026-07-18 15:09:08.684183+00	Veronica Sambeli	roni.sambeli13@gmail.com	09298485813	Iba Pa	Magandang gabe	iba-pa	open	112.210.229.35	\N	\N	ccf58acab1bb98194f52ce194fb14bcea9a7dd245b4b4fe43b15e86d2ac6980e
113	2026-07-20 02:43:11.535977+00	Niño Gallardo Malatag	fashionfusion2383@gmail.com	09972780888	Iba Pa	What's are the requirements for working permit?	iba-pa	open	110.54.140.218	\N	\N	0bfed9cb3e25e459184208d2ff5c843b010e7af2f2512676c8322fe2e089d9c4
114	2026-07-20 08:42:04.166219+00	samantha limbo	wellkindcorp@gmail.com	09175430626	Iba Pa	paano iregister ang aming business permit dito sa website nyo?	iba-pa	open	112.208.97.205	\N	\N	6de1e9c13daa2e4dcca8d6ffc07edb0882e034f368eb705f556d3ca7cd21301d
115	2026-07-20 12:37:09.540275+00	Elaine Gesmundo	egesmundo20@gmail.com	09284419064	Iba Pa	May vacant position for OJT Architectural drafting po ba ang Kapitolyo	iba-pa	open	49.144.160.207	\N	\N	f2d48c967eae51f38768b16cb5261160226eab7eaa6239a5a8a0b8afd48c7f1a
116	2026-07-21 15:06:33.189841+00	Mika Rafon	mikarafon@yahoo.com	09175852818	Iba Pa	Marriage License Application Requirements	iba-pa	open	131.226.106.233	\N	\N	202cacd230c037c19e38a4b0c5c11dc413fe0810bc9e1b3b4ff92e4676012dbc
117	2026-07-21 17:22:12.640375+00	Freesia Msakayan	0323-3508@lspu.edu.ph	09098978178	Iba Pa	Where can I address the letter for the License to Operate List for Pharmacies in San Pablo City for an undergraduate thesis. And Census for the list of middle aged adults to elderly living in San PAblo City?	iba-pa	open	136.158.65.134	\N	\N	75082c3919751075b9fa927820c94f4a58bcb9d2683f89c51f43167a8b0a6694
118	2026-07-22 03:45:35.853964+00	Gabriel Gonzales	gabgonzalss@gmail.com	09974299515	Iba Pa	Ano ang kabila ng kaliwa?	iba-pa	open	160.20.40.74	\N	\N	a7677de0f8a40aa96f4d274e7574f8eae8da8de3756cc2f85264d72561773aec
119	2026-07-22 07:08:11.109242+00	gab	gab@gmail.com	09238409348	Iba Pa	hello	iba-pa	open	::1	\N	\N	7fc46332d56764c32795b48e519c46341025899901b5cc43b525cbb6f4adcfcc
120	2026-07-22 07:12:57.718124+00	gab	gab@gmail.com	09238409348	Iba Pa	📷 Photo	iba-pa	open	::1	\N	\N	b2263801d1c65ef4983d4621253e63bddb6713a9d55e694024c9fc4d50e27445
121	2026-07-22 07:17:30.552258+00	gab	gab@gmail.com	09238409348	Iba Pa	asdada	iba-pa	open	::1	\N	\N	cfc4752ad03859b3f1f30509264a61c117de4792c0efe73b1c9262973b6554f1
122	2026-07-22 07:18:27.119072+00	gab	gab@gmail.com	09238409348	Iba Pa	asdasdasdasda	iba-pa	open	::1	\N	\N	2c1fd8a009cb9bcc3f3b4f47e764ced99cce714b4677b632712fccedf0309659
123	2026-07-22 07:23:02.217042+00	gab	gab@gmail.com	09238409348	Iba Pa	Hello	iba-pa	open	::1	\N	\N	e1fdf1d1d312aecb692783317a760d95f7f20ab03eba8cca94726f247a31e550
124	2026-07-22 11:56:34.845431+00	Maricar Gillamac	quinmargillamac@gmail.com	09566504814	Iba Pa	Tanong lng kung dto sa San bartolome ba ay nag umpisa na Ang pay out ng 2k sa mahihirap	iba-pa	open	209.35.172.206	\N	\N	28f3bb0d28b67856a2058edcc4d8ce9f3629ac73ccec9a86b0e82b1f663ead74
126	2026-07-23 02:56:56.404112+00	gab	gab@gmail.com	09974288517	Iba Pa	Hello	iba-pa	open	160.20.40.74	\N	\N	9fea9aa31e1159d947da407d4cabca95cc4f4143dcd5c5b6afd06850eee967a5
127	2026-07-23 03:01:14.260969+00	Gabriel Gonzales	gabgonzalss@gmail.com	09974299515	Iba Pa	hello	iba-pa	open	160.20.40.74	\N	\N	8ecc76e53e9ade0549d1849df60ab5b3621d4af30d0734b53cf6e061d639802e
128	2026-07-23 04:18:10.68003+00	ali Arcilla	alissonarcilla2003@gmail.com	09159508337	Iba Pa	Nagpa vaccine ako sa SM San pablo. Saan ako hihingi ng vax certificate?	iba-pa	open	111.90.218.151	\N	\N	f4e31594edb2f17df83102e38bc902c623fdd81e70ce2d286d8c4e6e5a0813d5
129	2026-07-23 04:43:06.545147+00	Alisson Arcilla	alisson.arcilla@intouchcx.com	09159508337	Iba Pa	Nagpa vaccine ako sa SM San pablo. Saan ako pwede pumunta para kumuha ng VAX CERTIFICATE?	iba-pa	open	103.140.120.95	\N	\N	6d8ed14eaf6e1ab018d7c3cbade8ade032cce745da708aabf02ab177a8bb7f10
125	2026-07-23 01:12:24.680721+00	Christina Flores	miso@sanpablocity.gov.ph	09360412192	Iba Pa	Si ñlra amante p ay ayaw ireair ang aming service pc	iba-pa	assigned	160.20.40.74	\N	\N	9635484f9b842a77bc02badc5459782d543aa715b83b117bcd446404dbeffcdb
130	2026-07-23 08:06:40.993935+00	gab	gab@gmail.com	09974288517	Iba Pa	hello	iba-pa	open	160.20.40.74	\N	\N	353c5f39fdeb97615a4c56037fde6d217adc613e834157ab711138d893ceda97
131	2026-07-23 11:34:07.917953+00	michelle sarona	saronamichelle098@gmail.com	09506073474	Iba Pa	Sa uplift beneficiaries ng San Pablo kasali po ba Ang pangalan ko duon	iba-pa	open	175.176.53.226	\N	\N	d6d472b41aab775e9555e1c3c05882fd5ca093688fc4c7370949194a234738b5
132	2026-07-23 11:58:10.120984+00	Aprilyn Velasco	velascoaprilyn0@gmail.com	09187922812	Iba Pa	Meron napo bang listahan ang brgy San Francisco D. i calihan. para sa Uplift program?	iba-pa	open	131.226.106.134	\N	\N	289d389a08edf227f699e1e36ea1f78aff085f65b176cae80ea8a6e55aa6e5d6
134	2026-07-24 06:00:53.110144+00	Maricris Privado	aklis8850@gmail.com	09206422633	Iba Pa	Saan nakikita ang master list ng mga kasali sa uplift	iba-pa	open	110.54.143.163	\N	\N	6f9decda276380e75e5c4af3908b21542d71c9a7d3746815d28e8c6a0363e9be
135	2026-07-24 08:38:39.103126+00	MISHELL CURA PALATINO	curamishell@ymail.com	09451783233	Iba Pa	Ordinance No. 2012-40 (revised revenue code of the City of San Pablo	iba-pa	open	122.3.114.62	\N	\N	9d0984dd7a2f03a55d858d0e0e0a7973f93453d67548de8dd856bd5ca94e109d
136	2026-07-26 05:35:30.353722+00	Modesto Porcado Jr	mcporcadojr@yahoo.com	09922278734	Iba Pa	Pano po mag bayad ng real property tax	iba-pa	open	112.207.101.100	\N	\N	3fa5c5a77cab3eafc6a4ffe9bbc0c5cb083951569bd86687b71c2379a04f6d02
133	2026-07-24 05:38:01.254218+00	gab	gab@gmail.com	09975374653	Iba Pa	saan po ang flag ceremony sa lunes?	iba-pa	assigned	160.20.40.74	\N	\N	295d41f2b0a67b77acffe6ff03ce9d57615f759ad79d04f1ce7756f34a1013c7
137	2026-07-27 04:04:52.71401+00	Cielo Marie L. Pido	pidocielomariel@gmail.com	09517553768	Iba Pa	CSWD Head officer in charge	iba-pa	open	175.176.53.10	\N	\N	1389ec9c965e35053b0c0c3afa51f4efe8f9c0bdfcbd90d3c854c0526b0b0810
138	2026-07-29 00:04:23.582279+00	Briana Angela Macaraig	brianaangela180@gmail.com	09165653082	Iba Pa	What is the Seven Lakes Ecotourism Program?	iba-pa	open	49.146.192.27	\N	\N	52c67cf4c2e4f7838bc8502720490bce4879be330fd75075078f025604eabb21
139	2026-07-29 01:51:38.79085+00	donnabel anaveza	donnabel.anaveza@gmail.com	09673204008	Iba Pa	sino ang baranggay chairman ng baranggay santo nino, san pablo city?	iba-pa	open	150.228.183.232	\N	\N	cd3caefde9489da243b83eb9b1766c40f694364b90df99d1dd5c30172b78cd7c
140	2026-07-29 08:59:23.378878+00	Angelika Aquino	angelikaaquino74@gmail.com	09953028542	Iba Pa	Planning for civil wedding. Ano ano po ang need na requirements or documents?	iba-pa	open	27.49.240.27	\N	\N	53bc6278f2f53c5e4058b7296554f9519150b5ccc2bb7e0c416a02ed185c54ed
141	2026-07-30 03:30:37.882696+00	JM Mendoza	jmmendoza082389@gmail.com	09455603524	Iba Pa	bakit po antagal ng renewal sa munisipyo ng 28 papo ako nagpasa	iba-pa	open	216.247.81.26	\N	\N	f1ea66ace08e3189c14b7b08f14b53c07f487c0ffe51c3df704b93ec6e3db978
142	2026-07-30 04:34:39.972947+00	PAUL ADRIAN SAUL AVECILLA	pauladrian.avecilla@deped.gov.ph	09764504567	Iba Pa	CDRRMO DEPARTMENT HEAD	iba-pa	open	49.144.194.97	\N	\N	6dd7ed4575900817c143398596d02003f2797c2e7fbab089955d8f0912b8f3b0
143	2026-07-30 12:45:20.499096+00	Jocelyn Gale	irisbaby12@gmail.com	09167351516	Iba Pa	Sino ang barangay captain ng san buenaventura?	iba-pa	closed	112.202.121.215	\N	\N	ee3d855de0eda774255b50c28af071738310c190e08eec2ec8a428014748366d
144	2026-07-31 01:30:14.423792+00	Mariejo L. Alvarez	mariejoalvarez88@gmail.com	09109099727	Iba Pa	Mayroon bang email address ang CPDO na maaari naming padalhan ng liham ng kahilingan sa paghingi ng Comprehensive Land Use Plan ng siyudad?	iba-pa	open	103.250.77.165	\N	\N	e1029ffc7a6b163fb35f9a71da50dbfa056417e250982c17b291aa5eb1ed109f
145	2026-08-01 03:00:58.163341+00	RELYN BACOLON	bacolonrelyn01@gmail.com	09076991123	Iba Pa	hello! Good morning! Tanong ko lang kung saan pwede magbayad ng amilyar online?	iba-pa	open	180.188.173.152	\N	\N	1e03ba29466f63db8521a9a43a53a622979016d7630892faa75292f1e6805c6d
146	2026-08-01 07:13:32.982432+00	Sziene Briol	briolsziene@gmail.com	09292550123	Iba Pa	I would like to ask if this lot is a government owned lot? For thesis purpose only	iba-pa	open	136.158.35.155	\N	\N	f0c3257dad1f9438b4a603675a68946004fd14109f665c0ceaa6d08ab56a1087
147	2026-08-01 07:35:44.743026+00	Ricky L. Briones	rickylubrinbriones1995@gmail.com	09308358576	Iba Pa	Good Afternoon po. Pede po makahingi ng Facebook Page, Contact Number or Email Address na pede pong macontact sa Office of Building Official ? Thank you po.	iba-pa	open	49.144.211.210	\N	\N	c043ec3919e7bd4703178acb16365b2268b7f9ec58d878c2b096a26dc973b884
148	2026-08-03 03:30:46.212851+00	Arlyn	atalisic75@gmail.con	09648762520	Iba Pa	Saan po pwedeng magtanong regarding sa document ng	iba-pa	open	49.144.155.101	\N	\N	d9878f04427bc5d6550de3bf55df6bd1ab25cf60f1e133cda45214c6a67abd39
149	2026-08-03 12:07:34.413471+00	crisanto deleon	crisantodeleon451@gmail.com	09610160953	Iba Pa	paano po yun contrata po namen isang buwan na po kameng walang sahod gawa ng papalit palit po ng administrasyon ano po kaya pwedeng gawin	iba-pa	closed	112.198.211.181	\N	\N	798c75eb5fee90543251c27b0ac4caf74d5a4e250f1361abd5efcd19a1bc04c1
150	2026-08-03 12:48:21.936723+00	Caroline Jane Pant	pantcarolinejane28@gmail.com	09087040221	Iba Pa	Suspension in government work tomorrow	iba-pa	closed	103.3.83.194	\N	\N	530cba1636ea813fca1fd7f007c33418de9a3eb557f3a24f294cf6fcc241c922
151	2026-08-04 02:20:16.450212+00	Jennifer Gazzingan	jggazzingan@landbank.com	09268689081	Iba Pa	Contact number of Business Permit And Licensing Office	iba-pa	open	136.158.213.20	\N	\N	5d67b54b638f177a3b6bc6bfac315d81c61da0901d96cf0af25edf7a9461dfe0
152	2026-08-04 06:06:05.709117+00	Sarah Jane Deliso	delisosarahjane@gmail.com	09273146893	Iba Pa	sino po ang municipal engineer ng san pablo	iba-pa	open	180.191.74.61	\N	\N	63fd898071e6c5956e65f69046757bfa5fe602efc44d29018c26dd9580a2ffa0
153	2026-08-04 06:32:21.545258+00	Marianne Gregorio	gregoriomarianne931@gmail.com	09562979902	Iba Pa	Mag tatanong lang po ako about sa pag legitimate ng PSA	iba-pa	open	120.28.70.139	\N	\N	2737d90060854c31654f1539ea50798cabe73bd04acd704a75337745c5690a3a
176	2026-08-22 04:07:06.762401+00	Dequito, Kyla Mae V.	kyladequito66@gmail.com	09455338883	Iba Pa	Ano pong hiring ngayon sa any government office at ano po ang mga kailangang i-submit?	iba-pa	open	110.54.143.6	\N	\N	5add52e5d667d879c66eb74dd753b7901b6913f9b64534cc4ee1efdd1dc41b1c
177	2026-08-24 07:43:08.458508+00	Joan Javier	joan.javierbns@gmail.com	09507750775	Iba Pa	renewal of solo parent id	iba-pa	open	180.191.75.2	\N	\N	6996d1e1d19553a601120a2ac5e34239095c3a1a1cec36717e8a144c33978e7a
154	2026-08-05 23:58:08.399221+00	Jennifer R. Padilla	rubiojennysidro@gmail.com	09466064143	Iba Pa	Magandang araw po. Ako po si Jennifer Rubio, residente ng San Pablo City. Humihingi po sana ako ng agarang tulong medikal para sa aking anak na may Acute Lymphoblastic Leukemia (ALL). Ngayon po ay madi-discharge na kami mula sa ospital, ngunit dahil sa deklarasyon ng walang pasok sa mga tanggapan ng gobyerno ay hindi po kami nakapag-request ng guarantee letter. Kung maaari po sana, nais naming malaman kung may duty personnel o anumang paraan upang makapag-apply ng medical assistance o guarantee letter ngayong araw. Malaking tulong po ang anumang maibibigay ninyo. Maraming salamat po at pagpalain kayo ng Diyos.	iba-pa	open	216.247.81.101	\N	\N	07a2367b55f4e31acdaf3d1e511e21ce205814644171f9cc1f7bcf09a36f27ed
155	2026-08-06 02:00:13.482121+00	Racquel Lebreton	rakelfranz@gmail.com	09567786203	Iba Pa	Rtc open today?	iba-pa	open	209.35.169.30	\N	\N	4bcc3966a9015d571c0f30887627992ce75e409303fe84cf48ac96f036e035ee
156	2026-08-06 13:27:45.671869+00	Andrew tanafranca	andrewmarkftanafranca@gmail.com	09922062245	Iba Pa	Paano mag apply ng trabaho bilang parte ng cdrrmo ng sanpablo	iba-pa	closed	136.158.64.228	\N	\N	6502a3656f0faeea7b791e109a56403ae224ceeaf65c842d795ed16b10421833
157	2026-08-07 18:21:03.66531+00	Princess Endrenal	bethinabeatrizzbernice122718@gmail.com	09623453284	Iba Pa	Mayroom po bang programang dental para sa mga batang my bingot..	iba-pa	open	2.49.129.24	\N	\N	85427b1b8b89c7712d62f7f1d3d3a8055fb04748d54aeeeef51527398e26cfec
158	2026-08-09 08:03:01.400488+00	Stella	stella.0987a@gmail.com	09125343243	Iba Pa	What is mayor email address	iba-pa	open	212.8.248.200	\N	\N	823cdd3bc08ae08ea971fdbe59b5a5c86138ee4ea26066afadf21fe6e16a5320
159	2026-08-09 09:53:53.48339+00	Mary lyn Pasko Rael	raelmarylyn8@gmail.com	09639107404	Iba Pa	I am formally requesting an investigation and inspection regarding the sale of suspected spoiled fish at the San Pablo City Public Market, and I am also requesting stronger monitoring of perishable food products to protect consumers.	iba-pa	closed	175.176.53.252	\N	\N	5b31e5b89c9d680b87d9e939c08b63ef33edc67c0b0d8a716a826ef04179a4c1
160	2026-08-10 00:15:27.362558+00	Mary lyn Pasko Rael	raelmarylyn8@gmail.com	09639107404	Iba Pa	I am writing to formally report an incident involving the sale of a suspected spoiled fish at the San Pablo City Public Market and to respectfully request an investigation and appropriate action. On August 9, 2026, my husband and I purchased a tambakol (tuna) from a vendor at the San Pablo City Public Market. Because of the bad weather and intermittent heavy rain, we were in a hurry and unfortunately were not able to properly inspect the fish before leaving the market. While we were already travelling home on our motorcycle, we noticed that the fish had an unusual smell. At first, we thought that the smell was simply part of the normal odor of fish. However, when we arrived home and I was about to wash and prepare it, the smell had become extremely foul. We also noticed that the fish's eyes were very red and that its overall condition appeared clearly unacceptable and potentially unsafe for consumption. I am currently pregnant, and this incident caused serious concern because I am taki	iba-pa	open	175.176.52.35	\N	\N	90cd7a379777b98a9ef132680463bad62d2187279dfb546c0b8b7570781fcfec
161	2026-08-10 01:58:21.281316+00	Joy Javina	javinabjr@gmail.com	09934720643	Iba Pa	Good morning po. I would like to ask for assistance regarding my baby’s birth certificate and surname. My baby is 8 months old, and the father and I are not married. During the registration of my baby’s birth, I personally signed an Affidavit to Use the Surname of the Father (AUSF), so my baby is currently using the father’s surname. I would now like to know if there is a legal or administrative procedure to cancel, revoke, or reverse the AUSF so that my baby can use my surname instead. May I please ask what the requirements and procedure are for this request, and whether I need to personally visit the Civil Registry Office or file a petition/court case? Thank you po.	iba-pa	open	136.158.66.194	\N	\N	785ec0f41cdd2f9b07781f95ccbe0544662a9f5871a8eb24850a57553a634e7b
162	2026-08-10 05:10:33.102025+00	Gelryn Symens	tenergerlyn1988@outlook.com	09451804743	Iba Pa	Bukas po ba ang munisipyo ngayon?	iba-pa	open	116.91.209.161	\N	\N	99f37c0bbcdbe54c277e52a2d4c8ce3846ea10a24597a43d4357800e8bacb919
163	2026-08-12 05:34:13.779658+00	MARILAE RAGOTERO DIMAANO	ealiram915@gmail.com	09262860611	Iba Pa	May hiring po ba para sa Registered Nurses?	iba-pa	open	180.191.85.238	\N	\N	056484db6385753a68db80fb4af406f56f5274ec917f0bec4bbf3b8d86485470
164	2026-08-12 21:48:21.852804+00	Maria Yambao	taurusako1@yahoo.com	09481158327	Iba Pa	Pangalan at contact information ng kapitan ng Sta Catalina at San Buenaventura. Maraming salamat po.	iba-pa	open	38.209.100.98	\N	\N	f5db18c042ce7deb69256258aab8e477480c180bc89f7369d8fa6bd8d48a0db0
165	2026-08-13 01:42:58.508843+00	Emmy Emradura	emraduraymme@gmail.com	09189640515	Iba Pa	Requirements for PESO Assistance on Job Mass Hiring	iba-pa	open	136.158.92.106	\N	\N	5dfcdb71fa348977edc2cb979d68a23dd2f9d604cb0db99d138bb0fadb389888
166	2026-08-13 04:11:25.371461+00	Jennifer Rodriguez	Jrod94103@yahoo.com	09156026111	Iba Pa	Paano po ma check kung legitimate ang business and registered sa San Pablo	iba-pa	open	112.207.212.7	\N	\N	0e7aa66b4a09c0007db509f9e55b466ce93bb77e045875c87e3679d176e1407a
167	2026-08-14 02:03:53.286249+00	Luisito Manalo	carleen1789@gmail.com	09084322977	Iba Pa	May pasok po ba ngayon sa BIR San Pablo?	iba-pa	open	175.176.31.21	\N	\N	1c2cbd57d4f390439ae10691061735104129941d1edddd8bfb62c3a37e38f561
168	2026-08-14 14:53:15.026851+00	Ella Buenaventura	mae.buenaventura28@gmail.com	09196051476	Iba Pa	Email address ng local civil registry	iba-pa	closed	59.190.12.132	\N	\N	2e3647f43ac5ed4dd32a499ca7702c93bc4808f7333e3f22b9b004e1e3d7e156
169	2026-08-17 01:26:57.453964+00	Ella Buenaventura	mae.buenaventura28@gmail.com	09196051476	Iba Pa	Contact number ngvlocal civil registry	iba-pa	open	59.190.12.132	\N	\N	4ff2cb9cfc6b18f0c5c065bcedb0fd929ddb5e459478129a2a55147e955d4da7
170	2026-08-17 04:28:51.472066+00	Jennery Divine Yambao	jediyambao19@gmail.com	09065950421	Iba Pa	Hingi po sa ako ng assistance to remove po ung mga nakaparak ng sirang sasakyan sa tadat at gilid ng bahay ko maari po ba mkahing ng mobile number ng pede mahiingan ng tulong pra sa brgy san Gregorio	iba-pa	open	112.207.208.241	\N	\N	f62adf6cf711a3c692c3991a2d9a345e513333b115466bd0f077ca743ce584fe
171	2026-08-17 11:10:53.215489+00	Juv David	juvmarianne@gmail.com	09976676882	Iba Pa	May facebook page ba kayo	iba-pa	closed	112.201.193.239	\N	\N	b7ee4ca7248824a97e3a93d8d22178a972a4ac6fe310e010dfcb08545bd9dcf5
172	2026-08-19 09:38:06.249565+00	Geraldine Jane Abdon	abdongejaned.7@gmail.com	09455361597	Iba Pa	Maari ko bang malaman kung ilan ang current ALS learners sa san pablo? at mayroon ba kayong facility nito	iba-pa	closed	103.60.170.231	\N	\N	bfbe2fb397d371af148c92b5f93f229460107609b175c7ed2eda04fff702a300
173	2026-08-19 21:55:51.694307+00	Rei Melbourne Sy	mauvillanueva0915@gmail.com	09956678129	Iba Pa	Open po ba ang municipal court?	iba-pa	open	149.30.144.177	\N	\N	56f34a154f2e2b2eee696fb316b22e7af8f0187c2ff8051179f690549aaadbb8
174	2026-08-20 00:15:00.064469+00	Jayaon aban	jaysonaban75@gmail.com	09760305091	Iba Pa	List of name in uplift program in san pablo city	iba-pa	open	49.144.197.154	\N	\N	99fef6e6f4e9f2e8f059882a31ac2cd7799f5ebe083722484d757a6a960c31cb
175	2026-08-20 06:24:22.941344+00	Crystal jeniefer l. Marasigan	crystaljeniefer@gmail.com	09093895406	Iba Pa	Paano kumuha ng vaccine certificate	iba-pa	open	136.158.66.204	\N	\N	863aa8a516f1b02d521768a10f0d70b6d80cc1d7df38044ec1124df9676b5a97
178	2026-08-25 01:12:36.570088+00	Louie Matute	louiematute7@gmail.com	09525532062	Iba Pa	magkano po bayad Ng traffic violation truck ban at obstruction	iba-pa	open	112.198.69.182	\N	\N	c2115f55c399e2d97f441d7e5e607cd49e92285ed9aca53153fe701964bb8381
179	2026-08-25 02:12:25.478187+00	Phoebe Blanche Agra	phoebeblanchevillafuerte@gmail.com	09171748737	Iba Pa	What is your contact number	iba-pa	open	112.202.96.148	\N	\N	e908806f8ac99173ed2ff18c2a33f49727bdf8d84d3f05b7dc36e07c749c0181
180	2026-08-25 03:07:52.702639+00	LYKA DURANO	lyka.durano06@gmail.com	09054805417	Iba Pa	mayroon po kayo kontak sa office of the building officials?	iba-pa	open	49.144.201.87	\N	\N	52b7ed47adccaa081e9e8230b9eb46271696a13d2864314841ef7061d3a59ebc
181	2026-08-25 06:46:56.927124+00	Karen Aquino	selina122125@yahoo.com	09209473741	Iba Pa	ano ang contact ng dswd san pablo city	iba-pa	open	49.144.197.91	\N	\N	2440e201fa49167c85505f0588f725c7246e5033e83e5cd0f0e91c488e22b365
182	2026-08-25 08:23:53.082317+00	Trishiamay Coma	trishiamay2016@gmail.com	09923774232	Iba Pa	san po pede mag inquire regarding sa stalls sa night market ?	iba-pa	open	152.32.93.26	\N	\N	d9095df1509f497eef6ebc66253a18267292ad2cbf723e48c7adc386e8381a90
183	2026-08-26 13:46:58.500392+00	Kimjoy Flores	kimjoyflores1@gmail.com	09997016028	Iba Pa	where can i get help for medical financial assistance?	iba-pa	closed	175.158.217.51	\N	\N	af4b01a4015ce8c47f19911396fdcd37edddae151c5147e481a85d9d7ab31de1
184	2026-08-26 23:18:21.532965+00	erick may	erickmaymanarinmundin@gmail.com	09920572711	Iba Pa	Hello po Goodmorning, we are 4th year Sanitary Engineering students na currently ay naghahanap po ng location / topic of our thesis. Would it be okay po if magpunta kami today sa inyong city hall?	iba-pa	open	103.100.136.49	\N	\N	24714f1feb273e6eda13553f5e0213e057599b49d2d66a2f9d32d15b82ab00ea
185	2026-08-27 05:25:53.503367+00	Nhoemy Adriana Capila	nhoemyadriana.capila@deped.gov.ph	09556391433	Iba Pa	Magandang araw po. Ako po ay nagtatanong tungkol sa delayed registration ng birth certificate ng isang student. Kasalukuyan po siyang nakatira sa San Pablo City, Laguna, ngunit ipinanganak po siya sa Macalelon, Quezon at doon dapat mairehistro ang kanyang birth. Maaari po bang malaman kung maaari siyang mag-apply o mag-file ng out-of-town delayed registration sa Local Civil Registrar ng San Pablo City, upang hindi na po kailangang bumiyahe agad sa Macalelon, Quezon? Maaari rin po bang malaman kung anu-ano ang mga requirements at proseso para rito? Maraming salamat po sa inyong tugon at tulong.	iba-pa	open	49.144.173.135	\N	\N	5198cc1d148ab842b698ab998e95aac0731e1a3339b7912151fca51adb1a4e87
186	2026-08-27 23:46:36.856065+00	Abie	a@gmail.com	09939268288	Iba Pa	Open today ang city hall?	iba-pa	open	49.145.7.4	\N	\N	451c2c4aee3599777357e418a08f69fc057e02b6ce1983f5529f22be1717ae9c
187	2026-08-28 02:27:45.656975+00	Jey Abadiano	301764ja@gmail.com	09195250723	Iba Pa	May isang kaibigan po ako na pumanaw kailan dahil sa aksidente sa motorsiklo sa inyong lugar, at hindi daw po bakalabas ang katawan ng pumanaw dahil sa bill nito sa ospital , maaari po bang ilapit at isangguni sainyo ito ? maraming salamat po	iba-pa	open	175.176.40.138	\N	\N	bd20f85e357a7132efcf517e1e46ebe2769fe754c1e95bd724742235e43c7043
188	2026-08-28 13:32:20.963903+00	John Patrick Bool	patrickjohnbo@gmail.com	09935405102	Iba Pa	meron po ba kayong official na Facebook page?	iba-pa	closed	49.144.201.77	\N	\N	47eb491396b4a376b0745142ef3289bb1dc86711a0cd0d1f2b7a0ad393a1d221
189	2026-08-30 07:37:29.08756+00	Marcus Ferrer	marcussferrerr@gmail.com	09272922805	Iba Pa	Magandang hapon po. Paano po mag-request ng city ordinances and resolutions patungkol sa pangangalaga ng Sampaloc Lake?	iba-pa	open	112.209.67.21	\N	\N	9598db3904c0d34826e008623fe103c2e1d96eecc0bbb617a0430f3b7eb036ad
190	2026-08-31 14:58:51.436794+00	Marcus Ferrer	marcussferrerr@gmail.com	09272922805	Iba Pa	Magandang hapon po. Paano po mag-request ng city ordinances and resolutions patungkol sa pangangalaga ng Sampaloc Lake?	iba-pa	closed	112.209.67.21	\N	\N	d0accce79bf51d6a6e0e1c0666395193f592b8fc02e1df7061bef975ae6c0551
191	2026-09-01 03:20:03.635774+00	Patrick James Corsame	pjcorsame@gmail.com	09959218611	Iba Pa	Pwede po mahinge copy ng Ordinance No. 345, Series of 2025, officially known as the "Expanded Solo Parents Welfare Act in the City of San Pablo,"	iba-pa	open	136.158.56.140	\N	\N	fddc5a212aecad42be757c7884a9fe5c6a7c60320231fc3d10c557afad84850a
192	2026-09-01 06:13:47.59591+00	Gwyneth Avril Gosila	gosila.llanto.ortega@gmail.com	09615918933	Iba Pa	Anobg oras ang sara ng office of assessor?	iba-pa	open	175.158.215.211	\N	\N	5cc2880ac4daca1ee5189844bd1ad4ea7d590e636246c4515d2da6ea93caa8c2
193	2026-09-01 12:58:05.403383+00	Catherine GULLAS Delacruz	pantingcatherine@gmail.com	09566537268	Iba Pa	gusto ko lang malaman kung merong hiring ngayun sa munisipyo ng spc	iba-pa	closed	49.144.169.211	\N	\N	65c8e1a7380ccb727bf4ed577206e00043874431cfed8bd9431656119da0c600
194	2026-09-02 05:20:43.079587+00	lanie buna	labuna@pdic.gov.ph	09178917640	Iba Pa	Magandang hapon. maaari po bang makuha ang contact number na pwdeng tawagan sa City Treasurer's Office?	iba-pa	open	112.199.124.217	\N	\N	f345680b275666ab96190e1e7fa0dc10a4edc996dc07936cbd34671ab1178f82
195	2026-09-03 21:10:36.788182+00	John	jbunda@1dynamix.com	09178074207	Iba Pa	May pasok po ang City hall ngaun ng San pablo city?	iba-pa	open	111.90.238.55	\N	\N	b4794aa90b587d5601dbc2bc6763cf1135ed482e44f3e16e9b5b1cbdb0411840
196	2026-09-03 21:32:10.412627+00	John	jbunda@1dynamix.com	09178074207	Iba Pa	May pasok po kayo ngaun?	iba-pa	open	112.206.66.90	\N	\N	99a1cf396687a2ac8e3d41180f0d5eba62644f5ef118b765bc2265dd498425da
197	2026-09-04 06:52:05.563287+00	Janella Dela Cruz	delacruzjanella3@gmail.com	09951192883	Iba Pa	I need another copy of a certification of business closure. The previous one that I have says that it's for BIR use only. I need a copy that says for SSS, Pagibig and Philhealth use. Will you please help?	iba-pa	open	49.144.8.4	\N	\N	dbb22a83653349f07f503d966ea8aac7b1218dc4dbe59887b2906dbb157fe545
198	2026-09-06 00:14:53.646928+00	cris bernadette gealon	crisbernadettegealon@gmail.com	09494676349	Iba Pa	Saan at paano mag bayad ng Amilyar	iba-pa	open	136.158.79.97	\N	\N	64b69704313b03a101395e63c28f765e97f12cb442c844379b12f59872c13c0f
199	2026-09-06 06:42:19.080375+00	NERI CRUZ	neri_2792@ymail.com	09153430557	Iba Pa	CAN I REQUEST A COPY OF BUILDING PERMIT FORMS?	iba-pa	open	112.206.53.162	\N	\N	51fc79fb7bc228377ba217d5d5c73004cb41dedf793917d33266339be39fadde
200	2026-09-07 00:21:27.029386+00	gab	gab@gmail.com	09974288517	Iba Pa	Hello	iba-pa	open	160.20.40.74	\N	\N	3c59ba805c43cc2601e3282985988046db2a90b2c023e15fb6cd55bf85ad0caa
201	2026-09-07 10:38:11.192421+00	Dee	heidetalagtag4@gmail.com	09912358952	Iba Pa	anong mga job vacancies ang available sa lgu? nag hihire ba sila ng fresh graduate na magna cum laude?	iba-pa	closed	103.132.168.227	\N	\N	be01fdfb935ad4e8dc695162191ff3c6c4b9b4fc8104d3c612b742bb9713223b
202	2026-09-08 01:33:53.059628+00	Maria Mariel Madeloso	madelosomariamariel@gmail.com	09057094329	Iba Pa	how to access computation of real property tax	iba-pa	open	131.226.101.50	\N	\N	17356cb96cbc41c39c76ea11414b72e7b766022df4492a4cebd97dd897b95bda
203	2026-09-08 01:45:44.854545+00	Kristine Go	nonosokristine01@gmail.com	09760027023	Iba Pa	Magtatanong lang po kung may available pa po na pwesto sa night market	iba-pa	open	49.147.87.242	\N	\N	5b121a5d14503a84103b5290507b798647f35e11dfc41e841a9795cc6afe5239
204	2026-09-08 01:53:01.626304+00	Crisalyn monasque	monasque.crisalyn0716@gmail.co	09369111262	Iba Pa	San po. Ped3 mkuha copy ng business pedmit	iba-pa	open	111.90.198.124	\N	\N	d8034758bb57b026866aa5470f7e6ec4afe1d016d1840a2a1582d059f683ff7b
205	2026-09-08 02:08:36.91893+00	crisalyn monasque	monasque.crisalyn0716@gmail.com	09369111262	Iba Pa	Paano po mkuha copy ng business permit	iba-pa	open	111.90.198.124	\N	\N	105fd348d0ebc58246217212818b9383a437dc8d9f4461b1bc41f5092f6568fb
206	2026-09-08 04:06:01.663034+00	Modesto Porcado Jr	porcadojrm@gmail.com	09922278734	Iba Pa	Mag bayad po ako ng real property tax pano po at saan pwede	iba-pa	open	112.207.106.32	\N	\N	d5bbc66166d13d24fc6d28ff8588ae5bb55468cc1d38abdde0dd40efea293304
207	2026-09-09 00:35:03.312117+00	Angelyn Pascual	angelyn.pascual@cardmri.com	09516909514	Iba Pa	For PTR processing, if a representative will process on behalf of the Soliciting Official, what original documents and IDs are required?	iba-pa	open	112.202.115.119	\N	\N	3d9bc64607fa94af9bfa381b5152a4eab6f99bdfd96a183f5baf0307f9414edf
208	2026-09-09 01:48:12.53519+00	Dominador Acedilla	dominadorii.acedilla@cvsu.edu.ph	09755511993	Iba Pa	Magandang Umaga! Ako po ay isang undergraduate from Cavite na nagbabalak po na mag conduct ng study sa mga mangingisda ng Sampaloc Lake. Sino po kaya ang pwedeng ma-contact para dito?	iba-pa	open	64.224.104.12	\N	\N	6b5354436ad75bd859f7c288ec1af81e141fb61da1f8a73c11bcd8215a87d207
\.


--
-- Data for Name: csm_response; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.csm_response (id, control_no, client_type, transaction_date, sex, age, region, service, cc1, cc2, cc3, sqd0, sqd1, sqd2, sqd3, sqd4, sqd5, sqd6, sqd7, sqd8, comments, email_address, created_at, office_id, office_name) FROM stdin;
5	2026-09-7-001	citizen	2026-09-07	male	22	Region IV-A (CALABARZON)	Comprehensive Indigency Assistance Program (Hospital Bills, Diagnostic Procedures, Burial Assistance, and Medical Equipment Assistance)	4	5	4	Strongly Disagree	Disagree	Neither Agree nor Disagree	Disagree	Strongly Disagree	Disagree	Neither Agree nor Disagree	Disagree	Strongly Disagree	test message	\N	2026-09-07 00:55:29.442925+00	3f1be338-b3ea-4588-88eb-459605f1e58b	City Indigency Affairs Office
\.


--
-- Data for Name: epacd_rate_limit; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.epacd_rate_limit (id, ip_address, created_at) FROM stdin;
\.


--
-- Data for Name: events; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.events (event_id, title, description, start_date, end_date, location, created_at, updated_at) FROM stdin;
\.


--
-- Data for Name: faqs; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.faqs (faq_id, question, answer, created_at, updated_at) FROM stdin;
10	Ano ang office hours ng mga opisina?	8am to 5pm	2026-07-22 06:03:14.457+00	2026-07-22 07:34:54.849123+00
\.


--
-- Data for Name: forms; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.forms (id, title, date_issued, file_url, status, created_at, updated_at, category, is_archived, archived_at) FROM stdin;
20	BUSINESS PERMIT APPLICATION FORM	2026-07-23	forms/permits_licensing/46mgwlyi1og-1784792583336.pdf	active	2026-07-23 07:43:06.118+00	2026-07-23 07:43:06.118+00	business-permits-licensing	f	\N
\.


--
-- Data for Name: map; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.map (id, name, lat, lng, address, contact, hours, image, sort_order, created_at, updated_at, offices) FROM stdin;
one-stop-processing-center	One Stop Processing Center	14.0749104	121.3248324	San Pablo City Hall, Rizal Avenue, San Pablo City, Laguna	\N	Monday to Friday, 8:00 AM - 5:00 PM	onestop.jpg	1	2026-07-23 00:57:58.610331+00	2026-07-23 00:57:58.610331+00	{}
vice-mayors-office	Vice Mayor's Office	14.0747234	121.3244554	\N	\N	\N	vice-mayors-office.jpg	2	2026-07-23 00:57:58.610331+00	2026-07-23 00:57:58.610331+00	{}
hr-management-office	Human Resource Management Office	14.0742988	121.3257541	\N	\N	\N	hr-management-office.jpg	4	2026-07-23 00:57:58.610331+00	2026-07-23 00:57:58.610331+00	{}
city-information-office	City Information Office	\N	\N	\N	\N	\N	city-information-office.jpg	1	2026-07-23 00:57:58.610331+00	2026-07-23 00:57:58.610331+00	{}
san-pablo-city-hall	San Pablo City Hall	14.0744654	121.3245421	\N	\N	\N	city-hall-old-building.jpg	3	2026-07-23 00:57:58.610331+00	2026-08-12 01:04:21.258588+00	{city-information-office}
\.


--
-- Data for Name: media; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.media (media_id, file_path, media_type, caption, uploaded_by, related_article_id, related_event_id, related_banner_id, order_index, created_at, updated_at) FROM stdin;
113	https://yljsclzmrxuhejgcesiv.supabase.co/storage/v1/object/sign/media/banners/banner-1786944293490-hw174coxgwd.png?token=eyJraWQiOiJzdG9yYWdlLXVybC1zaWduaW5nLWtleV83NGM0Nzc4My1kNGMzLTRlNDktOWUwYy01YjJlYmIxNzA2OGQiLCJhbGciOiJIUzI1NiJ9.eyJ1cmwiOiJtZWRpYS9iYW5uZXJzL2Jhbm5lci0xNzg2OTQ0MjkzNDkwLWh3MTc0Y294Z3dkLnBuZyIsInNjb3BlIjoiZG93bmxvYWQiLCJpYXQiOjE3ODY5NDQyOTQsImV4cCI6MTc4OTUzNjI5NH0.mqqM0HuQsdpgjOfvPUnzJgZXTFlJol7VjKx50-KvuEY	image	\N	47	\N	\N	\N	0	2026-08-17 05:24:58.022	2026-08-17 05:24:58.022
87	https://yljsclzmrxuhejgcesiv.supabase.co/storage/v1/object/public/media/articles/ptjukr4tm-1783481504500.webp	image	LIBRENG SCHOOL SUPPLIES PARA SA MGA MAG-AARAL NG SAN PABLO	\N	\N	\N	\N	0	2026-07-08 03:31:50.728	2026-08-14 01:56:57.558971
99	https://yljsclzmrxuhejgcesiv.supabase.co/storage/v1/object/public/media/banners/1d7o7xdh2-1784624045292.jpg	image	\N	\N	\N	\N	\N	0	2026-07-21 08:54:05.509	2026-08-14 01:56:57.558971
111	https://yljsclzmrxuhejgcesiv.supabase.co/storage/v1/object/public/media/banners/banner-1785729661097-64ccvqgnod.png	image	\N	47	\N	\N	\N	0	2026-08-03 04:01:11.538	2026-08-14 01:56:57.558971
18	https://yljsclzmrxuhejgcesiv.supabase.co/storage/v1/object/public/media/banners/1777363425876-sb6lrbm7h3.webp	image	this is a .webp image	\N	\N	\N	\N	0	2026-04-28 08:01:19.129	2026-08-14 01:56:57.558971
19	https://yljsclzmrxuhejgcesiv.supabase.co/storage/v1/object/public/media/banners/1777363565291-jjba6qrgyw.webp	image	this is a .webp image	\N	\N	\N	\N	0	2026-04-28 08:02:54.692	2026-08-14 01:56:57.558971
4	https://yljsclzmrxuhejgcesiv.supabase.co/storage/v1/object/public/media/banners/1776846797590-0r3htuxxxrfk.jpg	image	test banner	\N	\N	\N	\N	0	2026-04-22 08:33:41.289	2026-08-14 01:56:57.558971
5	https://yljsclzmrxuhejgcesiv.supabase.co/storage/v1/object/public/media/banners/1776912747227-184efludag2.png	image	\N	\N	\N	\N	\N	0	2026-04-23 02:52:32.136	2026-08-14 01:56:57.558971
52	https://yljsclzmrxuhejgcesiv.supabase.co/storage/v1/object/public/media/articles/bflfrmd3j-1779788217747.webp	image	KONSULTASYON, ISINAGAWA KAUGNAY NG CITY ORDINANCE NO. 2011-01 PARA SA SEKTOR NG TRICYCLE	\N	\N	\N	\N	0	2026-05-26 09:33:39.709	2026-08-14 01:56:57.558971
53	https://yljsclzmrxuhejgcesiv.supabase.co/storage/v1/object/public/media/articles/y1011w3sv-1779788633877.webp	image	BAGONG INVESTMENT SA SPORTS, 2 TENNIS COURTS, BINUKSAN SA SAN PABLO CITY	\N	\N	\N	\N	0	2026-05-26 09:40:34.659	2026-08-14 01:56:57.558971
114	https://yljsclzmrxuhejgcesiv.supabase.co/storage/v1/object/sign/media/banners/banner-1786944307262-cnbrkmyh7nf.png?token=eyJraWQiOiJzdG9yYWdlLXVybC1zaWduaW5nLWtleV83NGM0Nzc4My1kNGMzLTRlNDktOWUwYy01YjJlYmIxNzA2OGQiLCJhbGciOiJIUzI1NiJ9.eyJ1cmwiOiJtZWRpYS9iYW5uZXJzL2Jhbm5lci0xNzg2OTQ0MzA3MjYyLWNuYnJrbXloN25mLnBuZyIsInNjb3BlIjoiZG93bmxvYWQiLCJpYXQiOjE3ODY5NDQzMDgsImV4cCI6MTc4OTUzNjMwOH0.1OBYKEl28GJs9Y4AuFhN2ElRRRR7fsKwOJwM1--c648	image	\N	47	\N	\N	\N	0	2026-08-17 05:25:11.079	2026-08-17 05:25:11.079
91	https://yljsclzmrxuhejgcesiv.supabase.co/storage/v1/object/public/media/articles/g1g07u1bw-1783482396797.webp	image	CALABARZON STRENGTHENS EARTHQUAKE READINESS THROUGH FULL-SCALE NSED EXERCISE IN SAN PABLO CITY	\N	\N	\N	\N	0	2026-07-08 03:49:01.498	2026-08-14 01:56:57.558971
94	https://yljsclzmrxuhejgcesiv.supabase.co/storage/v1/object/public/media/articles/3n5okvgjm-1783483120156.webp	image	PARANGAL KAY MAYOR NAJIE AY PARANGAL SA TAUMBAYAN	\N	\N	\N	\N	0	2026-07-08 03:58:47.418	2026-08-14 01:56:57.558971
84	https://yljsclzmrxuhejgcesiv.supabase.co/storage/v1/object/public/media/articles/jrv9mf6b1-1783480617030.webp	image	28 PWD SA SAN PABLO, TUMANGGAP NG MOBILITY DEVICES	\N	\N	\N	\N	0	2026-07-08 03:17:03.553	2026-08-14 01:56:57.558971
88	https://yljsclzmrxuhejgcesiv.supabase.co/storage/v1/object/public/media/articles/g4dwlmf7x-1783481701729.webp	image	SPC VOLLEYBALL TEAM, KINILALA NG LGU	\N	\N	\N	\N	0	2026-07-08 03:35:07.24	2026-08-14 01:56:57.558971
92	https://yljsclzmrxuhejgcesiv.supabase.co/storage/v1/object/public/media/articles/lrponq5dh-1783482769617.jpg	image	ALAMINOS–SAN PABLO BYPASS ROAD, AAKSYUNAN NA	\N	\N	\N	\N	0	2026-07-08 03:52:57.122	2026-08-14 01:56:57.558971
95	https://yljsclzmrxuhejgcesiv.supabase.co/storage/v1/object/public/media/articles/qnoob6mj6-1783650724833.webp	image	6,000 MAGSASAKA NG SAN PABLO CITY, MAKIKINABANG SA ACCIDENT AND DISMEMBERMENT INSURANCE PROGRAM	\N	\N	\N	\N	0	2026-07-10 02:33:12.436	2026-08-14 01:56:57.558971
45	https://yljsclzmrxuhejgcesiv.supabase.co/storage/v1/object/public/media/articles/yafppuf2e-1779786423375.jpg	image	Government Services to Reach Barangays via UGNAYANG NBG	\N	\N	\N	\N	0	2026-05-26 09:04:24.501	2026-08-14 01:56:57.558971
46	https://yljsclzmrxuhejgcesiv.supabase.co/storage/v1/object/public/media/articles/t13bsco7m-1779786626137.png	image	Centenarian may P20,000 cash benefit mula LGU	\N	\N	\N	\N	0	2026-05-26 09:07:45.461	2026-08-14 01:56:57.558971
37	https://yljsclzmrxuhejgcesiv.supabase.co/storage/v1/object/public/media/banners/ojq85zrnz-1779765548766.webp	image	HONDA PCX 150	\N	\N	\N	\N	0	2026-05-26 03:19:16.417	2026-08-14 01:56:57.558971
40	https://yljsclzmrxuhejgcesiv.supabase.co/storage/v1/object/public/media/banners/fcixprvkd-1779768914788.png	image	86th CHARTER ANNIVESARY OF CITY OF SAN PABLO	\N	\N	\N	\N	0	2026-05-26 04:15:45.997	2026-08-14 01:56:57.558971
42	https://yljsclzmrxuhejgcesiv.supabase.co/storage/v1/object/public/media/articles/wdffoxywk-1779769729917.webp	image	P3.5M Aid, 619 San Pableños Assisted	\N	\N	\N	\N	0	2026-05-26 04:31:25.839	2026-08-14 01:56:57.558971
48	https://yljsclzmrxuhejgcesiv.supabase.co/storage/v1/object/public/media/articles/ukulbm677-1779787007966.jpg	image	BOYSEN AT DAVIES, KINILALA NI MAYOR NAJIE	\N	\N	\N	\N	0	2026-05-26 09:13:39.442	2026-08-14 01:56:57.558971
49	https://yljsclzmrxuhejgcesiv.supabase.co/storage/v1/object/public/media/articles/c71isduvf-1779787099960.jpg	image	BAGONG INVESTMENT SA SPORTS, 2 TENNIS COURTS, BINUKSAN SA SAN PABLO CITY	\N	\N	\N	\N	0	2026-05-26 09:15:15.863	2026-08-14 01:56:57.558971
50	https://yljsclzmrxuhejgcesiv.supabase.co/storage/v1/object/public/media/articles/1zaw4wv6x-1779787174828.jpg	image	BAGONG INVESTMENT SA SPORTS, 2 TENNIS COURTS, BINUKSAN SA SAN PABLO CITY	\N	\N	\N	\N	0	2026-05-26 09:16:22.654	2026-08-14 01:56:57.558971
51	https://yljsclzmrxuhejgcesiv.supabase.co/storage/v1/object/public/media/articles/1zaw4wv6x-1779787174828.jpg	image	KONSULTASYON, ISINAGAWA KAUGNAY NG CITY ORDINANCE NO. 2011-01 PARA SA SEKTOR NG TRICYCLE	\N	\N	\N	\N	0	2026-05-26 09:16:46.92	2026-08-14 01:56:57.558971
85	https://yljsclzmrxuhejgcesiv.supabase.co/storage/v1/object/public/media/articles/pwxxhwvdg-1783480905058.webp	image	PHILHEALTH YAKAP, IPINAKILALA SA LIGA NG MGA BARANGAY NG SAN PABLO	\N	\N	\N	\N	0	2026-07-08 03:21:52.948	2026-08-14 01:56:57.558971
89	https://yljsclzmrxuhejgcesiv.supabase.co/storage/v1/object/public/media/articles/csh29skyy-1783481945812.webp	image	ALAMINOS–SAN PABLO BYPASS ROAD, AAKSYUNAN NA	\N	\N	\N	\N	0	2026-07-08 03:39:11.783	2026-08-14 01:56:57.558971
93	https://yljsclzmrxuhejgcesiv.supabase.co/storage/v1/object/public/media/articles/h8li41r8d-1783482843084.webp	image	MAYOR NAJIE, SUPORTADO NG NETIZENS SA PANAWAGANG TAPUSIN ANG SAN PABLO-ALAMINOS BYPASS ROAD	\N	\N	\N	\N	0	2026-07-08 03:54:08.912	2026-08-14 01:56:57.558971
74	https://yljsclzmrxuhejgcesiv.supabase.co/storage/v1/object/public/media/banners/8i8sj2k8r-1781614217451.jpg	image	Antut	\N	\N	\N	\N	0	2026-06-16 12:50:36.967	2026-08-14 01:56:57.558971
65	https://yljsclzmrxuhejgcesiv.supabase.co/storage/v1/object/public/media/banners/lou15lf2i-1781149920435.png	image	\N	\N	\N	\N	\N	0	2026-06-11 03:51:54.907	2026-08-14 01:56:57.558971
7	https://yljsclzmrxuhejgcesiv.supabase.co/storage/v1/object/public/media/articles/1776913047798-m6ri4n65ka.png	image	This is a news title.	\N	\N	\N	\N	0	2026-04-23 02:57:31.776	2026-08-14 01:56:57.558971
66	https://yljsclzmrxuhejgcesiv.supabase.co/storage/v1/object/public/media/articles/plc590np2-1781606778364.jpg	image	BAGONG INVESTMENT SA SPORTS, 2 TENNIS COURTS, BINUKSAN SA SAN PABLO CITY	\N	\N	\N	\N	0	2026-06-16 10:47:59.251	2026-08-14 01:56:57.558971
67	https://yljsclzmrxuhejgcesiv.supabase.co/storage/v1/object/public/media/articles/wz19nq6aq-1781607231137.jpg	image	BAGONG INVESTMENT SA SPORTS, 2 TENNIS COURTS, BINUKSAN SA SAN PABLO CITY	\N	\N	\N	\N	0	2026-06-16 10:54:36.822	2026-08-14 01:56:57.558971
68	https://yljsclzmrxuhejgcesiv.supabase.co/storage/v1/object/public/media/articles/wz19nq6aq-1781607231137.php	image	BAGONG INVESTMENT SA SPORTS, 2 TENNIS COURTS, BINUKSAN SA SAN PABLO CITY	\N	\N	\N	\N	0	2026-06-16 10:59:11.083	2026-08-14 01:56:57.558971
116	https://yljsclzmrxuhejgcesiv.supabase.co/storage/v1/object/public/media/banners/banner-1788244605045-8ypdsqnnc6p.webp	image	\N	45	\N	\N	\N	0	2026-09-01 06:36:49.682	2026-09-01 06:36:49.682
30	https://yljsclzmrxuhejgcesiv.supabase.co/storage/v1/object/public/media/articles/7vc2zfdid-1778552686009.jpg	image	This is a test news articles	\N	\N	\N	\N	0	2026-05-12 02:21:49.264	2026-08-14 01:56:57.558971
31	https://yljsclzmrxuhejgcesiv.supabase.co/storage/v1/object/public/media/banners/lxzebnyjj-1778634209443.webp	image	test banner	\N	\N	\N	\N	0	2026-05-13 01:04:02.935	2026-08-14 01:56:57.558971
32	https://yljsclzmrxuhejgcesiv.supabase.co/storage/v1/object/public/media/banners/amylkzxpt-1779416643944.png	image	\N	\N	\N	\N	\N	0	2026-05-22 02:24:20.718	2026-08-14 01:56:57.558971
34	https://yljsclzmrxuhejgcesiv.supabase.co/storage/v1/object/public/media/articles/rvx7oiggb-1779416792014.png	image	Test news article	\N	\N	\N	\N	0	2026-05-22 02:26:42.335	2026-08-14 01:56:57.558971
35	https://yljsclzmrxuhejgcesiv.supabase.co/storage/v1/object/public/media/articles/jxfz3pdi1-1779416813321.png	image	Test news article 2	\N	\N	\N	\N	0	2026-05-22 02:27:07.52	2026-08-14 01:56:57.558971
96	https://yljsclzmrxuhejgcesiv.supabase.co/storage/v1/object/public/media/articles/12k2vh0pp-1783650907062.webp	image	LIBRENG BIGAS SA MGA SOLO PARENT NG SAN PABLO CITY 	\N	\N	\N	\N	0	2026-07-10 02:35:47.443	2026-08-14 01:56:57.558971
86	https://yljsclzmrxuhejgcesiv.supabase.co/storage/v1/object/public/media/articles/d8c0i3gse-1783481144063.webp	image	STAINLESS NA BASURAHAN PARA SA MAS MALINIS NA SAMPALOK LAKE	\N	\N	\N	\N	0	2026-07-08 03:25:50.461	2026-08-14 01:56:57.558971
90	https://yljsclzmrxuhejgcesiv.supabase.co/storage/v1/object/public/media/articles/s0ns6bb5h-1783482118457.webp	image	11,359 FOOD PACKS, NAIPAMAHAGI SA MGA PWD AT SOLO PARENT SA SAN PABLO CITY	\N	\N	\N	\N	0	2026-07-08 03:42:46.913	2026-08-14 01:56:57.558971
117	https://yljsclzmrxuhejgcesiv.supabase.co/storage/v1/object/public/media/banners/banner-1788253324007-vyy7cxicfz.webp	image	\N	45	\N	\N	\N	0	2026-09-01 09:02:11.053	2026-09-01 09:02:11.053
\.


--
-- Data for Name: offices; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.offices (id, sector, name, head, contact_info, address, sort_order, created_at, updated_at, slug, services, office_no) FROM stdin;
d4222374-b77f-4472-bba1-6ba343e37956	economic	City Mayor's Office - MISO	Christina I. Flores	{"email": "miso@sanpablocity.gov.ph"}	Trece Martirez St. San Pablo City	2	2026-07-24 01:29:49.676512+00	2026-07-24 01:29:49.676512+00	city-mayors-office-miso	{"Issuance of Employee ID Cards for Regular Employees","Issuance of Employee ID Cards for Job Order Employees","Employee ID Card Reprinting","MTOP System Service Request","Preventive Maintenance of Computer Hardware","Monitoring and Maintenance of Operational Applications","Data Verification and Editing","Network Maintenance Request","ICT Equipment and Peripheral Repair","Online Activity Technical Assistance","Onsite System Troubleshooting","Website Content Update","Auditorium Reservation"}	1
3f1be338-b3ea-4588-88eb-459605f1e58b	social	City Indigency Affairs Office	N/A	{}	N/A	14	2026-09-07 00:54:25.418284+00	2026-09-07 00:54:25.418284+00	city-indigency-affairs-office	{"Comprehensive Indigency Assistance Program"}	7
8fb48a8b-45b0-40d8-9686-db71cf915b37	social	City Mayor's Office	Arcadio B. Gapangada Jr.	{"email": "mayor@sanpablocity.gov.ph"}	City Hall Cmpd. Brgy. V-A, San Pablo City	1	2026-07-24 01:29:49.676512+00	2026-07-24 01:29:49.676512+00	city-mayors-office	{"Processing of Requests for Mayor's Signature on Communications","Requests for Social Services Assistance","Various Requests (Scheduling of Appointments with the Mayor)"}	4
16e0376d-e12d-4311-b904-3b81c56e1ea7	economic	City Cooperative Office	Dionisia U. Belen	{"email": "coop@sanpablocity.gov.ph"}	Brgy. V-A, San Pablo City	5	2026-07-24 01:29:49.676512+00	2026-07-24 01:29:49.676512+00	city-cooperative-office	{"Conduct of Pre-Membership Education Seminar","Assistance in Conduct of Cooperative Organizers' Training","Technical Assistance on Bookkeeping and Records Management","Technical Assistance on Online Cooperative Registration","Technical Assistance on Online Report Submission to the Cooperative Development Authority","Provision of Mandatory Trainings"}	18
e86c9a94-05e3-448a-ae87-9d5e37745cef	social	City Mayor's Office - OSCA	Josephine M. Velasco	{"email": "osca@sanpablocity.gov.ph", "contact_no": "049-502-7701"}	Brgy. V-A, San Pablo City	6	2026-07-24 01:29:49.676512+00	2026-07-24 01:29:49.676512+00	city-mayors-office-osca	{"Issuance of Senior Citizen ID Card","Replacement of Lost Senior Citizen ID Card","Issuance of Senior Citizen Purchase Booklet for Medicines","Processing of Incentive Benefits for Octogenarians, Nonagenarians, and Centenarians"}	9
f63e6ffb-a464-4914-ac7d-9dcd68fb38ec	economic	City Mayor's Office - PESO	Pedrito D. Bigueras	{"email": "peso@sanpablocity.gov.ph", "contact_no": "049-503-3112 / 0985-503-6522"}	Mega Capitol Brgy. San Jose, San Pablo City	6	2026-07-24 01:29:49.676512+00	2026-07-24 01:29:49.676512+00	city-mayors-office-peso	{"Acceptance of Job Application Résumés/Biodata","Issuance of Recommendation Letter","Processing of Requests to Conduct Local Recruitment Activities (LRA), Special Recruitment Activities (SRA), and Job Fairs","Issuance of Endorsement Letter for Provincial PESO/OWWA Financial Assistance"}	21
c714d3bb-b96e-40df-8c07-fa983a3ed3ad	institutional	City Information Office	Ernesto H. Empemano	{"email": "cio@sanpablocity.gov.ph", "contact_no": "049-503-5783"}	Brgy. V-A, San Pablo City	8	2026-07-24 01:29:49.676512+00	2026-07-24 01:29:49.676512+00	city-information-office	{"Photo Coverage of City Activities","Video Coverage of City Activities","Publication of the Mayor's and City Government's Announcements on Social Media","Preparation and Publication of City News Releases","Preparation and Publication of Public Announcements and Advisories","Issuance of Certifications, Clearances, and Other Required Documents","Issuance of Oath of Office and Appointment Documents for Barangay Officials","Preparation of City Nutrition Committee (CNC) and Technical Working Group (TWG) Meeting Minutes","Tarpaulin Layout and Design Services","Attendance at Meetings, Hearings, and Sessions","Provision of Data and Information","Endorsement of Requests for Public Documents (Freedom of Information)"}	39
1720bdfd-d185-425f-a20d-2aae4d9a5524	environment	City Environment & Natural Resources Office	Dennis A. Ramos	{"email": "cenro@sanpablocity.gov.ph", "contact_no": "facebook.com/cenro.san.pablo"}	Mega Capitol Brgy. San Jose, San Pablo City	2	2026-07-24 01:29:49.676512+00	2026-07-24 01:29:49.676512+00	city-environment-natural-resources-office	{"Issuance of Online CENRO Certification through ELGU-BPLS for New and Renewal Business Permit Applications","Distribution of Planting Materials for Tree Planting","Response to Complaints Regarding Violations of Environmental Laws","Conduct of Information, Education and Communication (IEC) Campaign on Environmental and Ecological Topics"}	31
8aeddf5e-ae6c-4aac-ab00-36e5cd6651e8	economic	City Agriculturist Office	Abegail F. Agnes	{"email": "agri@sanpablocity.gov.ph"}	Brgy. San Jose, San Pablo City	1	2026-07-24 01:29:49.676512+00	2026-07-24 01:29:49.676512+00	city-agriculturist-office	{"Issuance of Certification for Farmers","Provision of Technical Assistance","Control of Plant Pests and Diseases","Provision of Farming Supplies and Equipment","Distribution of Farming Supplies and Equipment","Livestock Support System","General Farming Assistance"}	17
1116860c-3476-40fc-8202-425f0efe4412	economic	City Mayor's Office - BPLO	John Andre A. Belen	{"email": "bplo@sanpablocity.gov.ph", "contact_no": "049-503-3481"}	One Stop Brgy. V-A, San Pablo City	3	2026-07-24 01:29:49.676512+00	2026-07-24 01:29:49.676512+00	city-mayors-office-bplo	{"Business Permit Renewal","Online Business Permit Renewal","New Business Permit Registration","Online New Business Permit Registration","Tricycle Franchise and Mayor's Permit Application (New/Renewal)","Business Inspection","Issuance of Certifications and Approval of Official Requests","Issuance of Special Mayor's Permit","Amendment of Business Permit and Tricycle Franchise Information","Issuance of Certified True Copy of Business Permit and Tricycle Permit","Business Retirement Processing"}	19
4ca0f3bb-b3ab-4e81-a61d-d835f17bfc2b	economic	City Mayor's Office - LEDIPO	N/A	{"email": "ledipo@sanpablocity.gov.ph"}	N/A	4	2026-07-24 01:29:49.676512+00	2026-07-24 01:29:49.676512+00	city-mayors-office-ledipo	{"Pre-Investment Counseling and Tax Incentive Advisory Services","Processing and Endorsement of Tax Incentive Applications"}	20
b39c8278-7648-47b0-84ca-44d50c77f796	economic	City Tourism Office	Maria Donnalyn E. Briñas	{"email": "tourism@sanpablocity.gov.ph", "contact_no": "049-562-1429"}	Trece Martirez St. San Pablo City	7	2026-07-24 01:29:49.676512+00	2026-07-24 01:29:49.676512+00	city-tourism-office	{"Department of Tourism (DOT) Accreditation - Application for DOT Accreditation of tourism-related businesses","History, Arts, Culture and Research - Provision of research-based knowledge and official publications on the history, arts, and culture of San Pablo City","Tourism-Related Inquiries, Tourist Assistance, and Tourist Arrival Count","Assistance to Tri-Media, Promotions, and City Celebrations/Events","Inquiries on Visits to the San Pablo Museum and Other Historical and Heritage Sites","Research, Teaching, and Interviews","Receiving and Sending of Letters/Correspondence from Various Offices and Agencies","Inspection of Businesses and Trade Related to the Tourism Sector","Requests for Use of Doña Leonila Park by Agencies, Guests, and Citizens"}	22
e1c8a19b-4ce5-4151-8a33-d07587431b50	economic	City Treasurer's Office - Market	N/A	{"email": "publicmarket@sanpablocity.gov.ph", "contact_no": "049-561-1223"}	Brgy. VII-E, San Pablo City	8	2026-07-24 01:29:49.676512+00	2026-07-24 01:29:49.676512+00	city-treasurers-office-market	{"Payment of Market Rent (for fixed stalls/sales booths at SPCSPMP)","Issuance of Market Clearance/Certificate","Application for Temporary Permit (Promotional Selling) at SPCSPMP","Issuance of Parking Privilege Sticker","Basement Parking Fee Payment","Payment of Daily Market Fee (DMF)"}	23
6b097dfb-e43b-410c-84f1-21741ce2de55	economic	City Veterinarian Office	Dra. Fara Jayne C. Orsolino	{"email": "vet@sanpablocity.gov.ph", "contact_no": "049-562-8266"}	Brgy. V-A, San Pablo City	9	2026-07-24 01:29:49.676512+00	2026-07-24 01:29:49.676512+00	city-veterinarian-office	{"Veterinary Services (Disease Control and Prevention, Consultation, Treatment, Vaccination)","Schedule of Vaccination in Different Barangays (Anti-Rabies Vaccination)","Meat Inspection, Market Price Monitoring, and Food Safety Investigation","Animal Transport Permit and Veterinary Health Certificate","Obtaining a Certificate of Death (Documentation of Reported Animal Deaths)","Renewal of Mayor's Permit and Licenses","Management and Maintenance of the Dog Pound","Support and Care Services for Wildlife","Participation in Joint Inspection Team (JIT) Programs Implemented in the City"}	24
b97b7a34-0008-49c4-b344-5774ca3b4a59	infrastructure	City Engineer	Engr. Jasmin M. Monfero	{"email": "engineering@sanpablocity.gov.ph"}	Trece Martirez St. San Pablo City	1	2026-07-24 01:29:49.676512+00	2026-07-24 01:29:49.676512+00	city-engineer	{"Repair and Maintenance of Water Drainage, Manholes and Canals; Clearing of Accumulated Debris; Repair of Buildings and Facilities; Repair of Roads","Review of Applications for Development Permit and Alteration Permit in Accordance with HLURB","Repair and Maintenance of Public Markets and Other Government Structures, Including Electrical Repairs, Installation and Maintenance of Electrical Facilities","Review and Preparation of Plans, Estimates and Work Programs for Various Barangays, Government Offices, Buildings and Other Structures, Including Public School Buildings","Review and Preparation of Bill of Materials Estimates, Work Programs, Inspection Reports and Certifications for Repair and Maintenance of All Government-Owned Vehicles","Preparation of Annual Budget, Annual Procurement Program, Annual Investment Program, Payrolls, Vouchers, Personnel Services and Other Administrative-Related Documents"}	25
c8e1b034-a2c9-4579-af4c-2897b38d3db0	infrastructure	City Mayor's Office - Zoning & Land Use	N/A	{"email": "zoning@sanpablocity.gov.ph", "contact_no": "049-566-9231"}	N/A	3	2026-07-24 01:29:49.676512+00	2026-07-24 01:29:49.676512+00	city-mayors-office-zoning-land-use	{"Issuance of Locational Clearance","Issuance of Zoning Certificate for Business Permit","Issuance of Zoning Certification for Land Classification"}	27
0b0482c6-f618-4e02-b136-72f1f0b1a617	infrastructure	City Planning and Development	Cristina D. Amante	{"email": "planning@sanpablocity.gov.ph"}	Mega Capitol Brgy. San Jose, San Pablo City	4	2026-07-24 01:29:49.676512+00	2026-07-24 01:29:49.676512+00	city-planning-and-development	{"Request for Copies of San Pablo Maps, Comprehensive Land Use Plan, and Economic/Statistical Data","Request for Copies of Monitoring and Evaluation Reports","Validation of Office Performance Commitment Review (OPCR)","Review and Approval of Barangay GAD Plan and Budget","Request for Certification","Preparation of Annual Barangay and/or SK Budget and Supplemental Budget"}	28
9676783d-dc44-4d3a-8102-5c09f90b6041	infrastructure	Office of the City Building Official	Arch. Herbert G. Cartabio	{"email": "obo@sanpablocity.gov.ph"}	Trece Martirez St. San Pablo City	5	2026-07-24 01:29:49.676512+00	2026-07-24 01:29:49.676512+00	office-of-the-city-building-official	{"Issuance of Building Permit (for Residential and Commercial Buildings)","Issuance of Electrical Permit","Issuance of Mechanical Permit","Issuance of Electronics Permit","Issuance of Sanitary/Plumbing Permit","Issuance of Sidewalk Construction Permit","Issuance of Demolition Permit","Issuance of Fencing Permit","Issuance of Permit for Temporary Service Connection","Occupancy Permit","Issuance of Certificate of Annual Inspection for Business Permit"}	29
a8d6adb5-c89e-435b-82e4-4ca3bac3e994	environment	City Disaster Risk Reduction & Management Office	Paul Michael M. Cuadra	{"email": "cdrrmo@sanpablocity.gov.ph", "contact_no": "8000-405 / 0998-540-7171"}	Mega Capitol Brgy. San Jose, San Pablo City	1	2026-07-24 01:29:49.676512+00	2026-07-24 01:29:49.676512+00	city-disaster-risk-reduction-management-office	{"Emergency Situations (Human-Induced: Vehicular Accidents, Drowning Accidents, Fire Incidents, and Other Emergency Situations Requiring First Aid)","Request for Training and Information Dissemination Campaign","Request for Documents (Memorandum, IEC Materials, and Other Related Documents)","Feedback/Comments and Suggestions"}	30
1ad70eef-c05b-4b2c-932c-94a7881d5729	environment	City Solid Waste Management Office	Engr. Ryla A. Nunag	{"email": "solidwaste@sanpablocity.gov.ph"}	Trece Martirez St. San Pablo City	3	2026-07-24 01:29:49.676512+00	2026-07-24 01:29:49.676512+00	city-solid-waste-management-office	{"Issuance of Certificate of Completion for Compliance with Solid Waste Management Orientation","Processing of Clearance for New and Renewal Applications of Business Permits","Processing of Clearance for Tricycle Franchise Applicants","Complaints and Other Services (related to garbage burning, illegal dumping, and garbage collection requests)","Daily Garbage Collection"}	32
08999130-4a96-4c2c-b1bf-9c2d68f10b79	institutional	City Administrator's Office	Rick Jayson A. Tatlong Hari	{"email": "cityadmin@sanpablocity.gov.ph", "contact_no": "049-521-0307"}	3rd Flr. New Governance Bldg. Brgy. V-A, San Pablo City	1	2026-07-24 01:29:49.676512+00	2026-07-24 01:29:49.676512+00	city-administrators-office	{"Issuance of Mayor's Clearance","Provision of Gas Allowance","Signing of Required Documents"}	33
d1944807-92de-4658-a76a-3ad68a26b12c	institutional	City Assessor's Office	Eva F. Punto	{"email": "assessor@sanpablocity.gov.ph", "contact_no": "049-548-4617"}	Mega Capitol Brgy. San Jose, San Pablo City	3	2026-07-24 01:29:49.676512+00	2026-07-24 01:29:49.676512+00	city-assessors-office	{"Issuance of Certified Tax Declaration and Other Certifications","Tracing of Tax Declaration History and Documents","Annotation and Cancellation of Mortgages and Encumbrances on Tax Declaration","Issuance of New Tax Declaration for Transfer of Ownership","Assessment and Appraisal of Real Property","Issuance of Tax Mapping Certificate","Subdivision and Consolidation of Property","Issuance of Tax Declaration for Newly Discovered Real Property"}	34
7fc9ca39-7bc0-4b7d-af9b-96d1dc254cfb	institutional	City Budget Office	Engr. Siegfred I. Palomar	{"email": "budget@sanpablocity.gov.ph", "contact_no": "049-548-1808"}	Mega Capitol Brgy. San Jose, San Pablo City	4	2026-07-24 01:29:49.676512+00	2026-07-24 01:29:49.676512+00	city-budget-office	{"Verification and Certification of Obligation Requests","Transmittal of Reviewed Barangay and SK Annual and Supplemental Budgets to the Sangguniang Panlungsod","Provision of Technical Assistance to Barangays"}	35
996336ef-dcc0-4e2b-ab9f-1e3aab2f8b0c	institutional	City Civil Registrar Office	Victoria G. Maloles	{"email": "civilregistry@sanpablocity.gov.ph", "contact_no": "0918-494-4981"}	Brgy. V-A, San Pablo City	5	2026-07-24 01:29:49.676512+00	2026-07-24 01:29:49.676512+00	city-civil-registrar-office	{"Certification and Issuance of Civil Registry Documents","Registration of Birth","Delayed Registration of Birth","Reporting of Out-of-Town Birth","Registration of Birth Supplemental Report","Application for Marriage License","Registration of Marriage","Delayed Registration of Marriage","Registration of Death","Delayed Registration of Death","Issuance of Burial Permit","Processing of Petitions under R.A. 9048 and R.A. 10172","Registration of Legitimation","Processing of Petition under R.A. 9255","PSA-BREQS Document Request","Registration of Court Decision or Order"}	36
b8865948-51c4-4bfe-960d-ffa00d3928e0	institutional	City General Services Office	Dra. Marianne Criselda D. Belen	{"email": "genservices@sanpablocity.gov.ph", "contact_no": "049-562-0779"}	Trece Martirez St. San Pablo City	6	2026-07-24 01:29:49.676512+00	2026-07-24 01:29:49.676512+00	city-general-services-office	{"Facilitation of Procurement of Government Goods and Services","Custodianship of Government Property","Request for Transfer of Property Accountability","Request for Confirmation of Unified Clearance Certificate Regarding Accountability for Property or Equipment","Request for Return of Waste Materials and Unserviceable Properties","Renewal of Registration of Government-Owned Vehicles with the Land Transportation Office (LTO)","Request for Fuel Allocation for Government Vehicles","Request for Printing Services"}	37
fc8e6a80-1782-4322-a851-65be73c16e68	institutional	City Human Resource Management Office	Elsa M. Barcelona	{"email": "chrmo@sanpablocity.gov.ph"}	Trece Martirez St. San Pablo City	7	2026-07-24 01:29:49.676512+00	2026-07-24 01:29:49.676512+00	city-human-resource-management-office	{"Issuance of Service Records and Certifications","Processing of Terminal Leave and Leave Applications","Loan Application Processing and Approval Assistance","Processing of GSIS Retirement and Separation Benefit Claims","Department Payroll Processing","Office Performance Commitment and Review (OPCR) / Individual Performance Commitment and Review (IPCR)","Job Order Appointment Processing","Recruitment, Selection, and Appointment of Employees","Employee Grievance and Complaint Management"}	38
c9c9b64c-de73-4469-9241-7788e24b6b7c	institutional	City Legal Office	Atty. Joseph Marnic V. De Mesa	{"email": "legal@sanpablocity.gov.ph"}	Brgy. V-A, San Pablo City	9	2026-07-24 01:29:49.676512+00	2026-07-24 01:29:49.676512+00	city-legal-office	{"Receipt and Registration of Incoming Documents and Communications","Preparation and Review of Legal Documents","Legal Consultation and Advice","Preparation of Written Legal Responses"}	40
e503ae99-80ca-4346-b146-171f936bbeda	institutional	City Mayor's Office - Records and Administrative Division	Rizza D. Villaflores	{"email": "cmors@sanpablocity.gov.ph", "contact_no": "049-544-9639"}	One Stop Brgy. V-A, San Pablo City	10	2026-07-24 01:29:49.676512+00	2026-07-24 01:29:49.676512+00	city-mayors-office-records-and-administrative-division	{"Civil Wedding Solemnization","Issuance of Recommendation/Endorsement (Mayor's Endorsement for Work Outside San Pablo)","Issuance of Recommendation/Referral (for Financial Assistance)","Issuance of Recommendation (for Meralco Connection/Reconnection - Government-Owned Land)","Permit to Travel Abroad (for Government Employees)","Application for Burial Permit at the City Cemetery","Application for Exhumation Permit at the City Cemetery","Application for Free Digging at the Himlayang San Pablena Communal Graveyard (Barangay Del Remedio)","Tahanan ng Kabataan ng Laguna / Bahay Pag-asa Endorsement (for Youth Involved in Drugs and Delinquency)","Certification of Unemployment/Low Income (for ESC Scholars)","Certification of Financial Support and Residency (for OFWs)","Certification of Residency (for Overseas Pension Application)"}	41
84245973-184e-4882-98d8-ec2b309c3ae2	institutional	City Prosecutor's Office	Rockefeller G. Cueto	{"email": "cityprosecutors@sanpablocity.gov.ph"}	Brgy. V-A, San Pablo City	11	2026-07-24 01:29:49.676512+00	2026-07-24 01:29:49.676512+00	city-prosecutors-office	{"Receiving of Criminal Complaints for Preliminary Investigation","Receiving of Complaints for Inquest Proceedings","Provision of Prosecutor's Clearance","Provision of Prosecutor's Certification of Case Status and Certified Copy of Documents"}	42
201018da-8092-4138-b658-4cdde0aa7a50	social	City Social Welfare & Development Office	Aida L. Tolentino (OIC)	{"email": "cswdo@sanpablocity.gov.ph", "contact_no": "049-562-1575"}	Brgy. V-A, San Pablo City	9	2026-07-24 01:29:49.676512+00	2026-07-24 01:29:49.676512+00	city-social-welfare-development-office	{"Preparation of Social Case Study Report","Issuance of Certificate of Indigency/Incapacity","Pre-Marriage Counseling","Food Assistance","Technical Assistance/Monitoring for Senior Citizens","Provision of Financial Assistance for Senior Citizens (Social Pension)","Provision of Financial Assistance under Aid to Individuals in Crisis Situation (AICS)","Issuance of Solo Parent Identification Card","Implementation of Early Childhood Care and Development (ECCD) for Pre-Schoolers Aged 3-4","Implementation of Supplemental Feeding Program for Day Care Students","Special Program for Employment of Students (SPES)","Promotion of PhilHealth for the Poor and Needy Families (PhilHealth para sa Masa)",Cash-for-Work,"Community Services for Women and Children in Need of Protection","Provision of Services for Children/Youth in Need of Special Protection (RA 9344 - Children in Conflict with the Law and Children at Risk)","Implementation of RA 9523 (Declaration of a Child Legally Available for Adoption)","Assessment of Minors Traveling with Parents/Non-Parents/Alone (Travel Clearance for Minors)","Capability Building on Laws Concerning Women and Children, Family Development Sessions","Sustainable Livelihood Program (SLP)","Provision of Temporary Residential Care Services (Center for Child Welfare and Protection)"}	12
9088e678-09dc-4f57-a7ad-f852611185a9	social	San Pablo City General Hospital	Dr. Jomer Mendeguarin	{"email": "spcgh@sanpablocity.gov.ph", "contact_no": "049-503-1351"}	Brgy. San Jose, San Pablo City	11	2026-07-24 01:29:49.676512+00	2026-07-24 01:29:49.676512+00	san-pablo-city-general-hospital	{"Outpatient Consultation/Check-up","OB / Prenatal / Gyne Consultation","Dental Consultation and Treatment","Online OPD Consultation (Telemedicine)",Triage,"Emergency Room Consultation","Admission of Sick Patients","Minor Surgery","Admission of Patients for Surgery","Patient Discharge (Ready to Go Home)","Radiology Services - Inpatient","Radiology Services - Outpatient","Laboratory Services for Admitted Patients","Laboratory Services - Outpatient","Preparation and Dispensing of Medicine - Inpatient","Preparation and Dispensing of Medicine - Outpatient","Diet Counseling","Preparation and Distribution of Patient Meals","Preparation and Issuance of Medical Supplies","Issuance of Hospital Bill","Issuance of Official Receipt","Provision of Financial Assistance (for Indigents) and Senior Citizen Discount","Processing of PhilHealth Benefits","Provision of Financial Assistance under Malasakit Center","Issuance of Medical Certificate","Submission of Birth Certificate Records to Civil Registry","Issuance of Certified True Copy of Laboratory and Other Medical Records","Submission of Death Certificate Records to Civil Registry","Issuance of Clean Linen","Reporting of Faulty/Defective Equipment","Receiving of Deliveries (Medicines, Medical Supplies, Equipment)","Receiving of Telephone Calls","Submission of Leave Documents","Filing of Complaints","Request for Transportation Service (Ambulance)"}	14
d5304a1a-173b-402b-841e-702e4a3bf7b3	infrastructure	City Mayor's Office - Urban Housing	Franeliza B. Caston	{"email": "cudho@sanpablocity.gov.ph", "contact_no": "049-561-2322"}	Mega Capitol Brgy. San Jose, San Pablo City	2	2026-07-24 01:29:49.676512+00	2026-07-24 01:29:49.676512+00	city-mayors-office-urban-housing	{"Assistance to Walk-in Clients Regarding Their Housing Status","Issuance of Certification as Informal Settler Family (ISF)","Handling of Housing-Related Complaints","Request for Proof of Deed of Sale","Inspection and Validation of Informal Settler Families (ISF) in Barangays"}	26
736cf448-f4b9-4516-9c66-b4a0e8ddf765	institutional	City Accountant's Office	Arlene M. Beltejar	{"email": "accounting@sanpablocity.gov.ph", "contact_no": "049-548-1533"}	Mega Capitol Brgy. San Jose, San Pablo City	2	2026-07-24 01:29:49.676512+00	2026-07-24 01:29:49.676512+00	city-accountants-office	{"Processing of Disbursement Vouchers and Payroll","Processing of Refunds for Overpayments","Veterans Financial Assistance","Issuance of Certifications","Issuance of Accountant's Advice","Verification of Barangay Financial Reports"}	2
63550830-4d44-47e4-a51d-14f7af59b1a5	social	City Health Office	Dr. Mercydina Abdona M. Caponpon	{"email": "cityhealth@sanpablocity.gov.ph", "contact_no": "049-562-7874"}	Brgy. V-A, San Pablo City	2	2026-07-24 01:29:49.676512+00	2026-07-24 01:29:49.676512+00	city-health-office	{"Issuance of Health Certificate for Food and Non-Food Handlers","Issuance of Medical Certificate for Employment, On-the-Job Training, Loans, Scholarships, and School Admission","Issuance of Medical Certificate for Tricycle Franchise Applicants","Issuance of Medical Certificate for Leave of Absence","Issuance of Medical Certificate for Persons with Disabilities (PWDs)","Issuance of Health Certificate for Entertainment Establishment Workers","Regular Follow-up and Physical Examination for Entertainment Establishment Workers","HIV Counseling and Testing","Consultation and Treatment for Sexually Transmitted Infections (STIs)","Community-Based Mental Health Assessment, Counseling, and Treatment (New Clients Without Prior Treatment)","Community-Based Mental Health Assessment, Counseling, and Treatment (New Clients With Existing Treatment)","Community-Based Mental Health Follow-up Services (Existing Clients)","Issuance of Medical Certificate for Persons Deprived of Liberty (PDLs)","Drug Dependency Counseling and Assessment for Individuals Under Probation","Referral to Community-Based Drug Rehabilitation or Drug Rehabilitation Facilities","Gender Certification and Physical Examination","Physical Injury Certification and Examination","Burial Construction Permit (City Cemetery)","Burial Authorization for Indigent Persons (Himlayang San Pableña Cemetery)","Issuance of Death Certificate (Without Prior Medical Attendance)","Issuance of Death Certificate (With Prior Medical Attendance)","Exhumation Permit","Medico-Legal Postmortem Examination for Vehicular Accident Cases"}	3
491e076e-0b7b-45ac-b859-363a610af5e5	social	City Mayor's Office - CTMO	Marino A. Garcia	{"email": "ctmo@sanpablocity.gov.ph", "contact_no": "049-503-2200 / 049-543-7889"}	One Stop Brgy. V-A, San Pablo City	3	2026-07-24 01:29:49.676512+00	2026-07-24 01:29:49.676512+00	city-mayors-office-ctmo	{"Payment of Traffic Violation Citation","Traffic Complaint Handling","Issuance of Permit for Motorcades, Parades, Fun Runs, and Religious Processions","CCTV Footage Review Request","Seminar for New Tricycle Franchise Applicants"}	5
f55e7763-a3fe-4a96-8215-98d45001f35f	social	City Mayor's Office - GAD	Lourdes B. Bravo	{"email": "gad@sanpablocity.gov.ph"}	Mega Capitol Brgy. V-A	4	2026-07-24 01:29:49.676512+00	2026-07-24 01:29:49.676512+00	city-mayors-office-gad	{"GAD Program Coordination and Monitoring","Receipt and Filing of Obligation Requests (OBR) and Purchase Requests (PR)","Submission and Recording of Barangay GAD Plan and Budget","Submission and Recording of Barangay GAD Accomplishment Reports"}	6
1d04c09b-830b-4f33-971d-851b8773f5be	social	Sports Division	Janquil D. Bumagat	{"email": null}	Mega Capitol Brgy. V-A	5	2026-07-24 01:29:49.676512+00	2026-07-24 01:29:49.676512+00	sports-division	{"Issuance of Permit for Sports Activities and Use of Local Government-Owned Facilities","Endorsement for Grant of Financial Assistance to Athletes and Coaches","Other Requests for Assistance"}	8
deee1bdb-d597-43a8-930a-dfe4e188bb96	social	City Mayor's Office - PDAO	Jimima B. Adao	{"email": "pdao@sanpablocity.gov.ph"}	Brgy. V-A, San Pablo City	7	2026-07-24 01:29:49.676512+00	2026-07-24 01:29:49.676512+00	city-mayors-office-pdao	{"Issuance of Persons with Disability (PWD) Identification Card"}	10
eb324706-8e28-4c9b-b6cb-8272f4528c6e	social	City Population Office	Mylene T. Deriquito	{"email": "citypopulation@sanpablocity.gov.ph"}	Mega Capitol Brgy. V-A	8	2026-07-24 01:29:49.676512+00	2026-07-24 01:29:49.676512+00	city-population-office	{"Provision of Data/Information on Population Management Program and Nutrition Services - Collection, Analysis, and Use of Data on Population and Nutrition Programs","Provision of Supplemental Food for Malnourished Children","Pre-Marriage Orientation and Counseling (PMOC) Seminar"}	11
b479f89a-4026-4b54-b2c0-91d66c800711	social	Dalubhasaang Lungsod ng San Pablo	Dr. Sigfredo D. Adajar	{"email": "dlspadmin@sanpablocity.gov.ph", "contact_no": "049-508-7295"}	Brgy. San Jose, San Pablo City	10	2026-07-24 01:29:49.676512+00	2026-07-24 01:29:49.676512+00	dalubhasaang-lungsod-ng-san-pablo	{}	13
cadb29de-e47c-4657-afd3-cff420c9b627	social	San Pablo City General Hospital - Dialysis	N/A	{"email": "dialysis@sanpablocity.gov.ph"}	Brgy. San Jose, San Pablo City	12	2026-07-24 01:29:49.676512+00	2026-07-24 01:29:49.676512+00	san-pablo-city-general-hospital-dialysis	{Hemodialysis,"Receiving of Deliveries","Filing of Leave","Provision of Diet Counseling"}	15
0dcec7d0-b969-47cc-a2c4-400b9ee2b880	social	Sangguniang Panlungsod - City Library	Ma. Rona C. Remojo	{"email": "citylibrary@sanpablocity.gov.ph"}	Brgy. V-A, San Pablo City	13	2026-07-24 01:29:49.676512+00	2026-07-24 01:29:49.676512+00	sangguniang-panlungsod-city-library	{"Guide to Using and Researching in the Public Library","Application/Registration for Public Library ID (Library Card)","Use of Multimedia and Internet Connection"}	16
3033703e-8882-447b-981d-e6386895f872	institutional	City Treasurer's Office	Lucio Geraldo G. Ciolo	{"email": "treasury@sanpablocity.gov.ph"}	Mega Capitol Brgy. San Jose, San Pablo City	12	2026-07-24 01:29:49.676512+00	2026-07-24 01:29:49.676512+00	city-treasurers-office	{"Issuance of Community Tax Certificate (Cedula)","Payment of Real Property Tax","Issuance of Real Property Tax Payment Certificate","Application/Renewal of Business Permit","Application for Business Retirement (Closure)","Issuance of Certificate of Business Transfer and/or Closure","Payment of Transfer Tax","Inspection and Sealing of Weighing Scales","Calibration and Sealing of Fuel Pumps","Issuance of Sticker for Delivery Van/Truck","Issuance of Professional Tax Receipt and Occupational Tax Receipt","Payment of Franchise Tax for Tricycle-for-Hire","Payment of Service Fees, Fines, and Other Charges","Issuance of Checks and Payment of Salaries and Wages","Recording and Review of Disbursement Vouchers and Purchase Requests","Review and Verification of Community Tax Certificate Reports and Receipts Issued by Barangays","Request for Issuance of Accountable Forms"}	43
01eb1d54-0f1a-4de1-89a6-6f6278ea5e4e	legislative	Office of the Sangguniang Panlungsod	Rufo D. Millar	{"email": "sanggunian@sanpablocity.gov.ph", "contact_no": "049-562-4733"}	Brgy. V-A, San Pablo City	1	2026-07-24 01:29:49.676512+00	2026-07-24 01:29:49.676512+00	office-of-the-sangguniang-panlungsod	{"Providing Information/Consultation on the Legislative Process","Assistance with Research on Filed Documents - Records Section","Issuance of Copies of Requested Public Documents on Record (Resolution, Ordinance, Minutes, Journal, etc.) - Records Division","Processing Requests for Inclusion in the Sangguniang Panlungsod Agenda","Facilitation of Regular/Special Sessions of the Sangguniang Panlungsod","Facilitation of En Banc Hearings of the Sangguniang Panlungsod","Preparation of Journal Draft","Preparation of Final Form of the Journal","Preparation of Draft and Final Form of Approved Resolutions and Ordinances","Preparation of Invitations for Committee Meetings/Hearings","Listing of Agenda Items Referred to Committees","Request for Copy of Meeting Minutes","Preparation of Annual Budget, Annual Investment Program, and Projects for the 20% Development Plan","Preparation of the Annual Procurement Plan","Proper Administration of Employee Leave","Preparation of Payroll","Preparation of Vouchers and Supporting Documents for Bill Payments","Preparation of Documents for Travel/Seminar/Reimbursement Vouchers and Required Supporting Documents","Delivery of Official Documents/Communications/Driving Service","Maintenance of Office Cleanliness"}	44
\.


--
-- Data for Name: publications; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.publications (publication_id, filename, file_path, uploaded_by, created_at, updated_at, is_archived, archived_at) FROM stdin;
27	CS-Form-No.-9-Revised-2025-Request-for-Publication-of-Vacant-Positions-08.10.25.pdf	publications/59biu13it9v-1786352485516.pdf	45	2026-08-10 09:01:27.688	2026-08-10 09:01:27.688	f	\N
\.


--
-- Data for Name: service_standard; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.service_standard (id, description, order_index, file_path, "timestamp") FROM stdin;
4a56daaa-d409-4baa-885c-f6718949ff10	When we go to work, we will come in complete uniform and display our identification cards.	1	service-standard/001.png	2026-07-28 03:29:26.953545+00
77d0c6b5-2821-403e-878f-c5338c554478	We will greet our clients with a sincere smile.	2	service-standard/002.png	2026-07-28 03:29:26.953545+00
d6fbb73e-c62c-4fb5-949a-b5de582c124e	When you enter our office premises, we will introduce ourselves to you so that you can address us back in an appropriate manner.	3	service-standard/003.png	2026-07-28 03:29:26.953545+00
c54ad8a9-2e1d-4907-8937-246a668f05d9	We will attend our clients' inquiries within three (3) minutes.	4	service-standard/004.png	2026-07-28 03:29:26.953545+00
5b4dc2fb-c22c-41f3-bee4-4434aec8e6c8	Appropriate action will immediately follow your queries and you will be referred accordingly.	5	service-standard/005.png	2026-07-28 03:29:26.953545+00
5540f94b-b31a-4f6e-b12f-49fe20a9df45	We will make you comfortable inside our facilities while you wait for your service request.	6	service-standard/006.png	2026-07-28 03:29:26.953545+00
069dca27-9077-4a87-9f55-64d9cfaf4e4f	Express/special lanes are provided for Senior Citizens, pregnant women and People With Disabilities.	7	service-standard/007.png	2026-07-28 03:29:26.953545+00
75769509-3cdc-4c9a-89cc-597fd329b4c6	We will teach the clients, needed requirements that can expedite their service request.	8	service-standard/008.png	2026-07-28 03:29:26.953545+00
4ccce6b9-7d0a-4b47-ae09-d75a42d4bb28	Our service stations will be properly labeled that will include our organizational chart and service flow chart.	10	service-standard/010.png	2026-07-28 03:29:26.953545+00
dd79a821-863c-4377-9e2b-62c0c31c52a2	Directional signs will be displayed conspicuously as guide so that you can establish familiarity with our work place.	11	service-standard/011.png	2026-07-28 03:29:26.953545+00
831652c1-0bc9-4a31-a107-6767c1a34e67	Public Assistance Complaints Desk (PACD) is at your service in strategic locations.	12	service-standard/012.png	2026-07-28 03:29:26.953545+00
0c2190ee-6a3b-4854-9fed-21bb628bfcb1	An information and hotline service is available 24/7 for anyone who has queries.	13	service-standard/013.png	2026-07-28 03:29:26.953545+00
3d3ff723-587a-4561-b37e-0399c52cf4db	No noon-break policy is followed and we are to serve beyond office hours if needed.	14	service-standard/014.png	2026-07-28 03:29:26.953545+00
19755e5d-1373-498f-9984-d79e2846109b	A satisfied client is our happiness in the government service.	15	service-standard/015.png	2026-07-28 03:29:26.953545+00
6ea35d70-438e-4b29-a1e3-65ce2817d08f	We will promptly return your denied request and explain to you the reason for such, which in turn will allow us to reprocess it.	9	service-standard/009.png	2026-07-28 06:27:51.508952+00
\.


--
-- Data for Name: services; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.services (service_id, name, slug, description, requirements, fees, processing_time, online_application_url, created_at, updated_at) FROM stdin;
1	Citizens Charter	citizens-charter	Official citizens charter document for San Pablo City	\N	\N	\N	https://files.sanpablocity.gov.ph/A7d9F3kH2mX0QwL5Z8vR1tY4nP6sB0.pdf	2026-04-23 05:52:27.46974+00	2026-04-23 05:52:27.46974+00
2	Fare Price Matrix	fare-price	Tricycle fare price matrix for San Pablo, Laguna	\N	\N	\N	https://files.sanpablocity.gov.ph/kT7x3qR2pF9L8aM1wV0zN6jH4bE5yC.pdf	2026-04-23 05:52:27.46974+00	2026-04-29 02:17:07.411157+00
\.


--
-- Data for Name: tourism; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.tourism (id, name, tagline, date, href, image, category, sort_order, created_at, updated_at) FROM stdin;
037e50f3-5773-406d-86bc-19e2b1849191	San Pablo Coco Festival	Come home and rediscover San Pablo's New Fiesta	January 12, 2026	https://cocofest.sanpablocity.gov.ph/	coco-festival.webp	festival	1	2026-08-27 03:45:35.957496+00	2026-08-27 03:45:35.957496+00
2ec44cf2-fef5-47d0-984c-e76ef45a8758	Yakap Lawa	Lahat may Kwento sa Lawa	May 9, 2026	https://yakaplawa.sanpablocity.gov.ph/	yakap-lawa.webp	festival	2	2026-08-27 03:45:35.957496+00	2026-08-27 03:45:35.957496+00
3f82184a-ce2a-4b52-a851-309b2036be9a	Gender and Development Portal	San Pablo City's hub for GAD programs, policies, and services	\N	https://sgp.sanpablocity.gov.ph/	sgp-portal.webp	program	3	2026-08-27 03:45:35.957496+00	2026-08-27 03:45:35.957496+00
\.


--
-- Data for Name: transparency; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.transparency (document_id, category, title, date_passed, document_path, status, uploaded_by, created_at, updated_at, is_archived, archived_at) FROM stdin;
28	city-ordinance-&-resolution	test	2026-07-23	transparency/city ordinances & resolution/7jd4h58fodi-1784793841123.pdf	repealed	\N	2026-07-23 08:04:02.923+00	2026-07-23 08:04:14.344+00	t	2026-07-23 08:04:14.344+00
\.


--
-- Data for Name: user_accounts; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.user_accounts (user_id, username, password_hash, role, is_active, last_login, created_at, updated_at, permissions, ba_user_id) FROM stdin;
42	cio.publisher	$2b$10$v6jO9YjIjs/bb4uEVDIkseaFo0RpnOTOot9xOVTB5OL5lanX0rNhO	staff	t	2026-07-09 08:28:40.427	2026-06-29 06:29:58.131	2026-07-15 00:04:56.287803	{news,activity-logs,categories}	\N
45	admin.main	509d0d7f580dfd4cf04e155fddf2ddab:fbe4c92a83a526cfa15fcd1a2fc3edbe9e1f0b56f6b133cc4eed12f865e30f18f6982bde17e43abb777d19c11354ddb12bfffcad6167c7bc10b569e5b0454179	admin	t	2026-09-01 09:01:54.329437	2026-07-27 03:06:38.458162	2026-09-01 09:01:54.329437	{dashboard,banners,news,transparency,downloadable-forms,publications,chatbot,categories,activity-logs,user-management}	d30a1156-bb83-430f-a0b5-8ce5238d9503
46	miso.staff	bebc0b8c8af7f48e582dc70e0b5ceb6b:610b936ef95ccb9d3fffc9afdfa5d5b0a27cf6dd01d00f8fae1545c45906ee6a62b03875ceb189c25404d7f0145f4d9d68afc712d447995eb9424c77c3eaae07	staff	t	2026-07-27 04:40:01.457931	2026-07-27 03:07:19.638	2026-07-27 04:40:01.457931	{banners,news,transparency,downloadable-forms,publications,chatbot,categories,activity-logs}	072d5455-0fa2-4213-b365-4d2899afa4fb
47	miso.access	04714bf2951dcf50b41291e2e5c8c9e7:e89d19e0d00fd8f8a6caa5e91286bd0015d8a85e6a4c283b896b733f04aeef8b60f6344498449b30e3b192c182076c26dea8e2a18996ae3832a184d290e0c3e6	staff	t	2026-08-17 05:24:04.689612	2026-07-27 04:03:15.276	2026-08-17 05:24:04.689612	{banners,activity-logs}	ff0252f9-b771-43a5-aacd-c0a1d93c84b7
\.


--
-- Name: articles_article_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.articles_article_id_seq', 45, true);


--
-- Name: audit_logs_log_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.audit_logs_log_id_seq', 1735, true);


--
-- Name: banners_banner_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.banners_banner_id_seq', 60, true);


--
-- Name: categories_category_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.categories_category_id_seq', 15, true);


--
-- Name: chat_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.chat_id_seq', 208, true);


--
-- Name: chat_messages_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.chat_messages_id_seq', 431, true);


--
-- Name: csm_response_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.csm_response_id_seq', 5, true);


--
-- Name: disclosure_documents_document_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.disclosure_documents_document_id_seq', 28, true);


--
-- Name: events_event_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.events_event_id_seq', 1, false);


--
-- Name: faqs_faq_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.faqs_faq_id_seq', 10, true);


--
-- Name: forms_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.forms_id_seq', 20, true);


--
-- Name: media_media_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.media_media_id_seq', 117, true);


--
-- Name: publications_publication_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.publications_publication_id_seq', 27, true);


--
-- Name: services_service_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.services_service_id_seq', 4, true);


--
-- Name: user_accounts_user_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.user_accounts_user_id_seq', 47, true);


--
-- Name: about_us about_us_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.about_us
    ADD CONSTRAINT about_us_pkey PRIMARY KEY (photo_id);


--
-- Name: articles articles_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.articles
    ADD CONSTRAINT articles_pkey PRIMARY KEY (article_id);


--
-- Name: articles articles_slug_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.articles
    ADD CONSTRAINT articles_slug_key UNIQUE (slug);


--
-- Name: audit_log audit_logs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.audit_log
    ADD CONSTRAINT audit_logs_pkey PRIMARY KEY (log_id);


--
-- Name: ba_account ba_account_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ba_account
    ADD CONSTRAINT ba_account_pkey PRIMARY KEY (id);


--
-- Name: ba_rate_limit ba_rate_limit_key_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ba_rate_limit
    ADD CONSTRAINT ba_rate_limit_key_key UNIQUE (key);


--
-- Name: ba_rate_limit ba_rate_limit_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ba_rate_limit
    ADD CONSTRAINT ba_rate_limit_pkey PRIMARY KEY (id);


--
-- Name: ba_session ba_session_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ba_session
    ADD CONSTRAINT ba_session_pkey PRIMARY KEY (id);


--
-- Name: ba_session ba_session_token_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ba_session
    ADD CONSTRAINT ba_session_token_key UNIQUE (token);


--
-- Name: ba_totp ba_totp_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ba_totp
    ADD CONSTRAINT ba_totp_pkey PRIMARY KEY (id);


--
-- Name: ba_totp ba_totp_user_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ba_totp
    ADD CONSTRAINT ba_totp_user_id_key UNIQUE ("userId");


--
-- Name: ba_user ba_user_email_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ba_user
    ADD CONSTRAINT ba_user_email_key UNIQUE (email);


--
-- Name: ba_user ba_user_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ba_user
    ADD CONSTRAINT ba_user_pkey PRIMARY KEY (id);


--
-- Name: ba_user ba_user_username_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ba_user
    ADD CONSTRAINT ba_user_username_key UNIQUE (username);


--
-- Name: ba_verification ba_verification_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ba_verification
    ADD CONSTRAINT ba_verification_pkey PRIMARY KEY (id);


--
-- Name: banners banners_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.banners
    ADD CONSTRAINT banners_pkey PRIMARY KEY (banner_id);


--
-- Name: categories categories_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.categories
    ADD CONSTRAINT categories_pkey PRIMARY KEY (category_id);


--
-- Name: categories categories_slug_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.categories
    ADD CONSTRAINT categories_slug_key UNIQUE (slug);


--
-- Name: chat_messages chat_messages_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.chat_messages
    ADD CONSTRAINT chat_messages_pkey PRIMARY KEY (id);


--
-- Name: conversations chat_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.conversations
    ADD CONSTRAINT chat_pkey PRIMARY KEY (id);


--
-- Name: csm_response csm_response_control_no_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.csm_response
    ADD CONSTRAINT csm_response_control_no_key UNIQUE (control_no);


--
-- Name: csm_response csm_response_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.csm_response
    ADD CONSTRAINT csm_response_pkey PRIMARY KEY (id);


--
-- Name: transparency disclosure_documents_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.transparency
    ADD CONSTRAINT disclosure_documents_pkey PRIMARY KEY (document_id);


--
-- Name: epacd_rate_limit epacd_rate_limit_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.epacd_rate_limit
    ADD CONSTRAINT epacd_rate_limit_pkey PRIMARY KEY (id);


--
-- Name: events events_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.events
    ADD CONSTRAINT events_pkey PRIMARY KEY (event_id);


--
-- Name: faqs faqs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.faqs
    ADD CONSTRAINT faqs_pkey PRIMARY KEY (faq_id);


--
-- Name: forms forms_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.forms
    ADD CONSTRAINT forms_pkey PRIMARY KEY (id);


--
-- Name: map map_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.map
    ADD CONSTRAINT map_pkey PRIMARY KEY (id);


--
-- Name: media media_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.media
    ADD CONSTRAINT media_pkey PRIMARY KEY (media_id);


--
-- Name: offices offices_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.offices
    ADD CONSTRAINT offices_pkey PRIMARY KEY (id);


--
-- Name: offices offices_slug_unique; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.offices
    ADD CONSTRAINT offices_slug_unique UNIQUE (slug);


--
-- Name: publications publications_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.publications
    ADD CONSTRAINT publications_pkey PRIMARY KEY (publication_id);


--
-- Name: service_standard service_standard_order_index_unique; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.service_standard
    ADD CONSTRAINT service_standard_order_index_unique UNIQUE (order_index);


--
-- Name: service_standard service_standard_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.service_standard
    ADD CONSTRAINT service_standard_pkey PRIMARY KEY (id);


--
-- Name: services services_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.services
    ADD CONSTRAINT services_pkey PRIMARY KEY (service_id);


--
-- Name: services services_slug_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.services
    ADD CONSTRAINT services_slug_key UNIQUE (slug);


--
-- Name: tourism tourism_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tourism
    ADD CONSTRAINT tourism_pkey PRIMARY KEY (id);


--
-- Name: user_accounts user_accounts_ba_user_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_accounts
    ADD CONSTRAINT user_accounts_ba_user_id_key UNIQUE (ba_user_id);


--
-- Name: user_accounts user_accounts_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_accounts
    ADD CONSTRAINT user_accounts_pkey PRIMARY KEY (user_id);


--
-- Name: user_accounts user_accounts_username_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_accounts
    ADD CONSTRAINT user_accounts_username_key UNIQUE (username);


--
-- Name: chat_created_at_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX chat_created_at_idx ON public.conversations USING btree (created_at DESC);


--
-- Name: chat_email_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX chat_email_idx ON public.conversations USING btree (email);


--
-- Name: chat_status_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX chat_status_idx ON public.conversations USING btree (status);


--
-- Name: epacd_rate_limit_ip_created_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX epacd_rate_limit_ip_created_idx ON public.epacd_rate_limit USING btree (ip_address, created_at);


--
-- Name: idx_articles_category; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_articles_category ON public.articles USING btree (category_id);


--
-- Name: idx_articles_published; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_articles_published ON public.articles USING btree (published_at);


--
-- Name: idx_articles_slug; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_articles_slug ON public.articles USING btree (slug);


--
-- Name: idx_articles_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_articles_status ON public.articles USING btree (status);


--
-- Name: idx_audit_created; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_audit_created ON public.audit_log USING btree (created_at);


--
-- Name: idx_audit_entity; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_audit_entity ON public.audit_log USING btree (entity_type, entity_id);


--
-- Name: idx_audit_user; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_audit_user ON public.audit_log USING btree (user_id);


--
-- Name: idx_ba_account_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ba_account_user_id ON public.ba_account USING btree ("userId");


--
-- Name: idx_ba_rate_limit_key; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ba_rate_limit_key ON public.ba_rate_limit USING btree (key);


--
-- Name: idx_ba_session_token; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ba_session_token ON public.ba_session USING btree (token);


--
-- Name: idx_ba_session_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ba_session_user_id ON public.ba_session USING btree ("userId");


--
-- Name: idx_ba_totp_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ba_totp_user_id ON public.ba_totp USING btree ("userId");


--
-- Name: idx_ba_user_username; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ba_user_username ON public.ba_user USING btree (username);


--
-- Name: idx_categories_parent; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_categories_parent ON public.categories USING btree (parent_category_id);


--
-- Name: idx_categories_slug; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_categories_slug ON public.categories USING btree (slug);


--
-- Name: idx_chat_messages_conversation_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_chat_messages_conversation_id ON public.chat_messages USING btree (conversation_id);


--
-- Name: idx_chat_messages_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_chat_messages_created_at ON public.chat_messages USING btree (created_at);


--
-- Name: idx_chat_messages_has_attachment; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_chat_messages_has_attachment ON public.chat_messages USING btree (conversation_id) WHERE (attachment_url IS NOT NULL);


--
-- Name: idx_conversations_visitor_token; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_conversations_visitor_token ON public.conversations USING btree (visitor_token);


--
-- Name: idx_csm_response_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_csm_response_created_at ON public.csm_response USING btree (created_at DESC);


--
-- Name: idx_csm_response_office_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_csm_response_office_id ON public.csm_response USING btree (office_id);


--
-- Name: idx_disclosure_category_date_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_disclosure_category_date_status ON public.transparency USING btree (category, status, date_passed DESC);


--
-- Name: idx_disclosure_date_passed; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_disclosure_date_passed ON public.transparency USING btree (date_passed);


--
-- Name: idx_forms_archived_category_date; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_forms_archived_category_date ON public.forms USING btree (category, is_archived, date_issued DESC);


--
-- Name: idx_forms_is_archived; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_forms_is_archived ON public.forms USING btree (is_archived);


--
-- Name: idx_map_offices; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_map_offices ON public.map USING gin (offices);


--
-- Name: idx_media_article; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_media_article ON public.media USING btree (related_article_id);


--
-- Name: idx_media_uploaded; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_media_uploaded ON public.media USING btree (uploaded_by);


--
-- Name: idx_offices_office_no; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_offices_office_no ON public.offices USING btree (office_no);


--
-- Name: idx_offices_slug; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_offices_slug ON public.offices USING btree (slug);


--
-- Name: idx_publications_archived_created; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_publications_archived_created ON public.publications USING btree (is_archived, created_at DESC);


--
-- Name: idx_publications_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_publications_created_at ON public.publications USING btree (created_at);


--
-- Name: idx_publications_is_archived; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_publications_is_archived ON public.publications USING btree (is_archived);


--
-- Name: idx_publications_title; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_publications_title ON public.publications USING btree (filename);


--
-- Name: idx_service_standard_order_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_service_standard_order_index ON public.service_standard USING btree (order_index);


--
-- Name: idx_services_slug; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_services_slug ON public.services USING btree (slug);


--
-- Name: idx_transparency_archived_category_date; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_transparency_archived_category_date ON public.transparency USING btree (category, is_archived, date_passed DESC);


--
-- Name: idx_transparency_is_archived; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_transparency_is_archived ON public.transparency USING btree (is_archived);


--
-- Name: idx_user_accounts_ba_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_user_accounts_ba_user_id ON public.user_accounts USING btree (ba_user_id);


--
-- Name: idx_users_role; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_users_role ON public.user_accounts USING btree (role);


--
-- Name: idx_users_username; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_users_username ON public.user_accounts USING btree (username);


--
-- Name: offices_sector_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX offices_sector_idx ON public.offices USING btree (sector, sort_order);


--
-- Name: about_us about_us_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER about_us_updated_at BEFORE UPDATE ON public.about_us FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: map map_set_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER map_set_updated_at BEFORE UPDATE ON public.map FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: csm_response trg_csm_response_set_control_no; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_csm_response_set_control_no BEFORE INSERT OR UPDATE OF office_id ON public.csm_response FOR EACH ROW EXECUTE FUNCTION public.csm_response_set_control_no();


--
-- Name: csm_response trg_csm_response_sync_office_name; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_csm_response_sync_office_name BEFORE INSERT OR UPDATE OF office_id ON public.csm_response FOR EACH ROW EXECUTE FUNCTION public.csm_response_sync_office_name();


--
-- Name: faqs trg_faqs_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_faqs_updated_at BEFORE UPDATE ON public.faqs FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: offices trg_offices_cascade_name_to_csm_response; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_offices_cascade_name_to_csm_response AFTER UPDATE OF name ON public.offices FOR EACH ROW EXECUTE FUNCTION public.offices_cascade_name_to_csm_response();


--
-- Name: offices trg_offices_set_slug; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_offices_set_slug BEFORE INSERT OR UPDATE OF name ON public.offices FOR EACH ROW EXECUTE FUNCTION public.offices_set_slug();


--
-- Name: services trg_services_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_services_updated_at BEFORE UPDATE ON public.services FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: tourism trg_tourism_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_tourism_updated_at BEFORE UPDATE ON public.tourism FOR EACH ROW EXECUTE FUNCTION public.set_tourism_updated_at();


--
-- Name: ba_account update_ba_account_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER update_ba_account_updated_at BEFORE UPDATE ON public.ba_account FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();


--
-- Name: ba_session update_ba_session_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER update_ba_session_updated_at BEFORE UPDATE ON public.ba_session FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();


--
-- Name: ba_totp update_ba_totp_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER update_ba_totp_updated_at BEFORE UPDATE ON public.ba_totp FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();


--
-- Name: ba_user update_ba_user_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER update_ba_user_updated_at BEFORE UPDATE ON public.ba_user FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();


--
-- Name: user_accounts update_user_accounts_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER update_user_accounts_updated_at BEFORE UPDATE ON public.user_accounts FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();


--
-- Name: articles articles_category_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.articles
    ADD CONSTRAINT articles_category_id_fkey FOREIGN KEY (category_id) REFERENCES public.categories(category_id) ON DELETE SET NULL;


--
-- Name: articles articles_featured_media_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.articles
    ADD CONSTRAINT articles_featured_media_id_fkey FOREIGN KEY (featured_media_id) REFERENCES public.media(media_id) ON DELETE SET NULL;


--
-- Name: audit_log audit_logs_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.audit_log
    ADD CONSTRAINT audit_logs_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.user_accounts(user_id) ON DELETE SET NULL;


--
-- Name: ba_account ba_account_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ba_account
    ADD CONSTRAINT ba_account_user_id_fkey FOREIGN KEY ("userId") REFERENCES public.ba_user(id) ON DELETE CASCADE;


--
-- Name: ba_session ba_session_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ba_session
    ADD CONSTRAINT ba_session_user_id_fkey FOREIGN KEY ("userId") REFERENCES public.ba_user(id) ON DELETE CASCADE;


--
-- Name: ba_totp ba_totp_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ba_totp
    ADD CONSTRAINT ba_totp_user_id_fkey FOREIGN KEY ("userId") REFERENCES public.ba_user(id) ON DELETE CASCADE;


--
-- Name: banners banners_image_media_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.banners
    ADD CONSTRAINT banners_image_media_id_fkey FOREIGN KEY (image_media_id) REFERENCES public.media(media_id) ON DELETE SET NULL;


--
-- Name: categories categories_parent_category_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.categories
    ADD CONSTRAINT categories_parent_category_id_fkey FOREIGN KEY (parent_category_id) REFERENCES public.categories(category_id) ON DELETE SET NULL;


--
-- Name: chat_messages chat_messages_conversation_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.chat_messages
    ADD CONSTRAINT chat_messages_conversation_id_fkey FOREIGN KEY (conversation_id) REFERENCES public.conversations(id) ON DELETE CASCADE;


--
-- Name: chat_messages chat_messages_sender_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.chat_messages
    ADD CONSTRAINT chat_messages_sender_id_fkey FOREIGN KEY (sender_id) REFERENCES public.user_accounts(user_id) ON DELETE SET NULL;


--
-- Name: conversations conversations_assigned_to_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.conversations
    ADD CONSTRAINT conversations_assigned_to_fkey FOREIGN KEY (assigned_to) REFERENCES public.user_accounts(user_id) ON DELETE SET NULL;


--
-- Name: csm_response csm_response_office_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.csm_response
    ADD CONSTRAINT csm_response_office_id_fkey FOREIGN KEY (office_id) REFERENCES public.offices(id);


--
-- Name: transparency disclosure_documents_uploaded_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.transparency
    ADD CONSTRAINT disclosure_documents_uploaded_by_fkey FOREIGN KEY (uploaded_by) REFERENCES public.user_accounts(user_id) ON DELETE SET NULL;


--
-- Name: media media_related_banner_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.media
    ADD CONSTRAINT media_related_banner_id_fkey FOREIGN KEY (related_banner_id) REFERENCES public.banners(banner_id) ON DELETE CASCADE;


--
-- Name: media media_related_event_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.media
    ADD CONSTRAINT media_related_event_id_fkey FOREIGN KEY (related_event_id) REFERENCES public.events(event_id) ON DELETE CASCADE;


--
-- Name: media media_uploaded_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.media
    ADD CONSTRAINT media_uploaded_by_fkey FOREIGN KEY (uploaded_by) REFERENCES public.user_accounts(user_id) ON DELETE SET NULL;


--
-- Name: publications publications_uploaded_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.publications
    ADD CONSTRAINT publications_uploaded_by_fkey FOREIGN KEY (uploaded_by) REFERENCES public.user_accounts(user_id) ON DELETE SET NULL;


--
-- Name: offices Admins and publishers can manage offices; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Admins and publishers can manage offices" ON public.offices USING ((auth.role() = 'authenticated'::text)) WITH CHECK ((auth.role() = 'authenticated'::text));


--
-- Name: articles Allow all on articles; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Allow all on articles" ON public.articles USING (true) WITH CHECK (true);


--
-- Name: audit_log Allow all on audit_log; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Allow all on audit_log" ON public.audit_log USING (true) WITH CHECK (true);


--
-- Name: banners Allow all on banners; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Allow all on banners" ON public.banners USING (true) WITH CHECK (true);


--
-- Name: categories Allow all on categories; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Allow all on categories" ON public.categories USING (true) WITH CHECK (true);


--
-- Name: events Allow all on events; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Allow all on events" ON public.events USING (true) WITH CHECK (true);


--
-- Name: media Allow all on media; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Allow all on media" ON public.media USING (true) WITH CHECK (true);


--
-- Name: publications Allow all on publications; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Allow all on publications" ON public.publications USING (true) WITH CHECK (true);


--
-- Name: user_accounts Allow all on user_accounts; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Allow all on user_accounts" ON public.user_accounts USING (true) WITH CHECK (true);


--
-- Name: audit_log Allow anon read audit_log; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Allow anon read audit_log" ON public.audit_log FOR SELECT TO anon USING (true);


--
-- Name: conversations Allow anonymous insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Allow anonymous insert" ON public.conversations FOR INSERT TO anon WITH CHECK (true);


--
-- Name: conversations Allow authenticated read/write; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Allow authenticated read/write" ON public.conversations TO authenticated USING (true);


--
-- Name: user_accounts Allow login lookup; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Allow login lookup" ON public.user_accounts FOR SELECT USING (true);


--
-- Name: forms Allow public read access for active forms; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Allow public read access for active forms" ON public.forms FOR SELECT TO anon USING ((status = 'active'::text));


--
-- Name: conversations Allow read access; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Allow read access" ON public.conversations FOR SELECT USING (true);


--
-- Name: about_us Authenticated users can manage about_us; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Authenticated users can manage about_us" ON public.about_us USING ((auth.role() = 'authenticated'::text));


--
-- Name: about_us Public can read about_us; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Public can read about_us" ON public.about_us FOR SELECT USING (true);


--
-- Name: transparency Public can read active disclosure documents; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Public can read active disclosure documents" ON public.transparency FOR SELECT TO anon USING (((status)::text = 'active'::text));


--
-- Name: articles Public can read articles; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Public can read articles" ON public.articles FOR SELECT USING (true);


--
-- Name: banners Public can read banners; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Public can read banners" ON public.banners FOR SELECT USING (true);


--
-- Name: categories Public can read categories; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Public can read categories" ON public.categories FOR SELECT USING (true);


--
-- Name: events Public can read events; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Public can read events" ON public.events FOR SELECT USING (true);


--
-- Name: media Public can read media; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Public can read media" ON public.media FOR SELECT USING (true);


--
-- Name: offices Public can read offices; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Public can read offices" ON public.offices FOR SELECT USING (true);


--
-- Name: publications Public can read publications; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Public can read publications" ON public.publications FOR SELECT USING (true);


--
-- Name: tourism Public read access; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Public read access" ON public.tourism FOR SELECT TO authenticated, anon USING (true);


--
-- Name: service_standard Public read access on service_standard; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Public read access on service_standard" ON public.service_standard FOR SELECT USING (true);


--
-- Name: audit_log Service role full access to audit_log; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Service role full access to audit_log" ON public.audit_log TO service_role USING (true) WITH CHECK (true);


--
-- Name: transparency Service role has full access; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Service role has full access" ON public.transparency TO service_role USING (true) WITH CHECK (true);


--
-- Name: about_us; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.about_us ENABLE ROW LEVEL SECURITY;

--
-- Name: chat_messages anon can insert visitor messages; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "anon can insert visitor messages" ON public.chat_messages FOR INSERT TO anon WITH CHECK ((sender_type = 'visitor'::text));


--
-- Name: chat_messages anon can read messages by conversation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "anon can read messages by conversation" ON public.chat_messages FOR SELECT TO anon USING (true);


--
-- Name: articles; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.articles ENABLE ROW LEVEL SECURITY;

--
-- Name: audit_log; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.audit_log ENABLE ROW LEVEL SECURITY;

--
-- Name: faqs authenticated users can manage faqs; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "authenticated users can manage faqs" ON public.faqs TO authenticated USING (true) WITH CHECK (true);


--
-- Name: services authenticated users can manage services; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "authenticated users can manage services" ON public.services TO authenticated USING (true) WITH CHECK (true);


--
-- Name: banners; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.banners ENABLE ROW LEVEL SECURITY;

--
-- Name: categories; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.categories ENABLE ROW LEVEL SECURITY;

--
-- Name: chat_messages; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.chat_messages ENABLE ROW LEVEL SECURITY;

--
-- Name: conversations; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.conversations ENABLE ROW LEVEL SECURITY;

--
-- Name: csm_response; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.csm_response ENABLE ROW LEVEL SECURITY;

--
-- Name: epacd_rate_limit; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.epacd_rate_limit ENABLE ROW LEVEL SECURITY;

--
-- Name: events; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.events ENABLE ROW LEVEL SECURITY;

--
-- Name: faqs; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.faqs ENABLE ROW LEVEL SECURITY;

--
-- Name: forms; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.forms ENABLE ROW LEVEL SECURITY;

--
-- Name: map; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.map ENABLE ROW LEVEL SECURITY;

--
-- Name: map map_public_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY map_public_read ON public.map FOR SELECT USING (true);


--
-- Name: media; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.media ENABLE ROW LEVEL SECURITY;

--
-- Name: offices; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.offices ENABLE ROW LEVEL SECURITY;

--
-- Name: faqs public can read faqs; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "public can read faqs" ON public.faqs FOR SELECT USING (true);


--
-- Name: services public can read services; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "public can read services" ON public.services FOR SELECT USING (true);


--
-- Name: publications; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.publications ENABLE ROW LEVEL SECURITY;

--
-- Name: service_standard; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.service_standard ENABLE ROW LEVEL SECURITY;

--
-- Name: services; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.services ENABLE ROW LEVEL SECURITY;

--
-- Name: tourism; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.tourism ENABLE ROW LEVEL SECURITY;

--
-- Name: transparency; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.transparency ENABLE ROW LEVEL SECURITY;

--
-- Name: user_accounts; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.user_accounts ENABLE ROW LEVEL SECURITY;

--
-- PostgreSQL database dump complete
--

\unrestrict vvVeTqdkgejtKKZKGiQossZQEnLzcciDmlBfkrG3LW2CkSMAkJwxngG509sIFVJ

