"""
youtube_core — minimal Python interface called from Swift via PythonKit.

All FFmpeg* postprocessors are deliberately disabled here. Swift runs
mp3 conversion, chapter slicing, thumbnail conversion, and silence-split
slicing via ffmpeg-kit so the iOS and Catalyst code paths are identical.
"""

from __future__ import annotations

import os
import re
from typing import Any

from yt_dlp import YoutubeDL


# Patterns copied from download.py to keep validation in lockstep.
_URL_PATTERNS = [
    r'(?:https?://)?(?:www\.)?youtube\.com/watch\?v=[\w-]+',
    r'(?:https?://)?(?:www\.)?youtu\.be/[\w-]+',
    r'(?:https?://)?(?:www\.)?youtube\.com/embed/[\w-]+',
    r'(?:https?://)?(?:www\.)?youtube\.com/v/[\w-]+',
    r'(?:https?://)?(?:www\.)?youtube\.com/playlist\?list=[\w-]+',
    r'(?:https?://)?music\.youtube\.com/playlist\?list=[\w-]+',
]


def is_valid_url(url: str) -> bool:
    return any(re.match(p, url) for p in _URL_PATTERNS)


class _PauseRequested(BaseException):
    """Raised from the progress hook to abort (pause) an in-flight download
    when a foreground lookup needs the shared Python thread.

    Subclasses ``BaseException`` (not ``Exception``) on purpose so yt-dlp's
    internal ``except Exception`` retry/ignore loops cannot swallow it — it
    propagates straight out of ``extract_info`` to ``download_raw``.
    """
    pass



def _base_opts(follow_playlist: bool) -> dict:
    return {
        'quiet': True,
        'no_warnings': True,
        'nocheckcertificate': True,
        'noplaylist': not follow_playlist,
        'extractor_args': {'youtube': {'player_client': ['android', 'web']}},
        # The native iOS app does its own ffmpeg work via ffmpeg-kit. Make
        # sure yt-dlp never tries to spawn an external ffmpeg binary.
        'postprocessors': [],
        'writethumbnail': False,
    }


def _ok_envelope(payload: dict) -> dict:
    payload['ok'] = True
    payload['error'] = ''
    payload.setdefault('paused', False)
    return payload


def _err_envelope(err: BaseException) -> dict:
    return {
        'ok': False,
        'error': f'{type(err).__name__}: {err}',
        'title': '',
        'is_playlist': False,
        'entry_count': 0,
        'chapter_count': 0,
        'duration': 0.0,
        'thumbnail': '',
        'chapters': [],
        'entries': [],
        'paths': [],
        'thumbnail_url': '',
        'paused': False,
    }


def probe(url: str, follow_playlist: bool = False) -> dict:
    """
    Fast metadata probe. For playlist URLs use follow_playlist=True with
    flat extraction so we don't fully resolve every entry.

    Always returns a dict with `ok` and `error` keys so Swift never sees a
    Python exception (which would crash PythonKit's non-throwing call site).
    """
    try:
        opts = _base_opts(follow_playlist)
        if follow_playlist:
            opts['extract_flat'] = 'in_playlist'

        with YoutubeDL(opts) as ydl:
            info = ydl.extract_info(url, download=False)

        entries = info.get('entries') or []
        return _ok_envelope({
            'title': info.get('title') or 'Unknown',
            'is_playlist': bool(entries) or info.get('_type') == 'playlist',
            'entry_count': len(entries) if entries else 1,
            'chapter_count': len(info.get('chapters') or []),
            'duration': float(info.get('duration') or 0.0),
            'thumbnail': info.get('thumbnail') or '',
            'chapters': info.get('chapters') or [],
            'entries': [
                {
                    'url': e.get('url') or e.get('webpage_url') or '',
                    'title': e.get('title') or '',
                    'duration': float(e.get('duration') or 0.0),
                }
                for e in entries
            ] if entries else [],
        })
    except BaseException as e:
        return _err_envelope(e)


def search(query: str, start: int, count: int) -> dict:
    """
    Flat YouTube search for items `start`..`start+count-1`.

    Returns a safe envelope ({ok, error, results: [...]}) so a network or
    extractor failure surfaces as data — never as a Python exception, which
    would crash PythonKit's non-throwing call site (and the whole app).
    """
    try:
        start = int(start)
        count = int(count)
        end = start + count - 1
        opts = {
            'quiet': True,
            'no_warnings': True,
            'extract_flat': True,
            'nocheckcertificate': True,
            'extractor_args': {'youtube': {'player_client': ['android', 'web']}},
            'playlist_items': f'{start}-{end}',
        }
        with YoutubeDL(opts) as ydl:
            info = ydl.extract_info(f'ytsearch{end}:{query}', download=False)

        results = []
        for e in (info.get('entries') or []):
            if not e:
                continue
            vid = e.get('id')
            title = e.get('title')
            if not vid or not title:
                continue
            thumb = ''
            thumbs = e.get('thumbnails') or []
            if thumbs:
                thumb = (thumbs[-1] or {}).get('url') or ''
            if not thumb:
                t = e.get('thumbnail')
                thumb = t if (t and t != 'None') else ''
            results.append({
                'id': vid,
                'title': title,
                'creator': e.get('uploader') or e.get('channel') or 'Unknown',
                'duration': float(e.get('duration') or 0.0),
                'view_count': int(e.get('view_count') or 0),
                'upload_date': e.get('upload_date') or '',
                'description': e.get('description') or '',
                'thumbnail': thumb,
                'is_live': bool(e.get('is_live') or False),
            })
        return {'ok': True, 'error': '', 'results': results}
    except BaseException as e:
        return {'ok': False, 'error': f'{type(e).__name__}: {e}', 'results': []}


