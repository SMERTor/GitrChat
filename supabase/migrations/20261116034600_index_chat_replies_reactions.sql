create index if not exists message_reactions_user_id_idx on public.message_reactions(user_id);
create index if not exists messages_reply_to_message_id_idx on public.messages(reply_to_message_id);
