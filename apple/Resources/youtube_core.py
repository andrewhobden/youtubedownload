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


def download_raw(
    url: str,
    out_dir: str,
    audio_only: bool,
    follow_playlist: bool = False,
    progress_cb=None,
) -> dict:
    """
    Download the URL into out_dir using yt-dlp. No ffmpeg-based
    post-processing happens here — the caller (Swift) is responsible.

    Returns:
      {
        'paths': [...],          # absolute file paths produced
        'title': '...',          # video / playlist title
        'thumbnail_url': '...',  # URL of remote thumbnail, if any
        'chapters': [...],       # raw yt-dlp chapter list
        'duration': float,       # seconds (best effort)
        'entries': [...],        # per-entry summary for playlists
      }
    """
    os.makedirs(out_dir, exist_ok=True)

    opts = _base_opts(follow_playlist)
    if audio_only:
        opts['format'] = 'bestaudio/best'
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

    if progress_cb is not None:
        def _hook(d):
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

    try:
        # Snapshot the directory so we can return only files newly produced
        # by THIS yt-dlp invocation. Without this, repeated downloads into
        # the same out_dir (e.g. the Videos/ folder) would re-attribute
        # earlier files to the latest job.
        pre_existing = set()
        if os.path.isdir(out_dir):
            for name in os.listdir(out_dir):
                full = os.path.join(out_dir, name)
                if os.path.isfile(full):
                    pre_existing.add(full)

        with YoutubeDL(opts) as ydl:
            info = ydl.extract_info(url, download=True)
            _accumulate(info)

        for name in sorted(os.listdir(out_dir)):
            full = os.path.join(out_dir, name)
            if os.path.isfile(full) and full not in pre_existing:
                produced.append(full)
    except BaseException as e:
        return _err_envelope(e)

    return _ok_envelope({
        'paths': produced,
        'title': title,
        'thumbnail_url': thumbnail,
        'chapters': chapters,
        'duration': duration,
        'entries': entries_out,
    })
