# 오디오 재생성

Python, NumPy와 ffmpeg(libvorbis)가 필요하다.

```bash
python docs/audio_synthesis_source.py ./beaver_audio_rebuilt
```

지정 폴더에 오디오 17개와 audio_manifest.json을 만든다. 기본값은 현재 폴더의 beaver_audio_rebuilt다. 같은 출력 폴더로 다시 실행하면 해당 오디오를 교체한다.
