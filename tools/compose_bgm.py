from pathlib import Path
import wave
import numpy as np

# Original melodies and synthetic instruments; no third-party audio samples.
out = Path(__file__).resolve().parents[1] / 'assets/audio'
sr = 22050

def compose(name, bpm, roots, phrases):
    beat = 60 / bpm
    n = round(64 * beat * sr)
    audio = np.zeros((n, 2))
    def note(pitch, start, duration, gain, pan=0, bass=False):
        t = np.arange(round(duration*sr))/sr
        hz = 440 * 2**((pitch-69)/12)
        tone = np.sin(2*np.pi*hz*t) + .22*np.sin(4*np.pi*hz*t)*np.exp(-7*t)
        env = np.minimum(1,t/.012)*np.minimum(1,np.maximum(0,duration-t)/.06)*np.exp(-t*(2 if bass else 4))
        indexes = (np.arange(len(t))+round(start*sr)) % n
        audio[indexes,0] += gain*tone*env*np.sqrt((1-pan)/2)
        audio[indexes,1] += gain*tone*env*np.sqrt((1+pan)/2)
    for bar in range(16):
        root = roots[bar % len(roots)]
        third = 3 if name == 'starry_run.wav' and root in [45,50,52] else 4
        chord = [root,root+third,root+7]
        for b in [0,2]: note(root-12, (bar*4+b)*beat, 1.5*beat,.13,bass=True)
        for step in range(8):
            start=(bar*4+step/2)*beat
            note(chord[step%3]+12,start,.6*beat,.045,-.35)
            pitch=phrases[bar%len(phrases)][step]
            if pitch is not None: note(root+24+pitch,start,.9*beat,.11,.2)
        for b in [0,2]:
            t=np.arange(round(.16*sr))/sr
            kick=.09*np.sin(2*np.pi*(62*t-70*t*t))*np.exp(-27*t)
            indexes=(np.arange(len(t))+round((bar*4+b)*beat*sr)) % n
            audio[indexes] += kick[:,None]
    # Wrap note tails and remove the remaining sample seam without a silent gap.
    fade=round(.005*sr)
    audio[-fade:] += np.linspace(0,1,fade)[:,None]*(audio[0]-audio[-1])
    audio *= .78/max(.001,np.max(np.abs(audio)))
    with wave.open(str(out/name),'wb') as f:
        f.setparams((2,2,sr,n,'NONE','not compressed'))
        f.writeframes((audio*32767).astype('<i2').tobytes())
    print(name,round(n/sr,2),'seconds; peak',round(float(np.max(np.abs(audio))),3))

compose('sunny_dash.wav',132,[48,53,55,48,57,53,55,48],[
 [0,4,7,12,7,4,2,4],[7,None,4,2,0,4,7,None],
 [2,7,11,7,4,None,2,0],[12,7,4,2,0,None,4,7]])
compose('sakura_step.wav',108,[50,55,57,50,59,55,57,50],[
 [0,None,2,7,9,7,2,None],[7,9,12,None,9,7,2,0],
 [2,None,7,9,12,9,7,None],[9,7,2,None,0,2,7,2]])
compose('starry_run.wav',112,[45,53,48,55,45,53,50,52],[
 [0,None,7,10,7,None,3,7],[4,7,None,11,7,4,2,None],
 [7,None,12,7,4,None,2,4],[2,7,11,None,7,2,0,None]])
