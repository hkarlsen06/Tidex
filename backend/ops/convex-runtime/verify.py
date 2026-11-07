#!/usr/bin/env python3
"""Verify a live runtime's executable, allocator, application reads and real Clerk authentication."""
import argparse,hashlib,json,pathlib,subprocess,urllib.request,urllib.error,urllib.parse
from rehearse import api,check,table,PROJECTS
PORTS={'paeonia':3210,'tidex':3220}

def real_auth(project,url,key,write_user_id=None):
 local_url='http://127.0.0.1:'+str(PORTS[project])
 variables=api(local_url,key,'_system/cli/queryEnvironmentVariables',{})
 secret=next(v['value'] for v in variables if v['name']=='CLERK_SECRET_KEY')
 users=table(local_url,key,'users')
 if project=='tidex':users=[u for u in users if u['id']=='032d8c2a-9af6-4777-99f0-24e2c4058bf3']
 else:
  active={m['user_id'] for m in table(local_url,key,'couple_members') if m['status']=='active'}
  users=[u for u in users if u['id'] in active]
 if write_user_id is not None:users=[u for u in users if u['id']==write_user_id]
 headers={'Authorization':'Bearer '+secret,'User-Agent':'Tidex-Health/1.0','Content-Type':'application/json'}
 for user in users:
  if not user.get('clerk_user_id'):continue
  request=urllib.request.Request('https://api.clerk.com/v1/sessions?'+urllib.parse.urlencode({'user_id':user['clerk_user_id']}),headers=headers)
  sessions=json.load(urllib.request.urlopen(request,timeout=15))
  active=[s for s in sessions if s['status']=='active']
  if not active:continue
  for endpoint in ['/tokens/convex','/tokens']:
   request=urllib.request.Request('https://api.clerk.com/v1/sessions/'+active[0]['id']+endpoint,data=b'{}',headers=headers)
   try:token=json.load(urllib.request.urlopen(request,timeout=15))['jwt']
   except urllib.error.HTTPError as error:
    if error.code==404:continue
    raise
   path='sync:revisions' if project=='tidex' else 'access:get_access_snapshot'
   request=urllib.request.Request(url+'/api/query',data=json.dumps({'path':path,'args':{},'format':'json'}).encode(),headers={'Authorization':'Bearer '+token,'Content-Type':'application/json','User-Agent':'Tidex-Health/1.0'})
   result=json.load(urllib.request.urlopen(request,timeout=15))
   assert result['status']=='success','Real Clerk JWT was refused'
   socket_input={'project':project,'url':url,'jwt':token,'readOnly':write_user_id is None}
   if write_user_id is not None:
    socket_input.update({'mutationUrl':local_url,'key':key,'userId':user['id'],'identity':{'subject':user['clerk_user_id'],'issuer':'https://runtime-test.invalid','tokenIdentifier':'https://runtime-test.invalid|'+user['clerk_user_id']}})
   socket_result=json.loads(subprocess.check_output(['node',str(pathlib.Path(__file__).parent/'check-subscription.cjs')],input=json.dumps(socket_input),text=True,stderr=subprocess.DEVNULL,timeout=40))
   assert socket_result['initial_received'],'Real JWT subscription did not arrive'
   if write_user_id is not None:assert socket_result['mutation_observed'],'Production write was not observed'
   return {'real_jwt_accepted':True,'query':path,'real_jwt_subscription_received':True,'write_observed':socket_result['mutation_observed']}
 raise RuntimeError('No existing operator session available for a real JWT check')

def verify(project,manifest,identity=True):
 stack,container=PROJECTS[project];url='http://127.0.0.1:'+str(PORTS[project]);key=(pathlib.Path(stack)/'admin-key').read_text().strip()
 info=json.loads(subprocess.check_output(['docker','inspect',container]))[0]
 assert info['State']['Running'],'Backend is not running'
 pid=info['State']['Pid'];exe=pathlib.Path('/proc/'+str(pid)+'/exe')
 if identity:
  assert hashlib.sha256(exe.read_bytes()).hexdigest()==manifest['backend_sha256'],'Running executable differs from the pinned release'
  assert '/usr/local/lib/libjemalloc.so.2' in pathlib.Path('/proc/'+str(pid)+'/maps').read_text(),'jemalloc is not mapped'
  assert info['Config']['Labels']['org.opencontainers.image.revision']==manifest['revision']
 result=check(project,url,key,writes=False)
 result.update(real_auth(project,url,key))
 result.update({'running':True,'release_verified':identity,'pid':pid,'image':info['Config']['Image']})
 return result

def main():
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('project',choices=PROJECTS);p.add_argument('--images',type=pathlib.Path,required=True);p.add_argument('--output',type=pathlib.Path,required=True);p.add_argument('--baseline',action='store_true');a=p.parse_args()
 result=verify(a.project,json.loads(a.images.read_text()),identity=not a.baseline)
 a.output.write_text(json.dumps(result));a.output.chmod(0o600)
 print(json.dumps({'project':a.project,'running':True,'release_verified':result['release_verified'],'real_jwt_accepted':True,'anonymous_refused':result['anonymous_refused'],'counts':result['counts']}),flush=True)

if __name__=='__main__':main()
