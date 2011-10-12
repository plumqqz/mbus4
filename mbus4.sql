--
-- PostgreSQL database dump
--

-- Dumped from database version 9.0.4
-- Dumped by pg_dump version 9.1beta2
-- Started on 2011-10-11 15:00:54

SET statement_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = off;
SET check_function_bodies = false;
SET client_min_messages = warning;
SET escape_string_warning = off;

--
-- TOC entry 8 (class 2615 OID 76767)
-- Name: mbus4; Type: SCHEMA; Schema: -; Owner: postgres
--

CREATE SCHEMA mbus4;


ALTER SCHEMA mbus4 OWNER TO postgres;

SET search_path = mbus4, pg_catalog;

SET default_tablespace = '';

SET default_with_oids = false;

--
-- TOC entry 2716 (class 1259 OID 76769)
-- Dependencies: 8 1170 1170 1170
-- Name: qt_model; Type: TABLE; Schema: mbus4; Owner: postgres; Tablespace: 
--

CREATE TABLE qt_model (
    id integer NOT NULL,
    added timestamp without time zone NOT NULL,
    iid text NOT NULL,
    delayed_until timestamp without time zone NOT NULL,
    expires timestamp without time zone,
    received integer[],
    headers hstore,
    properties hstore,
    data hstore
);


ALTER TABLE mbus4.qt_model OWNER TO postgres;

--
-- TOC entry 852 (class 1255 OID 79613)
-- Dependencies: 1230 8 1174
-- Name: build_users_record_consumer_list(qt_model); Type: FUNCTION; Schema: mbus4; Owner: postgres
--

CREATE FUNCTION build_users_record_consumer_list(qr qt_model) RETURNS integer[]
    LANGUAGE plpgsql
    AS $$
       begin
         return array( 
         with t as (select qr.*)
          select 207 from t where 
           ( (1=1) and t.added > '2011-09-26 16:45:41.996333'::timestamp without time zone) );
       end;
      $$;


ALTER FUNCTION mbus4.build_users_record_consumer_list(qr qt_model) OWNER TO postgres;

--
-- TOC entry 830 (class 1255 OID 79605)
-- Dependencies: 8 1230
-- Name: clear_queue_users(); Type: FUNCTION; Schema: mbus4; Owner: postgres
--

CREATE FUNCTION clear_queue_users() RETURNS void
    LANGUAGE plpgsql
    AS $_$
declare
 qry text;
begin
 select string_agg( 'select id from mbus4.consumer where id=' || id::text ||' and ( (' || r.selector || ')' || (case when r.added is null then ')' else $$ and q.added > '$$ || (r.added::text) || $$'::timestamp without time zone)$$ end) ||chr(10), ' union all '||chr(10))
  into qry
  from mbus4.consumer r where qname='users';
 execute 'delete from mbus4.qt$users q where expires < now() or (received @> array(' || qry || '))';
end; 
$_$;


ALTER FUNCTION mbus4.clear_queue_users() OWNER TO postgres;

--
-- TOC entry 807 (class 1255 OID 76768)
-- Dependencies: 8
-- Name: clear_tempq(); Type: FUNCTION; Schema: mbus4; Owner: postgres
--

CREATE FUNCTION clear_tempq() RETURNS void
    LANGUAGE sql
    AS $$
 delete from mbus4.tempq where not exists (select * from pg_stat_activity where (headers->'tempq') like 'temp.' || md5(procpid::text || backend_start::text) || '%');
$$;


ALTER FUNCTION mbus4.clear_tempq() OWNER TO postgres;

--
-- TOC entry 851 (class 1255 OID 79612)
-- Dependencies: 1230 8 1174
-- Name: consume(text, text); Type: FUNCTION; Schema: mbus4; Owner: postgres
--

CREATE FUNCTION consume(qname text, cname text DEFAULT 'default'::text) RETURNS SETOF qt_model
    LANGUAGE plpgsql
    AS $_$
        begin
          if qname like 'temp.%' then
            return query select * from mbus4.consume_temp(qname);
            return;
          end if;
         case lower(qname)
         when 'users' then case lower(cname)  when 'default' then return query select * from mbus4.consume_users_by_default(); return; else raise exception $$unknown consumer:%$$, consumer; end case;

         end case;
        end;
        $_$;


ALTER FUNCTION mbus4.consume(qname text, cname text) OWNER TO postgres;

--
-- TOC entry 808 (class 1255 OID 76775)
-- Dependencies: 8 1174 1230
-- Name: consume_temp(text); Type: FUNCTION; Schema: mbus4; Owner: postgres
--

CREATE FUNCTION consume_temp(tqname text) RETURNS SETOF qt_model
    LANGUAGE plpgsql
    AS $$
declare
 rv mbus4.qt_model;
begin
 select * into rv from mbus4.tempq where (headers->'tempq')=tqname and coalesce(expires,'2070-01-01'::timestamp)>now()::timestamp and coalesce(delayed_until,'1970-01-01'::timestamp)<now()::timestamp order by added limit 1;
 if rv.id is not null then
    delete from mbus4.tempq where iid=rv.iid;
    return next rv;
 end if;   
 return;
end;
$$;


ALTER FUNCTION mbus4.consume_temp(tqname text) OWNER TO postgres;

--
-- TOC entry 832 (class 1255 OID 79607)
-- Dependencies: 1174 1230 8
-- Name: consume_users_by_default(); Type: FUNCTION; Schema: mbus4; Owner: postgres
--

CREATE FUNCTION consume_users_by_default() RETURNS SETOF qt_model
    LANGUAGE plpgsql
    AS $_$
declare
 rv mbus4.qt_model;
 c_id int;
 pn int;
 cnt int;
 r record;
 gotrecord boolean:=false;
begin
 set local enable_seqscan=off;

  if version() like 'PostgreSQL 9.0%' then
     for r in 
      select * 
        from mbus4.qt$users t
       where 207<>all(received) and t.delayed_until<now() and (1=1)=true and added >'2011-09-26 16:45:41.996333' and coalesce(expires,'2070-01-01'::timestamp) > now()::timestamp 
       order by added, delayed_until
       limit 64
      loop
        begin
          select * into rv from mbus4.qt$users t where t.iid=r.iid and 207<>all(received) for update nowait;
          continue when not found;
          gotrecord:=true;
          exit;
        exception
         when lock_not_available then null;
        end;
      end loop;
  else
     for r in 
      select * 
        from mbus4.qt$users t
       where 207<>all(received) and t.delayed_until<now() and (1=1)=true and added > '2011-09-26 16:45:41.996333' and coalesce(expires,'2070-01-01'::timestamp) > now()::timestamp 
       order by added, delayed_until
       limit 64
      loop
        if pg_try_advisory_xact_lock( ('X' || md5('mbus4.qt$users.' || r.iid))::bit(64)::bigint ) then
          select * into rv from mbus4.qt$users t where t.iid=r.iid and 207<>all(received) for update;
          continue when not found;
          gotrecord:=true;
          exit;
        end if;
      end loop;
  end if;


 if gotrecord then 
    if mbus4.build_users_record_consumer_list(rv) <@ (rv.received || 207) then
      delete from mbus4.qt$users where iid = rv.iid;
    else
      update mbus4.qt$users t set received=received || 207 where t.iid=rv.iid;
    end if;
    rv.headers = rv.headers || hstore('destination','users');
    return next rv;
    return;
 end if; 
end;
$_$;


ALTER FUNCTION mbus4.consume_users_by_default() OWNER TO postgres;

--
-- TOC entry 848 (class 1255 OID 79608)
-- Dependencies: 8 1230 1174
-- Name: consumen_users_by_default(integer); Type: FUNCTION; Schema: mbus4; Owner: postgres
--

