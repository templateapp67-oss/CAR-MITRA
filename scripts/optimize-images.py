from pathlib import Path
from PIL import Image
import json
src=Path('src/assets');out=Path('src/site/assets');info={}
for p in src.glob('*.webp'):
 im=Image.open(p)
 logo='logo' in p.stem
 widths=[180,360,720] if logo else [480,800,1200,1600]
 widths=[w for w in widths if w<im.width]+[min(im.width,720 if logo else 1600)]
 widths=sorted(set(widths));variants=[]
 for w in widths:
  h=round(im.height*w/im.width);name=f'{p.stem}-{w}w.webp';im.resize((w,h),Image.Resampling.LANCZOS).save(out/name,quality=86 if logo else 76,method=6);variants.append([name,w,h])
 info[p.name]={'variants':variants,'width':im.width,'height':im.height,'logo':logo}
 # Optimize the compatibility asset too; retain originals under src/assets.
 shutil_image=Image.open(out/variants[-1][0]);shutil_image.save(out/p.name,quality=86 if logo else 76,method=6)
Path('src/image-variants.json').write_text(json.dumps(info))
