#!/usr/bin/env python3
"""Native GitLab operator evidence; credentials never cross the declared host."""
import base64
import hashlib
import io
import json
import os
from pathlib import Path
import re
import urllib.request
import urllib.parse
import zipfile
import yaml

NATIVE = {'ci.yml:generate':'generate','ci.yml:test':'test','ci.yml:injections':'injections',
          'ci.yml:lint':'lint','ci.yml:chart':'chart','ci.yml:zot':'zot',
          'ci.yml:kind-e2e':'kind-e2e','ci.yml:docker':'images','charts.yml:render':'charts-render',
          'charts.yml:ct':'charts-ct','charts.yml:admission':'charts-admission',
          'charts.yml:kaname-manifest':'charts-kaname-manifest','integration-kaname.yml:kaname':'kaname'}


def positive_ids(value, keys, require):
    require(all(type(value.get(k)) is int and value[k]>0 for k in keys),'invalid native numeric identity')


def descriptor(value, require):
    require(isinstance(value,dict) and set(value)=={'kind','host','project_id','path'}, 'invalid forge descriptor')
    require(value['kind']=='gitlab' and type(value['project_id']) is int and value['project_id']>0,
            'invalid GitLab project identity')
    require(isinstance(value['host'],str) and re.fullmatch(r'[a-z0-9][a-z0-9.-]*(?::[0-9]+)?',value['host']), 'invalid GitLab host')
    require(isinstance(value['path'],str) and re.fullmatch(r'(?:[A-Za-z0-9_-]+/)+registry-operator',value['path']), 'invalid Registry project path')
    return value


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        raise ValueError('GitLab redirects are forbidden')


class API:
    def __init__(self, forge, require):
        self.forge=descriptor(forge,require); self.require=require
        self.base='https://'+forge['host']+'/api/v4/projects/'+str(forge['project_id'])+'/'
        self.headers={'Accept':'application/json','Cache-Control':'no-cache'}
        token=os.environ.get('OPERATOR_GITLAB_TOKEN')
        if token:
            require(os.environ.get('OPERATOR_GITLAB_TOKEN_HOST')==forge['host'], 'credential host binding differs')
            self.headers['PRIVATE-TOKEN']=token
        self.opener=urllib.request.build_opener(NoRedirect())
    def get(self, path, raw=False):
        self.require(not path.startswith('/') and '://' not in path, 'non-relative GitLab API path')
        with self.opener.open(urllib.request.Request(self.base.rstrip('/')+('/'+path if path else ''),headers=self.headers),timeout=120) as response:
            self.require(response.status==200, 'GitLab response is not successful')
            data=response.read(32*1024*1024+1)
            self.require(len(data)<=32*1024*1024, 'GitLab evidence exceeds bound')
        return data if raw else json.loads(data)
    def pages(self,path):
        rows=[]
        for page in range(1,1001):
            chunk=self.get(path+('&' if '?' in path else '?')+urllib.parse.urlencode({'per_page':100,'page':page}))
            self.require(isinstance(chunk,list),'GitLab pagination is not an array')
            rows.extend(chunk)
            if len(chunk)<100:return rows
        self.require(False,'GitLab pagination exceeds bound')
    def file(self,path,head):
        item=self.get('repository/files/'+urllib.parse.quote(path,safe='')+'?ref='+head)
        self.require(item.get('file_path')==path and item.get('commit_id')==head,'GitLab file/source differs')
        raw=self.get('repository/files/'+urllib.parse.quote(path,safe='')+'/raw?ref='+head,raw=True)
        blob=hashlib.sha1(b'blob '+str(len(raw)).encode()+b'\0'+raw).hexdigest()
        self.require(blob==item.get('blob_id'),'GitLab raw file blob differs')
        return raw


def source(api, exp, require):
    project=api.get('')
    positive_ids(project,('id',),require)
    require(project.get('id')==exp['forge']['project_id'] and project.get('path_with_namespace')==exp['repo'], 'GitLab project identity differs')
    require(project.get('web_url')=='https://'+exp['forge']['host']+'/'+exp['repo'], 'GitLab project host differs')
    commit=api.get('repository/commits/'+exp['head'])
    require(commit.get('id')==exp['head'],'GitLab commit differs')
    entries=api.pages('repository/tree?ref='+exp['head']+'&recursive=false')
    names=[e['name'] for e in entries]
    require(len(set(names))==len(names),'duplicate Git tree entry')
    payload=b''
    for e in sorted(entries,key=lambda e:(e['name']+('/' if e['type']=='tree' else '')).encode()):
        require('/' not in e['name'] and '\0' not in e['name'] and e['mode'] in ('040000','100644','100755','120000','160000'),'invalid Git tree entry')
        payload+=e['mode'].lstrip('0').encode()+b' '+e['name'].encode()+b'\0'+bytes.fromhex(e['id'])
    tree=hashlib.sha1(b'tree '+str(len(payload)).encode()+b'\0'+payload).hexdigest()
    require(tree==exp['tree'],'GitLab source tree differs')
    ci_files=api.pages('repository/tree?'+urllib.parse.urlencode({'ref':exp['head'],'path':'ci/gitlab','recursive':'true'}))
    paths={e['path'] for e in ci_files if e['type']=='blob'}|{'.gitlab-ci.yml','Dockerfile','Dockerfile.iam-proxy'}
    require(paths==set(exp['ci_inputs']),'transitive CI input inventory differs')
    source_files={}
    for path,wanted in exp['ci_inputs'].items():
        source_files[path]=api.file(path,exp['head'])
        require(hashlib.sha256(source_files[path]).hexdigest()==wanted,'GitLab CI input differs: '+path)
    doc=yaml.safe_load(source_files['.gitlab-ci.yml'])
    require(isinstance(doc,dict) and 'include' not in doc,'native CI includes unsupported')
    for name,target in exp['definitions'].items():
        job=doc[NATIVE[name]]
        item={'job':job,'check':doc['.check'],'runtime':doc['.runtime'] if job.get('extends')=='.runtime' else None,
              'workflow':doc.get('workflow'),'variables':doc.get('variables'),'inputs':exp['ci_inputs']}
        require(item==target['definition'],'actual native CI definition differs')
    return project


