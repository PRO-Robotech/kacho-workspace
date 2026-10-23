#!/usr/bin/env python3
"""Closed GitLab native evidence boundaries; all network data is a local fixture."""
import base64,copy,hashlib,importlib.util,io,json,pathlib,unittest,zipfile,subprocess,tempfile
from unittest.mock import patch
import yaml
P=pathlib.Path(__file__).parent
spec=importlib.util.spec_from_file_location('native',P/'operator-gitlab.py')
m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
class Refusal(Exception):pass
def require(ok,why):
    if not ok:raise Refusal(why)
def sha(b):return hashlib.sha256(b).hexdigest()
class NativeProof(unittest.TestCase):
    def setUp(self):
        self.forge={'kind':'gitlab','host':'forge.example','project_id':7,'path':'group/registry-operator'}
        self.head='a'*40;self.tree='b'*40;self.name='ci.yml:kind-e2e'
        self.doc={'.check':{'tags':['docker']},'.runtime':{'extends':'.check'},'workflow':{},'variables':{}}
        for key in m.NATIVE.values():self.doc[key]={'extends':'.runtime','script':['bash ci/gitlab/runtime.sh '+key]}
        self.files={'.gitlab-ci.yml':yaml.safe_dump(self.doc).encode(),'ci/gitlab/runtime.sh':b'run\n','ci/gitlab/provenance.py':b'proof\n','Dockerfile':b'FROM scratch\n','Dockerfile.iam-proxy':b'FROM scratch\n'}
        inputs={k:sha(v) for k,v in self.files.items()}
        self.exp={'forge':self.forge,'repo':self.forge['path'],'head':self.head,'tree':self.tree,'ref':'refs/heads/topic','ci_inputs':inputs,'definitions':{}}
        for name,key in m.NATIVE.items():
            item={'job':self.doc[key],'check':self.doc['.check'],'runtime':self.doc['.runtime'],'workflow':{},'variables':{},'inputs':inputs}
            self.exp['definitions'][name]={'definition':item,'parser':'completion'}
        self.run={'id':10,'project_id':7,'sha':self.head,'ref':'topic','source':'push','status':'success'}
        self.jobs=[{'id':100+i,'name':key,'status':'success','commit':{'id':self.head},'ref':'topic','tag':False,'pipeline':{'id':10,'project_id':7},'finished_at':'2026-01-01T00:00:01Z'} for i,key in enumerate(m.NATIVE.values())]
        self.job=next(j for j in self.jobs if j['name']=='kind-e2e');self.old=[];self.all_override=None;self.detail_id=None
        self.art={'service-daemon-id':b'fixture-daemon\n','daemon-id':b'fixture-daemon\n','native.rc':b'0\n','runtime-wrapper.rc':b'0\n','kind-e2e.log':b'actual native result\n'}
        self.trace=b''
        for phase in ('before','after'):
            record={'phase':phase,'head':self.head,'tree':self.tree,'tracked_clean':True,'project_id':7,'pipeline_id':10,'job_id':self.job['id'],'job':'kind-e2e'}
            line=('OPERATOR_GITLAB_SOURCE_V1 '+json.dumps(record)+'\n').encode();self.art['source-'+phase+'.log']=line;self.trace+=line
        self.project={'id':7,'path_with_namespace':self.forge['path'],'web_url':'https://forge.example/'+self.forge['path'],'container_registry_image_prefix':'registry.example/group/registry-operator'}
        # Independent Git executable oracle, not a second copy of tree/blob encoding.
        self.git_dir=tempfile.TemporaryDirectory();self.addCleanup(self.git_dir.cleanup)
        def git(*args,input=None):
            return subprocess.check_output(['git','-C',self.git_dir.name,*args],input=input)
        git('init','-q')
        self.blobs={name:git('hash-object','-w','--stdin',input=raw).decode().strip() for name,raw in self.files.items()}
        # Include executable and symlink modes, plus a directory whose name sorts
        # differently when Git appends its slash for tree ordering.
        run_tree=git('mktree',input=('100755 blob '+self.blobs['ci/gitlab/runtime.sh']+'\truntime.sh\n100644 blob '+self.blobs['ci/gitlab/provenance.py']+'\tprovenance.py\n').encode()).decode().strip()
        ci_tree=git('mktree',input=('040000 tree '+run_tree+'\tgitlab\n').encode()).decode().strip()
        symlink=git('hash-object','-w','--stdin',input=b'Dockerfile').decode().strip()
        entries=''.join('100644 blob '+self.blobs[n]+'\t'+n+'\n' for n in ('.gitlab-ci.yml','Dockerfile','Dockerfile.iam-proxy'))
        entries+='040000 tree '+ci_tree+'\tci\n120000 blob '+symlink+'\tci.link\n'
        self.exp['tree']=git('mktree',input=entries.encode()).decode().strip()
        self.tree_entries=[]
        for row in git('ls-tree',self.exp['tree']).decode().splitlines():
            mode,kind,rest=row.split(' ',2);oid,name=rest.split('\t')
            self.tree_entries.append({'mode':mode,'type':kind,'id':oid,'name':name})
        self.trace=self.trace.replace(self.tree.encode(),self.exp['tree'].encode())
        for key in ('source-before.log','source-after.log'):self.art[key]=self.art[key].replace(self.tree.encode(),self.exp['tree'].encode())
        outer=self
        class FakeAPI(m.API):
            def __init__(self,forge,req):self.forge=m.descriptor(forge,req);self.require=req
            def pages(self,path):
                if path.startswith('repository/tree?ref='):return outer.tree_entries
                if path.startswith('repository/tree?'):return [{'path':p,'type':'blob'} for p in outer.files if p.startswith('ci/gitlab/')]
                if path.startswith('pipelines?'):return [outer.run]
                if 'include_retried=true' in path:return outer.all_override if outer.all_override is not None else outer.jobs+outer.old
                if 'include_retried=false' in path:return outer.jobs
                raise AssertionError(path)
            def get(self,path,raw=False):
                if path=='':return outer.project
                if path.startswith('repository/commits/'):return {'id':outer.head}
                if path=='pipelines/10':return dict(outer.run,id=outer.detail_id) if outer.detail_id is not None else outer.run
                if path.startswith('repository/files/'):
                    import urllib.parse
                    file=urllib.parse.unquote(path[len('repository/files/'):].split('?')[0].removesuffix('/raw'))
                    data=outer.files[file]
                    if '/raw?' in path:return data
                    return {'file_path':file,'commit_id':outer.head,'blob_id':outer.blobs[file]}
                if path.endswith('/trace'):return outer.trace
                if path.endswith('/artifacts'):
                    buf=io.BytesIO()
                    with zipfile.ZipFile(buf,'w') as z:
                        for key,val in outer.art.items():z.writestr('.ci-evidence/'+key,val)
                    return buf.getvalue()
                raise AssertionError(path)
        self.fake=FakeAPI
    def prove(self):
        with patch.object(m,'API',self.fake):return m.job_evidence(self.exp,self.name,lambda log,parser:1 if log=='actual native result\n' else require(False,'native bytes differ'),require)
    def test_lawful_native_ids_and_hashes(self):
        result=self.prove();self.assertEqual(result['job_id'],self.job['id']);self.assertEqual(result['log_digest'],sha(self.trace));self.assertNotIn('run_id',result)
    def test_source_and_project_negatives(self):
        for field,value in [('id',8),('path_with_namespace','other/registry-operator'),('web_url','https://other.example/x')]:
            old=self.project[field];self.project[field]=value
            with self.assertRaises(Refusal):self.prove()
            self.project[field]=old
        self.exp['tree']='c'*40
        with self.assertRaises(Refusal):self.prove()
    def test_ci_content_and_inventory_negatives(self):
        old=self.files['ci/gitlab/runtime.sh'];self.files['ci/gitlab/runtime.sh']=b'changed'
        with self.assertRaises(Refusal):self.prove()
        self.files['ci/gitlab/runtime.sh']=old;self.files['ci/gitlab/extra.sh']=b'new'
        with self.assertRaises(Refusal):self.prove()
    def test_pipeline_no_missing_or_mr_success(self):
        for field,value in [('status','running'),('source','merge_request_event'),('sha','d'*40),('project_id',8),('ref','foreign')]:
            old=self.run[field];self.run[field]=value
            with self.assertRaises(Refusal):self.prove()
            self.run[field]=old
    def test_retry_and_duplicate_boundaries(self):
        previous=copy.deepcopy(self.job);previous['id']=1;previous['status']='failed';self.old=[previous];self.prove()
        previous['id']=1000
        with self.assertRaises(Refusal):self.prove()
        self.old=[];self.jobs.append(copy.deepcopy(self.job))
        with self.assertRaises(Refusal):self.prove()
    def test_job_identity_and_incomplete(self):
        for field,value in [('status','skipped'),('tag',True),('finished_at',None),('id',True)]:
            old=self.job[field];self.job[field]=value
            with self.assertRaises(Refusal):self.prove()
            self.job[field]=old
    def test_native_cleanup_and_source_marker_boundaries(self):
        for key in ('native.rc','runtime-wrapper.rc'):
            old=self.art[key];self.art[key]=b'1\n'
            with self.assertRaises(Refusal):self.prove()
            self.art[key]=old
        self.art['daemon-id']=b'foreign-daemon'
        with self.assertRaises(Refusal):self.prove()
        self.art['daemon-id']=self.art['service-daemon-id']
        self.trace+=self.art['source-before.log']
        with self.assertRaises(Refusal):self.prove()
    def test_expected_native_definition_is_closed(self):
        import tempfile
        with tempfile.TemporaryDirectory() as tmp:
            root=pathlib.Path(tmp)
            doc=copy.deepcopy(self.doc)
            doc['charts-publish']={'rules':[{'if':'$CI_COMMIT_TAG =~ /^registry-(instance|platform|operator|stack)-/'}]}
            def seed():
                for name,raw in self.files.items():
                    path=root/name;path.parent.mkdir(parents=True,exist_ok=True);path.write_bytes(raw)
                (root/'.gitlab-ci.yml').write_text(yaml.safe_dump(doc))
            def git(co,*args):
                if args==('rev-parse','HEAD'):return self.head
                if args==('status','--porcelain','--untracked-files=all'):return ''
                if args==('remote','get-url','origin'):return 'https://forge.example/group/registry-operator.git'
                if args==('show','HEAD:go.mod'):return 'module github.com/PRO-Robotech/registry-operator\n'
                if args[0]=='ls-files':return '\n'.join(self.files)
                if args[0]=='rev-parse':return self.exp['tree']
                raise AssertionError(args)
            legacy={name:('github-hosted' if name in ('ci.yml:kind-e2e','ci.yml:docker','charts.yml:admission','integration-kaname.yml:kaname') else 'cluster-job','completion') for name in m.NATIVE}
            def check():
                seed();return m.expected(tmp,self.head,'main','refs/heads/topic',self.forge,legacy,git,require,lambda v:sha(v if isinstance(v,bytes) else json.dumps(v,sort_keys=True).encode()),yaml.safe_load)
            result=check();self.assertEqual(sum(v['executor']=='gitlab-job' for v in result['definitions'].values()),4)
            doc['include']='https://other.example/ci.yml'
            with self.assertRaises(Refusal):check()
            del doc['include'];doc['kind-e2e']['script']=['true']
            with self.assertRaises(Refusal):check()
            doc['kind-e2e']['script']=['bash ci/gitlab/runtime.sh kind-e2e'];doc['unexpected']={'script':['true']}
            with self.assertRaises(Refusal):check()
    def test_numeric_identity_family_and_endpoint_consistency(self):
        for value in (True,'1',0,None):
            with self.assertRaises(Refusal):m.positive_ids({'id':value},('id',),require)
        m.positive_ids({'id':1},('id',),require)
        self.detail_id=9
        with self.assertRaises(Refusal):self.prove()
        self.detail_id=None;self.prove()
        self.all_override=[j for j in self.jobs if j['id']!=self.job['id']]
        with self.assertRaises(Refusal):self.prove()
        self.all_override=copy.deepcopy(self.jobs);self.all_override[0]['status']='failed'
        with self.assertRaises(Refusal):self.prove()
        self.all_override=None;self.prove()
        marker=json.loads(self.art['source-before.log'].decode().split(' ',1)[1]);marker['project_id']=True
        self.art['source-before.log']=('OPERATOR_GITLAB_SOURCE_V1 '+json.dumps(marker)).encode()
        with self.assertRaises(Refusal):self.prove()
    def test_nonempty_git_oracle_tampering(self):
        self.prove()
        old=self.tree_entries[0]['mode'];self.tree_entries[0]['mode']='100755'
        with self.assertRaises(Refusal):self.prove()
        self.tree_entries[0]['mode']=old
        self.blobs['Dockerfile']='0'*40
        with self.assertRaises(Refusal):self.prove()
    def test_descriptor_and_credential_host_boundary(self):
        for key,value in [('host','user:secret@forge.example'),('project_id',True),('path','group/other')]:
            bad=dict(self.forge);bad[key]=value
            with self.assertRaises(Refusal):m.descriptor(bad,require)
        with patch.dict('os.environ',{'OPERATOR_GITLAB_TOKEN':'fixture','OPERATOR_GITLAB_TOKEN_HOST':'other.example'}):
            with self.assertRaises(Refusal):m.API(self.forge,require)
        with self.assertRaises(ValueError):m.NoRedirect().redirect_request(None,None,302,'',{},'https://other.example')
if __name__=='__main__':unittest.main(verbosity=2)
