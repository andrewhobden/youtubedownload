#!/usr/bin/env python3
"""
YouTube Downloader CLI Tool
Downloads YouTube videos as MP4 or audio as MP3
"""

import sys
import re
import os
import subprocess
from yt_dlp import YoutubeDL
from yt_dlp.utils import DownloadError, ExtractorError


def print_usage():
    """Print usage information"""
    print("Usage: python download.py <youtube_url> <format> "
          "[--chapters | --playlist | --autosplit]")
    print("\nParameters:")
    print("  <youtube_url>  - The YouTube video or playlist URL")
    print("  <format>       - Either 'mp3' (audio) or 'mp4' (video)")
    print("  --chapters     - Optional. Split the download into one file per")
    print("                   YouTube chapter (named videotitle_chapter.mp3/mp4)")
    print("  --playlist     - Optional. Download every video in the playlist into")
    print("                   a folder named after the playlist. Each file is")
    print("                   prefixed with its 3-digit track number (e.g. 001title.mp3)")
    print("  --autosplit    - Optional, mp3 only. For videos without chapters: download")
    print("                   as MP3 into a folder (with the thumbnail), then detect")
    print("                   short quiet gaps to split it into separate track files")
    print("                   (001title.mp3, 002title.mp3, ...). Useful for music")
    print("                   album uploads that lack chapter metadata.")
    print("\nExamples:")
    print("  python download.py https://www.youtube.com/watch?v=dQw4w9WgXcQ mp4")
    print("  python download.py https://www.youtube.com/watch?v=dQw4w9WgXcQ mp3")
    print("  python download.py https://www.youtube.com/watch?v=dQw4w9WgXcQ mp3 --chapters")
    print("  python download.py 'https://www.youtube.com/playlist?list=PLxxxx' mp3 --playlist")
    print("  python download.py https://www.youtube.com/watch?v=dQw4w9WgXcQ mp3 --autosplit")


def is_valid_youtube_url(url):
    """
    Validate if the URL is a valid YouTube URL
    Supports various YouTube URL formats
    """
    youtube_patterns = [
        r'(?:https?://)?(?:www\.)?youtube\.com/watch\?v=[\w-]+',
        r'(?:https?://)?(?:www\.)?youtu\.be/[\w-]+',
        r'(?:https?://)?(?:www\.)?youtube\.com/embed/[\w-]+',
        r'(?:https?://)?(?:www\.)?youtube\.com/v/[\w-]+',
        r'(?:https?://)?(?:www\.)?youtube\.com/playlist\?list=[\w-]+',
        r'(?:https?://)?music\.youtube\.com/playlist\?list=[\w-]+',
    ]
    
    for pattern in youtube_patterns:
        if re.match(pattern, url):
            return True
    return False


def validate_arguments():
    """
    Validate command-line arguments
    Returns: (url, format, split_chapters, playlist, autosplit) tuple if valid,
    None if invalid
    """
    # Check argument count (url + format + up to one optional flag)
    if len(sys.argv) not in (3, 4):
        print("Error: Invalid number of arguments")
        print_usage()
        return None

    url = sys.argv[1]
    format_type = sys.argv[2].lower()
    split_chapters = False
    playlist = False
    autosplit = False

    if len(sys.argv) == 4:
        flag = sys.argv[3].lower()
        if flag == '--chapters':
            split_chapters = True
        elif flag == '--playlist':
            playlist = True
        elif flag == '--autosplit':
            autosplit = True
        else:
            print(f"Error: Unknown option '{sys.argv[3]}'")
            print_usage()
            return None

    # Validate URL
    if not is_valid_youtube_url(url):
        print(f"Error: Invalid YouTube URL: {url}")
        print("Please provide a valid YouTube URL")
        return None

    # Validate format
    if format_type not in ['mp3', 'mp4']:
        print(f"Error: Invalid format '{format_type}'")
        print("Format must be either 'mp3' or 'mp4'")
        return None

    if autosplit and format_type != 'mp3':
        print("Error: --autosplit only works with mp3 format")
        return None

    return url, format_type, split_chapters, playlist, autosplit


