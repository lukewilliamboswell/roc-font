from pathlib import Path
import dataclasses,os,subprocess,sys
source=Path('/private/tmp/roc-font-graphite');sys.path.insert(0,str(source/'scripts'))
import flight,run_fuzz
roc=os.environ['ROC'];work=Path('/private/tmp/graphite-direction-fuzz');work.mkdir(exist_ok=True)
with flight.flight(roc,bundle=Path('/private/tmp/graphite-index-bundle/2quGXLcXBgc1urPX3Z2svaxJvuK8GSrRLqKcGBKTt6Nf.tar.zst'),work=work/'flight') as dep:
 mirror=flight.make_mirror(work/'mirror')
 template=run_fuzz.TARGETS['font-shape']
 config=dataclasses.replace(template,sources=(mirror/'fuzz/font-graphite-direction.roc',),seeds=mirror/'fuzz/seeds/font-graphite-direction.json',dictionary=mirror/'fuzz/dictionaries/font.dict',font_prefix=b'',max_input_size=9,timeout=10,contract='font-defined NSM direction changes are deterministic, preserve slots and input clusters, align columns, stay within caller budgets and have linear allocation growth without leaks; reference geometry checked separately',font_files=False,smoke_runs=1000)
 run_fuzz.ROOT=mirror;run_fuzz.FUZZ_ROOT=mirror/'fuzz';run_fuzz.WORK_ROOT=work/'fuzz';run_fuzz.TARGETS={'font-graphite-direction':config};run_fuzz.TARGET_ORDER=('font-graphite-direction',)
 def build(name,args):
  output=run_fuzz.binary_path(name);output.parent.mkdir(parents=True,exist_ok=True)
  command=[args.roc,'build','--opt=speed','--fuzz',str(config.source()),f'--output={output}',*args.dep]
  print(command,flush=True)
  return subprocess.run(command,cwd=mirror).returncode
 run_fuzz.build_target=build
 args=run_fuzz.make_parser().parse_args(['smoke','font-graphite-direction','--runs=1000','--seed=266','--roc',roc]);args.dep=dep
 raise SystemExit(run_fuzz.run_mode(args))
