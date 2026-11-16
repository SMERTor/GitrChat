-- GitrChat voice-message and reaction realtime support.
-- Review this migration before applying it to the production Supabase project.

alter table public.messages
  drop constraint if exists messages_body_or_media_check;

alter table public.messages
  add constraint messages_body_or_media_check check (
    (body is not null and char_length(trim(body)) between 1 and 2000
      and media_path is null and media_type is null)
    or
    (body is null and media_path is not null
      and media_type in ('image','video_circle','voice'))
  );

update storage.buckets
set allowed_mime_types = array[
  'image/jpeg','image/png','image/webp','image/heic',
  'video/mp4','video/quicktime',
  'audio/mp4','audio/aac','audio/m4a','audio/mpeg','audio/ogg','audio/wav'
]
where id = 'chat-media';

do $$
begin
  if exists (
    select 1 from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public' and c.relname = 'message_reactions'
  ) and not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'message_reactions'
  ) then
    alter publication supabase_realtime add table public.message_reactions;
  end if;
end $$;
