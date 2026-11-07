#!/usr/bin/env python3
"""Run old/new/rollback application checks on private copies with external networking blocked."""
import datetime
import fcntl
import argparse,base64,hashlib,json,os,pathlib,shutil,subprocess,time,secrets,urllib.request,urllib.error,uuid
ROOT=pathlib.Path('/srv/convex-runtime/rehearsal')
PROJECTS={'paeonia':('/srv/paeonia/convex','convex-backend-1'), 'tidex':('/srv/tidex/convex','tidex-convex-backend-1')}

def command(*args):return subprocess.check_output(args,stderr=subprocess.DEVNULL,text=True).strip()

def api(url,key,path,args,identity=None,kind='query'):
 auth=key+(':'+base64.b64encode(json.dumps(identity).encode()).decode() if identity else '')
 req=urllib.request.Request(url+'/api/'+kind,data=json.dumps({'path':path,'args':args,'format':'json'}).encode(),headers={'Authorization':'Convex '+auth,'Content-Type':'application/json'})
 with urllib.request.urlopen(req,timeout=25) as r:out=json.load(r)
 if out.get('status')!='success':raise RuntimeError('Function failed: '+path)
 return out['value']

def table(url,key,name):
 return api(url,key,'_system/cli/tableData:default',{'table':name,'order':'asc','paginationOpts':{'numItems':100,'cursor':None}})['page']

def fingerprint(value):return hashlib.sha256(json.dumps(value,sort_keys=True,separators=(',',':')).encode()).hexdigest()

def check(project,url,key,writes):
 users=table(url,key,'users')
 eligible=[u for u in users if u.get('clerk_user_id') and not u.get('banned_at')]
 if project=='tidex':eligible=[u for u in eligible if u['id']!='032d8c2a-9af6-4777-99f0-24e2c4058bf3']+ [u for u in eligible if u['id']=='032d8c2a-9af6-4777-99f0-24e2c4058bf3']
 if project=='paeonia':
  active={m['user_id'] for m in table(url,key,'couple_members') if m['status']=='active'}
  eligible=[u for u in eligible if u['id'] in active]
 user=eligible[-1] if project=='tidex' else eligible[0]
 who={'subject':user['clerk_user_id'],'issuer':'https://runtime-test.invalid','tokenIdentifier':'https://runtime-test.invalid|'+user['clerk_user_id']}
 required={'tidex':['users','profiles','jobs','user_shifts','events'],'paeonia':['users','profiles','couples','couple_members','thread_messages']}[project]
 counts={name:api(url,key,'_system/frontend/tableSize:default',{'tableName':name}) for name in required}
 reads={}
 if project=='tidex':
  assert api(url,key,'monitoring:health',{})=={'ok':True}
  for name in ['jobs','user_shifts','events','user_settings']:
   out=api(url,key,'sync:pull',{'table':name,'after':0,'limit':100},who);assert isinstance(out['rows'],list);assert all(row['user_id']==user['id'] for row in out['rows']);reads[name]=fingerprint(out)
  revisions=api(url,key,'sync:revisions',{},who);assert 'jobs' in revisions
  path='sync:revisions';args={}
 else:
  for path in ['access:get_access_snapshot','identity:get_notification_preferences','badges:get_badges']:
   value=api(url,key,path,{},who);assert isinstance(value,(list,dict));reads[path]=fingerprint(value)
  path='identity:get_notification_preferences';args={}
 # Anonymous callers must not obtain a private query, including internal monitoring.
 request=urllib.request.Request(url+'/api/query',data=json.dumps({'path':path,'args':args,'format':'json'}).encode(),headers={'Content-Type':'application/json'})
 try:
  with urllib.request.urlopen(request,timeout=10) as response:anonymous=json.load(response)
 except urllib.error.HTTPError:anonymous={'status':'error'}
 assert anonymous.get('status')!='success','Anonymous private read was accepted'
 if writes:
  if project=='tidex':
   row={'id':str(uuid.uuid4()),'name':'Runtime verification','is_default':False,'sort_order':999,'currency':'kr'}
   created=api(url,key,'jobs:insert',{'row':row,'expected_user_id':user['id']},who,kind='mutation');assert created['status']=='ok'
   found=api(url,key,'sync:pull',{'table':'jobs','after':created['row']['revision']-1,'limit':100},who)
   assert any(r['id']==row['id'] for r in found['rows'])
   removed=api(url,key,'jobs:remove',{'id':row['id'],'expected_revision':created['row']['revision'],'expected_user_id':user['id']},who,kind='mutation');assert removed['status']=='ok'
  else:
   previous=api(url,key,path,args,who);original=previous['lock_screen_detail_level'];changed='private' if original=='descriptive' else 'descriptive'
   saved=api(url,key,'identity:set_lock_screen_detail_level',{'p_level':changed},who,kind='mutation');assert saved['lock_screen_detail_level']==changed
   assert api(url,key,path,args,who)['lock_screen_detail_level']==changed
   api(url,key,'identity:set_lock_screen_detail_level',{'p_level':original},who,kind='mutation')
   grant=api(url,key,'entitlementGrants:create_entitlement_grant',{'p_user_id':user['id'],'p_grant_kind':'test','p_reason':'Isolated runtime rehearsal','p_granted_by':'runtime-rehearsal','p_expires_at':(datetime.datetime.now(datetime.timezone.utc)+datetime.timedelta(days=1)).isoformat()},kind='mutation')
   overview=api(url,key,'games:get_games_overview',{},who);assert overview['couple_id']
   daily=api(url,key,'daily:get_today_daily_challenge_snapshot',{},who);assert isinstance(daily,list) and daily
   state=api(url,key,'widget:get_lock_screen_state',{'p_now':time.strftime('%Y-%m-%dT%H:%M:00.000Z',time.gmtime())},who);assert isinstance(state,dict)
   assert api(url,key,'push:send_push',{'kind':'app','outbox_id':str(uuid.uuid4())},kind='action') is None
 socket_result=None
 if writes:
  request={'project':project,'url':url,'key':key,'identity':who,'userId':user['id']}
  socket_result=json.loads(subprocess.check_output(['node',str(pathlib.Path(__file__).parent/'check-subscription.cjs')],input=json.dumps(request),text=True,stderr=subprocess.DEVNULL,timeout=40))
 return {'counts':counts,'read_hashes':reads,'anonymous_refused':True,'writes_checked':writes,'websocket':socket_result}