CREATE FUNCTION consumen_users_by_default(amt integer) RETURNS SETOF qt_model
    LANGUAGE plpgsql
    AS $_$
declare
 rv mbus4.qt_model;
 rvarr mbus4.qt_model[];
 c_id int;
 pn int;
 cnt int;
 r record;
 inloop boolean;
 trycnt integer:=0;
begin
 set local enable_seqscan=off;

 rvarr:=array[]::mbus4.qt_model[];
 <<mainloop>>
 while coalesce(array_length(rvarr,1),0)<amt loop
  
   inloop:=false;
   for r in select * 
              from mbus4.qt$users t
             where 207<>all(received) 
              and t.delayed_until<now() 
              and (1=1)=true 
              and added > '2011-09-26 16:45:41.996333' 
              and coalesce(expires,'2070-01-01'::timestamp) > now()::timestamp 
              and t.iid not in (select a.iid from unnest(rvarr) as a)
              order by added, delayed_until
            limit amt
   loop
      inloop:=true;
      if version() like 'PostgreSQL 9.0%' then
        begin
          select * into rv from mbus4.qt$users t where t.iid=r.iid and 207<>all(received) for update nowait;
          continue when not found;
          rvarr:=rvarr||rv;
         exception
          when lock_not_available then null;
        end;
      else
        if pg_try_advisory_xact_lock( ('X' || md5('mbus4.qt$users.' || r.iid))::bit(64)::bigint ) then
         select * into rv from mbus4.qt$users t where t.iid=r.iid and 207<>all(received) for update nowait;
         continue when not found;
         rvarr:=rvarr||rv;
        else
         exit mainloop when trycnt=64;
         trycnt:=trycnt+1;
        end if;
      end if;
   end loop;
   exit when not inloop;
 end loop; 

 if array_length(rvarr,1)>0 then 
   for rv in select * from unnest(rvarr) loop
    if mbus4.build_users_record_consumer_list(rv) <@ (rv.received || 207) then
      delete from mbus4.qt$users where iid = rv.iid;
    else
      update mbus4.qt$users t set received=received || 207 where t.iid=rv.iid;
    end if;
   end loop; 
   return query select id, added, iid, delayed_until, expires, received, headers || hstore('destination','users') as headers, properties, data from unnest(rvarr);
   return;
 end if; 
end;
$_$;


ALTER FUNCTION mbus4.consumen_users_by_default(amt integer) OWNER TO postgres;

--
-- TOC entry 809 (class 1255 OID 76776)
-- Dependencies: 1230 8
-- Name: create_consumer(text, text, text, boolean); Type: FUNCTION; Schema: mbus4; Owner: postgres
--

CREATE FUNCTION create_consumer(cname text, qname text, p_selector text DEFAULT NULL::text, noindex boolean DEFAULT false) RETURNS void
    LANGUAGE plpgsql
    AS $_$
declare
 c_id integer;
 cons_src text;
 consn_src text;
 take_src text;
 ind_src text;
 selector text;
 nowtime text:=(now()::text)::timestamp without time zone;
begin
 selector := case when p_selector is null or p_selector ~ '^ *$' then '1=1' else p_selector end;
 insert into mbus4.consumer(name, qname, selector, added) values(cname, qname, selector, now()::timestamp without time zone) returning id into c_id;
 cons_src:=$CONS_SRC$
----------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION mbus4.consume_<!qname!>_by_<!cname!>()
  RETURNS SETOF mbus4.qt_model AS
$DDD$
declare
 rv mbus4.qt_model;
 c_id int;
 pn int;
 cnt int;
 r record;
 gotrecord boolean:=false;
begin
 set local enable_seqscan=off;

  if version() like 'PostgreSQL 9.0%' then
     for r in 
      select * 
        from mbus4.qt$<!qname!> t
       where <!consumer_id!><>all(received) and t.delayed_until<now() and (<!selector!>)=true and added >'<!now!>' and coalesce(expires,'2070-01-01'::timestamp) > now()::timestamp 
       order by added, delayed_until
       limit <!consumers!>
      loop
        begin
          select * into rv from mbus4.qt$<!qname!> t where t.iid=r.iid and <!consumer_id!><>all(received) for update nowait;
          continue when not found;
          gotrecord:=true;
          exit;
        exception
         when lock_not_available then null;
        end;
      end loop;
  else
     for r in 
      select * 
        from mbus4.qt$<!qname!> t
       where <!consumer_id!><>all(received) and t.delayed_until<now() and (<!selector!>)=true and added > '<!now!>' and coalesce(expires,'2070-01-01'::timestamp) > now()::timestamp 
       order by added, delayed_until
       limit <!consumers!>
      loop
        if pg_try_advisory_xact_lock( ('X' || md5('mbus4.qt$<!qname!>.' || r.iid))::bit(64)::bigint ) then
          select * into rv from mbus4.qt$<!qname!> t where t.iid=r.iid and <!consumer_id!><>all(received) for update;
          continue when not found;
          gotrecord:=true;
          exit;
        end if;
      end loop;
  end if;


 if gotrecord then 
    if mbus4.build_<!qname!>_record_consumer_list(rv) <@ (rv.received || <!c_id!>) then
      delete from mbus4.qt$<!qname!> where iid = rv.iid;
    else
      update mbus4.qt$<!qname!> t set received=received || <!c_id!> where t.iid=rv.iid;
    end if;
    rv.headers = rv.headers || hstore('destination','<!qname!>');
    return next rv;
    return;
 end if; 
end;
$DDD$
  LANGUAGE plpgsql VOLATILE
$CONS_SRC$; 

 cons_src:=regexp_replace(cons_src,'<!qname!>', qname, 'g');
 cons_src:=regexp_replace(cons_src,'<!cname!>', cname,'g');
 cons_src:=regexp_replace(cons_src,'<!consumers!>', (select consumers_cnt::text from mbus4.queue q where q.qname=create_consumer.qname),'g');
 cons_src:=regexp_replace(cons_src,'<!consumer_id!>',c_id::text,'g');
 cons_src:=regexp_replace(cons_src,'<!selector!>',selector,'g');
 cons_src:=regexp_replace(cons_src,'<!now!>',nowtime,'g');
 cons_src:=regexp_replace(cons_src,'<!c_id!>',c_id::text,'g');
 execute cons_src;

 consn_src:=$CONSN_SRC$
----------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION mbus4.consumen_<!qname!>_by_<!cname!>(amt integer)
  RETURNS SETOF mbus4.qt_model AS
$DDD$
declare
 rv mbus4.qt_model;
 rvarr mbus4.qt_model[];
 c_id int;
 pn int;
 cnt int;
 r record;
 inloop boolean;
 trycnt integer:=0;
begin
 set local enable_seqscan=off;

 rvarr:=array[]::mbus4.qt_model[];
 <<mainloop>>
 while coalesce(array_length(rvarr,1),0)<amt loop
  
   inloop:=false;
   for r in select * 
              from mbus4.qt$<!qname!> t
             where <!c_id!><>all(received) 
              and t.delayed_until<now() 
              and (<!selector!>)=true 
              and added > '<!now!>' 
              and coalesce(expires,'2070-01-01'::timestamp) > now()::timestamp 
              and t.iid not in (select a.iid from unnest(rvarr) as a)
              order by added, delayed_until
            limit amt
   loop
      inloop:=true;
      if version() like 'PostgreSQL 9.0%' then
        begin
          select * into rv from mbus4.qt$<!qname!> t where t.iid=r.iid and <!c_id!><>all(received) for update nowait;
          continue when not found;
          rvarr:=rvarr||rv;
         exception
          when lock_not_available then null;
        end;
      else
        if pg_try_advisory_xact_lock( ('X' || md5('mbus4.qt$<!qname!>.' || r.iid))::bit(64)::bigint ) then
         select * into rv from mbus4.qt$<!qname!> t where t.iid=r.iid and <!c_id!><>all(received) for update nowait;
         continue when not found;
         rvarr:=rvarr||rv;
        else
         exit mainloop when trycnt=<!consumers!>;
         trycnt:=trycnt+1;
        end if;
      end if;
   end loop;
   exit when not inloop;
 end loop; 

 if array_length(rvarr,1)>0 then 
   for rv in select * from unnest(rvarr) loop
    if mbus4.build_<!qname!>_record_consumer_list(rv) <@ (rv.received || <!c_id!>) then
      delete from mbus4.qt$<!qname!> where iid = rv.iid;
    else
      update mbus4.qt$<!qname!> t set received=received || <!c_id!> where t.iid=rv.iid;
    end if;
   end loop; 
   return query select id, added, iid, delayed_until, expires, received, headers || hstore('destination','<!qname!>') as headers, properties, data from unnest(rvarr);
   return;
 end if; 