def download_raw(
    url: str,
    out_dir: str,
    audio_only: bool,
    follow_playlist: bool = False,
    progress_cb=None,
    should_pause=None,
    baseline_paths=None,
) -> dict:
    """
    Download the URL into out_dir using yt-dlp. No ffmpeg-based
    post-processing happens here — the caller (Swift) is responsible.

    ``should_pause`` (optional) is a zero-arg callable returning truthy when a
    foreground lookup needs the shared Python thread; when it does, the
    download aborts cleanly and returns ``paused: True`` (NOT an error). The
    caller can re-invoke with the same args to resume from the partial file.

    ``baseline_paths`` (optional) is the set of files that existed before the
    FIRST attempt; pass it on resume so already-completed files (e.g. earlier
    playlist entries) are still reported in ``paths``.

    Returns:
      {
        'paths': [...],          # absolute file paths produced
        'title': '...',          # video / playlist title
        'thumbnail_url': '...',  # URL of remote thumbnail, if any
        'chapters': [...],       # raw yt-dlp chapter list
        'duration': float,       # seconds (best effort)
        'entries': [...],        # per-entry summary for playlists
        'paused': bool,          # True if aborted to yield to a foreground op
      }
    """
    os.makedirs(out_dir, exist_ok=True)

    opts = _base_opts(follow_playlist)
    opts['continuedl'] = True  # resume partial .part files after a pause
    # Download HLS/m3u8 streams with yt-dlp's native downloader instead of
    # shelling out to an ffmpeg binary (which this app doesn't bundle — it does
    # its ffmpeg work via the ffmpeg-kit library on the Swift side). Without
    # this, m3u8-only media fails with "ffmpeg could not be found".
    opts['hls_prefer_native'] = True
    if audio_only:
        # Prefer progressive/DASH (http/https) audio; fall back to anything
        # (incl. HLS, handled natively above).
        opts['format'] = 'bestaudio[protocol^=http]/bestaudio/best'
    else:
        opts['format'] = (
            'bestvideo[ext=mp4]+bestaudio[ext=m4a]/best[ext=mp4]/best'
        )
        opts['merge_output_format'] = 'mp4'

    # Output template: <out_dir>/<title>.<ext>  for single videos,
    #                  <out_dir>/<playlist_index>_<title>.<ext> for playlists.
    if follow_playlist:
        opts['outtmpl'] = os.path.join(
            out_dir, '%(playlist_index)03d_%(title)s.%(ext)s'
        )
    else:
        opts['outtmpl'] = os.path.join(out_dir, '%(title)s.%(ext)s')

    if progress_cb is not None or should_pause is not None:
        def _hook(d):
            # Abort (pause) the transfer the moment a foreground lookup needs
            # the Python thread. _PauseRequested subclasses BaseException so
            # yt-dlp's internal `except Exception` loops don't swallow it.
            if should_pause is not None and should_pause():
                raise _PauseRequested()
            if progress_cb is not None:
                try:
                    progress_cb(d.get('status', ''),
                                float(d.get('downloaded_bytes') or 0),
                                float(d.get('total_bytes') or d.get('total_bytes_estimate') or 0))
                except Exception:
                    pass
        opts['progress_hooks'] = [_hook]

    produced: list[str] = []
    title = ''
    thumbnail = ''
    chapters: list[dict] = []
    duration = 0.0
    entries_out: list[dict] = []

    def _accumulate(info: dict) -> None:
        nonlocal title, thumbnail, chapters, duration, entries_out
        title = info.get('title') or title
        thumbnail = info.get('thumbnail') or thumbnail
        chapters = info.get('chapters') or chapters
        duration = float(info.get('duration') or duration)
        if info.get('entries'):
            entries_out = [
                {
                    'url': e.get('webpage_url') or '',
                    'title': e.get('title') or '',
                    'duration': float(e.get('duration') or 0.0),
                }
                for e in info['entries']
                if e
            ]

    # Baseline: files present before the FIRST attempt. On resume Swift passes
    # the original baseline so already-completed files (e.g. earlier playlist
    # entries) are still attributed to this job; otherwise snapshot now.
    if baseline_paths is not None:
        pre_existing = set(str(p) for p in baseline_paths)
    else:
        pre_existing = set()
        if os.path.isdir(out_dir):
            for name in os.listdir(out_dir):
                full = os.path.join(out_dir, name)
                if os.path.isfile(full):
                    pre_existing.add(full)

    def _collect_produced() -> list[str]:
        # Completed files only — skip yt-dlp's in-progress temp files so a
        # paused download never reports a partial .part as a finished path.
        out: list[str] = []
        if not os.path.isdir(out_dir):
            return out
        for name in sorted(os.listdir(out_dir)):
            if name.endswith('.part') or name.endswith('.ytdl'):
                continue
            full = os.path.join(out_dir, name)
            if os.path.isfile(full) and full not in pre_existing:
                out.append(full)
        return out

    try:
        with YoutubeDL(opts) as ydl:
            info = ydl.extract_info(url, download=True)
            _accumulate(info)

        produced = _collect_produced()
    except _PauseRequested:
        # Yielded to a foreground lookup. Return what completed so far; the
        # partial file stays on disk for `continuedl` to resume.
        return _ok_envelope({
            'paths': _collect_produced(),
            'title': title,
            'thumbnail_url': thumbnail,
            'chapters': chapters,
            'duration': duration,
            'entries': entries_out,
            'paused': True,
        })
    except BaseException as e:
        return _err_envelope(e)

    return _ok_envelope({
        'paths': produced,
        'title': title,
        'thumbnail_url': thumbnail,
        'chapters': chapters,
        'duration': duration,
        'entries': entries_out,
        'paused': False,
    })
