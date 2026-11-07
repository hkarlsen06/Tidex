#!/usr/bin/env python3
"""Snapshot both live SQLite stores and copy blob storage for isolated upgrade tests."""
import hashlib,json,os,pathlib,shutil,sqlite3,subprocess,time
ROOT=pathlib.Path('/srv/convex-runtime/rehearsal')
ROOT.mkdir(exist_ok=True);os.chmod(ROOT,0o700)
projects={'paeonia':('/srv/paeonia/convex','convex-backend-1'),'tidex':('/srv/tidex/convex','tidex-convex-backend-1')}
for name,(stack,container) in projects.items():
 dest=ROOT/name;dest.mkdir(exist_ok=True);os.chmod(dest,0o700)
 source=pathlib.Path(stack)/'data';data=dest/'data';data.mkdir(exist_ok=True)
 if (dest/'prepared.json').exists():print(name,'already prepared');continue
 with sqlite3.connect('file:'+str(source/'db.sqlite3')+'?mode=ro',uri=True) as src,sqlite3.connect(data/'db.sqlite3') as target:
  src.backup(target);assert target.execute('PRAGMA integrity_check').fetchone()[0]=='ok'
 shutil.copytree(source/'credentials',data/'credentials',dirs_exist_ok=True)
 info=json.loads(subprocess.check_output(['docker','inspect',container]))[0]
 env=dict(v.split('=',1) for v in info['Config']['Env'] if '=' in v)
 if name=='tidex':
  for category in ['modules','files','search']:
   shutil.copytree(source/'storage'/category,data/'storage'/category,dirs_exist_ok=True)
 else:
  r_env=os.environ.copy()
  for k,v in {'TYPE':'s3','PROVIDER':'Cloudflare','ACCESS_KEY_ID':env['AWS_ACCESS_KEY_ID'],'SECRET_ACCESS_KEY':env['AWS_SECRET_ACCESS_KEY'],'ENDPOINT':env['S3_ENDPOINT_URL'],'REGION':'auto','FORCE_PATH_STYLE':'true'}.items():r_env['RCLONE_CONFIG_CLONE_'+k]=v
  with (dest/'blob-copy.log').open('w') as log:
   for category in ['modules','files','search']:
    target=data/'storage'/category;target.mkdir(parents=True,exist_ok=True)
    bucket=env['S3_STORAGE_'+category.upper()+'_BUCKET']
    subprocess.run(['rclone','copy','clone:'+bucket,str(target),'--s3-no-check-bucket','--transfers','2'],env=r_env,check=True,stdout=log,stderr=log)
    subprocess.run(['rclone','check','clone:'+bucket,str(target),'--one-way','--download','--s3-no-check-bucket'],env=r_env,check=True,stdout=log,stderr=log)
 blob_count=sum(1 for p in (data/'storage').rglob('*') if p.is_file())
 record={'prepared':True,'ts':time.time(),'sqlite_sha256':hashlib.sha256((data/'db.sqlite3').read_bytes()).hexdigest(),'blob_files':blob_count,'source_image':info['Image'],'source_reference':info['Config']['Image']}
 (dest/'prepared.json').write_text(json.dumps(record));print(name,json.dumps(record),flush=True)