end;
$DDD$
  LANGUAGE plpgsql VOLATILE
$CONSN_SRC$; 

 consn_src:=regexp_replace(consn_src,'<!qname!>', qname, 'g');
 consn_src:=regexp_replace(consn_src,'<!cname!>', cname,'g');
 consn_src:=regexp_replace(consn_src,'<!consumers!>', (select consumers_cnt::text from mbus4.queue q where q.qname=create_consumer.qname),'g');
 consn_src:=regexp_replace(consn_src,'<!consumer_id!>',c_id::text,'g');
 consn_src:=regexp_replace(consn_src,'<!selector!>',selector,'g');
 consn_src:=regexp_replace(consn_src,'<!now!>',nowtime,'g');
 consn_src:=regexp_replace(consn_src,'<!c_id!>',c_id::text,'g');
 execute consn_src;

 take_src:=$TAKE$
 create or replace function mbus4.take_from_<!qname!>_by_<!cname!>(msgid text)
  returns mbus4.qt_model as
  $PRC$
     update mbus4.qt$<!qname!> t set received=received || <!consumer_id!> where iid=$1 and <!c_id!> <> ALL(received) returning *;
  $PRC$
  language sql;
 $TAKE$;
 take_src:=regexp_replace(take_src,'<!qname!>', qname, 'g');
 take_src:=regexp_replace(take_src,'<!cname!>', cname,'g');
 take_src:=regexp_replace(take_src,'<!consumers!>', (select consumers_cnt::text from mbus4.queue q where q.qname=create_consumer.qname),'g');
 take_src:=regexp_replace(take_src,'<!consumer_id!>',c_id::text,'g');
 take_src:=regexp_replace(take_src,'<!c_id!>',c_id::text,'g');

 execute take_src;
 

-- ind_src:= $IND$create index qt$<!qname!>_for_<!cname!> on mbus4.qt$<!qname!>((id % <!consumers!>), id, delayed_until)  WHERE <!consumer_id!> <> ALL (received) and (<!selector!>)=true and added >'<!now!>'$IND$;
 ind_src:= $IND$create index qt$<!qname!>_for_<!cname!> on mbus4.qt$<!qname!>(added, delayed_until)  WHERE <!consumer_id!> <> ALL (received) and (<!selector!>)=true and added >'<!now!>'$IND$;
 ind_src:=regexp_replace(ind_src,'<!qname!>', qname, 'g');
 ind_src:=regexp_replace(ind_src,'<!cname!>', cname,'g');
 ind_src:=regexp_replace(ind_src,'<!consumers!>', (select consumers_cnt::text from mbus4.queue q where q.qname=create_consumer.qname),'g');
 ind_src:=regexp_replace(ind_src,'<!consumer_id!>',c_id::text,'g');
 ind_src:=regexp_replace(ind_src,'<!selector!>',selector,'g');
 ind_src:=regexp_replace(ind_src,'<!now!>',nowtime,'g');
 if noindex then
   raise notice '%', 'You must create index ' || ind_src;
 else
   execute ind_src;
 end if;  
 perform mbus4.regenerate_functions();
end;
$_$;


ALTER FUNCTION mbus4.create_consumer(cname text, qname text, p_selector text, noindex boolean) OWNER TO postgres;

--
-- TOC entry 810 (class 1255 OID 76778)
-- Dependencies: 1230 8
-- Name: create_queue(text, integer); Type: FUNCTION; Schema: mbus4; Owner: postgres
--

CREATE FUNCTION create_queue(qname text, consumers_cnt integer) RETURNS void
    LANGUAGE plpgsql
    AS $_$
declare
 schname text:= 'mbus4';
 post_src text;
 clr_src text;
 peek_src text;
begin
 execute 'create table ' || schname || '.qt$' || qname || '( like ' || schname || '.qt_model including all)';
 insert into mbus4.queue(qname,consumers_cnt) values(qname,consumers_cnt);
 post_src := $post_src$
CREATE OR REPLACE FUNCTION mbus4.post_<!qname!>(data hstore, headers hstore DEFAULT NULL::hstore, properties hstore DEFAULT NULL::hstore, delayed_until timestamp without time zone DEFAULT NULL::timestamp without time zone, expires timestamp without time zone DEFAULT NULL::timestamp without time zone)
  RETURNS text AS
$BDY$
 notify QN_<!qname!>;
 select mbus4.run_trigger('<!qname!>', $1, $2, $3, $4, $5);
 insert into mbus4.qt$<!qname!>(data, 
                                headers, 
                                properties, 
                                delayed_until, 
                                expires, 
                                added, 
                                iid, 
                                received
                               )values(
                                $1,
                                hstore('enqueue_time',now()::timestamp::text) ||
                                hstore('source_db', current_database())       ||
                                case when $2 is null then hstore('seenby','{' || current_database() || '}') else hstore('seenby', (($2->'seenby')::text[] || current_database()::text)::text) end,
                                $3,
                                coalesce($4, now() - '1h'::interval),
                                $5, 
                                now(), 
                                current_database() || '.' || nextval('mbus4.seq') || '.' || txid_current() || '.' || md5($1::text), 
                                array[]::int[] 
                               ) returning iid;
$BDY$
  LANGUAGE sql VOLATILE
  COST 100;
$post_src$;
 post_src:=regexp_replace(post_src,'<!qname!>', qname, 'g');
 execute post_src;

 clr_src:=$CLR_SRC$
create or replace function mbus4.clear_queue_<!qname!>()
returns void as
$ZZ$
declare
 qry text;
begin
 select string_agg( 'select id from mbus4.consumer where id=' || id::text ||' and ( (' || r.selector || ')' || (case when r.added is null then ')' else $$ and q.added > '$$ || (r.added::text) || $$'::timestamp without time zone)$$ end) ||chr(10), ' union all '||chr(10))
  into qry
  from mbus4.consumer r where qname='<!qname!>';
 execute 'delete from mbus4.qt$<!qname!> q where expires < now() or (received @> array(' || qry || '))';
end; 
$ZZ$
language plpgsql
$CLR_SRC$;

 clr_src:=regexp_replace(clr_src,'<!qname!>', qname, 'g');
 execute clr_src;

 peek_src:=$PEEK$
  create or replace function mbus4.peek_<!qname!>(msgid text default null)
  returns boolean as
  $PRC$
   select case 
              when $1 is null then exists(select * from mbus4.qt$<!qname!>)
              else exists(select * from mbus4.qt$<!qname!> where iid=$1)
           end;
  $PRC$
  language sql
 $PEEK$;
 peek_src:=regexp_replace(peek_src,'<!qname!>', qname, 'g');
 execute peek_src;
 
 perform mbus4.create_consumer('default',qname);
 perform mbus4.regenerate_functions(); 
end; 
$_$;


ALTER FUNCTION mbus4.create_queue(qname text, consumers_cnt integer) OWNER TO postgres;

