"""The implementation-limit gate must never accept a new/stale observation."""
from pathlib import Path
import copy,json,tempfile,unittest
from limitations import PolicyError,load,classify,payload_sha

class ExactLimits(unittest.TestCase):
 def setUp(self):
  self.actual={'success':True,'abort':'NoAbort','engine':'Graphite','budgets':[],'glyphs':[{'glyph':1,'cluster':0,'advance':[600,0],'offset':[17,0],'flags':0}]}
  self.entry={'id':'case','reference_key':'a'*64,'actual_sha256':payload_sha(self.actual),'budgets':[],'reason':'Positioning'}
 def test_exact_observation_is_coverage_not_reference_agreement(self):
  self.assertIsNone(classify(self.entry,self.actual,False))
  self.assertEqual(classify(self.entry,self.actual,True),'stale known limit now agrees with the reference')
 def test_changed_geometry_fails(self):
  changed=copy.deepcopy(self.actual);changed['glyphs'][0]['offset'][0]=18
  self.assertEqual(classify(self.entry,changed,False),'known-limit native payload changed')
 def test_budget_is_part_of_exact_payload(self):
  changed=copy.deepcopy(self.actual);changed['budgets']=['Operations']
  self.assertEqual(classify(self.entry,changed,False),'known-limit budget diagnostics changed')
  self.assertNotEqual(payload_sha(changed),payload_sha(self.actual))
 def test_process_failure_is_never_an_observation(self):
  self.assertEqual(classify(self.entry,None,False),'known limit has no native result')
 def test_load_rejects_unknown_id_and_stale_reference(self):
  with tempfile.TemporaryDirectory()as tmp:
   path=Path(tmp)/'policy.json';data={'schema':1,'sets':{'shape':[self.entry]},'reasons':{'Positioning':'Known measured gap'}}
   path.write_text(json.dumps(data));cases=[{'id':'case'}];records={'case':{'key':'a'*64}}
   entries,_=load(path,'shape',cases,records);self.assertEqual(set(entries),{'case'})
   with self.assertRaisesRegex(PolicyError,'stale known-limit reference'):load(path,'shape',cases,{'case':{'key':'b'*64}})
   with self.assertRaisesRegex(PolicyError,'unknown known-limit id'):load(path,'shape',[{'id':'another'}],records)
 def test_opt_in_is_explicit(self):
  self.assertEqual(load(None,'',[],{}),({},None))
  with self.assertRaisesRegex(PolicyError,'requires'):load(None,'shape',[],{})
  with tempfile.TemporaryDirectory()as tmp:
   path=Path(tmp)/'policy.json';path.write_text(json.dumps({'schema':1,'sets':{'shape':[self.entry]},'reasons':{}}))
   with self.assertRaisesRegex(PolicyError,'explicit'):load(path,'',[],{})
 def test_changed_engine_is_not_hidden(self):
  changed=copy.deepcopy(self.actual);changed['engine']='OpenType'
  self.assertEqual(classify(self.entry,changed,False),'known-limit native payload changed')

if __name__=='__main__':unittest.main()
