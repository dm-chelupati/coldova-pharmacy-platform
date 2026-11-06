import pdfplumber,sys,re
BAN=['red alert','rehearsal','read-only','RunAzCli','QueryLogAnalytics','subagent','az containerapp','http://','https://','/subscriptions/','sha256:']
ok=True
with pdfplumber.open(sys.argv[1]) as pdf:
    print('pages',len(pdf.pages))
    for i,p in enumerate(pdf.pages,1):
        w,h=p.width/72,p.height/72
        if abs(w-13.333)>0.01 or abs(h-7.5)>0.01: print(i,'BAD SIZE',w,h); ok=False
        ch=p.chars; mn=min(c['size'] for c in ch)
        oob=[c['text'] for c in ch if c['x0']<0.5*72-1 or c['x1']>p.width-0.5*72+1 or c['top']<0.3*72 or c['bottom']>p.height-0.15*72]
        txt=p.extract_text() or ''; words=len(txt.split())
        bans=[b for b in BAN if b.lower() in txt.lower()]
        print(f'p{i}: minfont={mn:.1f} words={words} oob={len(oob)} banned={bans}')
        if mn<8 or oob or bans: ok=False
print('QC', 'PASS' if ok else 'FAIL'); sys.exit(0 if ok else 1)