--
-- TOC entry 811 (class 1255 OID 76779)
-- Dependencies: 8
-- Name: create_temporary_queue(); Type: FUNCTION; Schema: mbus4; Owner: postgres
--

CREATE FUNCTION create_temporary_queue() RETURNS text
    LANGUAGE sql
    AS $$
  select 'temp.' || md5(procpid::text || backend_start::text) || '.' || txid_current() from pg_stat_activity where procpid=pg_backend_pid();
$$;


ALTER FUNCTION mbus4.create_temporary_queue() OWNER TO postgres;

--
-- TOC entry 812 (class 1255 OID 76780)
-- Dependencies: 1230 8
-- Name: create_trigger(text, text, text); Type: FUNCTION; Schema: mbus4; Owner: postgres
--

CREATE FUNCTION create_trigger(src text, dst text, selector text DEFAULT NULL::text) RETURNS void
    LANGUAGE plpgsql
    AS $_$
declare
 selfunc text;
begin
   if not exists(select * from pg_catalog.pg_tables where schemaname='mbus4' and tablename='qt$' || src) then
        raise notice 'WARNING: source queue (%) does not exists (yet?)', src;
   end if;
   if not exists(select * from pg_catalog.pg_tables where schemaname='mbus4' and tablename='qt$' || dst) then
        raise notice 'WARNING: destination queue (%) does not exists (yet?)', dst;
   end if;

   if exists(
              with recursive tq as(
                select 1 as rn, src as src, dst as dst
                union all
                select tq.rn+1, t.src, t.dst from mbus4.trigger t, tq where t.dst=tq.src
              )
              select * from tq t1, tq t2 where t1.dst=t2.src and t1.rn=1   
             ) then
     raise exception 'Loop detected';
   end if;
   
   if selector is not null then
        begin
        execute $$with t as (
                     select now() as added, 
                           'IID' as iid, 
                           now() as delayed_until, 
                           now() as expires, 
                           array[]::integer[] as received, 
                           hstore('$%$key','NULL') as headers, 
                           hstore('$%$key','NULL') as properties,
                           hstore('$%$key','NULL') as data
                       )
                       select * from t where $$ || selector;
          exception
           when sqlstate '42000' then 
             raise exception 'Syntax error in selector:%', selector;
          end;
          
          selfunc:= $SRC$create or replace function mbus4.trigger_<!srcdst!>(t mbus4.qt_model) returns boolean as $FUNC$
                         begin
                           return <!selector!>;
                         end;
                        $FUNC$
                        language plpgsql immutable
                     $SRC$;
          selfunc:=regexp_replace(selfunc,'<!srcdst!>', src || '_to_' || dst);
          selfunc:=regexp_replace(selfunc,'<!selector!>', selector);
      
          execute selfunc;
      end if;
      insert into mbus4.trigger(src,dst,selector) values(src,dst,selector);         
end;
$_$;


ALTER FUNCTION mbus4.create_trigger(src text, dst text, selector text) OWNER TO postgres;

--
-- TOC entry 813 (class 1255 OID 76781)
-- Dependencies: 1230 8
-- Name: drop_consumer(text, text); Type: FUNCTION; Schema: mbus4; Owner: postgres
--

CREATE FUNCTION drop_consumer(cname text, qname text) RETURNS void
    LANGUAGE plpgsql
    AS $_$
 begin
   delete from mbus4.consumer c where c.name=drop_consumer.cname and c.qname=drop_consumer.qname;
   execute 'drop index mbus4.qt$' || qname || '_for_' || cname;
   execute 'drop function mbus4.consume_' || qname || '_by_' || cname || '()';
   execute 'drop function mbus4.consumen_' || qname || '_by_' || cname || '(integer)';
   execute 'drop function mbus4.take_from_' || qname || '_by_' || cname || '(text)';
   perform mbus4.regenerate_functions();
 end;
$_$;


ALTER FUNCTION mbus4.drop_consumer(cname text, qname text) OWNER TO postgres;

--
-- TOC entry 814 (class 1255 OID 76782)
-- Dependencies: 1230 8
-- Name: drop_queue(text); Type: FUNCTION; Schema: mbus4; Owner: postgres
--

CREATE FUNCTION drop_queue(qname text) RETURNS void
    LANGUAGE plpgsql
    AS $_X$
declare
 r record;
begin
 execute 'drop table mbus4.qt$' || qname || ' cascade';
 for r in (select * from 
                  pg_catalog.pg_proc prc, pg_catalog.pg_namespace nsp 
                  where  prc.pronamespace=nsp.oid and nsp.nspname='mbus4'
                  and ( prc.proname ~ ('^post_' || qname || '$')
                        or
                        prc.proname ~ ('^consume_' || qname || $Q$_by_\w+$$Q$)
                        or 
                        prc.proname ~ ('^consumen_' || qname || $Q$_by_\w+$$Q$)
                        or 
                        prc.proname ~ ('^peek_' || qname || '$')
                        or 
                        prc.proname ~ ('^take_from_' || qname)
                  )
  ) loop
    case 
      when r.proname like 'post_%' then
       execute 'drop function mbus4.' || r.proname || '(hstore, hstore, hstore, timestamp without time zone, timestamp without time zone)';
      when r.proname like 'consumen_%' then
       execute 'drop function mbus4.' || r.proname || '(integer)';
      when r.proname like 'peek_%' then
       execute 'drop function mbus4.' || r.proname || '(text)';
      when r.proname like 'take_%' then
       execute 'drop function mbus4.' || r.proname || '(text)';
      else
       execute 'drop function mbus4.' || r.proname || '()';
    end case;   
  end loop;
  delete from mbus4.consumer c where c.qname=drop_queue.qname;
  delete from mbus4.queue q where q.qname=drop_queue.qname;
  execute 'drop function mbus4.clear_queue_' || qname || '()'; 
  
  begin
    execute 'drop function mbus4.build_' || qname || '_record_consumer_list(mbus4.qt_model)';
  exception when others then null;
  end;
  
  perform mbus4.regenerate_functions();  
end;
$_X$;


ALTER FUNCTION mbus4.drop_queue(qname text) OWNER TO postgres;

--
-- TOC entry 815 (class 1255 OID 76783)
-- Dependencies: 1230 8
-- Name: drop_trigger(text, text); Type: FUNCTION; Schema: mbus4; Owner: postgres
--

CREATE FUNCTION drop_trigger(src text, dst text) RETURNS void
    LANGUAGE plpgsql
    AS $$
 begin
  delete from mbus4.trigger where trigger.src=drop_trigger.src and trigger.dst=drop_trigger.dst;
  if found then
    begin
      execute 'drop function mbus4.trigger_' || src || '_to_' || dst ||'(mbus4.qt_model)';
    exception
     when sqlstate '42000' then null;
    end;
  end if;
 end;
$$;


ALTER FUNCTION mbus4.drop_trigger(src text, dst text) OWNER TO postgres;

--
-- TOC entry 828 (class 1255 OID 79606)
-- Dependencies: 8
-- Name: peek_users(text); Type: FUNCTION; Schema: mbus4; Owner: postgres
--

CREATE FUNCTION peek_users(msgid text DEFAULT NULL::text) RETURNS boolean
    LANGUAGE sql
    AS $_$
   select case 
              when $1 is null then exists(select * from mbus4.qt$users)
              else exists(select * from mbus4.qt$users where iid=$1)
           end;
  $_$;


ALTER FUNCTION mbus4.peek_users(msgid text) OWNER TO postgres;

--
-- TOC entry 850 (class 1255 OID 79611)
-- Dependencies: 1170 8 1230 1170 1170
-- Name: post(text, hstore, hstore, hstore, timestamp without time zone, timestamp without time zone); Type: FUNCTION; Schema: mbus4; Owner: postgres
--