def stop(name,log):
 try:
  info=json.loads(command('docker','inspect',name))[0]
 except subprocess.CalledProcessError:return
 assert info['Config']['Labels'].get('convex-runtime-rehearsal')=='true','Unexpected test container owner'
 with log.open('w') as f:subprocess.run(['docker','logs',name],stdout=f,stderr=f)
 subprocess.run(['docker','stop','--time','10',name],check=True,stdout=subprocess.DEVNULL)
 subprocess.run(['docker','rm','--volumes',name],check=True,stdout=subprocess.DEVNULL)
 for _ in range(100):
  try:command('docker','inspect',name)
  except subprocess.CalledProcessError:return
  time.sleep(.1)
 raise RuntimeError('Test container removal did not complete')

def main():
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('project',choices=PROJECTS);p.add_argument('--images',type=pathlib.Path,required=True);a=p.parse_args()
 lease=(ROOT/'experiment.lock').open('w');fcntl.flock(lease,fcntl.LOCK_EX|fcntl.LOCK_NB)
 stack,live=PROJECTS[a.project];folder=ROOT/a.project;assert (folder/'prepared.json').exists()
 manifest=json.loads(a.images.read_text());key=(pathlib.Path(stack)/'admin-key').read_text().strip()
 live_info=json.loads(command('docker','inspect',live))[0]
 prepared=json.loads((folder/'prepared.json').read_text())
 old=prepared['source_reference'];new=manifest['images']['backend']['image']
 name='convex-rehearsal-'+a.project;url='http://127.0.0.1:3320';record={'complete':False,'project':a.project,'old_image':old,'new_image':new,'expected_backend_sha256':manifest['backend_sha256'],'stages':{}}
 out=folder/'result.json';out.write_text(json.dumps(record));os.chmod(out,0o600)
 source_env=dict(v.split('=',1) for v in live_info['Config']['Env'] if '=' in v)
 uses_s3='S3_STORAGE_MODULES_BUCKET' in source_env
 env={k:v for k,v in source_env.items() if not k.startswith(('AWS_','S3_','MALLOC_')) and k not in ['LD_PRELOAD','POSTGRES_URL','MYSQL_URL','DATABASE_URL']}
 env.update({'CONVEX_CLOUD_ORIGIN':'http://127.0.0.1:3210','CONVEX_SITE_ORIGIN':'http://127.0.0.1:3211','DISABLE_BEACON':'true','DISABLE_METRICS_ENDPOINT':'true'})
 mock_secret=secrets.token_hex(24);gateway=json.loads(command('docker','network','inspect','convex-rehearsal'))[0]['IPAM']['Config'][0]['Gateway']
 if uses_s3:
  env.update({k:v for k,v in source_env.items() if k.startswith(('S3_','AWS_'))})
  env.update({'AWS_ACCESS_KEY_ID':'rehearsal','AWS_SECRET_ACCESS_KEY':mock_secret,'S3_ENDPOINT_URL':'http://'+gateway+':3340'})
 assert all('\n' not in v for v in env.values())
 env_file=folder/'clone.env';env_file.write_text(''.join(k+'='+v+'\n' for k,v in env.items()));os.chmod(env_file,0o600)
 stop(name,folder/'previous.log')
 working=folder/'working';mock=None
 def stop_mock():
  if mock is not None:
   mock.terminate()
   try:mock.wait(timeout=5)
   except subprocess.TimeoutExpired:mock.kill();mock.wait()
 try:
  for stage,image in [('old',old),('new',new),('rollback',old)]:
   if stage!='new':
    if working.exists():shutil.rmtree(working)
    shutil.copytree(folder/'data',working)
   if uses_s3:
    s3=working/'mock-s3';s3.mkdir(exist_ok=True)
    for category in ['modules','files','search','exports','snapshot_imports']:
     bucket=s3/source_env['S3_STORAGE_'+category.upper()+'_BUCKET']
     if not bucket.exists():
      local=working/'storage'/category
      if local.exists():shutil.move(str(local),str(bucket))
      else:bucket.mkdir()
    mock_env=os.environ.copy();mock_env['RCLONE_AUTH_KEY']='\"rehearsal,'+mock_secret+'\"'
    mock_log=(folder/(stage+'-s3.log')).open('w')
    mock=subprocess.Popen(['rclone','serve','s3',str(s3),'--addr',gateway+':3340'],env=mock_env,stdout=mock_log,stderr=mock_log)
    for _ in range(50):
     if mock.poll() is not None:raise RuntimeError('Isolated S3 server exited')
     try:urllib.request.urlopen('http://'+gateway+':3340',timeout=.2);break
     except urllib.error.HTTPError:break
     except OSError:time.sleep(.1)
   subprocess.run(['docker','run','-d','--name',name,'--label','convex-runtime-rehearsal=true','--network','convex-rehearsal','--stop-signal','SIGINT','--cpus','2','--memory','1536m','--env-file',str(env_file),'-v',str(working)+':/convex/data',image],check=True,stdout=subprocess.DEVNULL)
   address=json.loads(command('docker','inspect',name))[0]['NetworkSettings']['Networks']['convex-rehearsal']['IPAddress']
   url='http://'+address+':3210'
   for _ in range(120):
    if json.loads(command('docker','inspect',name))[0]['State']['Status']!='running':raise RuntimeError('Test backend exited before readiness; inspect its private log')
    try:
     with urllib.request.urlopen(url+'/version',timeout=1) as response:
      if response.status==200:break
    except (OSError,ValueError):time.sleep(.25)
   else:raise RuntimeError('Test backend did not start')
   external=subprocess.run(['docker','exec',name,'curl','--connect-timeout','1','--max-time','2','-fsS','https://api.clerk.com'],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
   assert external.returncode!=0,'Test container has external network access'
   # Do not mutate the baseline used for the in-place migration comparison.
   result=check(a.project,url,key,writes=stage=='new');record['stages'][stage]=result
   if stage=='new':
    assert result['counts']==record['stages']['old']['counts'],'Application table counts changed during engine migration'
    assert result['read_hashes']==record['stages']['old']['read_hashes'],'Application reads changed during engine migration'
    info=json.loads(command('docker','inspect',name))[0];pid=info['State']['Pid']
    assert hashlib.sha256(pathlib.Path('/proc/'+str(pid)+'/exe').read_bytes()).hexdigest()==manifest['backend_sha256']
    assert '/usr/local/lib/libjemalloc.so.2' in pathlib.Path('/proc/'+str(pid)+'/maps').read_text()
    record['release_and_allocator_verified']=True
   if stage=='rollback':assert result==record['stages']['old'],'Restored old snapshot does not match baseline'
   stop(name,folder/(stage+'.log'));stop_mock();mock=None;out.write_text(json.dumps(record));print(a.project,stage,'passed',flush=True)
  record['complete']=True;out.write_text(json.dumps(record));print(a.project,'upgrade and rollback verified',flush=True)
 finally:
  stop(name,folder/'final.log');stop_mock()

if __name__=='__main__':main()
