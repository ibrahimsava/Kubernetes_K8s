--
-- PostgreSQL database dump
--

\restrict VS1VVJJhuNfgguxegdLx8oYEvlcygH6DKzeHLZSki4vWmh9w0OuY5zKfznXHknJ

-- Dumped from database version 16.15
-- Dumped by pg_dump version 16.15

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: produits; Type: TABLE; Schema: public; Owner: boutique_app
--

CREATE TABLE public.produits (
    id integer NOT NULL,
    nom text,
    prix numeric
);


ALTER TABLE public.produits OWNER TO boutique_app;

--
-- Name: produits_id_seq; Type: SEQUENCE; Schema: public; Owner: boutique_app
--

CREATE SEQUENCE public.produits_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.produits_id_seq OWNER TO boutique_app;

--
-- Name: produits_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: boutique_app
--

ALTER SEQUENCE public.produits_id_seq OWNED BY public.produits.id;


--
-- Name: produits id; Type: DEFAULT; Schema: public; Owner: boutique_app
--

ALTER TABLE ONLY public.produits ALTER COLUMN id SET DEFAULT nextval('public.produits_id_seq'::regclass);


--
-- Data for Name: produits; Type: TABLE DATA; Schema: public; Owner: boutique_app
--

COPY public.produits (id, nom, prix) FROM stdin;
1	Clavier	25
2	Souris	12
\.


--
-- Name: produits_id_seq; Type: SEQUENCE SET; Schema: public; Owner: boutique_app
--

SELECT pg_catalog.setval('public.produits_id_seq', 2, true);


--
-- Name: produits produits_pkey; Type: CONSTRAINT; Schema: public; Owner: boutique_app
--

ALTER TABLE ONLY public.produits
    ADD CONSTRAINT produits_pkey PRIMARY KEY (id);


--
-- PostgreSQL database dump complete
--

\unrestrict VS1VVJJhuNfgguxegdLx8oYEvlcygH6DKzeHLZSki4vWmh9w0OuY5zKfznXHknJ

