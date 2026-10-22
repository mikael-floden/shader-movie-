#!/usr/bin/env python3
"""Render a Shadertoy-style GLSL fragment shader to video with headless Chromium (WebGL2).

usage: render.py shader.glsl out.mp4 [--w 640] [--h 360] [--fps 24] [--start 0] [--dur 30] [--audio src.mp4] [--still t]
"""
import argparse, base64, json, subprocess, sys
from playwright.sync_api import sync_playwright

PAGE = """<!doctype html><html><body style="margin:0"><canvas id=c></canvas><script>
const W=%(w)d,H=%(h)d; const c=document.getElementById('c'); c.width=W; c.height=H;
const gl=c.getContext('webgl2',{preserveDrawingBuffer:true,antialias:false});
const vs=`#version 300 es
in vec2 p; void main(){gl_Position=vec4(p,0.,1.);}`;
const fs=`#version 300 es
precision highp float; precision highp int;
uniform vec3 iResolution; uniform float iTime; uniform int iFrame; uniform vec4 iMouse;
out vec4 outColor;
`+%(src)s+`
void main(){ vec4 col=vec4(0.); mainImage(col, gl_FragCoord.xy); outColor=vec4(col.rgb,1.); }`;
function sh(t,s){const o=gl.createShader(t);gl.shaderSource(o,s);gl.compileShader(o);
  if(!gl.getShaderParameter(o,gl.COMPILE_STATUS)) throw new Error(gl.getShaderInfoLog(o)); return o;}
const pr=gl.createProgram(); gl.attachShader(pr,sh(gl.VERTEX_SHADER,vs)); gl.attachShader(pr,sh(gl.FRAGMENT_SHADER,fs));
gl.linkProgram(pr); if(!gl.getProgramParameter(pr,gl.LINK_STATUS)) throw new Error(gl.getProgramInfoLog(pr));
gl.useProgram(pr);
const b=gl.createBuffer(); gl.bindBuffer(gl.ARRAY_BUFFER,b);
gl.bufferData(gl.ARRAY_BUFFER,new Float32Array([-1,-1,3,-1,-1,3]),gl.STATIC_DRAW);
const loc=gl.getAttribLocation(pr,'p'); gl.enableVertexAttribArray(loc); gl.vertexAttribPointer(loc,2,gl.FLOAT,false,0,0);
const U=n=>gl.getUniformLocation(pr,n);
gl.uniform3f(U('iResolution'),W,H,1); gl.uniform4f(U('iMouse'),0,0,0,0);
const px=new Uint8Array(W*H*4);
window.frame=(t,i)=>{gl.uniform1f(U('iTime'),t); gl.uniform1i(U('iFrame'),i); gl.drawArrays(gl.TRIANGLES,0,3);
  gl.readPixels(0,0,W,H,gl.RGBA,gl.UNSIGNED_BYTE,px);
  let s=''; const ch=0x8000; for(let k=0;k<px.length;k+=ch) s+=String.fromCharCode.apply(null,px.subarray(k,k+ch));
  return btoa(s);};
window.ready=true;
</script></body></html>"""

def main():
    a = argparse.ArgumentParser()
    a.add_argument('shader'); a.add_argument('out')
    a.add_argument('--w', type=int, default=640); a.add_argument('--h', type=int, default=360)
    a.add_argument('--fps', type=int, default=24); a.add_argument('--start', type=float, default=0.0)
    a.add_argument('--dur', type=float, default=30.0); a.add_argument('--audio')
    a.add_argument('--still', type=float, nargs='*', help='render PNG stills at these times instead of a video')
    o = a.parse_args()
    src = open(o.shader).read()
    html = PAGE % dict(w=o.w, h=o.h, src=json.dumps(src))
    with sync_playwright() as pw:
        br = pw.chromium.launch(executable_path='/opt/pw-browsers/chromium', args=['--use-gl=angle', '--use-angle=swiftshader', '--enable-unsafe-swiftshader',
                                      '--ignore-gpu-blocklist'])
        pg = br.new_page()
        errs = []
        pg.on('pageerror', lambda e: errs.append(str(e)))
        pg.set_content(html)
        pg.wait_for_timeout(200)
        if errs or not pg.evaluate('window.ready === true'):
            sys.exit('shader error:\n' + '\n'.join(errs))
        if o.still is not None:
            for t in o.still:
                raw = base64.b64decode(pg.evaluate(f'frame({t},0)'))
                name = o.out.replace('%t', f'{t:05.2f}')
                subprocess.run(['ffmpeg', '-v', 'error', '-y', '-f', 'rawvideo', '-pix_fmt', 'rgba',
                                '-s', f'{o.w}x{o.h}', '-i', '-', '-vf', 'vflip', name], input=raw, check=True)
            br.close(); return
        n = int(round(o.dur * o.fps))
        cmd = ['ffmpeg', '-v', 'error', '-y', '-f', 'rawvideo', '-pix_fmt', 'rgba', '-s', f'{o.w}x{o.h}',
               '-r', str(o.fps), '-i', '-']
        if o.audio:
            cmd += ['-ss', str(o.start), '-t', str(o.dur), '-i', o.audio, '-map', '0:v', '-map', '1:a', '-c:a', 'aac']
        cmd += ['-vf', 'vflip', '-c:v', 'libx264', '-pix_fmt', 'yuv420p', '-crf', '18', '-shortest', o.out]
        ff = subprocess.Popen(cmd, stdin=subprocess.PIPE)
        for i in range(n):
            t = o.start + i / o.fps
            ff.stdin.write(base64.b64decode(pg.evaluate(f'frame({t},{i})')))
            if i % 24 == 0: print(f'frame {i}/{n}', file=sys.stderr, flush=True)
        ff.stdin.close(); ff.wait(); br.close()

if __name__ == '__main__':
    main()