CREATE FUNCTION post(qname text, data hstore, headers hstore DEFAULT NULL::hstore, properties hstore DEFAULT NULL::hstore, delayed_until timestamp without time zone DEFAULT NULL::timestamp without time zone, expires timestamp without time zone DEFAULT NULL::timestamp without time zone) RETURNS void
    LANGUAGE plpgsql
    AS $$
         begin
          if qname like 'temp.%' then
            perform mbus4.post_temp(qname, data, headers, properties, delayed_until, expires);
            return;
          end if;
          case lower(qname)  when 'users' then perform mbus4.post_users(data, headers, properties, delayed_until, expires);

          else
           raise exception 'Unknown queue:%', qname;
         end case;
         end;
        $$;


ALTER FUNCTION mbus4.post(qname text, data hstore, headers hstore, properties hstore, delayed_until timestamp without time zone, expires timestamp without time zone) OWNER TO postgres;

--
-- TOC entry 816 (class 1255 OID 76784)
-- Dependencies: 1170 1170 1170 8
-- Name: post_temp(text, hstore, hstore, hstore, timestamp without time zone, timestamp without time zone); Type: FUNCTION; Schema: mbus4; Owner: postgres
--

CREATE FUNCTION post_temp(tqname text, data hstore, headers hstore DEFAULT NULL::hstore, properties hstore DEFAULT NULL::hstore, delayed_until timestamp without time zone DEFAULT NULL::timestamp without time zone, expires timestamp without time zone DEFAULT NULL::timestamp without time zone) RETURNS void
    LANGUAGE sql
    AS $_$
 insert into mbus4.tempq(data, 
                                headers, 
                                properties, 
                                delayed_until, 
                                expires, 
                                added, 
                                iid, 
                                received
                               )values(
                                $2,
                                hstore('tempq',$1)                        ||
                                hstore('enqueue_time',now()::timestamp::text) ||
                                hstore('source_db', current_database())       ||
                                case when $3 is null then hstore('seenby','{' || current_database() || '}') else hstore('seenby', (($3->'seenby')::text[] || current_database()::text)::text) end,
                                $4,
                                coalesce($5, now() - '1h'::interval),
                                $6, 
                                now(), 
                                current_database() || '.' || nextval('mbus4.seq') || '.' || txid_current() || '.' || md5($1::text), 
                                array[]::int[] 
                               );

$_$;


ALTER FUNCTION mbus4.post_temp(tqname text, data hstore, headers hstore, properties hstore, delayed_until timestamp without time zone, expires timestamp without time zone) OWNER TO postgres;

--
-- TOC entry 829 (class 1255 OID 79604)
-- Dependencies: 1170 1170 8 1170
-- Name: post_users(hstore, hstore, hstore, timestamp without time zone, timestamp without time zone); Type: FUNCTION; Schema: mbus4; Owner: postgres
--

CREATE FUNCTION post_users(data hstore, headers hstore DEFAULT NULL::hstore, properties hstore DEFAULT NULL::hstore, delayed_until timestamp without time zone DEFAULT NULL::timestamp without time zone, expires timestamp without time zone DEFAULT NULL::timestamp without time zone) RETURNS text
    LANGUAGE sql
    AS $_$
 notify QN_users;
 select mbus4.run_trigger('users', $1, $2, $3, $4, $5);
 insert into mbus4.qt$users(data, 
                                headers, 
                                properties, 
                                delayed_until, 
                                expires, 
                                added, 
                                iid, 
                                received
                               )values(
                                $1,
                                hstore('enqueue_time',now()::timestamp::text) ||
                                hstore('source_db', current_database())       ||
                                case when $2 is null then hstore('seenby','{' || current_database() || '}') else hstore('seenby', (($2->'seenby')::text[] || current_database()::text)::text) end,
                                $3,
                                coalesce($4, now() - '1h'::interval),
                                $5, 
                                now(), 
                                current_database() || '.' || nextval('mbus4.seq') || '.' || txid_current() || '.' || md5($1::text), 
                                array[]::int[] 
                               ) returning iid;
$_$;


ALTER FUNCTION mbus4.post_users(data hstore, headers hstore, properties hstore, delayed_until timestamp without time zone, expires timestamp without time zone) OWNER TO postgres;

--
-- TOC entry 817 (class 1255 OID 76785)
-- Dependencies: 8
-- Name: readme(); Type: FUNCTION; Schema: mbus4; Owner: postgres
--