def job_evidence(exp,name,census,require):
    api=API(exp['forge'],require);project=source(api,exp,require)
    ref=exp['ref'].removeprefix('refs/heads/')
    runs=api.pages('pipelines?'+urllib.parse.urlencode({'sha':exp['head'],'ref':ref,'source':'push','order_by':'id','sort':'desc'}))
    require(runs,'no branch push pipeline')
    require(all(type(r.get('id')) is int and r['id']>0 for r in runs),'invalid pipeline IDs')
    chosen_id=max(runs,key=lambda r:r['id'])['id']
    run=api.get('pipelines/'+str(chosen_id))
    positive_ids(run,('id','project_id'),require)
    require(run['id']==chosen_id,'pipeline detail identity differs')
    require(run.get('project_id')==exp['forge']['project_id'] and run.get('sha')==exp['head'] and run.get('ref')==ref and run.get('source')=='push' and run.get('status')=='success','latest GitLab branch pipeline is not exact-source success')
    jobs=api.pages('pipelines/'+str(run['id'])+'/jobs?include_retried=true')
    active=api.pages('pipelines/'+str(run['id'])+'/jobs?include_retried=false')
    require(len(active)==len(NATIVE) and {j.get('name') for j in active}==set(NATIVE.values()),'native job inventory differs')
    require(all(j.get('status')=='success' for j in active),'native pipeline has incomplete/failed jobs')
    require(all(type(j.get('id')) is int and j['id']>0 for j in jobs+active),'invalid job IDs')
    require(len({j['id'] for j in jobs})==len(jobs),'duplicate job ID')
    for observed in jobs+active:
        positive_ids(observed.get('pipeline',{}),('id','project_id'),require)
    all_by_id={j['id']:j for j in jobs}
    require(all(j['id'] in all_by_id and all(all_by_id[j['id']].get(k)==j.get(k) for k in ('name','status','commit','ref','tag','pipeline','finished_at')) for j in active),'active/all job endpoint binding differs')
    selected=[j for j in active if j.get('name')==NATIVE[name]]
    require(len(selected)==1,'missing/duplicate current GitLab job')
    job=selected[0]
    positive_ids(job.get('pipeline',{}),('id','project_id'),require)
    require(job.get('status')=='success' and job.get('commit',{}).get('id')==exp['head'] and job.get('ref')==ref and job.get('tag') is False,'GitLab job source/status differs')
    require(job.get('pipeline',{}).get('id')==run['id'] and job['pipeline'].get('project_id')==exp['forge']['project_id'],'GitLab job pipeline/project differs')
    require(type(job.get('id')) is int and job['id']>0 and job.get('finished_at'),'GitLab job not terminal')
    older=[j for j in jobs if j.get('name')==NATIVE[name] and j['id']!=job['id']]
    require(all(j['id']<job['id'] and j['id'] not in {a['id'] for a in active} for j in older),'GitLab retried-job ordering differs')
    trace=api.get('jobs/'+str(job['id'])+'/trace',raw=True)
    archive=api.get('jobs/'+str(job['id'])+'/artifacts',raw=True)
    with zipfile.ZipFile(io.BytesIO(archive)) as z:
        require(len(z.namelist())==len(set(z.namelist())),'duplicate artifact path')
        def read(path):
            info=z.getinfo('.ci-evidence/'+path)
            require(info.file_size<16*1024*1024,'artifact exceeds bound')
            return z.read(info)
        require(read('native.rc').strip()==b'0','native command failed/missing')
        require(read('runtime-wrapper.rc').strip()==b'0','job-private runtime cleanup failed/missing')
        daemon=read('service-daemon-id').strip()
        require(bool(daemon) and daemon==read('daemon-id').strip(),'service/inner daemon binding differs')
        native=read(NATIVE[name]+'.log').decode()
        markers=[]
        for phase in ('before','after'):
            raw=read('source-'+phase+'.log').decode().strip()
            require(raw.startswith('OPERATOR_GITLAB_SOURCE_V1 '),'source artifact missing marker')
            marker=json.loads(raw.split(' ',1)[1]);markers.append(marker)
            positive_ids(marker,('project_id','pipeline_id','job_id'),require)
            require(marker.get('tracked_clean') is True,'source cleanliness is not boolean true')
            require(marker=={'phase':phase,'head':exp['head'],'tree':exp['tree'],'tracked_clean':True,'project_id':exp['forge']['project_id'],'pipeline_id':run['id'],'job_id':job['id'],'job':NATIVE[name]},'native source identity differs')
            require(trace.decode().count(raw)==1,'source marker missing/duplicated in native trace')
        if NATIVE[name]=='images':
            for image in ('operator','iam-proxy'):
                refs=json.loads(read(image+'-digests.json'))
                require(isinstance(refs,list) and refs and all(re.fullmatch(re.escape(project['container_registry_image_prefix']+'/'+image)+r'@sha256:[0-9a-f]{64}',r) for r in refs),'image publication digest missing')
        count=census(native,exp['definitions'][name]['parser'])
    return {'executor':'gitlab-job','pipeline_id':run['id'],'job_id':job['id'],'cases':count,'log_digest':hashlib.sha256(trace).hexdigest(),'artifacts_digest':hashlib.sha256(archive).hexdigest()}


