#!/usr/bin/env python3
"""
YouTube Downloader CLI Tool
Downloads YouTube videos as MP4 or audio as MP3
"""

import sys
import re
import os
from yt_dlp import YoutubeDL
from yt_dlp.utils import DownloadError, ExtractorError


def print_usage():
    """Print usage information"""
    print("Usage: python download.py <youtube_url> <format>")
    print("\nParameters:")
    print("  <youtube_url>  - The YouTube video URL")
    print("  <format>       - Either 'mp3' (audio) or 'mp4' (video)")
    print("\nExamples:")
    print("  python download.py https://www.youtube.com/watch?v=dQw4w9WgXcQ mp4")
    print("  python download.py https://www.youtube.com/watch?v=dQw4w9WgXcQ mp3")


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
    ]
    
    for pattern in youtube_patterns:
        if re.match(pattern, url):
            return True
    return False


def validate_arguments():
    """
    Validate command-line arguments
    Returns: (url, format) tuple if valid, None if invalid
    """
    # Check argument count
    if len(sys.argv) != 3:
        print("Error: Invalid number of arguments")
        print_usage()
        return None
    
    url = sys.argv[1]
    format_type = sys.argv[2].lower()
    
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
    
    return url, format_type


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


def download_video(url, format_type):
    """
    Download YouTube video in specified format
    
    Args:
        url: YouTube video URL
        format_type: 'mp3' or 'mp4'
    
    Returns:
        True if successful, False otherwise
    """
    # Check for ffmpeg if MP3 format requested
    if format_type == 'mp3' and not check_ffmpeg():
        print("✗ Error: ffmpeg is not installed or not in PATH")
        print("\nffmpeg is required for MP3 conversion.")
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
    }
    
    # Configure options based on format
    if format_type == 'mp4':
        # For MP4: download best video with audio
        ydl_opts.update({
            'format': 'bestvideo[ext=mp4]+bestaudio[ext=m4a]/best[ext=mp4]/best',
            'merge_output_format': 'mp4',
        })
        print("Downloading video in MP4 format...")
    else:  # mp3
        # For MP3: extract audio and convert
        ydl_opts.update({
            'format': 'bestaudio/best',
            'postprocessors': [{
                'key': 'FFmpegExtractAudio',
                'preferredcodec': 'mp3',
                'preferredquality': '192',
            }],
        })
        print("Extracting audio in MP3 format...")
    
    try:
        with YoutubeDL(ydl_opts) as ydl:
            # Extract video info first to show title
            info = ydl.extract_info(url, download=False)
            video_title = info.get('title', 'Unknown')
            print(f"Video: {video_title}")
            
            # Sanitize the title for filename
            safe_title = sanitize_filename(video_title)
            
            # Update output template with sanitized title
            ydl_opts['outtmpl'] = f"{safe_title}.%(ext)s"
            
            # Perform the actual download with updated options
            with YoutubeDL(ydl_opts) as ydl2:
                ydl2.download([url])
            
            # Determine the actual output filename
            if format_type == 'mp3':
                expected_file = f"{safe_title}.mp3"
            else:
                expected_file = f"{safe_title}.mp4"
            
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
    
    url, format_type = args
    
    # Perform download
    success = download_video(url, format_type)
    
    if not success:
        sys.exit(1)


if __name__ == "__main__":
    main()