def sanitize_filename(filename, max_length=200):
    """
    Sanitize filename for safe filesystem usage
    
    Args:
        filename: Original filename
        max_length: Maximum filename length (excluding extension)
    
    Returns:
        Sanitized filename
    """
    # Remove or replace problematic characters
    # Keep alphanumeric, spaces, hyphens, underscores, and periods
    sanitized = re.sub(r'[<>:"/\\|?*]', '', filename)
    sanitized = re.sub(r'[\x00-\x1f\x7f-\x9f]', '', sanitized)  # Remove control characters
    
    # Replace multiple spaces with single space
    sanitized = re.sub(r'\s+', ' ', sanitized)
    
    # Strip leading/trailing spaces and periods
    sanitized = sanitized.strip(' .')
    
    # Limit length
    if len(sanitized) > max_length:
        sanitized = sanitized[:max_length].strip()
    
    # Fallback if empty after sanitization
    if not sanitized:
        sanitized = "video"
    
    return sanitized


def get_unique_filename(base_name, extension):
    """
    Get a unique filename by appending numbers if file exists
    
    Args:
        base_name: Base filename without extension
        extension: File extension (with or without dot)
    
    Returns:
        Unique filename that doesn't exist
    """
    # Ensure extension has a dot
    if not extension.startswith('.'):
        extension = '.' + extension
    
    filename = base_name + extension
    
    # If file doesn't exist, return as-is
    if not os.path.exists(filename):
        return filename
    
    # File exists, append number
    counter = 1
    while True:
        filename = f"{base_name}_{counter}{extension}"
        if not os.path.exists(filename):
            return filename
        counter += 1


def progress_hook(d):
    """Progress callback for yt-dlp"""
    if d['status'] == 'downloading':
        # Show download progress
        if 'total_bytes' in d:
            percent = d['downloaded_bytes'] / d['total_bytes'] * 100
            print(f"\rDownloading: {percent:.1f}%", end='', flush=True)
        elif '_percent_str' in d:
            print(f"\rDownloading: {d['_percent_str']}", end='', flush=True)
    elif d['status'] == 'finished':
        print("\nDownload complete! Processing...")


def check_ffmpeg():
    """
    Check if ffmpeg is installed
    Returns True if found, False otherwise
    """
    import shutil
    return shutil.which('ffmpeg') is not None


def detect_silence_gaps(mp3_path, noise_db=-30.0, min_silence=1.5):
    """
    Run ffmpeg's silencedetect filter on an audio file and return the gaps
    it found as a list of (silence_start, silence_end) tuples (seconds).
    """
    result = subprocess.run(
        [
            'ffmpeg', '-hide_banner', '-nostats', '-i', mp3_path,
            '-af', f'silencedetect=noise={noise_db}dB:d={min_silence}',
            '-f', 'null', '-',
        ],
        capture_output=True,
        text=True,
    )
    output = result.stderr or ''
    starts = [float(m) for m in re.findall(r'silence_start:\s*([0-9.]+)', output)]
    ends = [float(m) for m in re.findall(r'silence_end:\s*([0-9.]+)', output)]
    # Pair them up; ignore any trailing unmatched silence_start
    return list(zip(starts, ends))


def split_audio_by_silence(mp3_path, out_dir, base_name, total_duration,
                           noise_db=-30.0, min_silence=1.5, min_track=30.0):
    """
    Slice mp3_path into tracks at silence gaps and write them into out_dir
    as <NNN><base_name>.mp3.

    Returns (track_files, silence_gaps).
    """
    silences = detect_silence_gaps(mp3_path, noise_db, min_silence)

    # Build track ranges by walking the silences in order. The track start is
    # the previous silence's end (or 0 for the first), the track end is the
    # next silence's start (or duration for the last). Skip ranges shorter
    # than min_track to discard leading/trailing silence noise.
    tracks = []
    cursor = 0.0
    for s_start, s_end in silences:
        end = s_start
        if end - cursor >= min_track:
            tracks.append((cursor, end))
        cursor = s_end
    if total_duration - cursor >= min_track:
        tracks.append((cursor, total_duration))

    track_files = []
    for i, (t_start, t_end) in enumerate(tracks, 1):
        out_name = f"{i:03d}{base_name}.mp3"
        out_path = os.path.join(out_dir, out_name)
        subprocess.run(
            [
                'ffmpeg', '-hide_banner', '-loglevel', 'error', '-y',
                '-i', mp3_path,
                '-ss', f"{t_start:.3f}", '-to', f"{t_end:.3f}",
                '-c', 'copy', out_path,
            ],
            check=True,
        )
        track_files.append(out_name)

    return track_files, silences


