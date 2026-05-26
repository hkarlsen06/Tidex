insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('legal-documents', 'legal-documents', false, 10485760, array['application/pdf'])
on conflict (id) do update
set public = excluded.public,
    file_size_limit = excluded.file_size_limit,
    allowed_mime_types = excluded.allowed_mime_types,
    updated_at = now();

drop policy if exists "Temp exact upload for NDA PDF" on storage.objects;

create policy "Temp exact upload for NDA PDF"
on storage.objects
for insert
to anon
with check (
  bucket_id = 'legal-documents'
  and name = 'legal/taushetserklaring-alvilde-sofie-kristensen-tidex-2026-05-25.pdf'
);
