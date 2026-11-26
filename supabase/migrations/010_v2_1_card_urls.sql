-- Bellamia v2.1
-- Canonical client URLs now keep the bearer token in the path itself.

create or replace function private.normalize_client_notification_target()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  v_token text;
begin
  if new.audience <> 'client' then
    return new;
  end if;

  if new.target_path like '/c/%' then
    v_token := substring(new.target_path from 4);

  elsif new.target_path like '/client?token=%' then
    v_token := substring(
      new.target_path
      from length('/client?token=') + 1
    );

  elsif new.target_path like '/client/index.html?token=%' then
    v_token := substring(
      new.target_path
      from length('/client/index.html?token=') + 1
    );
  end if;

  if v_token is not null and v_token <> '' then
    new.target_path := '/card/' || v_token;
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

-- Normalize old pending client notifications.
update public.notification_outbox
set target_path =
  case
    when target_path like '/c/%'
      then '/card/' || substring(target_path from 4)
    when target_path like '/client?token=%'
      then '/card/' || substring(
        target_path from length('/client?token=') + 1
      )
    when target_path like '/client/index.html?token=%'
      then '/card/' || substring(
        target_path from length('/client/index.html?token=') + 1
      )
    else target_path
  end
where audience = 'client'
  and processed_at is null
  and (
    target_path like '/c/%'
    or target_path like '/client?token=%'
    or target_path like '/client/index.html?token=%'
  );
