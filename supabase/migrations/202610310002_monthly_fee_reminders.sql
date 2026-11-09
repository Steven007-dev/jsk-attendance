create extension if not exists pg_cron;

create or replace function public.run_jsk_monthly_fee_reminders()
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_state jsonb;
  v_inbox jsonb;
  v_students jsonb;
  v_payments jsonb;
  v_users jsonb;
  v_today date := (now() at time zone 'Asia/Kolkata')::date;
  v_month text;
  v_month_label text;
  v_now_ms bigint := (extract(epoch from now()) * 1000)::bigint;
  v_student jsonb;
  v_guardian jsonb;
  v_user jsonb;
  v_recipient jsonb;
  v_recipients jsonb;
  v_student_id text;
  v_student_name text;
  v_user_id text;
  v_name text;
  v_ref_id text;
  v_is_paid boolean;
  v_exists boolean;
  v_added integer := 0;
  v_message text;
  v_record jsonb;
begin
  if extract(day from v_today) <> 1 then
    return jsonb_build_object('sent', 0, 'reason', 'not_first_day_in_asia_kolkata');
  end if;

  v_month := to_char(v_today, 'YYYY-MM');
  v_month_label := to_char(date_trunc('month', v_today::timestamp), 'FMMonth YYYY');

  select app.content
    into v_state
    from public.app_data as app
   where app.id = 'main_state'
   for update;

  if v_state is null or jsonb_typeof(v_state) <> 'object' then
    return jsonb_build_object('sent', 0, 'reason', 'main_state_missing');
  end if;
  if v_state ->> 'feeReminderMonth' = v_month then
    return jsonb_build_object('sent', 0, 'reason', 'already_processed', 'month', v_month);
  end if;

  v_students := case when jsonb_typeof(v_state -> 'students') = 'array' then v_state -> 'students' else '[]'::jsonb end;
  v_payments := case when jsonb_typeof(v_state -> 'feePayments') = 'array' then v_state -> 'feePayments' else '[]'::jsonb end;
  v_users := case when jsonb_typeof(v_state -> 'users') = 'array' then v_state -> 'users' else '[]'::jsonb end;
  v_inbox := case when jsonb_typeof(v_state -> 'inbox') = 'array' then v_state -> 'inbox' else '[]'::jsonb end;

  for v_student in
    select item.value from jsonb_array_elements(v_students) as item(value)
  loop
    v_student_id := nullif(v_student ->> 'id', '');
    v_student_name := coalesce(nullif(v_student ->> 'name', ''), 'Student');
    if v_student_id is null then continue; end if;

    select exists (
      select 1
        from jsonb_array_elements(v_payments) as payment(value)
       where payment.value ->> 'studentId' = v_student_id
         and payment.value ->> 'month' = v_month
    ) into v_is_paid;
    if v_is_paid then continue; end if;

    v_ref_id := v_student_id || '|' || v_month;
    v_message := 'Monthly fee reminder: the fees for ' || v_month_label || ' are NOT PAID yet.' || E'\n\n' ||
      'Student: ' || v_student_name || E'\n' ||
      'Month: ' || v_month_label || E'\n\n' ||
      'Please pay at the institute office.';

    v_recipients := '[]'::jsonb;
    v_user_id := nullif(v_student ->> 'userId', '');
    if v_user_id is not null then
      select item.value into v_user
        from jsonb_array_elements(v_users) as item(value)
       where item.value ->> 'id' = v_user_id
       limit 1;
      v_recipients := v_recipients || jsonb_build_array(jsonb_build_object(
        'userId', v_user_id, 'type', 'student', 'name', coalesce(nullif(v_user ->> 'name', ''), v_student_name)
      ));
    end if;

    v_user_id := nullif(v_student ->> 'guardianUserId', '');
    v_name := coalesce(nullif(v_student ->> 'guardianName', ''), 'Guardian of ' || v_student_name);
    if v_user_id is not null then
      select item.value into v_user
        from jsonb_array_elements(v_users) as item(value)
       where item.value ->> 'id' = v_user_id
       limit 1;
      v_name := coalesce(nullif(v_user ->> 'name', ''), v_name);
    end if;
    v_recipients := v_recipients || jsonb_build_array(jsonb_build_object(
      'userId', v_user_id, 'type', 'guardian', 'name', v_name
    ));

    if jsonb_typeof(v_student -> 'additionalGuardians') = 'array' then
      for v_guardian in
        select item.value from jsonb_array_elements(v_student -> 'additionalGuardians') as item(value)
      loop
        v_recipients := v_recipients || jsonb_build_array(jsonb_build_object(
          'userId', null,
          'type', 'guardian',
          'name', coalesce(nullif(v_guardian ->> 'name', ''), 'Guardian of ' || v_student_name)
        ));
      end loop;
    end if;

    for v_recipient in
      select item.value from jsonb_array_elements(v_recipients) as item(value)
    loop
      v_user_id := nullif(v_recipient ->> 'userId', '');
      v_name := coalesce(nullif(v_recipient ->> 'name', ''), 'Guardian');
      if v_user_id is not null then
        select exists (
          select 1 from jsonb_array_elements(v_inbox) as item(value)
           where item.value ->> 'refType' = 'fee_period'
             and item.value ->> 'refId' = v_ref_id
             and item.value ->> 'recipientUserId' = v_user_id
        ) into v_exists;
      else
        select exists (
          select 1 from jsonb_array_elements(v_inbox) as item(value)
           where item.value ->> 'refType' = 'fee_period'
             and item.value ->> 'refId' = v_ref_id
             and item.value -> 'recipientUserId' = 'null'::jsonb
             and item.value ->> 'recipientName' = v_name
        ) into v_exists;
      end if;
      if v_exists then continue; end if;

      v_record := jsonb_build_object(
        'id', 'ntf_cron_' || replace(gen_random_uuid()::text, '-', ''),
        'dedupKey', null,
        'recipientUserId', case when v_user_id is null then 'null'::jsonb else to_jsonb(v_user_id) end,
        'recipientType', coalesce(nullif(v_recipient ->> 'type', ''), 'guardian'),
        'recipientName', v_name,
        'studentId', v_student_id,
        'type', 'FEES_DUE',
        'title', 'JSK Institute Fees Reminder',
        'message', v_message,
        'refType', 'fee_period',
        'refId', v_ref_id,
        'attachment', null,
        'ts', v_now_ms,
        'read', '{}'::jsonb
      );
      v_inbox := jsonb_build_array(v_record) || v_inbox;
      v_added := v_added + 1;
    end loop;
  end loop;

  v_state := jsonb_set(v_state, '{inbox}', v_inbox, true);
  v_state := jsonb_set(v_state, '{feeReminderMonth}', to_jsonb(v_month), true);
  update public.app_data set content = v_state where id = 'main_state';
  return jsonb_build_object('sent', v_added, 'month', v_month);
end;
$$;

revoke all on function public.run_jsk_monthly_fee_reminders() from public, anon, authenticated;
grant execute on function public.run_jsk_monthly_fee_reminders() to service_role;

-- Run daily at 00:05 Asia/Kolkata (18:35 UTC); the function only acts on the
-- first local calendar day and writes normal inbox items that the push webhook
-- then delivers through OneSignal.
select cron.unschedule(jobid)
  from cron.job
 where jobname = 'jsk-monthly-fee-reminders';

select cron.schedule(
  'jsk-monthly-fee-reminders',
  '35 18 * * *',
  'select public.run_jsk_monthly_fee_reminders();'
);
