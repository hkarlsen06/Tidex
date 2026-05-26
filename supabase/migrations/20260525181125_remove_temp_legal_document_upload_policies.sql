drop policy if exists "Temp exact upload for NDA PDF" on storage.objects;
drop policy if exists "Temp exact update for NDA PDF" on storage.objects;

drop table if exists public._tmp_legal_doc_upload_chunks;