CREATE FUNCTION readme() RETURNS text
    LANGUAGE sql
    AS $_$
 select $TEXT$
 Управление очередями
 Очереди нормальные, полноценные, умеют
 1. pub/sub
 2. queue
 3. request-response

 Еще умеют message selectorы, expiration и задержки доставки
 Payload'ом очереди является значение hstore (так что тип hstore должен быть установлен в базе)

 Очередь создается функцией
  mbus4.create_queue(qname, ncons)
  где
  qname - имя очереди. Допустимы a-z (НЕ A-Z!), _, 0-9
  ncons - число одновременно доступных частей. Разумные значения - от 2 до 128-256
  больше ставить можно, но тогда будут слишком большие задержки на перебор всех частей
 
  Теперь в очередь можно помещать сообщения:
  select mbus4.post_<qname>(data hstore, 
                            headers hstore DEFAULT NULL::hstore, 
                            properties hstore DEFAULT NULL::hstore, 
                            delayed_until timestamp without time zone DEFAULT NULL::timestamp without time zone, 
                            expires timestamp without time zone DEFAULT NULL::timestamp without time zone)
   где
   data - собственно payload
   headers - заголовки сообщения, в общем, не ожидается, что прикладная программа(ПП) будет их
             отправлять
   properties - заголовки сообщения, предназначенные для ПП
   delayed_until - сообщение будет доставлено ПОСЛЕ указанной даты. Зачем это надо?
             например, пытаемся отправить письмо, почтовая система недоступна.
             Тогда пишем куда-нибудь в properties число попыток, в delayed_until - (now()+'1h'::interval)::timestamp
             Через час это сообщение будет снова выбрано и снова предпринята попытка
             что-то сделать с сообщением
   expires - дата, до которой живет сообщение. По умолчанию - всегда. По достижению указанной даты сообщение удаляется
             Полезно, чтобы не забивать очереди всякой фигней типа "получить урл", а сеть полегла,
             сообщение было проигнорировано и так и осталось болтаться в очереди.
             От таких сообщений очередь чистится функцией mbus4.clear_queue_<qname>()
   Возвращаемое значение: iid добавленного сообщения.

   и еще:
   mbus4.post(qname text, data ...)
   Функция ничего не возвращает

   Получаем сообщения:
   mbus4.consume(qname) - получает сообщения из очереди qname. Возвращает result set из одного
             сообщения, колонки как в mbus4.qt_model. Кроме описанных выше в post_<qname>,
             существуют колонки:
              id - просто id сообщения. Единственное, что про него можно сказать - оно уникально.
                   используется исключительно для генерирования id сообщения
              iid - глобальное уникальное id сообщения. Предполагается, что оно глобально среди всех
                   сообщений; предполагается, что среди всех баз, обменивающихся сообщениями, каждая
                   имеет уникальное имя.
              added - дата добавления сообщения в очередь

   Если сообщение было получено одним процессом вызовом функции mbus4.consume(qname), то другой процесс
   его НЕ ПОЛУЧИТ. Это классическая очередь.

   Реализация publish/subscribe
   В настояшей реализации доступны только постоянные подписчики (durable subscribers). Подписчик создается
   функцией 
    mbus4.create_consumer(qname, cname, selector)
    где
     qname - имя очереди
     cname - имя подписчика
     selector - выражение, ограничивающее множество получаемых сообщений
     Имя подписчика должно быть уникальным среди всех подписчиков (т.е. не только подписчиков этой очереди)
     В selector допустимы только статические значения, известные на момент создания подписчика
     Алиас выбираемой записи - t, тип - mbus.qt_model, т.е. селектор может иметь вид
      $$(t.properties->'STATE')='DONE'$$,
      но не
      $$(t.properties>'user_posted')=current_user$$,
      Следует заметить, что в настоящей реализации селекторы весьма эффективны и предпочтительней
      пользоваться ими, чем фильтровать сообщения уже после получения.
     Замечание: при создании очереди создается подписчик default

    Получение сообщений подписчиком:
     mbus4.consume(qname, cname) - возвращает набор типа mbus4.qt_model из одной записи из очереди qname для подписчика cname
     mbus4.consume_<qname>_by_<cname>() - см. выше
     mbus4.consumen_<qname>_by_<cname>(amt integer) - получить не одно сообщение, а набор не более чем из amt штук.

     Сообщение msg, помещенное в очередь q, которую выбирают два процесса, получающие сообщения для подписчика
     'cons', будет выбрано только одним из двух процессов. Если эти процессы получают сообщения из очереди q для
     подписчиков 'cons1' и 'cons2' соответственно, то каждый из них получит свою копию сообщения.
     После получения поле headers сообщения содержит следующие сообщения:
     seenby - text[], массив баз, которые получили это сообщение по пути к получаетелю
     source_db - имя базы, в которой было создано данное сообщение
     destination - имя очереди, из которой было получено это сообщение
     enqueue_time - время помещения в очередь исходного сообщения (может отличаться от added,
     которое указывает, в какое время сообщение было помещено в ту очередь, из которой происходит получение)

     Если сообщение не может быть получено, возвращается пустой набор. Почему не может быть получено сообщение?
     Вариантов два:
      1. очередь просто пуста
      2. все выбираемые ветви очереди уже заняты подписчиками, получающими сообщения. Заняты они могут быть 
      как тем же подписчиком, так и другими.

     Всмпомогательные функции:
     mbus4.peek_<qname>(msgid text default null) - проверяет, если ли в очереди qname сообщение с iid=msgid
     Если msgid is null, то проверяет наличие хоть какого-то сообщения. Следует учесть, что значение "истина",
     возвращенное функцией peek, НЕ ГАРАНТИРУЕТ, что какие-либо функции из семейства consume вернут какое-либо
     значение.
     mbus4.take_from_<qname>_by_<cname>(msgid text) - получить из очереди qname сообщение с iid=msgid
     ВНИМАНИЕ: это блокирующая функция, в случае, если запись с iid=msgid уже заблокирована какой-либо транзакцией,
     эта функция будет ожидать доступности записи.



     Временные очереди.
     Временная очередь создается функцией
      mbus4.create_temporary_queue()
     Сообщения отправляются обычным mbus4.post(qname, data...)
     Сообщения получаются обычным mbus4.consume(qname)      
     Временные очереди должны периодически очищаться от мусора вызовом функции
     mbus4.clear_tempq()

     Удаление очередей.
     Временные очереди удалять не надо: они будут удалены автоматически после окончания сессии.
     Обычные очереди удаляются функцией mbus4.drop_queue(qname)

     Следует также обратить внимание на то, что активно используемые очереди должны _весьма_
     агрессивно очищаться (VACUUM)

     Триггеры
     Для каждой очереди можно создать триггер - т.е. при поступлении сообщения в очередь
     оно может быть скопировано в другую очередь, если селектор для триггера истинный.
     Для чего это надо? Например, есть очень большая очередь, на которую потребовалось
     подписаться. Создание еще одного подписчика - достаточно затратная вещь, для каждого
     подписчика создается отдельный индекс; при большой очереди надо при создании подписчика
     указывать параметр noindex - тогда индекс не будет создаваться, но текст запроса для
     создания требуемого индекса будет возвращен как raise notice.

$TEXT$::text;
$_$;


ALTER FUNCTION mbus4.readme() OWNER TO postgres;

--
-- TOC entry 818 (class 1255 OID 76787)
-- Dependencies: 8 1230
-- Name: regenerate_functions(); Type: FUNCTION; Schema: mbus4; Owner: postgres
--

CREATE FUNCTION regenerate_functions() RETURNS void
    LANGUAGE plpgsql
    AS $_X$
declare
 r record; 
 r2 record;
 post_qry text:='';
 consume_qry text:='';
 oldqname text:='';
 visibilty_qry text:='';
begin
 for r in select * from mbus4.queue loop
   post_qry:=post_qry || $$ when '$$ || lower(r.qname) || $$' then perform mbus4.post_$$ || r.qname || '(data, headers, properties, delayed_until, expires);'||chr(10);
 end loop;
 
 if post_qry='' then
        begin
          execute 'drop function mbus4.post(text, hstore, hstore, hstore, timestamp, timestamp)';
        exception when others then null;
        end;
 else
        execute $FUNC$
        ---------------------------------------------------------------------------------------------------------------------------------------------
        create or replace function mbus4.post(qname text, data hstore, headers hstore default null, properties hstore default null, delayed_until timestamp default null, expires timestamp default null)
        returns void as
        $QQ$
         begin
          if qname like 'temp.%' then
            perform mbus4.post_temp(qname, data, headers, properties, delayed_until, expires);
            return;
          end if;
          case lower(qname) $FUNC$ || post_qry || $FUNC$
          else
           raise exception 'Unknown queue:%', qname;
         end case;
         end;
        $QQ$
        language plpgsql;
        $FUNC$;
