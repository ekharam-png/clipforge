import sys
from fontTools.ttLib import TTFont
import os
F=os.path.join(os.path.dirname(os.path.abspath(__file__)),'..','..','assets','fonts')+os.sep
fonts=[('rubik','Rubik'),('bonaNova','BonaNova'),('amaticSc','AmaticSC')]
ranges=[('Ascii',0x20,0x7E),('Latin1',0xA0,0xFF),('Cyrillic',0x400,0x45F),('Hebrew',0x5D0,0x5EA)]
out=[]
out.append('// GENERATED from assets/fonts (fontTools, hmtx advance widths in 1/1000 em)')
out.append('// by docs/tools/title_font_metrics.py - do not edit by hand.')
out.append('// Ranges: U+0020..007E, U+00A0..00FF, U+0400..045F, U+05D0..05EA;')
out.append('// -1 = the font has no such character (the fallback advance is used).')
out.append('')
out.append('part of \'title_layout.dart\';')
out.append('')
for key,base in fonts:
  for style in ['Regular','Bold']:
    t=TTFont(F+f'{base}-{style}.ttf'); cmap=t.getBestCmap(); upm=t['head'].unitsPerEm; hm=t['hmtx'].metrics
    vals_all=[]
    for name,a,b in ranges:
      vals=[]
      for c in range(a,b+1):
        if c in cmap: v=round(hm[cmap[c]][0]*1000/upm); vals.append(v); vals_all.append(v)
        else: vals.append(-1)
      out.append(f'const List<int> _{key}{style}{name} = [')
      for i in range(0,len(vals),12):
        out.append('  '+', '.join(str(v) for v in vals[i:i+12])+',')
      out.append('];')
      out.append('')
    # average advance of letters outside the tables
    others=[c for c in cmap if c>0x24F and not (0x400<=c<=0x45F) and not (0x5D0<=c<=0x5EA) and c<0x3000]
    adv=[hm[cmap[c]][0]*1000/upm for c in others if hm[cmap[c]][0]>0]
    avg=round(sum(adv)/len(adv)) if adv else 600
    out.append(f'const int _{key}{style}Fallback = {avg};')
    out.append('')
print('\n'.join(out))
