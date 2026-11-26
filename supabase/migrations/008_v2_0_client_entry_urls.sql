-- Bellamia v2.0
-- Normalize client push target URLs to the dedicated physical client shell.

create or replace function private.normalize_client_notification_target()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  v_token text;
begin
  if new.audience = 'client'
     and new.target_path like '/c/%' then

    v_token := substring(new.target_path from 4);

    if v_token is not null and v_token <> '' then
      new.target_path :=
        '/client/index.html?token=' || v_token;
    end if;
  end if;

  return new;
end;
$$;

drop trigger if exists normalize_client_notification_target
on public.notification_outbox;

create trigger normalize_client_notification_target
before insert or update of target_path
on public.notification_outbox
for each row
execute function private.normalize_client_notification_target();

-- Normalize any queued, not-yet-processed client notifications too.
update public.notification_outbox
set target_path =
  '/client/index.html?token=' ||
  substring(target_path from 4)
where audience = 'client'
  and target_path like '/c/%'
  and processed_at is null;