end if;
 for r2 in select * from mbus4.consumer order by qname loop
   if oldqname<>r2.qname then
     if consume_qry<>'' then
       consume_qry:=consume_qry || ' else raise exception $$unknown consumer:%$$, cname; end case;' || chr(10);
     end if;
     consume_qry:=consume_qry || $$ when '$$ || lower(r2.qname) ||$$' then case lower(cname) $$;
   end if;
   consume_qry:=consume_qry || $$ when '$$ || lower(r2.name) || $$' then return query select * from mbus4.consume_$$ || r2.qname || '_by_' || r2.name ||'(); return;';
   oldqname=r2.qname;
 end loop;

 if consume_qry<>'' then
    consume_qry:=consume_qry || ' else raise exception $$unknown consumer:%$$, consumer; end case;' || chr(10);
 end if;

 if consume_qry='' then 
        begin
          execute 'drop function mbus4.consume(text, text)';
        exception when others then null;
        end;
 else 
        execute $FUNC$
        create or replace function mbus4.consume(qname text, cname text default 'default') returns setof mbus4.qt_model as
        $QQ$
        begin
          if qname like 'temp.%' then
            return query select * from mbus4.consume_temp(qname);
            return;
          end if;
         case lower(qname)
        $FUNC$ || consume_qry || $FUNC$
         end case;
        end;
        $QQ$
        language plpgsql;
        $FUNC$;
 end if;
 
 --create functions for tests for visibility
  for r in 
    select string_agg( 
          'select '|| id::text ||' from t where 
           ( (' 
          || cons.selector 
          || ')' 
          || (case when cons.added is null then ')' else $$ and t.added > '$$ 
          || (cons.added::text) 
          || $$'::timestamp without time zone)$$ end),
          chr(10) || ' union all ' ||chr(10)) as src,
          qname
        from mbus4.consumer cons
        group by cons.qname
    loop
      execute $RCL$
      create or replace function mbus4.build_$RCL$ || lower(r.qname) || $RCL$_record_consumer_list(qr mbus4.qt_model) returns int[] as
      $FUNC$
       begin
         return array( 
         with t as (select qr.*)
          $RCL$ || r.src || $RCL$ );
       end;
      $FUNC$
      language plpgsql;
      $RCL$;
    end loop;
end;
$_X$;


ALTER FUNCTION mbus4.regenerate_functions() OWNER TO postgres;

--
-- TOC entry 819 (class 1255 OID 76788)
-- Dependencies: 1230 8 1170 1170 1170
-- Name: run_trigger(text, hstore, hstore, hstore, timestamp without time zone, timestamp without time zone); Type: FUNCTION; Schema: mbus4; Owner: postgres
--

CREATE FUNCTION run_trigger(qname text, data hstore, headers hstore DEFAULT NULL::hstore, properties hstore DEFAULT NULL::hstore, delayed_until timestamp without time zone DEFAULT NULL::timestamp without time zone, expires timestamp without time zone DEFAULT NULL::timestamp without time zone) RETURNS void
    LANGUAGE plpgsql
    AS $_$
declare
 r record;
 res boolean;
 qtm mbus4.qt_model;
begin
 if headers->'Redeploy' then
  return;
 end if;
 <<mainloop>>
  for r in select * from mbus4.trigger t where src=qname loop
   if r.selector is not null then
     begin
       qtm.data:=data;
       qtm.headers:=headers;
       qtm.properties:=properties;
       qtm.delayed_until:=delayed_until;
       qtm.expires:=expires;
       execute 'select mbus4.trigger_'||r.src||'_to_'||r.dst||'($1)' into res using qtm;
     exception
      when others then
        continue mainloop;
    end;  
     continue mainloop when not res;
   end if;
   perform mbus4.post(r.dst, data:=run_trigger.data, properties:=coalesce(run_trigger.properties,''::hstore) || hstore('source_queue',qname), headers:=run_trigger.headers );
  end loop;
end;
$_$;


ALTER FUNCTION mbus4.run_trigger(qname text, data hstore, headers hstore, properties hstore, delayed_until timestamp without time zone, expires timestamp without time zone) OWNER TO postgres;

--
-- TOC entry 849 (class 1255 OID 79609)
-- Dependencies: 1174 8
-- Name: take_from_users_by_default(text); Type: FUNCTION; Schema: mbus4; Owner: postgres
--

CREATE FUNCTION take_from_users_by_default(msgid text) RETURNS qt_model
    LANGUAGE sql
    AS $_$
     update mbus4.qt$users t set received=received || 207 where iid=$1 and 207 <> ALL(received) returning *;
  $_$;


ALTER FUNCTION mbus4.take_from_users_by_default(msgid text) OWNER TO postgres;

--
-- TOC entry 2717 (class 1259 OID 76789)
-- Dependencies: 8
-- Name: consumer; Type: TABLE; Schema: mbus4; Owner: postgres; Tablespace: 
--

CREATE TABLE consumer (
    id integer NOT NULL,
    name text,
    qname text,
    selector text,
    added timestamp without time zone
);


ALTER TABLE mbus4.consumer OWNER TO postgres;

--
-- TOC entry 2718 (class 1259 OID 76795)
-- Dependencies: 8 2717
-- Name: consumer_id_seq; Type: SEQUENCE; Schema: mbus4; Owner: postgres
--

CREATE SEQUENCE consumer_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE mbus4.consumer_id_seq OWNER TO postgres;

--
-- TOC entry 2863 (class 0 OID 0)
-- Dependencies: 2718
-- Name: consumer_id_seq; Type: SEQUENCE OWNED BY; Schema: mbus4; Owner: postgres
--

ALTER SEQUENCE consumer_id_seq OWNED BY consumer.id;


--
-- TOC entry 2864 (class 0 OID 0)
-- Dependencies: 2718
-- Name: consumer_id_seq; Type: SEQUENCE SET; Schema: mbus4; Owner: postgres
--

SELECT pg_catalog.setval('consumer_id_seq', 207, true);


--
-- TOC entry 2719 (class 1259 OID 76797)
-- Dependencies: 2716 8
-- Name: qt_model_id_seq; Type: SEQUENCE; Schema: mbus4; Owner: postgres
--

CREATE SEQUENCE qt_model_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE mbus4.qt_model_id_seq OWNER TO postgres;

--
-- TOC entry 2865 (class 0 OID 0)
-- Dependencies: 2719
-- Name: qt_model_id_seq; Type: SEQUENCE OWNED BY; Schema: mbus4; Owner: postgres
--

ALTER SEQUENCE qt_model_id_seq OWNED BY qt_model.id;


--
-- TOC entry 2866 (class 0 OID 0)
-- Dependencies: 2719
-- Name: qt_model_id_seq; Type: SEQUENCE SET; Schema: mbus4; Owner: postgres
--

SELECT pg_catalog.setval('qt_model_id_seq', 13240625, true);


--
-- TOC entry 2720 (class 1259 OID 76799)
-- Dependencies: 2832 8 1170 1170 1170
-- Name: dmq; Type: TABLE; Schema: mbus4; Owner: postgres; Tablespace: 
--

CREATE TABLE dmq (
    id integer DEFAULT nextval('qt_model_id_seq'::regclass) NOT NULL,
    added timestamp without time zone NOT NULL,
    iid text NOT NULL,
    delayed_until timestamp without time zone NOT NULL,
    expires timestamp without time zone,
    received integer[],
    headers hstore,
    properties hstore,
    data hstore
);


ALTER TABLE mbus4.dmq OWNER TO postgres;

--
-- TOC entry 2742 (class 1259 OID 79595)
-- Dependencies: 2835 1170 1170 8 1170
-- Name: qt$users; Type: TABLE; Schema: mbus4; Owner: postgres; Tablespace: 
--

CREATE TABLE "qt$users" (
    id integer DEFAULT nextval('qt_model_id_seq'::regclass) NOT NULL,
    added timestamp without time zone NOT NULL,
    iid text NOT NULL,
    delayed_until timestamp without time zone NOT NULL,
    expires timestamp without time zone,
    received integer[],
    headers hstore,
    properties hstore,
    data hstore
);


ALTER TABLE mbus4."qt$users" OWNER TO postgres;

--
-- TOC entry 2721 (class 1259 OID 76806)
-- Dependencies: 8
-- Name: queue; Type: TABLE; Schema: mbus4; Owner: postgres; Tablespace: 
--

CREATE TABLE queue (
    id integer NOT NULL,
    qname text NOT NULL,
    consumers_cnt integer
);


ALTER TABLE mbus4.queue OWNER TO postgres;

--
-- TOC entry 2722 (class 1259 OID 76812)
-- Dependencies: 2721 8
-- Name: queue_id_seq; Type: SEQUENCE; Schema: mbus4; Owner: postgres
--

CREATE SEQUENCE queue_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE mbus4.queue_id_seq OWNER TO postgres;

--
-- TOC entry 2867 (class 0 OID 0)
-- Dependencies: 2722
-- Name: queue_id_seq; Type: SEQUENCE OWNED BY; Schema: mbus4; Owner: postgres
--

ALTER SEQUENCE queue_id_seq OWNED BY queue.id;


--
-- TOC entry 2868 (class 0 OID 0)
-- Dependencies: 2722
-- Name: queue_id_seq; Type: SEQUENCE SET; Schema: mbus4; Owner: postgres
--

SELECT pg_catalog.setval('queue_id_seq', 122, true);


--
-- TOC entry 2723 (class 1259 OID 76814)
-- Dependencies: 8
-- Name: seq; Type: SEQUENCE; Schema: mbus4; Owner: postgres
--

CREATE SEQUENCE seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE mbus4.seq OWNER TO postgres;

--
-- TOC entry 2869 (class 0 OID 0)
-- Dependencies: 2723
-- Name: seq; Type: SEQUENCE SET; Schema: mbus4; Owner: postgres
--

SELECT pg_catalog.setval('seq', 13240626, true);


--
-- TOC entry 2724 (class 1259 OID 76816)
-- Dependencies: 2834 1170 1170 1170 8
-- Name: tempq; Type: TABLE; Schema: mbus4; Owner: postgres; Tablespace: 
--

CREATE TABLE tempq (
    id integer DEFAULT nextval('qt_model_id_seq'::regclass) NOT NULL,
    added timestamp without time zone NOT NULL,
    iid text NOT NULL,
    delayed_until timestamp without time zone NOT NULL,
    expires timestamp without time zone,
    received integer[],
    headers hstore,
    properties hstore,
    data hstore
);


ALTER TABLE mbus4.tempq OWNER TO postgres;

--
-- TOC entry 2725 (class 1259 OID 76823)
-- Dependencies: 8
-- Name: trigger; Type: TABLE; Schema: mbus4; Owner: postgres; Tablespace: 
--

CREATE TABLE trigger (
    src text NOT NULL,
    dst text NOT NULL,
    selector text
);


ALTER TABLE mbus4.trigger OWNER TO postgres;

--
-- TOC entry 2831 (class 2604 OID 76829)
-- Dependencies: 2718 2717
-- Name: id; Type: DEFAULT; Schema: mbus4; Owner: postgres
--

ALTER TABLE consumer ALTER COLUMN id SET DEFAULT nextval('consumer_id_seq'::regclass);


--
-- TOC entry 2830 (class 2604 OID 76830)
-- Dependencies: 2719 2716
-- Name: id; Type: DEFAULT; Schema: mbus4; Owner: postgres
--

ALTER TABLE qt_model ALTER COLUMN id SET DEFAULT nextval('qt_model_id_seq'::regclass);


--
-- TOC entry 2833 (class 2604 OID 76831)
-- Dependencies: 2722 2721
-- Name: id; Type: DEFAULT; Schema: mbus4; Owner: postgres
--

ALTER TABLE queue ALTER COLUMN id SET DEFAULT nextval('queue_id_seq'::regclass);


--
-- TOC entry 2855 (class 0 OID 76789)
-- Dependencies: 2717
-- Data for Name: consumer; Type: TABLE DATA; Schema: mbus4; Owner: postgres
--

COPY consumer (id, name, qname, selector, added) FROM stdin;
207	default	users	1=1	2011-09-26 16:45:41.996333
\.


--
-- TOC entry 2856 (class 0 OID 76799)
-- Dependencies: 2720
-- Data for Name: dmq; Type: TABLE DATA; Schema: mbus4; Owner: postgres
--

COPY dmq (id, added, iid, delayed_until, expires, received, headers, properties, data) FROM stdin;
\.


--
-- TOC entry 2860 (class 0 OID 79595)
-- Dependencies: 2742
-- Data for Name: qt$users; Type: TABLE DATA; Schema: mbus4; Owner: postgres
--

COPY "qt$users" (id, added, iid, delayed_until, expires, received, headers, properties, data) FROM stdin;
\.


--
-- TOC entry 2854 (class 0 OID 76769)
-- Dependencies: 2716
-- Data for Name: qt_model; Type: TABLE DATA; Schema: mbus4; Owner: postgres
--

COPY qt_model (id, added, iid, delayed_until, expires, received, headers, properties, data) FROM stdin;
\.


--
-- TOC entry 2857 (class 0 OID 76806)
-- Dependencies: 2721
-- Data for Name: queue; Type: TABLE DATA; Schema: mbus4; Owner: postgres
--

COPY queue (id, qname, consumers_cnt) FROM stdin;
122	users	64
\.


--
-- TOC entry 2858 (class 0 OID 76816)
-- Dependencies: 2724
-- Data for Name: tempq; Type: TABLE DATA; Schema: mbus4; Owner: postgres
--

COPY tempq (id, added, iid, delayed_until, expires, received, headers, properties, data) FROM stdin;
\.


--
-- TOC entry 2859 (class 0 OID 76823)
-- Dependencies: 2725
-- Data for Name: trigger; Type: TABLE DATA; Schema: mbus4; Owner: postgres
--

COPY trigger (src, dst, selector) FROM stdin;
\.


--
-- TOC entry 2839 (class 2606 OID 76833)
-- Dependencies: 2717 2717
-- Name: consumer_pkey; Type: CONSTRAINT; Schema: mbus4; Owner: postgres; Tablespace: 
--

ALTER TABLE ONLY consumer
    ADD CONSTRAINT consumer_pkey PRIMARY KEY (id);


--
-- TOC entry 2841 (class 2606 OID 76835)
-- Dependencies: 2720 2720
-- Name: dmq_iid_key; Type: CONSTRAINT; Schema: mbus4; Owner: postgres; Tablespace: 
--

ALTER TABLE ONLY dmq
    ADD CONSTRAINT dmq_iid_key UNIQUE (iid);


--
-- TOC entry 2853 (class 2606 OID 79603)
-- Dependencies: 2742 2742
-- Name: qt$users_iid_key; Type: CONSTRAINT; Schema: mbus4; Owner: postgres; Tablespace: 
--

ALTER TABLE ONLY "qt$users"
    ADD CONSTRAINT "qt$users_iid_key" UNIQUE (iid);


--
-- TOC entry 2837 (class 2606 OID 76837)
-- Dependencies: 2716 2716
-- Name: qt_model_iid_key; Type: CONSTRAINT; Schema: mbus4; Owner: postgres; Tablespace: 
--

ALTER TABLE ONLY qt_model
    ADD CONSTRAINT qt_model_iid_key UNIQUE (iid);


--
-- TOC entry 2843 (class 2606 OID 76839)
-- Dependencies: 2721 2721
-- Name: queue_pkey; Type: CONSTRAINT; Schema: mbus4; Owner: postgres; Tablespace: 
--

ALTER TABLE ONLY queue
    ADD CONSTRAINT queue_pkey PRIMARY KEY (id);


--
-- TOC entry 2845 (class 2606 OID 76841)
-- Dependencies: 2721 2721
-- Name: queue_qname_key; Type: CONSTRAINT; Schema: mbus4; Owner: postgres; Tablespace: 
--

ALTER TABLE ONLY queue
    ADD CONSTRAINT queue_qname_key UNIQUE (qname);


--
-- TOC entry 2847 (class 2606 OID 76843)
-- Dependencies: 2724 2724
-- Name: tempq_iid_key; Type: CONSTRAINT; Schema: mbus4; Owner: postgres; Tablespace: 
--

ALTER TABLE ONLY tempq
    ADD CONSTRAINT tempq_iid_key UNIQUE (iid);


--
-- TOC entry 2850 (class 2606 OID 76845)
-- Dependencies: 2725 2725 2725
-- Name: trigger_src_dst; Type: CONSTRAINT; Schema: mbus4; Owner: postgres; Tablespace: 
--

ALTER TABLE ONLY trigger
    ADD CONSTRAINT trigger_src_dst UNIQUE (src, dst);


--
-- TOC entry 2851 (class 1259 OID 79610)
-- Dependencies: 2742 2742 2742 2742
-- Name: qt$users_for_default; Type: INDEX; Schema: mbus4; Owner: postgres; Tablespace: 
--

CREATE INDEX "qt$users_for_default" ON "qt$users" USING btree (added, delayed_until) WHERE (((207 <> ALL (received)) AND ((1 = 1) = true)) AND (added > '2011-09-26 16:45:41.996333'::timestamp without time zone));


--
-- TOC entry 2848 (class 1259 OID 76846)
-- Dependencies: 2724 1983 2724 1983 2724
-- Name: tempq_name_added; Type: INDEX; Schema: mbus4; Owner: postgres; Tablespace: 
--

CREATE INDEX tempq_name_added ON tempq USING btree (((headers -> 'tempq'::text)), added) WHERE ((headers -> 'tempq'::text) IS NOT NULL);


-- Completed on 2011-10-11 15:00:56

--
-- PostgreSQL database dump complete
--

