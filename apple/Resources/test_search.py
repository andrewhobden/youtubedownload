#!/usr/bin/env python3
import sys
sys.path.insert(0, '/Users/anhobden/Documents/GitHub/youtubedownload/apple/Resources/site-packages')

from yt_dlp import YoutubeDL

opts = {
    'quiet': True,
    'no_warnings': True,
    'extract_flat': True,
    'force_generic_extractor': False
}

with YoutubeDL(opts) as ydl:
    info = ydl.extract_info("ytsearch5:led zeppelin", download=False)
    
    if 'entries' in info:
        for i, entry in enumerate(info['entries']):
            print(f"\n=== Entry {i+1} ===")
            print(f"ID: {entry.get('id', 'N/A')}")
            print(f"Title: {entry.get('title', 'N/A')}")
            print(f"Thumbnail: {entry.get('thumbnail', 'N/A')}")
            print(f"Has thumbnails array: {'thumbnails' in entry}")
            if 'thumbnails' in entry and entry['thumbnails']:
                print(f"Thumbnails count: {len(entry['thumbnails'])}")
                print(f"Last thumbnail URL: {entry['thumbnails'][-1].get('url', 'N/A')}")
