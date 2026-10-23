#!/usr/bin/env python3
# Настоящие исходники и native фрагменты — фикстуры формы, не текущая приёмка продукта.
import base64
from collections import Counter
import copy
import hashlib
import importlib.util
import json
from pathlib import Path
import re
import sys
import unittest
sys.dont_write_bytecode=True
HERE=Path(__file__).resolve().parent
spec=importlib.util.spec_from_file_location('gate',HERE/'operator-stand.py');M=importlib.util.module_from_spec(spec);spec.loader.exec_module(M)
FIX=HERE/'operator-stand-fixtures'
DATA=json.loads((FIX/'pipeline-source-native.json').read_text())
OLD={k:v.encode() for k,v in DATA['base'].items()}
NEW={**OLD,**{k:v.encode() for k,v in DATA['delta'].items()}}
for key in DATA['deleted']:NEW.pop(key)
LOGS={key:(FIX/('pipeline-'+key+'.log')).read_text() for key in ('legacy870','extended751')}
REPO='PRO-Robotech/vault-operator';NAME='test-e2e.yml:test-e2e-pipeline'
class PipelineSource(unittest.TestCase):
 def verify(self,files,log):M.verify_vault_native(REPO,NAME,log,M.vault_pipeline_inventory(files))
 def test_real_old_and_new(self):
  for label,files,count in [('legacy870',OLD,14),('extended751',NEW,16)]:
   with self.subTest(label=label):
    self.assertEqual(len(M.vault_pipeline_inventory(files)),count);self.verify(files,LOGS[label]);print('PIPELINE_SOURCE_CASE '+label+' accepted',flush=True)
 def test_native_negatives_with_twins(self):
  log=LOGS['extended751'];first='TestSecretLegacyKVCompatibility'
  omit=lambda name:'\n'.join(x for x in log.splitlines() if name not in x)+'\n'
  negatives={'old14':LOGS['legacy870'],'missing-first':omit(first),'missing-second':omit('TestS3LegacyKVCompatibility'),
   'wrong-name':log.replace(first,'TestUnexpectedReplacement'),'duplicate':log+'=== RUN   '+first+'\n',
   'skip':log.replace('--- PASS: '+first,'--- SKIP: '+first),'failed':log.replace('--- PASS: '+first,'--- FAIL: '+first),
   'unexpected':log+'=== RUN   TestUnexpected\n--- PASS: TestUnexpected (0.01s)\n'}
  for label,broken in negatives.items():
   with self.subTest(label=label):
    self.verify(NEW,log)
    with self.assertRaises(M.Unread):self.verify(NEW,broken)
    print('PIPELINE_SOURCE_CASE '+label+' rejected twin accepted',flush=True)
  with self.assertRaises(M.Unread):self.verify(OLD,log)
  with self.assertRaises(M.Unread):M.verify_vault_native(REPO,NAME,log)
 def test_source_negatives_with_twins(self):
  path='test/e2e_pipeline/kv_compat_test.go';owner='test/e2e_pipeline/ownership_test.go'
  mutations={
   'unknown-tag':(path,lambda x:x.replace(b'//go:build e2e',b'//go:build e2e || other')),
   'unknown-declaration':(path,lambda x:x.replace(b'func TestSecretLegacyKVCompatibility(t *testing.T)',b'func TestSecretLegacyKVCompatibility(ctx *testing.T)',1)),
   'duplicate-test':(path,lambda x:x+b'\nfunc TestSecretLegacyKVCompatibility(t *testing.T) {}\n'),
   'dynamic-child':(owner,lambda x:x.replace(b't.Run("a policy that exists before the claim keeps its body",',b't.Run(dynamicName,',1)),
   'nested-child':(owner,lambda x:x.replace(b'\tt.Run(',b'\t\tt.Run(',1)),
   'baseline-removed':(owner,lambda x:x.replace(b'func TestGuestOnOperatorMountE2E',b'func XGuestOnOperatorMountE2E'))}
  for label,(name,change) in mutations.items():
   with self.subTest(label=label):
    files=dict(NEW);files[name]=change(files[name]);self.assertNotEqual(files[name],NEW[name]);self.verify(NEW,LOGS['extended751'])
    with self.assertRaises(M.Unread):M.vault_pipeline_inventory(files)
    print('PIPELINE_SOURCE_CASE '+label+' rejected twin accepted',flush=True)
 def test_authoritative_api_blob_binding(self):
  original=M.api;head=DATA['new_head'];mode='lawful';calls=[]
  def api(repo,endpoint,raw=False):
   self.assertEqual(repo,REPO);self.assertTrue(endpoint.endswith('?ref='+head));calls.append(endpoint)
   def item(path):
    data=NEW[path];sha=DATA['new_blob_ids'][path]
    return {'type':'file','path':path,'sha':sha,'encoding':'base64','content':base64.b64encode(data).decode()}
   if endpoint == 'contents/test/e2e_pipeline?ref='+head:
    result=[item(k) for k in sorted(NEW)]
    if mode=='nested':result.append({'type':'dir','path':'test/e2e_pipeline/other'})
    return result
   path=endpoint.removeprefix('contents/').split('?',1)[0];result=item(path)
   if mode=='wrong-blob':result['content']=base64.b64encode(NEW[path]+b'\n').decode()
   if mode=='wrong-path':result['path']='other'
   return result
  M.api=api
  try:
   required,digest=M.vault_pipeline_source(REPO,head);self.assertEqual(len(required),16);self.assertRegex(digest,r'^[0-9a-f]{64}$');self.assertGreater(len(calls),1)
   for value in ('nested','wrong-blob','wrong-path'):
    mode='lawful';self.assertEqual(len(M.vault_pipeline_source(REPO,head)[0]),16);mode=value
    with self.assertRaises(M.Unread):M.vault_pipeline_source(REPO,head)
    print('PIPELINE_SOURCE_CASE api-'+value+' rejected twin accepted',flush=True)
  finally:M.api=original
if __name__=='__main__':unittest.main(verbosity=2)
