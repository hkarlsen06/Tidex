drop policy if exists "Temp exact delete generated NDA PDF" on storage.objects;

create policy "Temp exact delete generated NDA PDF"
on storage.objects
for delete
to anon
using (
  bucket_id = 'legal-documents'
  and name = 'legal/taushetserklaring-alvilde-sofie-kristensen-tidex-2026-05-25.pdf'
);
