-- Bellamia v2.0.1
-- Cloudflare canonicalizes /client/index.html to /client.

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
        '/client?token=' || v_token;
    end if;
  end if;

  if new.audience = 'client'
     and new.target_path like '/client/index.html?token=%' then
    new.target_path :=
      replace(new.target_path, '/client/index.html?token=', '/client?token=');
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

update public.notification_outbox
set target_path =
  replace(target_path, '/client/index.html?token=', '/client?token=')
where audience = 'client'
  and target_path like '/client/index.html?token=%'
  and processed_at is null;
