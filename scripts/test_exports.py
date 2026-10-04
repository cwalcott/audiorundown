#!/usr/bin/env python3
"""Real FFmpeg integration checks; no speech model or third-party Python packages."""
import array
import json
import math
import os
import pathlib
import shutil
import subprocess
import sys
import tempfile

binary = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else '.build/release/audiorundown').resolve()
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


with tempfile.TemporaryDirectory(prefix='audiorundown-tests-') as tmp:
    root = pathlib.Path(tmp)
    os.environ['AUDIORUNDOWN_CONFIG'] = str(root / 'config.json')
    source = root / 'input with spaces.mp3'
    run(ffmpeg, '-v', 'error', '-f', 'lavfi', '-i', 'sine=frequency=440:duration=2',
        '-f', 'lavfi', '-i', 'sine=frequency=880:duration=2',
        '-f', 'lavfi', '-i', 'sine=frequency=1320:duration=2',
        '-filter_complex', '[0:a][1:a][2:a]concat=n=3:v=0:a=1[out]',
        '-map', '[out]', '-c:a', 'libmp3lame', '-q:a', '4', '-write_xing', '0', source)
    # Add source metadata while keeping the original headerless timing fixture.
    tagged = root / 'tagged.mp3'
    run(ffmpeg, '-v', 'error', '-i', source, '-c:a', 'copy', '-write_xing', '0',
        '-metadata', 'title=Test episode 2026-06-02', '-metadata', 'artist=Test host', tagged)
    tagged.replace(source)
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

    # Exercise the complete original-MP3 -> imported rundown -> selector export path.
    transcript = source.with_suffix('.transcript')
    transcript.mkdir()
    (transcript / 'transcript.json').write_text(json.dumps({
        'schemaVersion': 1, 'engine': 'Synthetic fixture', 'source': str(source), 'language': 'en-US', 'duration': 6, 'createdAt': '2026-10-04T00:00:00Z',
        'segments': [{'start': 0, 'end': 6, 'text': 'Test transcript.', 'words': []}]}))
    guide = root / 'guide.md'
    long_title = 'The detailed discussion about television appearances and memorable stories from the early years'
    guide.write_text(f"""# Test episode

## 1. Television — 00:00:00–00:00:06
### Summary
Television memories.
### Detailed rundown
**1a. {long_title} — 00:00:02–00:00:04**
The full story summary is retained in the export record.
""")
    catalog = root / 'custom-rundown'
    imported = run(binary, 'import-rundown', guide, '--transcript', transcript, '--out-dir', catalog)
    assert f"Choose clips: audiorundown select '{source}'" in imported.stdout.decode()
    preview = run(binary, 'select', source, '--request', '1a', '--preview')
    assert long_title in preview.stdout.decode()
    assert not source.with_suffix('.clips').exists()
    run(binary, 'select', source, '--request', '1a')
    exported = source.with_suffix('.clips') / 'selection-001'
    selected = next(exported.glob('*.mp3'))
    tags = inspect(selected)['format']['tags']
    assert tags['title'].startswith('Test episode 2026-06-02 · 1a · The detailed discussion')
    assert '…' in tags['title']
    assert tags['album'] == 'Test episode 2026-06-02'
    assert tags['artist'] == 'Test host' and tags['track'] == '1/1'
    assert selected.name.startswith('Test episode 2026-06-02 - 01a - The detailed discussion')
    assert len(selected.name.encode('utf-8')) <= 240
    receipt = json.loads((exported / 'export.json').read_text())
    assert receipt['clips'][0]['originalTitle'] == '1a. ' + long_title
    assert receipt['clips'][0]['summary'] == 'The full story summary is retained in the export record.'
    assert receipt['clips'][0]['start'] == 2 and receipt['clips'][0]['end'] == 4
    # A second selection uses a new folder, with no overwritten MP3s.
    run(binary, 'select', source, '--request', '1a')
    assert (source.with_suffix('.clips') / 'selection-002').is_dir()
    assert next((source.with_suffix('.clips') / 'selection-002').glob('*.mp3')).name == selected.name

    # Same selection from a different episode stays distinct in a shared folder.
    second_source = root / 'second episode.mp3'
    run(ffmpeg, '-v', 'error', '-i', source, '-c:a', 'copy',
        '-metadata', 'title=Test episode 2026-06-03', second_source)
    run(binary, 'select', catalog, '--source', second_source, '--request', '1a')
    second_clip = next((second_source.with_suffix('.clips') / 'selection-001').glob('*.mp3'))
    assert second_clip.name.startswith('Test episode 2026-06-03 - 01a - ')
    shared = root / 'shared'
    shared.mkdir()
    shutil.copy2(selected, shared / selected.name)
    shutil.copy2(second_clip, shared / second_clip.name)
    assert len(list(shared.glob('*.mp3'))) == 2

    padded_plan = json.loads((exported / 'sections.json').read_text())
    padded_plan['clips'][0]['includeRangeInFilename'] = True
    padded_file = root / 'padded.json'
    padded_file.write_text(json.dumps(padded_plan))
    run(binary, 'export', source, '--plan', padded_file, '--out-dir', root / 'padded')
    padded_clip = next((root / 'padded').glob('*.mp3'))
    assert '[00-00-02.000_00-00-04.000]' in padded_clip.name

    # Untagged sources fall back to their filename; hand-written plans remain compatible.
    untagged = root / 'Untagged episode.mp3'
    run(ffmpeg, '-v', 'error', '-i', source, '-map_metadata', '-1', '-c:a', 'copy', untagged)
    run(binary, 'select', catalog, '--source', untagged, '--request', '1a')
    fallback = next((untagged.with_suffix('.clips') / 'selection-001').glob('*.mp3'))
    fallback_tags = inspect(fallback)['format']['tags']
    assert fallback_tags['title'].startswith('Untagged episode · 1a · ')
    assert fallback_tags['album'] == 'Untagged episode' and fallback_tags['artist'] == 'AudioRundown'

    run(binary, 'configure', '--model', 'openai:gpt-6.1-sol', '--editor', 'Visual Studio Code')
    config = json.loads((root / 'config.json').read_text())
    assert config['model'] == 'openai:gpt-6.1-sol' and config['reasoning'] == 'medium'
    run(binary, 'configure', '--max-cost', 'nan', ok=False)
    assert json.loads((root / 'config.json').read_text()) == config
    # A saved API preference never affects exact-ID selection or makes a network request.
    run(binary, 'select', source, '--request', '1a', '--preview')

print('Passed audio, metadata, original-MP3 selection, title shortening, source-tag fallback, preferences, and safe-output checks.')