def download_video(url, format_type, split_chapters=False, playlist=False,
                   autosplit=False):
    """
    Download YouTube video in specified format

    Args:
        url: YouTube video URL (or playlist URL when playlist=True)
        format_type: 'mp3' or 'mp4'
        split_chapters: If True, split output into one file per YouTube chapter
        playlist: If True, download every video in the playlist into a folder
                  named after the playlist; files are prefixed with a 3-digit
                  track number (e.g. 001<title>.<ext>)
        autosplit: mp3-only. If True, download into a folder (with the
                   thumbnail) then use silence detection to split the file
                   into separate track files (001<title>.mp3, ...).

    Returns:
        True if successful, False otherwise
    """
    # ffmpeg is required for MP3 conversion, chapter splitting, and autosplit
    needs_ffmpeg = format_type == 'mp3' or split_chapters or autosplit
    if needs_ffmpeg and not check_ffmpeg():
        print("✗ Error: ffmpeg is not installed or not in PATH")
        reason = "MP3 conversion" if format_type == 'mp3' else "chapter splitting"
        print(f"\nffmpeg is required for {reason}.")
        print("\nInstall instructions:")
        print("  macOS:    brew install ffmpeg")
        print("  Ubuntu:   sudo apt install ffmpeg")
        print("  Windows:  Download from https://ffmpeg.org/download.html")
        return False

    # Base options for yt-dlp
    ydl_opts = {
        'progress_hooks': [progress_hook],
        'outtmpl': '%(title)s.%(ext)s',  # Output filename template
        'restrictfilenames': False,  # We'll handle sanitization ourselves
        'windowsfilenames': True,  # Ensure Windows-compatible filenames
        'quiet': False,
        'no_warnings': False,
        # Help avoid 403 errors
        'nocheckcertificate': True,
        'extractor_args': {'youtube': {'player_client': ['android', 'web']}},
        # Only follow playlist links when the user explicitly opts in with --playlist
        'noplaylist': not playlist,
    }

    # Configure options based on format
    if format_type == 'mp4':
        # For MP4: download best video with audio
        ydl_opts.update({
            'format': 'bestvideo[ext=mp4]+bestaudio[ext=m4a]/best[ext=mp4]/best',
            'merge_output_format': 'mp4',
        })
        print("Downloading video in MP4 format...")
        postprocessors = []
    else:  # mp3
        # For MP3: extract audio and convert
        ydl_opts['format'] = 'bestaudio/best'
        postprocessors = [{
            'key': 'FFmpegExtractAudio',
            'preferredcodec': 'mp3',
            'preferredquality': '192',
        }]
        print("Extracting audio in MP3 format...")

    if split_chapters:
        # Run after extraction/merge so we split the final mp3/mp4
        postprocessors.append({'key': 'FFmpegSplitChapters'})
        # Also grab the video thumbnail and convert it to PNG so it can live
        # alongside the chapter files.
        postprocessors.append({'key': 'FFmpegThumbnailsConvertor', 'format': 'png'})
        ydl_opts['writethumbnail'] = True
        print("Chapter split enabled: one file per chapter will be produced.")
    elif autosplit:
        # We split the MP3 manually after yt-dlp finishes; still write the
        # thumbnail next to the resulting tracks.
        postprocessors.append({'key': 'FFmpegThumbnailsConvertor', 'format': 'png'})
        ydl_opts['writethumbnail'] = True
        print("Auto-split enabled: tracks will be detected from silence after "
              "download.")

    if postprocessors:
        ydl_opts['postprocessors'] = postprocessors

    try:
        if playlist:
            # Resolve the playlist title (and verify it really is a playlist) using
            # flat extraction — much faster than fully resolving every entry up front.
            info_opts = {
                **ydl_opts,
                'extract_flat': 'in_playlist',
                'quiet': True,
                'no_warnings': True,
            }
            with YoutubeDL(info_opts) as ydl_info:
                playlist_info = ydl_info.extract_info(url, download=False)

            entries = playlist_info.get('entries') if playlist_info else None
            if not entries:
                print("✗ Error: --playlist was set but no playlist entries were found")
                print("   Make sure the URL points to a playlist (e.g. contains list=...).")
                return False

            playlist_title = playlist_info.get('title') or 'playlist'
            entry_count = sum(1 for e in entries if e)
            print(f"Playlist: {playlist_title}")
            print(f"Detected {entry_count} video(s) in playlist.")

            # Create the destination folder (named after the sanitized playlist title)
            safe_playlist_dir = sanitize_filename(playlist_title)
            os.makedirs(safe_playlist_dir, exist_ok=True)

            # Files inside the folder are prefixed with the 3-digit track number,
            # e.g. 001<title>.mp3
            ydl_opts['outtmpl'] = os.path.join(
                safe_playlist_dir,
                '%(playlist_index)03d%(title)s.%(ext)s',
            )

            with YoutubeDL(ydl_opts) as ydl_dl:
                ydl_dl.download([url])

            ext = format_type
            files = sorted(
                f for f in os.listdir(safe_playlist_dir)
                if f.lower().endswith(f'.{ext}')
            )
            if not files:
                print(f"\n✗ Error: no {ext} files were created in {safe_playlist_dir}/")
                return False

            print(f"\n✓ Successfully downloaded {len(files)} file(s) to "
                  f"{safe_playlist_dir}/:")
            for f in files:
                print(f"   - {f}")
            return True

        with YoutubeDL(ydl_opts) as ydl:
            # Extract video info first to show title and chapters
            info = ydl.extract_info(url, download=False)
            video_title = info.get('title', 'Unknown')
            chapters = info.get('chapters') or []
            print(f"Video: {video_title}")

            if split_chapters:
                if not chapters:
                    print("✗ Error: --chapters was requested but this video has no chapters.")
                    return False
                print(f"Detected {len(chapters)} chapter(s).")

            # Sanitize the title for filename
            safe_title = sanitize_filename(video_title)

            # Update output template with sanitized title.
            # For chapter splits, the chapter files are placed in a folder named
            # after the video title. Each chapter file is prefixed with its
            # zero-padded 3-digit chapter number, e.g. 001<videotitle>_<chapter>.<ext>
            if split_chapters:
                os.makedirs(safe_title, exist_ok=True)
                ydl_opts['outtmpl'] = {
                    'default': os.path.join(safe_title, f"{safe_title}.%(ext)s"),
                    'chapter': os.path.join(
                        safe_title,
                        f"%(section_number)03d{safe_title}_%(section_title)s.%(ext)s",
                    ),
                }
            elif autosplit:
                # MP3 + thumbnail go into a folder; we'll split into tracks below.
                os.makedirs(safe_title, exist_ok=True)
                ydl_opts['outtmpl'] = os.path.join(
                    safe_title, f"{safe_title}.%(ext)s"
                )
            else:
                ydl_opts['outtmpl'] = f"{safe_title}.%(ext)s"

            # Perform the actual download with updated options
            with YoutubeDL(ydl_opts) as ydl2:
                ydl2.download([url])

            if split_chapters:
                # Find the chapter files that were created inside the folder.
                # Chapter files start with a 3-digit chapter number prefix.
                ext = format_type
                chapter_files = sorted(
                    f for f in os.listdir(safe_title)
                    if re.match(r'^\d{3}', f) and f.endswith(f'.{ext}')
                )

                # FFmpegSplitChapters keeps the original full-length file alongside
                # the chapter files. Remove it so only the chapter files remain.
                full_file = os.path.join(safe_title, f"{safe_title}.{ext}")
                if os.path.exists(full_file):
                    try:
                        os.remove(full_file)
                    except OSError as e:
                        print(f"Warning: could not remove full-length file {full_file}: {e}")

                # Locate the thumbnail (writethumbnail + FFmpegThumbnailsConvertor
                # produces <safe_title>.png next to the chapter files).
                thumbnail = os.path.join(safe_title, f"{safe_title}.png")
                thumbnail_note = ""
                if os.path.exists(thumbnail):
                    thumbnail_note = f" (+ thumbnail: {safe_title}.png)"

                if not chapter_files:
                    print("\n✗ Error: chapter splitting did not produce any files.")
                    return False

                print(f"\n✓ Successfully downloaded {len(chapter_files)} chapter file(s) "
                      f"to {safe_title}/{thumbnail_note}:")
                for f in chapter_files:
                    print(f"   - {f}")
                return True

            if autosplit:
                full_mp3 = os.path.join(safe_title, f"{safe_title}.mp3")
                if not os.path.exists(full_mp3):
                    print(f"\n✗ Error: expected file {full_mp3} not found after download.")
                    return False

                duration = info.get('duration') or 0.0
                print(f"\nAnalysing {full_mp3} for silence gaps "
                      f"(threshold -30 dB, min 1.5 s)...")
                track_files, silences = split_audio_by_silence(
                    full_mp3, safe_title, safe_title, duration,
                )
                print(f"Detected {len(silences)} silence gap(s); produced "
                      f"{len(track_files)} track(s).")

                if not track_files:
                    print("\n✗ Error: no tracks detected. The video may be a "
                          "continuous mix, or the silence threshold may be too "
                          "strict for this audio.")
                    print(f"   Keeping original file: {full_mp3}")
                    return False

                # Remove the intermediate full-length mp3 — only the tracks remain.
                try:
                    os.remove(full_mp3)
                except OSError as e:
                    print(f"Warning: could not remove original mp3 {full_mp3}: {e}")

                thumbnail = os.path.join(safe_title, f"{safe_title}.png")
                thumbnail_note = ""
                if os.path.exists(thumbnail):
                    thumbnail_note = f" (+ thumbnail: {safe_title}.png)"

                print(f"\n✓ Auto-split produced {len(track_files)} track(s) to "
                      f"{safe_title}/{thumbnail_note}:")
                for f in track_files:
                    print(f"   - {f}")
                return True

            # Determine the actual output filename (single-file case)
            expected_file = f"{safe_title}.{format_type}"

            # Check if file exists and get final name (in case of duplicates handled by yt-dlp)
            if os.path.exists(expected_file):
                final_file = expected_file
            else:
                # yt-dlp might have added a suffix, try to find it
                matching_files = [f for f in os.listdir('.')
                                if f.startswith(safe_title) and f.endswith(f'.{format_type}')]
                if matching_files:
                    # Sort to get the most recent one
                    final_file = sorted(matching_files)[-1]
                else:
                    final_file = expected_file  # Fallback

            print(f"\n✓ Successfully downloaded: {final_file}")
            return True
    
    except ExtractorError as e:
        # Video unavailable, private, or removed
        print(f"\n✗ Error: Unable to access video")
        print(f"   {str(e)}")
        print("\nPossible reasons:")
        print("  - Video is private or deleted")
        print("  - Video is age-restricted or requires login")
        print("  - Geographic restrictions apply")
        return False
    
    except DownloadError as e:
        # Download-specific errors
        print(f"\n✗ Download error: {str(e)}")
        print("\nPossible reasons:")
        print("  - Network connection issues")
        print("  - Insufficient disk space")
        print("  - Temporary YouTube issues")
        return False
    
    except KeyboardInterrupt:
        print("\n\n✗ Download cancelled by user")
        return False
    
    except Exception as e:
        # Catch-all for other errors
        error_msg = str(e).lower()
        
        # Check for network-related errors
        if 'network' in error_msg or 'connection' in error_msg or 'timeout' in error_msg:
            print(f"\n✗ Network error: Unable to connect")
            print("   Please check your internet connection and try again")
        # Check for permission errors
        elif 'permission' in error_msg or 'access denied' in error_msg:
            print(f"\n✗ Permission error: Cannot write to current directory")
            print("   Please check folder write permissions")
        else:
            print(f"\n✗ Unexpected error: {str(e)}")
            print("   Please try again or report this issue")
        
        return False


def main():
    """Main entry point"""
    # Validate arguments
    args = validate_arguments()
    if args is None:
        sys.exit(1)
    
    url, format_type, split_chapters, playlist, autosplit = args

    # Perform download
    success = download_video(
        url,
        format_type,
        split_chapters=split_chapters,
        playlist=playlist,
        autosplit=autosplit,
    )
    
    if not success:
        sys.exit(1)


if __name__ == "__main__":
    main()
