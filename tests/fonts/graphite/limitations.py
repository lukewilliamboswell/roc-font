"""Exact observed implementation limits; deliberately separate from oracle policy.

An opted-in known limit is neither agreement nor a normative divergence. Every
entry is tied to one reference key and one complete observed native payload.
"""
import hashlib,json,re

class PolicyError(ValueError):pass

def payload_sha(value):
 return hashlib.sha256(json.dumps(value,sort_keys=True,separators=(',',':')).encode()).hexdigest()

def load(path,name,cases,records):
 if path is None:
  if name:raise PolicyError('--limitation-set requires --known-limitations')
  return {},None
 data=json.loads(path.read_text())
 if data.get('schema')!=1 or not isinstance(data.get('sets'),dict):raise PolicyError('invalid implementation-limit registry schema')
 if not name or name not in data['sets']:raise PolicyError('choose an explicit --limitation-set from the registry')
 case_ids={c['id']for c in cases};entries={};reasons=data.get('reasons',{})
 if not isinstance(data['sets'][name],list):raise PolicyError('known-limit set must be a list')
 for entry in data['sets'][name]:
  if not isinstance(entry,dict)or not isinstance(entry.get('id'),str):raise PolicyError('known-limit entry needs an id')
  key=entry['id']
  if key in entries:raise PolicyError('duplicate known-limit id: '+str(key))
  if key not in case_ids or key not in records:raise PolicyError('unknown known-limit id: '+str(key))
  if entry.get('reference_key')!=records[key]['key']:raise PolicyError('stale known-limit reference: '+key)
  if not isinstance(entry.get('actual_sha256'),str)or not re.fullmatch('[0-9a-f]{64}',entry['actual_sha256']):raise PolicyError('invalid known-limit actual hash: '+key)
  if not isinstance(entry.get('reason'),str)or entry['reason']not in reasons:raise PolicyError('missing known-limit reason: '+key)
  if not isinstance(entry.get('budgets'),list)or not all(isinstance(v,str)for v in entry['budgets']):raise PolicyError('invalid known-limit budgets: '+key)
  entries[key]=entry
 return entries,{'set':name,'registry_sha256':hashlib.sha256(path.read_bytes()).hexdigest()}

def classify(entry,actual,reference_agrees):
 if reference_agrees:return 'stale known limit now agrees with the reference'
 if not isinstance(actual,dict):return 'known limit has no native result'
 if actual.get('budgets')!=entry['budgets']:return 'known-limit budget diagnostics changed'
 if payload_sha(actual)!=entry['actual_sha256']:return 'known-limit native payload changed'
 return None