def inventory(legacy):
    return {name:('gitlab-job' if executor=='github-hosted' else executor,parser)
            for name,(executor,parser) in legacy.items()}


def expected(co,head,base,ref,forge,legacy,git,require,digest,load):
    descriptor(forge,require)
    require(git(co,'rev-parse','HEAD')==head and not git(co,'status','--porcelain','--untracked-files=all'),'checkout source differs/dirty')
    require(ref.startswith('refs/heads/') and len(ref)>11,'explicit branch ref required')
    remote=git(co,'remote','get-url','origin')
    host,path=forge['host'],forge['path']
    accepted={'https://'+host+'/'+path,'https://'+host+'/'+path+'.git','ssh://git@'+host+'/'+path,'ssh://git@'+host+'/'+path+'.git'}
    if ':' not in host:accepted|={'git@'+host+':'+path,'git@'+host+':'+path+'.git'}
    require(remote in accepted,'remote differs from trusted forge descriptor')
    require(re.findall(r'^module\s+(\S+)\s*$',git(co,'show','HEAD:go.mod'),re.M)==['github.com/PRO-Robotech/registry-operator'],'unsupported operator module')
    raw=(Path(co)/'.gitlab-ci.yml').read_bytes();doc=load(raw)
    require(isinstance(doc,dict) and 'include' not in doc,'remote CI includes are unsupported')
    globals_={'workflow','stages','variables','default'}
    actual={k for k in doc if not k.startswith('.') and k not in globals_}
    require(actual==set(NATIVE.values())|{'charts-publish'},'native CI job inventory differs')
    require(doc['charts-publish'].get('rules')==[{'if':'$CI_COMMIT_TAG =~ /^registry-(instance|platform|operator|stack)-/'}],'chart publication is not the closed tag-only exclusion')
    files=git(co,'ls-files','.gitlab-ci.yml','ci/gitlab','Dockerfile','Dockerfile.iam-proxy').splitlines()
    require('.gitlab-ci.yml' in files and 'ci/gitlab/provenance.py' in files and 'ci/gitlab/runtime.sh' in files,'native proof inputs missing')
    inputs={p:hashlib.sha256((Path(co)/p).read_bytes()).hexdigest() for p in files}
    definitions={}
    for name,(executor,parser) in inventory(legacy).items():
        key=NATIVE[name];job=doc[key]
        require(isinstance(job,dict) and not ({'parallel','trigger','needs'}&set(job)),'unsupported native job')
        require(job.get('rules') in (None,[{'if':'$CI_PIPELINE_SOURCE == "push"'}]),'unsupported native job rule')
        parent=job.get('extends');require(parent in ('.check','.runtime'),'unsupported native job parent')
        expected_script='bash ci/gitlab/'+('runtime.sh' if parent=='.runtime' else 'run.sh')+' '+key
        require(job.get('script')==[expected_script],'native job command differs')
        require(doc['.check'].get('tags')==['docker'],'native jobs require explicit Docker executor tag')
        require(doc['.runtime'].get('extends')=='.check','native runtime ancestry differs')
        item={'job':job,'check':doc['.check'],'runtime':doc['.runtime'] if parent=='.runtime' else None,
              'workflow':doc.get('workflow'),'variables':doc.get('variables'),'inputs':inputs}
        definitions[name]={'executor':executor,'parser':parser,'native_job':key,'definition':item,
                           'definition_digest':digest(item),'workflow_digest':digest(raw),'name':key}
    return {'schema':'operator-stand-v1','forge':forge,'operator_kind':'registry-operator','repo':path,
            'head':head,'tree':git(co,'rev-parse','HEAD^{tree}'),'base':base,'base_sha':git(co,'rev-parse',base),
            'ref':ref,'source':'operator-full','full':True,'ledger':list(legacy),'jobs':list(legacy),
            'definitions':definitions,'ci_inputs':inputs}
