#!/usr/bin/env python3
"""Real FFmpeg integration checks; no speech model or third-party Python packages."""
import array
import json
import math
import pathlib
import shutil
import subprocess
import sys
import tempfile

binary = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else '.build/release/audiochapters').resolve()
ffmpeg = shutil.which('ffmpeg') or '/opt/homebrew/bin/ffmpeg'
ffprobe = shutil.which('ffprobe') or '/opt/homebrew/bin/ffprobe'


def run(*args, ok=True):
    result = subprocess.run([str(x) for x in args], capture_output=True)
    if ok:
        assert result.returncode == 0, result.stderr.decode()
    else:
        assert result.returncode != 0, 'Expected rejection'
    return result


def inspect(path):
    return json.loads(run(ffprobe, '-v', 'error', '-show_format', '-show_streams', '-of', 'json', path).stdout)


with tempfile.TemporaryDirectory(prefix='audiochapters-tests-') as tmp:
    root = pathlib.Path(tmp)
    source = root / 'input with spaces.mp3'
    run(ffmpeg, '-v', 'error', '-f', 'lavfi', '-i', 'sine=frequency=440:duration=2',
        '-f', 'lavfi', '-i', 'sine=frequency=880:duration=2',
        '-f', 'lavfi', '-i', 'sine=frequency=1320:duration=2',
        '-filter_complex', '[0:a][1:a][2:a]concat=n=3:v=0:a=1[out]',
        '-map', '[out]', '-c:a', 'libmp3lame', '-q:a', '4', '-write_xing', '0', source)
    output = root / 'selected.mp3'
    title = 'A title; $(not-a-command) "quoted"'
    run(binary, 'clip', source, '--start', '2.25', '--end', '3.75', '--title', title,
        '--album', 'My episodes', '--artist', 'Test artist', '--output', output)
    info = inspect(output)
    assert info['streams'][0]['codec_name'] == 'mp3'
    assert abs(float(info['format']['duration']) - 1.5) < .1
    assert info['format']['tags']['title'] == title
    assert info['format']['tags']['album'] == 'My episodes'
    assert info['format']['tags']['artist'] == 'Test artist'
    # Decode the exported clip and verify it contains the middle tone, not the beginning.
    pcm = run(ffmpeg, '-v', 'error', '-i', output, '-f', 'f32le', '-ac', '1', '-ar', '8000', '-').stdout
    samples = array.array('f', pcm)[1000:7000]
    def power(hz):
        real = sum(x * math.cos(2 * math.pi * hz * i / 8000) for i, x in enumerate(samples))
        imag = sum(x * math.sin(2 * math.pi * hz * i / 8000) for i, x in enumerate(samples))
        return real * real + imag * imag
    assert power(880) > 100 * max(power(440), power(1320))
    before = output.read_bytes()
    run(binary, 'clip', source, '--start', '0', '--end', '1', '--output', output, ok=False)
    assert output.read_bytes() == before
    run(binary, 'clip', source, '--start', '0', '--end', '100', '--output', root / 'bad.mp3', ok=False)
    assert not (root / 'bad.mp3').exists()

    plan = root / 'sections.json'
    plan.write_text(json.dumps({'album': 'Batch episodes', 'clips': [
        {'title': '../../Same title', 'start': '0', 'end': '1'},
        {'title': '../../Same title', 'start': '4', 'end': '5'}]}))
    destination = root / 'episodes'
    run(binary, 'export', source, '--plan', plan, '--out-dir', destination)
    clips = sorted(destination.glob('*.mp3'))
    assert [p.name for p in clips] == ['001-Same-title.mp3', '002-Same-title.mp3']
    assert inspect(clips[1])['format']['tags']['track'] == '2/2'
    receipt = json.loads((destination / 'export.json').read_text())
    assert receipt['clips'][1]['start'] == 4

    plan.write_text(json.dumps({'clips': [
        {'title': 'Valid', 'start': '0', 'end': '1'},
        {'title': 'Invalid', 'start': '4', 'end': '100'}]}))
    run(binary, 'export', source, '--plan', plan, '--out-dir', root / 'invalid-batch', ok=False)
    assert not (root / 'invalid-batch').exists()

print('Passed MP3 codec, duration, seek-content, metadata, overwrite, invalid-range, and batch-export checks.')
