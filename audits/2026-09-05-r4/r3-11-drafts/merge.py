"""Lead-side merge for R3-11 drafts. Dry-run by default; --apply writes db/source."""
import json, re, sys, glob, os, sqlite3
S=os.path.dirname(os.path.abspath(__file__)); W=sys.argv[1]; APPLY='--apply' in sys.argv
cat={r['id']:r for r in json.load(open(f'{S}/exercise-catalog.json'))}
inj={k:v for k,v in json.load(open(f'{S}/injuries.json')).items()}
existing=json.load(open(f'{S}/existing-rows.json'))
con=sqlite3.connect(f'{W}/PhaseTraining/Resources/coach.db')
live={(r[0],r[1],r[2]) for r in con.execute("SELECT exercise_id,injury_id,role FROM exercise_injury_relevance")}
early={(r[0],r[1]) for r in con.execute("SELECT exercise_id,injury_id FROM exercise_injury_relevance WHERE role='rehab_early'")}
new_rows=[]; problems=[]; summary=[]
for f in sorted(glob.glob(f'{S}/*.json')):
    if os.path.basename(f) in ('exercise-catalog.json','injuries.json','existing-rows.json','movement-patterns.json'): continue
    region=os.path.basename(f)[:-5]; d=json.load(open(f))
    blob=json.dumps(d)
    for ch in ('—','–'):
        if ch in blob: problems.append(f"[{region}] contains {'em' if ch=='—' else 'en'} dash")
    for rule in d.get('rules',[]):
        slug=rule['injury_slug']
        if slug not in inj: problems.append(f"[{region}] unknown injury {slug}"); continue
        iid=inj[slug]['id']; pred=rule.get('predicate',{})
        pats=set(pred.get('patterns',[])); rx=re.compile(pred['name_regex']) if pred.get('name_regex') else None
        excl=set(pred.get('exclude_exercise_ids',[]))
        note=rule.get('note','')
        if not note.rstrip().endswith('unreviewed.'): problems.append(f"[{region}/{slug}] note must end 'Sourced (mechanism), unreviewed.'")
        if not rule.get('source_url') or not rule.get('mechanism'): problems.append(f"[{region}/{slug}] rule missing source_url or mechanism")
        hits=[]
        for xid,x in cat.items():
            xp=set((x['patterns'] or '').split('/'))
            if (pats and xp & pats) or (rx and rx.search(x['name'])):
                if xid in excl: continue
                if (xid,iid) in early: problems.append(f"[{region}/{slug}] would contraindicate rehab_early exercise {xid} {x['name']}"); continue
                if (xid,iid,'contraindicated') in live: continue
                hits.append(xid)
        for xid in hits: new_rows.append({"exercise_id":xid,"injury_id":iid,"role":"contraindicated","notes":note})
        summary.append(f"  {region:>12}/{slug:<24} +{len(hits):>3} contraindicated  patterns={sorted(pats)} regex={pred.get('name_regex')!r}")
    for r in d.get('rehab_early',[]):
        slug=r['injury_slug']; iid=inj[slug]['id']; xid=r['exercise_id']
        if xid not in cat: problems.append(f"[{region}/{slug}] rehab_early exercise {xid} not in catalog"); continue
        if not r.get('source_url'): problems.append(f"[{region}/{slug}] rehab_early {xid} has no source_url")
        if (xid,iid,'rehab_early') in live: continue
        if (xid,iid,'contraindicated') in live: summary.append(f"  NOTE {region}/{slug}: rehab_early {xid} {cat[xid]['name']} currently contraindicated; the clash test will fail unless that row is dropped")
        new_rows.append({"exercise_id":xid,"injury_id":iid,"role":"rehab_early","notes":(r.get('note','') or 'Treatment while symptomatic.')+" Source: "+r['source_url']})
        summary.append(f"  {region:>12}/{slug:<24} rehab_early {xid} {cat[xid]['name'][:40]}")
print("\n".join(summary)); print(f"\nnew rows: {len(new_rows)}   problems: {len(problems)}")
for p in problems: print("  PROBLEM", p)
if APPLY and not problems:
    p=f'{W}/db/source/exercise_injury_relevance.json'; rows=json.load(open(p))
    keys={(r['exercise_id'],r['injury_id'],r['role']) for r in rows}
    add=[r for r in new_rows if (r['exercise_id'],r['injury_id'],r['role']) not in keys]
    rows.extend(add); json.dump(rows,open(p,'w'),indent=2,ensure_ascii=False); open(p,'a').write("\n")
    print(f"APPLIED {len(add)} rows -> {len(rows)}")
