from pathlib import Path
import dataclasses,os,subprocess,sys
source=Path('/private/tmp/roc-font-graphite');sys.path.insert(0,str(source/'scripts'))
import flight,run_fuzz
roc=os.environ['ROC'];work=Path('/private/tmp/graphite-delete-fuzz');work.mkdir(exist_ok=True)
with flight.flight(roc,bundle=Path('/private/tmp/graphite-lifetime-dev/flight/bundle/FUmiew97AKLoH5U41SLgKCtWhjoLmFrom8V4xpYtfJmE.tar.zst'),work=work/'flight') as dep:
 mirror=flight.make_mirror(work/'mirror')
 public=subprocess.run([roc,'test','tests/api/GraphiteDeletionMain.roc',*dep],cwd=mirror,text=True,capture_output=True);(work/'public.log').write_text(public.stdout+public.stderr);print(public.stdout+public.stderr,flush=True)
 if public.returncode:raise SystemExit(public.returncode)
 template=run_fuzz.TARGETS['font-shape']
 config=dataclasses.replace(template,sources=(mirror/'fuzz/font-graphite-delete.roc',),seeds=mirror/'fuzz/seeds/font-graphite-delete.json',dictionary=mirror/'fuzz/dictionaries/font.dict',font_prefix=b'',max_input_size=9,timeout=10,contract='deletion-time attachment programs terminate deterministically, preserve every surviving glyph column and original cluster, remain within caller budgets, have linear allocation growth and leak no memory; complete outputs separately reference-checked',font_files=False,smoke_runs=1000)
 run_fuzz.ROOT=mirror;run_fuzz.FUZZ_ROOT=mirror/'fuzz';run_fuzz.WORK_ROOT=work/'fuzz';run_fuzz.TARGETS={'font-graphite-delete':config};run_fuzz.TARGET_ORDER=('font-graphite-delete',)
 def build(name,args):
  output=run_fuzz.binary_path(name);output.parent.mkdir(parents=True,exist_ok=True)
  command=[args.roc,'build','--opt=speed','--fuzz',str(config.source()),f'--output={output}',*args.dep]
  print(command,flush=True)
  return subprocess.run(command,cwd=mirror).returncode
 run_fuzz.build_target=build
 args=run_fuzz.make_parser().parse_args(['smoke','font-graphite-delete','--runs=1000','--seed=268','--roc',roc]);args.dep=dep
 raise SystemExit(run_fuzz.run_mode(args))
